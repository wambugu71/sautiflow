#include "mp4_aac_decoder.h"
#include <stdlib.h>
#include <string.h>
#include <stdio.h>
#include <stdarg.h>
#ifdef _WIN32
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif

// Diagnostic logging: writes to %TEMP%\mp4_aac_log.txt + OutputDebugString
static void mp4_log(const char *fmt, ...)
{
    va_list args;
    char buf[512];
    va_start(args, fmt);
    vsnprintf(buf, sizeof(buf), fmt, args);
    va_end(args);

    fputs(buf, stderr);
    fflush(stderr);

#ifdef _WIN32
    OutputDebugStringA(buf);

    char logPath[MAX_PATH];
    DWORD tempLen = GetTempPathA(MAX_PATH, logPath);
    if (tempLen > 0 && tempLen < MAX_PATH - 20)
    {
        strcat(logPath, "mp4_aac_log.txt");
        FILE *f = fopen(logPath, "a");
        if (f)
        {
            fputs(buf, f);
            fclose(f);
        }
    }
#else
    // Try multiple writable paths
    static const char *paths[] = {
        "/tmp/mp4_aac_log.txt",
        NULL};
    for (int i = 0; paths[i] != NULL; i++)
    {
        FILE *f = fopen(paths[i], "a");
        if (f)
        {
            fputs(buf, f);
            fclose(f);
            break;
        }
    }
#endif
}

#define MINIMP4_IMPLEMENTATION
#include "third_party/minimp4.h"
#include "third_party/faad2/include/neaacdec.h"

// -------------------------------------------------------------------------
// Fragmented MP4 (fMP4) sample table built by scanning moof/traf/trun boxes.
// Used when minimp4's stsz sample_count==0 (init-segment-only moov box).
// -------------------------------------------------------------------------
typedef struct
{
    uint64_t file_offset; // absolute byte offset in file
    uint32_t size;        // sample byte size
} fmp4_sample_entry_t;

// -------------------------------------------------------------------------
// Define our state
// -------------------------------------------------------------------------
typedef struct
{
    ma_data_source_base ds;

    ma_read_proc onRead;
    ma_seek_proc onSeek;
    ma_tell_proc onTell;
    void *pUserData;

    ma_format format;
    ma_uint32 channels;
    ma_uint32 sampleRate;

    // MP4 State
    MP4D_demux_t mp4_demux;
    int aac_track_id;
    unsigned int mp4_sample_count;
    unsigned int current_mp4_sample;

    // fMP4 sample table (populated when stsz is empty)
    fmp4_sample_entry_t *fmp4_samples; // malloc'd array
    unsigned int fmp4_sample_count;
    int use_fmp4; // non-zero if fmp4_samples should be used instead of MP4D_frame_offset

    // FAAD State
    NeAACDecHandle hDecoder;
    long total_pcm_frames;
    long cursor_pcm_frames;

    // Buffering for decoded frames
    float *pDecodedBuffer;
    size_t decodedBufferSizeFrames;
    size_t decodedBufferCursorFrames;
    size_t decodedBufferCapacitySamples; // allocated capacity in float samples

    // Buffer for reading MP4 payload
    unsigned char *pPayloadBuffer;
    size_t payloadBufferSize;

    // Dynamic samples-per-AAC-frame (1024 for LC-AAC, 2048 for HE-AAC/SBR)
    unsigned int samplesPerAACFrame; // in PCM frames (per channel), 0 = not yet known

} mp4_aac_decoder_state;

// minimp4 read callback bridging to miniaudio
static int mp4_read_callback(int64_t offset, void *buffer, size_t size, void *token)
{
    mp4_aac_decoder_state *pState = (mp4_aac_decoder_state *)token;

    if (pState->onSeek != NULL)
    {
        // MP4D seek is absolute
        ma_result seekResult = pState->onSeek(pState->pUserData, offset, ma_seek_origin_start);
        if (seekResult != MA_SUCCESS)
        {
            mp4_log("[mp4_aac] mp4_read_callback: seek to %lld FAILED (result=%d)\n", (long long)offset, seekResult);
            return 1;
        }
    }

    size_t bytesRead = 0;
    if (pState->onRead != NULL)
    {
        pState->onRead(pState->pUserData, buffer, size, &bytesRead);
    }

    if (bytesRead != size)
    {
        mp4_log("[mp4_aac] mp4_read_callback: offset=%lld size=%zu bytesRead=%zu (short/EOF)\n",
                (long long)offset, size, bytesRead);
    }

    // minimp4 read_callback convention: return 0 on success, non-zero on error/EOF.
    // (minimp4_fgets does `if (read_callback(...)) return -1;`)
    return bytesRead == size ? 0 : 1;
}

// -------------------------------------------------------------------------
// fMP4 scanner: walks top-level boxes looking for moof->traf->trun and
// builds a flat array of (file_offset, size) for every audio sample.
// Returns MA_SUCCESS and fills pState->fmp4_samples/fmp4_sample_count.
// -------------------------------------------------------------------------
static uint32_t fmp4_read_u32_be(const unsigned char *p)
{
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static ma_result fmp4_scan_moof_boxes(mp4_aac_decoder_state *pState, int64_t file_size)
{
    // We do a linear scan from offset=0, reading box headers.
    // For each 'moof' box we find, we parse traf/trun to collect samples.
    // For each 'mdat' box following a 'moof', data_offset in trun is relative
    // to start of the moof box.

    unsigned char hdr[8];
    int64_t pos = 0;
    uint64_t moof_start = 0;

    // Dynamic array growth
    unsigned int capacity = 0;
    unsigned int count = 0;
    fmp4_sample_entry_t *samples = NULL;

    // Last trun data_offset (relative to moof start), used for mdat offset calc
    // When trun has data-offset-present, mdat_base_offset = moof_start + data_offset
    // When not present, samples lie at mdat start (offset 0x11 bytes from mdat header)

    while (pos + 8 <= file_size)
    {
        // Read box header
        if (pState->onSeek(pState->pUserData, pos, ma_seek_origin_start) != MA_SUCCESS)
            break;
        size_t bytesRead = 0;
        pState->onRead(pState->pUserData, hdr, 8, &bytesRead);
        if (bytesRead < 8)
            break;

        uint64_t box_size = fmp4_read_u32_be(hdr);
        uint32_t box_type = fmp4_read_u32_be(hdr + 4);

        if (box_size == 1)
        {
            // 64-bit size field follows
            unsigned char sz64[8];
            pState->onRead(pState->pUserData, sz64, 8, &bytesRead);
            if (bytesRead < 8)
                break;
            box_size = ((uint64_t)fmp4_read_u32_be(sz64) << 32) | fmp4_read_u32_be(sz64 + 4);
        }
        else if (box_size == 0)
        {
            // Box extends to end of file
            box_size = (uint64_t)(file_size - pos);
        }

        if (box_size < 8)
            break; // Malformed

        // Is this a 'moof' box?
        // BOX_moof = 'moof' = 0x6d6f6f66
        static const uint32_t BOXTYPE_moof = 0x6d6f6f66u;
        static const uint32_t BOXTYPE_traf = 0x74726166u;
        static const uint32_t BOXTYPE_tfhd = 0x74666864u;
        static const uint32_t BOXTYPE_trun = 0x7472756eu;
        static const uint32_t BOXTYPE_mfhd = 0x6d666864u;

        if (box_type == BOXTYPE_moof)
        {
            moof_start = (uint64_t)pos;
            uint64_t moof_end = (uint64_t)pos + box_size;

            // Walk children of moof
            int64_t moof_child_pos = pos + 8;
            while (moof_child_pos + 8 <= (int64_t)moof_end)
            {
                if (pState->onSeek(pState->pUserData, moof_child_pos, ma_seek_origin_start) != MA_SUCCESS)
                    break;
                pState->onRead(pState->pUserData, hdr, 8, &bytesRead);
                if (bytesRead < 8)
                    break;

                uint64_t child_size = fmp4_read_u32_be(hdr);
                uint32_t child_type = fmp4_read_u32_be(hdr + 4);
                if (child_size < 8)
                    break;

                if (child_type == BOXTYPE_traf)
                {
                    // Walk children of traf
                    int64_t traf_end = moof_child_pos + (int64_t)child_size;
                    int64_t traf_child_pos = moof_child_pos + 8;

                    // We need tfhd to get default_sample_size / base_data_offset
                    uint32_t tfhd_flags = 0;
                    // uint64_t base_data_offset = 0; // not used right now
                    uint32_t default_sample_duration = 0;
                    uint32_t default_sample_size = 0;
                    (void)default_sample_duration;

                    while (traf_child_pos + 8 <= traf_end)
                    {
                        if (pState->onSeek(pState->pUserData, traf_child_pos, ma_seek_origin_start) != MA_SUCCESS)
                            break;
                        pState->onRead(pState->pUserData, hdr, 8, &bytesRead);
                        if (bytesRead < 8)
                            break;

                        uint64_t traf_child_size = fmp4_read_u32_be(hdr);
                        uint32_t traf_child_type = fmp4_read_u32_be(hdr + 4);
                        if (traf_child_size < 8)
                            break;

                        if (traf_child_type == BOXTYPE_tfhd)
                        {
                            // Parse tfhd (FullBox: 4 bytes version+flags, 4 bytes track_ID)
                            unsigned char tfhd_buf[24];
                            pState->onRead(pState->pUserData, tfhd_buf, 8, &bytesRead);
                            if (bytesRead >= 8)
                            {
                                tfhd_flags = fmp4_read_u32_be(tfhd_buf) & 0x00FFFFFF;
                                // track_ID = fmp4_read_u32_be(tfhd_buf + 4);  // not used
                                int tfhd_off = 8; // bytes after box header already consumed
                                // base-data-offset-present
                                if (tfhd_flags & 0x000001)
                                    tfhd_off += 8;
                                // sample-description-index-present
                                if (tfhd_flags & 0x000002)
                                    tfhd_off += 4;
                                // default-sample-duration-present
                                if (tfhd_flags & 0x000008)
                                {
                                    unsigned char dur[4];
                                    if (pState->onSeek(pState->pUserData, traf_child_pos + 8 + tfhd_off, ma_seek_origin_start) == MA_SUCCESS)
                                    {
                                        pState->onRead(pState->pUserData, dur, 4, &bytesRead);
                                        if (bytesRead == 4)
                                            default_sample_duration = fmp4_read_u32_be(dur);
                                    }
                                    tfhd_off += 4;
                                }
                                // default-sample-size-present
                                if (tfhd_flags & 0x000010)
                                {
                                    unsigned char sz[4];
                                    if (pState->onSeek(pState->pUserData, traf_child_pos + 8 + tfhd_off, ma_seek_origin_start) == MA_SUCCESS)
                                    {
                                        pState->onRead(pState->pUserData, sz, 4, &bytesRead);
                                        if (bytesRead == 4)
                                            default_sample_size = fmp4_read_u32_be(sz);
                                    }
                                }
                            }
                        }
                        else if (traf_child_type == BOXTYPE_trun)
                        {
                            // trun is a FullBox: 4 bytes version+flags
                            // Then: sample_count (4 bytes)
                            // Optional: data_offset (4 bytes) if flags & 0x001
                            //           first_sample_flags (4 bytes) if flags & 0x004
                            // Per-sample (sample_count entries):
                            //   sample_duration (4) if flags & 0x100
                            //   sample_size     (4) if flags & 0x200
                            //   sample_flags    (4) if flags & 0x400
                            //   sample_composition_time_offset (4) if flags & 0x800

                            // Read version+flags and sample_count (cursor is already at traf_child_pos+8)
                            unsigned char trun_hdr[8];
                            pState->onRead(pState->pUserData, trun_hdr, 8, &bytesRead);
                            if (bytesRead < 8)
                            {
                                goto next_traf_child;
                            }
                            uint32_t trun_flags = fmp4_read_u32_be(trun_hdr) & 0x00FFFFFFu;
                            uint32_t sample_count = fmp4_read_u32_be(trun_hdr + 4);

                            // Optional data_offset
                            int32_t data_offset = 0;
                            if (trun_flags & 0x001)
                            {
                                unsigned char do_buf[4];
                                pState->onRead(pState->pUserData, do_buf, 4, &bytesRead);
                                if (bytesRead == 4)
                                    data_offset = (int32_t)fmp4_read_u32_be(do_buf);
                            }
                            // Optional first_sample_flags
                            if (trun_flags & 0x004)
                            {
                                unsigned char dummy[4];
                                pState->onRead(pState->pUserData, dummy, 4, &bytesRead);
                            }

                            // The mdat data starts at: moof_start + data_offset
                            // (data_offset is relative to start of the moof box)
                            uint64_t sample_data_base = moof_start + (uint64_t)(uint32_t)data_offset;
                            uint64_t running_offset = sample_data_base;

                            // Grow array
                            if (count + sample_count > capacity)
                            {
                                unsigned int new_cap = (capacity == 0) ? 256 : capacity * 2;
                                while (new_cap < count + sample_count)
                                    new_cap *= 2;
                                fmp4_sample_entry_t *new_arr = (fmp4_sample_entry_t *)realloc(samples, new_cap * sizeof(fmp4_sample_entry_t));
                                if (!new_arr)
                                {
                                    free(samples);
                                    return MA_OUT_OF_MEMORY;
                                }
                                samples = new_arr;
                                capacity = new_cap;
                            }

                            for (uint32_t si = 0; si < sample_count; si++)
                            {
                                uint32_t s_duration = default_sample_duration;
                                uint32_t s_size = default_sample_size;
                                (void)s_duration;

                                if (trun_flags & 0x100)
                                {
                                    unsigned char d[4];
                                    pState->onRead(pState->pUserData, d, 4, &bytesRead);
                                    if (bytesRead == 4)
                                        s_duration = fmp4_read_u32_be(d);
                                }
                                if (trun_flags & 0x200)
                                {
                                    unsigned char d[4];
                                    pState->onRead(pState->pUserData, d, 4, &bytesRead);
                                    if (bytesRead == 4)
                                        s_size = fmp4_read_u32_be(d);
                                }
                                if (trun_flags & 0x400)
                                {
                                    unsigned char d[4];
                                    pState->onRead(pState->pUserData, d, 4, &bytesRead);
                                }
                                if (trun_flags & 0x800)
                                {
                                    unsigned char d[4];
                                    pState->onRead(pState->pUserData, d, 4, &bytesRead);
                                }

                                samples[count].file_offset = running_offset;
                                samples[count].size = s_size;
                                count++;
                                running_offset += s_size;
                            }
                        }

                    next_traf_child:
                        traf_child_pos += (int64_t)traf_child_size;
                    }
                }

                moof_child_pos += (int64_t)child_size;
            }
        }

        pos += (int64_t)box_size;
    }

    if (count == 0)
    {
        free(samples);
        mp4_log("[mp4_aac] fMP4 scan: no moof/trun samples found\n");
        return MA_INVALID_DATA;
    }

    pState->fmp4_samples = samples;
    pState->fmp4_sample_count = count;
    pState->use_fmp4 = 1;
    mp4_log("[mp4_aac] fMP4 scan: found %u samples\n", count);
    return MA_SUCCESS;
}

static ma_result ma_decoding_backend_read__mp4_aac(ma_data_source *pDataSource, void *pFramesOut, ma_uint64 frameCount, ma_uint64 *pFramesRead)
{
    mp4_aac_decoder_state *pState = (mp4_aac_decoder_state *)pDataSource;
    if (pState == NULL)
        return MA_INVALID_ARGS;

    if (pFramesRead != NULL)
        *pFramesRead = 0;

    ma_uint64 framesToRead = frameCount;
    ma_uint64 totalFramesRead = 0;
    float *pOutF32 = (float *)pFramesOut;

    while (framesToRead > 0)
    {
        // Serve from buffer if we have available frames
        size_t availableFrames = pState->decodedBufferSizeFrames - pState->decodedBufferCursorFrames;
        if (availableFrames > 0)
        {
            size_t framesToCopy = (framesToRead < availableFrames) ? (size_t)framesToRead : availableFrames;
            size_t samplesToCopy = framesToCopy * pState->channels;

            if (pOutF32 != NULL)
            {
                float *src = pState->pDecodedBuffer + (pState->decodedBufferCursorFrames * pState->channels);
                memcpy(pOutF32, src, samplesToCopy * sizeof(float));
                pOutF32 += samplesToCopy;
            }

            pState->decodedBufferCursorFrames += framesToCopy;
            pState->cursor_pcm_frames += (long)framesToCopy;
            framesToRead -= framesToCopy;
            totalFramesRead += framesToCopy;

            if (pFramesRead != NULL)
                *pFramesRead = totalFramesRead;

            if (framesToRead == 0)
                return MA_SUCCESS;
        }

        // Buffer is empty, decode next AAC frame
        unsigned int total_samples = pState->use_fmp4 ? pState->fmp4_sample_count : pState->mp4_sample_count;
        if (pState->current_mp4_sample >= total_samples)
        {
            if (pState->current_mp4_sample == 0 && total_samples == 0)
            {
                mp4_log("[mp4_aac] read: sample_count=0, returning MA_AT_END immediately\n");
            }
            return (totalFramesRead > 0) ? MA_SUCCESS : MA_AT_END; // EOF
        }

        // Get payload frame size and offset
        uint64_t frame_offset64 = 0;
        uint32_t frame_bytes = 0;

        if (pState->use_fmp4)
        {
            fmp4_sample_entry_t *e = &pState->fmp4_samples[pState->current_mp4_sample];
            frame_offset64 = e->file_offset;
            frame_bytes = e->size;
        }
        else
        {
            unsigned int timestamp = 0, duration = 0, fb32 = 0;
            unsigned int off32 = MP4D_frame_offset(&pState->mp4_demux, pState->aac_track_id,
                                                   pState->current_mp4_sample, &fb32, &timestamp, &duration);
            frame_offset64 = (uint64_t)off32;
            frame_bytes = fb32;
        }

        if (frame_bytes == 0)
        {
            pState->current_mp4_sample++;
            continue; // Skip invalid frame
        }

        // Expand payload buffer if needed
        if (frame_bytes > pState->payloadBufferSize)
        {
            unsigned char *newBuf = (unsigned char *)realloc(pState->pPayloadBuffer, frame_bytes);
            if (!newBuf)
            {
                mp4_log("[mp4_aac] realloc payload FAILED: sample=%u frame_bytes=%u\n",
                        pState->current_mp4_sample, frame_bytes);
                pState->current_mp4_sample++;
                continue;
            }
            pState->pPayloadBuffer = newBuf;
            pState->payloadBufferSize = frame_bytes;
        }

        // Seek to offset and read
        ma_result seekResult = MA_SUCCESS;
        if (pState->onSeek)
            seekResult = pState->onSeek(pState->pUserData, (ma_int64)frame_offset64, ma_seek_origin_start);

        size_t bytesRead = 0;
        if (pState->onRead)
            pState->onRead(pState->pUserData, pState->pPayloadBuffer, frame_bytes, &bytesRead);

        // Log the first 5 frame reads for diagnostics
        if (pState->current_mp4_sample < 5)
        {
            mp4_log("[mp4_aac] sample[%u]: offset=%llu size=%u seek=%d read=%zu\n",
                    pState->current_mp4_sample,
                    (unsigned long long)frame_offset64,
                    frame_bytes, (int)seekResult, bytesRead);
        }

        if (bytesRead != frame_bytes)
        {
            mp4_log("[mp4_aac] short read on sample %u: offset=%llu want=%u got=%zu seekResult=%d\n",
                    pState->current_mp4_sample,
                    (unsigned long long)frame_offset64,
                    frame_bytes, bytesRead, (int)seekResult);
            pState->current_mp4_sample++;
            continue;
        }

        // Decode AAC payload
        NeAACDecFrameInfo frameInfo;
        memset(&frameInfo, 0, sizeof(frameInfo));
        void *decodedData = NeAACDecDecode(pState->hDecoder, &frameInfo, pState->pPayloadBuffer, frame_bytes);

        if (frameInfo.error != 0)
        {
            mp4_log("[mp4_aac] decode error %u on sample %u: %s\n",
                    (unsigned)frameInfo.error, pState->current_mp4_sample,
                    NeAACDecGetErrorMessage(frameInfo.error));
            // Invalidate buffer so stale data is NOT re-served (Bug 3)
            pState->decodedBufferSizeFrames = 0;
            pState->decodedBufferCursorFrames = 0;
            pState->current_mp4_sample++;
            continue;
        }

        if (decodedData == NULL || frameInfo.samples == 0 || frameInfo.channels == 0)
        {
            // Guard against channels==0 division-by-zero (Bug 2) and NULL output
            pState->decodedBufferSizeFrames = 0;
            pState->decodedBufferCursorFrames = 0;
            pState->current_mp4_sample++;
            continue;
        }

        // Success — copy decoded PCM into our buffer
        size_t decodedFrames = frameInfo.samples / frameInfo.channels;
        size_t totalSamples = (size_t)frameInfo.samples; // channels * frames

        // Track actual samples-per-AAC-frame for accurate duration (Bug 7)
        if (pState->samplesPerAACFrame == 0)
        {
            pState->samplesPerAACFrame = (unsigned int)decodedFrames;
            mp4_log("[mp4_aac] detected %u samples/AAC-frame (HE-AAC if 2048)\n", pState->samplesPerAACFrame);
        }

        // --- DIAGNOSTIC: log first sample values for the first 3 decoded frames ---
        static int s_diagFrameCount = 0;
        if (s_diagFrameCount < 10)
        {
            s_diagFrameCount++;
            const int16_t *rawI16 = (const int16_t *)decodedData;
            mp4_log("[mp4_aac] FRAME#%d output: samples=%u ch=%u sr=%lu | i16[0..5]: %d %d %d %d %d %d\n",
                    s_diagFrameCount,
                    frameInfo.samples,
                    (unsigned)frameInfo.channels,
                    frameInfo.samplerate,
                    totalSamples > 0 ? (int)rawI16[0] : 0,
                    totalSamples > 1 ? (int)rawI16[1] : 0,
                    totalSamples > 2 ? (int)rawI16[2] : 0,
                    totalSamples > 3 ? (int)rawI16[3] : 0,
                    totalSamples > 4 ? (int)rawI16[4] : 0,
                    totalSamples > 5 ? (int)rawI16[5] : 0);
        }
        // --- END DIAGNOSTIC ---

        // Adjust format if dynamic changes occur (should be rare)
        pState->channels = frameInfo.channels;
        pState->sampleRate = frameInfo.samplerate;

        // Grow pDecodedBuffer only if needed, reuse otherwise (Bug 5)
        if (totalSamples > pState->decodedBufferCapacitySamples)
        {
            float *newBuf = (float *)realloc(pState->pDecodedBuffer, totalSamples * sizeof(float));
            if (newBuf == NULL)
            {
                // Allocation failed — invalidate buffer, don't crash (Bug 1)
                mp4_log("[mp4_aac] realloc failed for %zu samples\n", totalSamples);
                pState->decodedBufferSizeFrames = 0;
                pState->decodedBufferCursorFrames = 0;
                pState->current_mp4_sample++;
                continue;
            }
            pState->pDecodedBuffer = newBuf;
            pState->decodedBufferCapacitySamples = totalSamples;
        }

        // FAAD2 outputs int16 (FAAD_FMT_16BIT). Convert to float32 for the audio engine.
        // Int16 range [-32768, 32767] → float [-1.0, ~1.0]
        {
            const int16_t *src = (const int16_t *)decodedData;
            for (size_t s = 0; s < totalSamples; s++)
            {
                pState->pDecodedBuffer[s] = (float)src[s] * (1.0f / 32768.0f);
            }
        }

        pState->decodedBufferSizeFrames = decodedFrames;
        pState->decodedBufferCursorFrames = 0;

        pState->current_mp4_sample++;
    }

    if (pFramesRead != NULL)
        *pFramesRead = totalFramesRead;
    return totalFramesRead > 0 ? MA_SUCCESS : MA_AT_END;
}

static ma_result ma_decoding_backend_seek__mp4_aac(ma_data_source *pDataSource, ma_uint64 frameIndex)
{
    mp4_aac_decoder_state *pState = (mp4_aac_decoder_state *)pDataSource;
    if (pState == NULL)
        return MA_INVALID_ARGS;

    // Use actual samples-per-frame if known, fallback to 1024
    unsigned int spf = (pState->samplesPerAACFrame > 0) ? pState->samplesPerAACFrame : 1024;

    pState->current_mp4_sample = 0;
    pState->cursor_pcm_frames = 0;
    pState->decodedBufferSizeFrames = 0;     // invalidate buffer (don't serve stale data)
    pState->decodedBufferCursorFrames = 0;

    unsigned int total_samples = pState->use_fmp4 ? pState->fmp4_sample_count : pState->mp4_sample_count;
    unsigned int targetSample = (unsigned int)(frameIndex / spf);
    if (targetSample < total_samples)
    {
        pState->current_mp4_sample = targetSample;
        pState->cursor_pcm_frames = (long)(targetSample * spf);
    }

    // Reset FAAD2 internal state after seek (Bug 6)
    if (pState->hDecoder)
    {
        NeAACDecPostSeekReset(pState->hDecoder, (long)pState->current_mp4_sample);
    }

    mp4_log("[mp4_aac] seek to frameIndex=%llu => mp4_sample=%u cursor=%ld\n",
            (unsigned long long)frameIndex, pState->current_mp4_sample, pState->cursor_pcm_frames);

    return MA_SUCCESS;
}

static ma_result ma_decoding_backend_get_data_format__mp4_aac(ma_data_source *pDataSource, ma_format *pFormat, ma_uint32 *pChannels, ma_uint32 *pSampleRate, ma_channel *pChannelMap, size_t channelMapCap)
{
    // Removed (void)pChannelMap; (void)channelMapCap;

    mp4_aac_decoder_state *pState = (mp4_aac_decoder_state *)pDataSource;
    if (pState == NULL)
        return MA_INVALID_ARGS;

    if (pFormat != NULL)
        *pFormat = pState->format;
    if (pChannels != NULL)
        *pChannels = pState->channels;
    if (pSampleRate != NULL)
        *pSampleRate = pState->sampleRate;
    if (pChannelMap != NULL)
        ma_channel_map_init_standard(ma_standard_channel_map_default, pChannelMap, channelMapCap, pState->channels);

    return MA_SUCCESS;
}

static ma_result ma_decoding_backend_get_cursor_in_pcm_frames__mp4_aac(ma_data_source *pDataSource, ma_uint64 *pCursor)
{
    mp4_aac_decoder_state *pState = (mp4_aac_decoder_state *)pDataSource;
    if (pState == NULL)
        return MA_INVALID_ARGS;

    if (pCursor != NULL)
        *pCursor = pState->cursor_pcm_frames;
    return MA_SUCCESS;
}

static ma_result ma_decoding_backend_get_length_in_pcm_frames__mp4_aac(ma_data_source *pDataSource, ma_uint64 *pLength)
{
    mp4_aac_decoder_state *pState = (mp4_aac_decoder_state *)pDataSource;
    if (pState == NULL)
        return MA_INVALID_ARGS;

    if (pLength != NULL)
    {
        unsigned int total = pState->use_fmp4 ? pState->fmp4_sample_count : pState->mp4_sample_count;
        // Use actual samples-per-frame if known (1024 for LC-AAC, 2048 for HE-AAC/SBR)
        unsigned int spf = (pState->samplesPerAACFrame > 0) ? pState->samplesPerAACFrame : 1024;
        *pLength = (ma_uint64)total * (ma_uint64)spf;
    }
    return MA_SUCCESS;
}

static ma_data_source_vtable g_ma_data_source_vtable_mp4_aac = {
    ma_decoding_backend_read__mp4_aac,
    ma_decoding_backend_seek__mp4_aac,
    ma_decoding_backend_get_data_format__mp4_aac,
    ma_decoding_backend_get_cursor_in_pcm_frames__mp4_aac,
    ma_decoding_backend_get_length_in_pcm_frames__mp4_aac,
    NULL,
    0};

static ma_result ma_decoding_backend_init__mp4_aac(void *pUserData, ma_read_proc onRead, ma_seek_proc onSeek, ma_tell_proc onTell, void *pReadSeekTellUserData, const ma_decoding_backend_config *pConfig, const ma_allocation_callbacks *pAllocationCallbacks, ma_data_source **ppBackend)
{
    (void)pUserData;
    (void)pConfig;
    (void)pAllocationCallbacks;

    if (onRead == NULL || onSeek == NULL)
    {
        return MA_INVALID_ARGS; // We need seeking for MP4
    }

    mp4_log("[mp4_aac] onInit called (onRead=%p onSeek=%p)\n", (void *)onRead, (void *)onSeek);

    mp4_aac_decoder_state *pState = (mp4_aac_decoder_state *)malloc(sizeof(*pState));
    if (pState == NULL)
    {
        return MA_OUT_OF_MEMORY;
    }
    memset(pState, 0, sizeof(*pState));

    pState->onRead = onRead;
    pState->onSeek = onSeek;
    pState->onTell = onTell;
    pState->pUserData = pReadSeekTellUserData;

    int64_t file_size = INT64_MAX; // safe fallback if seek-to-end fails
    {
        // Seek to end to get real file size so minimp4's EOF guard fires correctly
        // for moov-at-end M4A files. ma_seek_origin_end is supported by the
        // default VFS even though miniaudio's decoder pipeline doesn't normally use it.
        ma_result seekOk = onSeek(pReadSeekTellUserData, 0, ma_seek_origin_end);
        if (seekOk == MA_SUCCESS && onTell != NULL)
        {
            ma_int64 pos = 0;
            if (onTell(pReadSeekTellUserData, &pos) == MA_SUCCESS)
            {
                file_size = (int64_t)pos;
                mp4_log("[mp4_aac] file_size=%lld\n", (long long)file_size);
            }
        }
        // Seek back to start for minimp4
        onSeek(pReadSeekTellUserData, 0, ma_seek_origin_start);
    }

    // 1. Initialize minimp4 and open stream
    int openResult = MP4D_open(&pState->mp4_demux, mp4_read_callback, pState, file_size);
    mp4_log("[mp4_aac] MP4D_open result=%d track_count=%d\n",
            openResult, pState->mp4_demux.track_count);
    if (openResult == 0)
    {
        free(pState);
        return MA_INVALID_DATA;
    }

    // 2. Find AAC track
    pState->aac_track_id = -1;
    for (int i = 0; i < pState->mp4_demux.track_count; i++)
    {
        if (pState->mp4_demux.track[i].handler_type == MP4D_HANDLER_TYPE_SOUN)
        {
            // In a complete implementation, check object_type_indication for AAC
            pState->aac_track_id = i;
            break;
        }
    }

    if (pState->aac_track_id == -1)
    {
        mp4_log("[mp4_aac] No SOUN track found (track_count=%d)\n", pState->mp4_demux.track_count);
        MP4D_close(&pState->mp4_demux);
        free(pState);
        return MA_INVALID_DATA;
    }

    MP4D_track_t *track = &pState->mp4_demux.track[pState->aac_track_id];
    pState->mp4_sample_count = track->sample_count;

    mp4_log("[mp4_aac] aac_track_id=%d sample_count=%u dsi_bytes=%u handler=0x%x chunk_count=%u stsc_count=%u\n",
            pState->aac_track_id, pState->mp4_sample_count, track->dsi_bytes,
            (unsigned)track->handler_type,
            track->chunk_count,
            track->sample_to_chunk_count);

    // If stsz has no entries, this is a fragmented MP4 (fMP4/CMAF).
    // Scan the file for moof/traf/trun boxes to build our own sample table.
    if (pState->mp4_sample_count == 0 && file_size > 0 && file_size != INT64_MAX)
    {
        mp4_log("[mp4_aac] sample_count=0 — scanning for fMP4 moof/trun boxes (file_size=%lld)\n", (long long)file_size);
        ma_result scanResult = fmp4_scan_moof_boxes(pState, file_size);
        if (scanResult != MA_SUCCESS)
        {
            mp4_log("[mp4_aac] fMP4 scan failed — no samples, decoder will return MA_AT_END\n");
            // We continue anyway; the decoder will just return MA_AT_END immediately
        }
    }

    // 3. Initialize FAAD2
    pState->hDecoder = NeAACDecOpen();
    if (!pState->hDecoder)
    {
        MP4D_close(&pState->mp4_demux);
        free(pState);
        return MA_ERROR;
    }

    // Configure FAAD to output 16-bit signed integers.
    // NOTE: FAAD2 on MSVC (without FIXED_POINT) ignores FAAD_FMT_FLOAT and silently
    // returns int16 anyway. Explicitly request int16 and convert to float ourselves.
    NeAACDecConfigurationPtr conf = NeAACDecGetCurrentConfiguration(pState->hDecoder);
    conf->outputFormat = FAAD_FMT_16BIT;
    NeAACDecSetConfiguration(pState->hDecoder, conf);

    // Initialise decoder using DSI from MP4
    unsigned char *dsi = track->dsi;
    unsigned int dsi_size = track->dsi_bytes;

    unsigned long samplerate;
    unsigned char channels;

    // Log DSI bytes for diagnostics
    {
        char dsi_hex[64] = {0};
        int dsi_hex_pos = 0;
        for (unsigned int di = 0; di < dsi_size && di < 16 && dsi_hex_pos < 60; di++)
            dsi_hex_pos += snprintf(dsi_hex + dsi_hex_pos, sizeof(dsi_hex) - dsi_hex_pos, "%02x ", dsi[di]);
        mp4_log("[mp4_aac] DSI raw (%u bytes): %s\n", dsi_size, dsi_hex);
    }

    if (dsi && dsi_size > 0)
    {
        // minimp4 zero-pads track->dsi to its allocated buffer size.
        // NeAACDecInit2 expects the exact raw AudioSpecificConfig bytes (typically 2-5 bytes).
        // Passing trailing zeros causes FAAD2 to misparse the config and output silence.
        // Fix: strip trailing zero bytes to find the true end of the ASC.
        unsigned int true_dsi_size = dsi_size;
        while (true_dsi_size > 1 && dsi[true_dsi_size - 1] == 0)
            true_dsi_size--;
        if (true_dsi_size != dsi_size)
            mp4_log("[mp4_aac] stripped %u trailing zero bytes from DSI: %u -> %u bytes\n",
                    dsi_size - true_dsi_size, dsi_size, true_dsi_size);

        int initResult = NeAACDecInit2(pState->hDecoder, dsi, true_dsi_size, &samplerate, &channels);
        mp4_log("[mp4_aac] NeAACDecInit2 result=%d samplerate=%lu channels=%u\n",
                initResult, samplerate, (unsigned)channels);
        
        if (initResult < 0)
        {
            NeAACDecClose(pState->hDecoder);
            MP4D_close(&pState->mp4_demux);
            free(pState);
            return MA_ERROR;
        }
    }
    else
    {
        // Fallback: decode first frame to init
        unsigned int frame_bytes, timestamp, duration;
        unsigned int offset = MP4D_frame_offset(&pState->mp4_demux, pState->aac_track_id, 0, &frame_bytes, &timestamp, &duration);

        unsigned char *tempBuf = (unsigned char *)malloc(frame_bytes);
        if (pState->onSeek)
            pState->onSeek(pState->pUserData, offset, ma_seek_origin_start);
        size_t bytesRead = 0;
        if (pState->onRead)
            pState->onRead(pState->pUserData, tempBuf, frame_bytes, &bytesRead);

        long initResult = NeAACDecInit(pState->hDecoder, tempBuf, frame_bytes, &samplerate, &channels);
        free(tempBuf);

        mp4_log("[mp4_aac] NeAACDecInit (fallback) result=%ld samplerate=%lu channels=%u\n",
                initResult, samplerate, (unsigned)channels);

        if (initResult < 0)
        {
            NeAACDecClose(pState->hDecoder);
            MP4D_close(&pState->mp4_demux);
            free(pState);
            return MA_ERROR;
        }
    }

    pState->format = ma_format_f32;
    pState->channels = channels;
    pState->sampleRate = samplerate;
    pState->current_mp4_sample = 0;

    mp4_log("[mp4_aac] Init SUCCESS: sample_count=%u samplerate=%u channels=%u\n",
            pState->mp4_sample_count, pState->sampleRate, pState->channels);

    ma_data_source_config baseConfig = ma_data_source_config_init();
    baseConfig.vtable = &g_ma_data_source_vtable_mp4_aac;
    ma_result result = ma_data_source_init(&baseConfig, &pState->ds);
    if (result != MA_SUCCESS)
    {
        NeAACDecClose(pState->hDecoder);
        MP4D_close(&pState->mp4_demux);
        free(pState);
        return result;
    }

    *ppBackend = (ma_data_source *)pState;
    return MA_SUCCESS;
}

static void ma_decoding_backend_uninit__mp4_aac(void *pUserData, ma_data_source *pBackend, const ma_allocation_callbacks *pAllocationCallbacks)
{
    (void)pUserData;
    (void)pAllocationCallbacks;

    mp4_aac_decoder_state *pState = (mp4_aac_decoder_state *)pBackend;
    if (pState == NULL)
        return;

    ma_data_source_uninit(&pState->ds);

    if (pState->hDecoder)
        NeAACDecClose(pState->hDecoder);
    MP4D_close(&pState->mp4_demux);

    if (pState->fmp4_samples)
        free(pState->fmp4_samples);
    if (pState->pDecodedBuffer)
        free(pState->pDecodedBuffer);
    if (pState->pPayloadBuffer)
        free(pState->pPayloadBuffer);

    free(pState);
}

ma_decoding_backend_vtable g_ma_decoding_backend_vtable_mp4_aac = {
    ma_decoding_backend_init__mp4_aac,
    NULL, // onInitFile
    NULL, // onInitFileW
    NULL, // onInitMemory
    ma_decoding_backend_uninit__mp4_aac};
