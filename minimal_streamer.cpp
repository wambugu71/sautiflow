/*
 * minimal_streamer.cpp
 *
 * Buffered network audio playback with:
 *   - libcurl (HTTP producer)
 *   - miniaudio decoder + playback
 *   - ma_rb for encoded bytes
 *   - ma_pcm_rb for decoded PCM frames
 */

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#include <curl/curl.h>

#include <atomic>
#include <chrono>
#include <condition_variable>
#include <cstring>
#include <iostream>
#include <mutex>
#include <thread>

#define FORMAT ma_format_f32
#define CHANNELS 2
#define SAMPLE_RATE 44100

#define ENCODED_BUFFER_SIZE (1024 * 1024) /* 1MB encoded jitter buffer */
#define PCM_BUFFER_SIZE (SAMPLE_RATE * 8) /* 8 seconds PCM */
#define DECODE_CHUNK_FRAMES 1024

#define STREAM_URL "https://cdn400.savetube.vip/media/60ItHLz5WEA/alan-walker-faded-128-ytshorts.savetube.me.mp3" //"http://stream.radioparadise.com/mp3-128"

struct AudioContext
{
    ma_rb encodedRB;
    ma_pcm_rb pcmRB;
    ma_decoder decoder;
    ma_device device;

    std::mutex encodedMutex;
    std::condition_variable encodedCv;

    std::atomic<bool> decoderInitialized{false};
    std::atomic<bool> playbackStarted{false};
    std::atomic<bool> networkDone{false};
    std::atomic<bool> stopRequested{false};
    std::atomic<bool> hasError{false};
};

static ma_result decoder_on_read(ma_decoder *pDecoder, void *pBufferOut, size_t bytesToRead, size_t *pBytesRead)
{
    AudioContext *ctx = (AudioContext *)pDecoder->pUserData;
    if (ctx == nullptr)
        return MA_INVALID_ARGS;

    if (pBytesRead == nullptr)
        return MA_INVALID_ARGS;

    *pBytesRead = 0;
    size_t totalRead = 0;

    while (totalRead < bytesToRead)
    {
        void *pRead = nullptr;
        size_t toRead = bytesToRead - totalRead;

        if (ma_rb_acquire_read(&ctx->encodedRB, &toRead, &pRead) == MA_SUCCESS && toRead > 0)
        {
            std::memcpy((char *)pBufferOut + totalRead, pRead, toRead);
            ma_rb_commit_read(&ctx->encodedRB, toRead);
            totalRead += toRead;
            continue;
        }

        if (ctx->stopRequested || (ctx->networkDone && ma_rb_available_read(&ctx->encodedRB) == 0))
            break;

        std::unique_lock<std::mutex> lk(ctx->encodedMutex);
        ctx->encodedCv.wait_for(lk, std::chrono::milliseconds(50));
    }

    *pBytesRead = totalRead;
    return MA_SUCCESS;
}

static ma_result decoder_on_seek(ma_decoder *, ma_int64, ma_seek_origin)
{
    return MA_SUCCESS;
}

static size_t curl_on_write(char *contents, size_t size, size_t nmemb, void *userp)
{
    AudioContext *ctx = (AudioContext *)userp;
    if (ctx == nullptr)
        return 0;

    const size_t total = size * nmemb;
    size_t written = 0;

    while (written < total && !ctx->stopRequested)
    {
        void *pWrite = nullptr;
        size_t toWrite = total - written;

        if (ma_rb_acquire_write(&ctx->encodedRB, &toWrite, &pWrite) == MA_SUCCESS && toWrite > 0)
        {
            std::memcpy(pWrite, contents + written, toWrite);
            ma_rb_commit_write(&ctx->encodedRB, toWrite);
            written += toWrite;
            ctx->encodedCv.notify_one();
            continue;
        }

        std::this_thread::sleep_for(std::chrono::milliseconds(2));
    }

    return written;
}

static int curl_on_progress(void *clientp, curl_off_t, curl_off_t, curl_off_t, curl_off_t)
{
    AudioContext *ctx = (AudioContext *)clientp;
    return (ctx != nullptr && ctx->stopRequested) ? 1 : 0;
}

static void device_on_data(ma_device *pDevice, void *pOutput, const void *, ma_uint32 frameCount)
{
    AudioContext *ctx = (AudioContext *)pDevice->pUserData;
    const ma_uint32 bytesPerFrame = ma_get_bytes_per_frame(pDevice->playback.format, pDevice->playback.channels);

    ma_uint32 framesRead = frameCount;
    void *pRead = nullptr;
    if (ma_pcm_rb_acquire_read(&ctx->pcmRB, &framesRead, &pRead) == MA_SUCCESS && framesRead > 0)
    {
        std::memcpy(pOutput, pRead, framesRead * bytesPerFrame);
        ma_pcm_rb_commit_read(&ctx->pcmRB, framesRead);
    }
    else
    {
        framesRead = 0;
    }

    if (framesRead < frameCount)
    {
        std::memset((char *)pOutput + framesRead * bytesPerFrame, 0, (frameCount - framesRead) * bytesPerFrame);
    }
}

int main()
{
    AudioContext ctx{};
    std::cout << "Initializing buffered streamer..." << std::endl;

    if (ma_rb_init(ENCODED_BUFFER_SIZE, nullptr, nullptr, &ctx.encodedRB) != MA_SUCCESS)
    {
        std::cerr << "Failed to initialize encoded ring buffer." << std::endl;
        return 1;
    }

    if (ma_pcm_rb_init(FORMAT, CHANNELS, PCM_BUFFER_SIZE, nullptr, nullptr, &ctx.pcmRB) != MA_SUCCESS)
    {
        std::cerr << "Failed to initialize PCM ring buffer." << std::endl;
        ma_rb_uninit(&ctx.encodedRB);
        return 1;
    }

    ma_device_config deviceConfig = ma_device_config_init(ma_device_type_playback);
    deviceConfig.playback.format = FORMAT;
    deviceConfig.playback.channels = CHANNELS;
    deviceConfig.sampleRate = SAMPLE_RATE;
    deviceConfig.dataCallback = device_on_data;
    deviceConfig.pUserData = &ctx;

    if (ma_device_init(nullptr, &deviceConfig, &ctx.device) != MA_SUCCESS)
    {
        std::cerr << "Failed to open playback device." << std::endl;
        ma_pcm_rb_uninit(&ctx.pcmRB);
        ma_rb_uninit(&ctx.encodedRB);
        return 1;
    }

    if (curl_global_init(CURL_GLOBAL_DEFAULT) != CURLE_OK)
    {
        std::cerr << "curl_global_init failed." << std::endl;
        ma_device_uninit(&ctx.device);
        ma_pcm_rb_uninit(&ctx.pcmRB);
        ma_rb_uninit(&ctx.encodedRB);
        return 1;
    }

    std::thread networkThread([&ctx]()
                              {
        std::cerr << "[NetworkThread] started" << std::endl;
        CURL *curl = curl_easy_init();
        if (curl == nullptr)
        {
            ctx.hasError = true;
            ctx.networkDone = true;
            ctx.encodedCv.notify_all();
            return;
        }

        curl_easy_setopt(curl, CURLOPT_URL, STREAM_URL);
        curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
        curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 10L);
        curl_easy_setopt(curl, CURLOPT_TIMEOUT, 0L);
        curl_easy_setopt(curl, CURLOPT_FAILONERROR, 1L);
        curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, curl_on_write);
        curl_easy_setopt(curl, CURLOPT_WRITEDATA, &ctx);

        curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
        curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, curl_on_progress);
        curl_easy_setopt(curl, CURLOPT_XFERINFODATA, &ctx);

        std::cout << "[Network] " << STREAM_URL << std::endl;
        CURLcode rc = curl_easy_perform(curl);
        if (rc != CURLE_OK && !ctx.stopRequested)
        {
            std::cerr << "[Network] " << curl_easy_strerror(rc) << std::endl;
            ctx.hasError = true;
        }

        curl_easy_cleanup(curl);
        ctx.networkDone = true;
        ctx.encodedCv.notify_all();
        std::cerr << "[NetworkThread] done" << std::endl; });

    std::thread decodeThread([&ctx]()
                             {
        std::cerr << "[DecodeThread] started" << std::endl;
        const size_t initPrebufferBytes = 64 * 1024;
        while (!ctx.stopRequested && !ctx.networkDone && ma_rb_available_read(&ctx.encodedRB) < initPrebufferBytes)
        {
            std::unique_lock<std::mutex> lk(ctx.encodedMutex);
            ctx.encodedCv.wait_for(lk, std::chrono::milliseconds(50));
        }

        ma_decoder_config cfgMP3 = ma_decoder_config_init(FORMAT, CHANNELS, SAMPLE_RATE);
        cfgMP3.encodingFormat = ma_encoding_format_mp3;
        ma_result initRes = ma_decoder_init(decoder_on_read, decoder_on_seek, &ctx, &cfgMP3, &ctx.decoder);

        if (initRes != MA_SUCCESS)
        {
            ma_decoder_config cfgVorbis = ma_decoder_config_init(FORMAT, CHANNELS, SAMPLE_RATE);
            cfgVorbis.encodingFormat = ma_encoding_format_vorbis;
            initRes = ma_decoder_init(decoder_on_read, decoder_on_seek, &ctx, &cfgVorbis, &ctx.decoder);
        }

        if (initRes != MA_SUCCESS)
        {
            std::cerr << "[Decoder] init failed: " << initRes << std::endl;
            ctx.hasError = true;
            return;
        }

        ctx.decoderInitialized = true;
        std::cout << "[Decoder] initialized" << std::endl;

        const ma_uint32 bytesPerFrame = ma_get_bytes_per_frame(FORMAT, CHANNELS);
        char localPCM[DECODE_CHUNK_FRAMES * 8 /* f32 stereo max 8 bytes/frame */] = {};

        while (!ctx.stopRequested)
        {
            ma_uint32 writable = DECODE_CHUNK_FRAMES;
            void *pWrite = nullptr;
            if (ma_pcm_rb_acquire_write(&ctx.pcmRB, &writable, &pWrite) != MA_SUCCESS || writable == 0)
            {
                std::this_thread::sleep_for(std::chrono::milliseconds(2));
                continue;
            }

            ma_uint64 framesRead = 0;
            ma_result rr = ma_decoder_read_pcm_frames(&ctx.decoder, localPCM, writable, &framesRead);
            if (rr != MA_SUCCESS && rr != MA_AT_END)
            {
                std::cerr << "[Decoder] read failed: " << rr << std::endl;
                ma_pcm_rb_commit_write(&ctx.pcmRB, 0);
                ctx.hasError = true;
                break;
            }

            if (framesRead > 0)
            {
                std::memcpy(pWrite, localPCM, (size_t)framesRead * bytesPerFrame);
                ma_pcm_rb_commit_write(&ctx.pcmRB, (ma_uint32)framesRead);
            }
            else
            {
                ma_pcm_rb_commit_write(&ctx.pcmRB, 0);
                if (ctx.networkDone && ma_rb_available_read(&ctx.encodedRB) == 0)
                    break;
                std::this_thread::sleep_for(std::chrono::milliseconds(5));
            }
        }

        ma_decoder_uninit(&ctx.decoder);
        std::cerr << "[DecodeThread] done" << std::endl; });

    const ma_uint32 prebufferFrames = PCM_BUFFER_SIZE / 2;
    std::cout << "[State] prebuffering 50%..." << std::endl;
    while (!ctx.stopRequested && !ctx.hasError)
    {
        if (ctx.decoderInitialized && ma_pcm_rb_available_read(&ctx.pcmRB) >= prebufferFrames)
        {
            if (ma_device_start(&ctx.device) == MA_SUCCESS)
            {
                ctx.playbackStarted = true;
                std::cout << "[State] playback started" << std::endl;
            }
            else
            {
                std::cerr << "Failed to start playback device." << std::endl;
                ctx.hasError = true;
            }
            break;
        }

        if (ctx.networkDone && ma_pcm_rb_available_read(&ctx.pcmRB) == 0)
            break;

        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }

    if (!ctx.hasError)
    {
        std::cout << "Press ENTER to stop..." << std::endl;
        (void)getchar();
    }

    ctx.stopRequested = true;
    ctx.encodedCv.notify_all();

    if (networkThread.joinable())
        networkThread.join();
    if (decodeThread.joinable())
        decodeThread.join();

    ma_device_uninit(&ctx.device);
    ma_pcm_rb_uninit(&ctx.pcmRB);
    ma_rb_uninit(&ctx.encodedRB);
    curl_global_cleanup();

    std::cout << "[Exit] hasError=" << (ctx.hasError ? "true" : "false")
              << " networkDone=" << (ctx.networkDone ? "true" : "false")
              << " playbackStarted=" << (ctx.playbackStarted ? "true" : "false")
              << std::endl;

    return ctx.hasError ? 1 : 0;
}
