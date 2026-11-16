#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
#include "dsd_processor.h"

#include <cassert>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <string>
#include <vector>

using namespace sautiflow::dsd;

namespace {

inline void pushLe16(std::vector<uint8_t>& out, uint16_t v) {
    out.push_back(static_cast<uint8_t>(v & 0xFFu));
    out.push_back(static_cast<uint8_t>((v >> 8) & 0xFFu));
}

inline void pushLe32(std::vector<uint8_t>& out, uint32_t v) {
    out.push_back(static_cast<uint8_t>(v & 0xFFu));
    out.push_back(static_cast<uint8_t>((v >> 8) & 0xFFu));
    out.push_back(static_cast<uint8_t>((v >> 16) & 0xFFu));
    out.push_back(static_cast<uint8_t>((v >> 24) & 0xFFu));
}

inline void pushLe64(std::vector<uint8_t>& out, uint64_t v) {
    for (int i = 0; i < 8; ++i) {
        out.push_back(static_cast<uint8_t>((v >> (8 * i)) & 0xFFu));
    }
}

inline void pushBe16(std::vector<uint8_t>& out, uint16_t v) {
    out.push_back(static_cast<uint8_t>((v >> 8) & 0xFFu));
    out.push_back(static_cast<uint8_t>(v & 0xFFu));
}

inline void pushBe32(std::vector<uint8_t>& out, uint32_t v) {
    out.push_back(static_cast<uint8_t>((v >> 24) & 0xFFu));
    out.push_back(static_cast<uint8_t>((v >> 16) & 0xFFu));
    out.push_back(static_cast<uint8_t>((v >> 8) & 0xFFu));
    out.push_back(static_cast<uint8_t>(v & 0xFFu));
}

inline void pushBe64(std::vector<uint8_t>& out, uint64_t v) {
    for (int i = 7; i >= 0; --i) {
        out.push_back(static_cast<uint8_t>((v >> (8 * i)) & 0xFFu));
    }
}

inline void pushFourCC(std::vector<uint8_t>& out, const char tag[4]) {
    out.insert(out.end(), tag, tag + 4);
}

inline void encodeSyncsafe32(uint8_t* dst, uint32_t val) {
    dst[0] = static_cast<uint8_t>((val >> 21) & 0x7Fu);
    dst[1] = static_cast<uint8_t>((val >> 14) & 0x7Fu);
    dst[2] = static_cast<uint8_t>((val >> 7) & 0x7Fu);
    dst[3] = static_cast<uint8_t>(val & 0x7Fu);
}

std::vector<uint8_t> makeId3v23TextFrame(const char id[4], const std::string& text) {
    std::vector<uint8_t> f;
    pushFourCC(f, id);
    const uint32_t payloadSize = 1u + static_cast<uint32_t>(text.size()); // UTF-8 encoding byte = 0x03
    pushBe32(f, payloadSize);
    pushBe16(f, 0); // flags
    f.push_back(0x03); // UTF-8
    f.insert(f.end(), text.begin(), text.end());
    return f;
}

std::vector<uint8_t> makeId3v23TxxxFrame(const std::string& desc, const std::string& val) {
    std::vector<uint8_t> f;
    pushFourCC(f, "TXXX");
    const uint32_t payloadSize = 1u + static_cast<uint32_t>(desc.size()) + 1u + static_cast<uint32_t>(val.size());
    pushBe32(f, payloadSize);
    pushBe16(f, 0);
    f.push_back(0x03); // UTF-8
    f.insert(f.end(), desc.begin(), desc.end());
    f.push_back(0x00);
    f.insert(f.end(), val.begin(), val.end());
    return f;
}

std::vector<uint8_t> makeId3v23ApicFrame(const std::string& mime, const std::vector<uint8_t>& imgBytes) {
    std::vector<uint8_t> f;
    pushFourCC(f, "APIC");
    const uint32_t payloadSize =
        1u + static_cast<uint32_t>(mime.size()) + 1u + 1u + 1u + static_cast<uint32_t>(imgBytes.size());
    pushBe32(f, payloadSize);
    pushBe16(f, 0);
    f.push_back(0x00); // ISO-8859-1
    f.insert(f.end(), mime.begin(), mime.end());
    f.push_back(0x00);
    f.push_back(0x03); // Front cover
    f.push_back(0x00); // empty description
    f.insert(f.end(), imgBytes.begin(), imgBytes.end());
    return f;
}

std::vector<uint8_t> buildTestId3v2Tag() {
    std::vector<uint8_t> frames;
    auto append = [&](const std::vector<uint8_t>& fr) {
        frames.insert(frames.end(), fr.begin(), fr.end());
    };
    append(makeId3v23TextFrame("TIT2", "Kind of Blue (DSD)"));
    append(makeId3v23TextFrame("TPE1", "Miles Davis"));
    append(makeId3v23TextFrame("TALB", "Kind of Blue"));
    append(makeId3v23TextFrame("TRCK", "01/05"));
    append(makeId3v23TxxxFrame("replaygain_track_gain", "-4.25 dB"));
    append(makeId3v23TxxxFrame("replaygain_track_peak", "0.875000"));
    append(makeId3v23TxxxFrame("replaygain_album_gain", "-3.50 dB"));
    append(makeId3v23ApicFrame("image/png", {0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A}));

    std::vector<uint8_t> tag;
    tag.push_back('I');
    tag.push_back('D');
    tag.push_back('3');
    tag.push_back(0x03); // v2.3
    tag.push_back(0x00);
    tag.push_back(0x00);
    uint8_t ss[4]{};
    encodeSyncsafe32(ss, static_cast<uint32_t>(frames.size()));
    tag.insert(tag.end(), ss, ss + 4);
    tag.insert(tag.end(), frames.begin(), frames.end());
    return tag;
}

// Generates a 1st-order delta-sigma modulated bitstream for a 1 kHz sine wave (MSB-first bytes).
std::vector<uint8_t> generateSigmaDeltaSineMsb(
    uint32_t dsdRate,
    double freqHz,
    double amplitude,
    uint32_t totalBytesPerCh
) {
    std::vector<uint8_t> out(totalBytesPerCh, kDsdSilenceByte);
    double integrator = 0.0;
    const double twoPiOverRate = 2.0 * 3.14159265358979323846 * freqHz / static_cast<double>(dsdRate);
    uint64_t sampleIdx = 0;

    for (uint32_t b = 0; b < totalBytesPerCh; ++b) {
        uint8_t byteVal = 0;
        for (int bit = 7; bit >= 0; --bit) {
            const double x = amplitude * std::sin(twoPiOverRate * static_cast<double>(sampleIdx++));
            const double y = (integrator + x >= 0.0) ? 1.0 : -1.0;
            integrator += (x - y);
            if (y > 0.0) {
                byteVal |= static_cast<uint8_t>(1u << bit);
            }
        }
        out[b] = byteVal;
    }
    return out;
}

bool writeSyntheticDsfFile(
    const char* path,
    uint32_t dsdRate,
    uint32_t channels,
    uint32_t bitsPerSample,
    const std::vector<uint8_t>& ch0MsbBytes,
    const std::vector<uint8_t>& ch1MsbBytes,
    const std::vector<uint8_t>* id3Tag
) {
    const uint32_t blockSize = 4096u;
    const uint64_t byteLen = ch0MsbBytes.size();
    const uint32_t numBlocks = static_cast<uint32_t>((byteLen + blockSize - 1u) / blockSize);
    const uint64_t dataPayloadSize = static_cast<uint64_t>(numBlocks) * channels * blockSize;
    const uint64_t dataChunkSize = 12ull + dataPayloadSize;
    const uint64_t dsdChunkSize = 28ull;
    const uint64_t fmtChunkSize = 52ull;
    const uint64_t id3Offset = id3Tag ? (dsdChunkSize + fmtChunkSize + dataChunkSize) : 0ull;
    const uint64_t totalSize = dsdChunkSize + fmtChunkSize + dataChunkSize + (id3Tag ? id3Tag->size() : 0ull);

    std::vector<uint8_t> buf;
    buf.reserve(static_cast<size_t>(totalSize));

    // 'DSD ' chunk (28 bytes)
    pushFourCC(buf, "DSD ");
    pushLe64(buf, dsdChunkSize);
    pushLe64(buf, totalSize);
    pushLe64(buf, id3Offset);

    // 'fmt ' chunk (52 bytes)
    pushFourCC(buf, "fmt ");
    pushLe64(buf, fmtChunkSize);
    pushLe32(buf, 1u); // formatVersion
    pushLe32(buf, 0u); // formatId (DSD raw)
    pushLe32(buf, (channels == 1) ? 1u : 2u); // channelType
    pushLe32(buf, channels);
    pushLe32(buf, dsdRate);
    pushLe32(buf, bitsPerSample); // 1 = LSB-first, 8 = MSB-first
    pushLe64(buf, byteLen * 8ull); // sampleCount per channel
    pushLe32(buf, blockSize);
    pushLe32(buf, 0u); // reserved

    // 'data' chunk
    pushFourCC(buf, "data");
    pushLe64(buf, dataChunkSize);
    for (uint32_t blk = 0; blk < numBlocks; ++blk) {
        for (uint32_t ch = 0; ch < channels; ++ch) {
            const auto& src = (ch == 0) ? ch0MsbBytes : ch1MsbBytes;
            for (uint32_t i = 0; i < blockSize; ++i) {
                uint64_t idx = static_cast<uint64_t>(blk) * blockSize + i;
                uint8_t msbByte = (idx < src.size()) ? src[static_cast<size_t>(idx)] : kDsdSilenceByte;
                buf.push_back((bitsPerSample == 1u) ? kBitReverseTable[msbByte] : msbByte);
            }
        }
    }

    if (id3Tag) {
        buf.insert(buf.end(), id3Tag->begin(), id3Tag->end());
    }

    FILE* fp = std::fopen(path, "wb");
    if (!fp) return false;
    bool ok = (std::fwrite(buf.data(), 1, buf.size(), fp) == buf.size());
    std::fclose(fp);
    return ok;
}

bool writeSyntheticDffFile(
    const char* path,
    uint32_t dsdRate,
    uint32_t channels,
    const std::vector<uint8_t>& ch0MsbBytes,
    const std::vector<uint8_t>& ch1MsbBytes,
    bool dstCompressed,
    const std::vector<uint8_t>* id3Tag
) {
    // Build subchunks first to measure PROP and FRM8 lengths.
    std::vector<uint8_t> propSub;
    pushFourCC(propSub, "SND ");
    // FS chunk: 12 + 4 bytes
    pushFourCC(propSub, "FS  ");
    pushBe64(propSub, 4ull);
    pushBe32(propSub, dsdRate);
    // CHNL chunk: 12 + 2 + 4*channels bytes
    pushFourCC(propSub, "CHNL");
    pushBe64(propSub, 2ull + 4ull * channels);
    pushBe16(propSub, static_cast<uint16_t>(channels));
    for (uint32_t c = 0; c < channels; ++c) {
        pushFourCC(propSub, (c == 0) ? "SLFT" : "SRGT");
    }
    // CMPR chunk: 12 + 4 bytes
    pushFourCC(propSub, "CMPR");
    pushBe64(propSub, 4ull);
    pushFourCC(propSub, dstCompressed ? "DST " : "DSD ");

    // Build DIIN chunk with DIAR and DITI
    std::vector<uint8_t> diinSub;
    {
        const std::string artist = "Miles Davis (DFF)";
        pushFourCC(diinSub, "DIAR");
        pushBe64(diinSub, 4ull + artist.size());
        pushBe32(diinSub, static_cast<uint32_t>(artist.size()));
        diinSub.insert(diinSub.end(), artist.begin(), artist.end());
        if (diinSub.size() & 1u) diinSub.push_back(0);
    }

    // Interleaved DSD audio payload
    std::vector<uint8_t> dsdAudio;
    dsdAudio.resize(ch0MsbBytes.size() * channels);
    for (size_t i = 0; i < ch0MsbBytes.size(); ++i) {
        dsdAudio[i * channels] = ch0MsbBytes[i];
        if (channels > 1) {
            dsdAudio[i * channels + 1] = ch1MsbBytes[i];
        }
    }

    std::vector<uint8_t> body;
    pushFourCC(body, "DSD ");
    // FVER chunk
    pushFourCC(body, "FVER");
    pushBe64(body, 4ull);
    pushBe32(body, 0x01050000u);
    // PROP chunk
    pushFourCC(body, "PROP");
    pushBe64(body, propSub.size());
    body.insert(body.end(), propSub.begin(), propSub.end());
    // Audio chunk ("DSD " or "DST ")
    pushFourCC(body, dstCompressed ? "DST " : "DSD ");
    pushBe64(body, dsdAudio.size());
    body.insert(body.end(), dsdAudio.begin(), dsdAudio.end());
    if (body.size() & 1u) body.push_back(0);
    // DIIN chunk
    pushFourCC(body, "DIIN");
    pushBe64(body, diinSub.size());
    body.insert(body.end(), diinSub.begin(), diinSub.end());
    if (body.size() & 1u) body.push_back(0);
    // Optional ID3 chunk
    if (id3Tag) {
        pushFourCC(body, "ID3 ");
        pushBe64(body, id3Tag->size());
        body.insert(body.end(), id3Tag->begin(), id3Tag->end());
        if (body.size() & 1u) body.push_back(0);
    }

    std::vector<uint8_t> file;
    pushFourCC(file, "FRM8");
    pushBe64(file, body.size());
    file.insert(file.end(), body.begin(), body.end());

    FILE* fp = std::fopen(path, "wb");
    if (!fp) return false;
    bool ok = (std::fwrite(file.data(), 1, file.size(), fp) == file.size());
    std::fclose(fp);
    return ok;
}

double dftMagAtHz(const std::vector<float>& mono, double sampleRate, double targetHz) {
    double re = 0.0, im = 0.0;
    const size_t n = mono.size();
    const double w = 2.0 * 3.14159265358979323846 * targetHz / sampleRate;
    for (size_t i = 0; i < n; ++i) {
        re += static_cast<double>(mono[i]) * std::cos(w * static_cast<double>(i));
        im -= static_cast<double>(mono[i]) * std::sin(w * static_cast<double>(i));
    }
    return std::sqrt(re * re + im * im) * 2.0 / static_cast<double>(n);
}

void testDsfParsingAndMetadata() {
    const char* path = "build/test_synth_dsd64.dsf";
    auto id3 = buildTestId3v2Tag();
    // 1 second? Keep test fast: 44100 bytes per ch (= 0.125s at DSD64: 2822400/8 = 352800 B/s)
    const uint32_t bytesPerCh = 44100u;
    auto ch0 = generateSigmaDeltaSineMsb(2822400u, 1000.0, 0.5, bytesPerCh);
    std::vector<uint8_t> ch1(bytesPerCh, kDsdSilenceByte);

    assert(writeSyntheticDsfFile(path, 2822400u, 2u, 1u, ch0, ch1, &id3));

    DsdFileHeader hdr = parse_dsd_file_header_utf8(path);
    assert(hdr.valid);
    assert(hdr.container == DsdContainerType::Dsf);
    assert(!hdr.isDstCompressed);
    assert(hdr.bitsLsbFirst);
    assert(hdr.blockInterleaved);
    assert(hdr.channels == 2u);
    assert(hdr.dsdSampleRate == 2822400u);
    assert(hdr.blockSizePerChannel == 4096u);
    assert(std::abs(hdr.durationSeconds() - 0.125) < 1e-4);

    DsdMetadata meta = read_dsd_file_metadata_utf8(path);
    assert(meta.valid);
    assert(meta.title == "Kind of Blue (DSD)");
    assert(meta.artist == "Miles Davis");
    assert(meta.album == "Kind of Blue");
    assert(meta.trackNumber == 1);
    assert(meta.hasReplayGainTrack);
    assert(std::abs(meta.replayGainTrackDb - (-4.25f)) < 0.01f);
    assert(std::abs(meta.replayGainTrackPeak - 0.875f) < 0.01f);
    assert(meta.hasReplayGainAlbum);
    assert(std::abs(meta.replayGainAlbumDb - (-3.50f)) < 0.01f);
    assert(meta.pictureMimeType == "image/png");
    assert(meta.pictureData.size() == 8u);

    std::remove(path);
    std::printf("[PASS] testDsfParsingAndMetadata\n");
}

void testDffParsingAndDstRejection() {
    const char* dffPath = "build/test_synth_dsd128.dff";
    const char* dstPath = "build/test_synth_dst.dff";
    auto id3 = buildTestId3v2Tag();
    const uint32_t bytesPerCh = 35280u;
    std::vector<uint8_t> ch0(bytesPerCh, 0xAAu);
    std::vector<uint8_t> ch1(bytesPerCh, 0x55u);

    assert(writeSyntheticDffFile(dffPath, 5644800u, 2u, ch0, ch1, false, &id3));
    DsdFileHeader hdr = parse_dsd_file_header_utf8(dffPath);
    assert(hdr.valid);
    assert(hdr.container == DsdContainerType::Dff);
    assert(!hdr.isDstCompressed);
    assert(!hdr.bitsLsbFirst);
    assert(hdr.channels == 2u);
    assert(hdr.dsdSampleRate == 5644800u);

    DsdMetadata meta = read_dsd_file_metadata_utf8(dffPath);
    assert(meta.valid);
    assert(meta.title == "Kind of Blue (DSD)");

    // DST-compressed DFF must be flagged and rejected cleanly
    assert(writeSyntheticDffFile(dstPath, 2822400u, 2u, ch0, ch1, true, nullptr));
    DsdFileHeader dstHdr = parse_dsd_file_header_utf8(dstPath);
    assert(dstHdr.isDstCompressed);
    assert(!dstHdr.valid);

    std::remove(dffPath);
    std::remove(dstPath);
    std::printf("[PASS] testDffParsingAndDstRejection\n");
}

void testDecimatorSilenceSineBoostAndDsd512() {
    // 1. Silence (0x69 bytes) -> near-zero PCM output
    {
        DsdToPcmDecimator dec;
        assert(dec.init(2822400u, 88200u, 2u, 6.0f));
        assert(dec.isExactIntegerBytes());
        assert(dec.bytesPerOutFrame() == 4u);

        const uint64_t pcmFrames = 512u;
        std::vector<uint8_t> sil(static_cast<size_t>(pcmFrames * dec.bytesPerOutFrame() * 2u), kDsdSilenceByte);
        std::vector<float> out(static_cast<size_t>(pcmFrames * 2u), 0.0f);
        dec.decimateExact(sil.data(), out.data(), pcmFrames);

        float maxAbs = 0.0f;
        for (float s : out) {
            maxAbs = std::max(maxAbs, std::abs(s));
        }
        assert(maxAbs < 1e-4f);
    }

    // 2. 1 kHz modulated DSD64 sine -> accurate reconstruction & +6 dB Scarlet Book boost
    {
        const uint32_t outFrames = 4410u; // 50 ms at 88.2kHz
        const uint32_t bytesPerCh = outFrames * 4u;
        auto ch0 = generateSigmaDeltaSineMsb(2822400u, 1000.0, 0.45, bytesPerCh);
        std::vector<uint8_t> interleaved(static_cast<size_t>(bytesPerCh * 2u), kDsdSilenceByte);
        for (uint32_t i = 0; i < bytesPerCh; ++i) {
            interleaved[static_cast<size_t>(i) * 2u] = ch0[i];
        }

        DsdToPcmDecimator dec0dB, dec6dB;
        assert(dec0dB.init(2822400u, 88200u, 2u, 0.0f));
        assert(dec6dB.init(2822400u, 88200u, 2u, 6.0f));

        std::vector<float> out0(static_cast<size_t>(outFrames * 2u));
        std::vector<float> out6(static_cast<size_t>(outFrames * 2u));
        dec0dB.decimateExact(interleaved.data(), out0.data(), outFrames);
        dec6dB.decimateExact(interleaved.data(), out6.data(), outFrames);

        std::vector<float> mono0(outFrames - 256u), mono6(outFrames - 256u);
        for (uint32_t i = 256u; i < outFrames; ++i) {
            mono0[i - 256u] = out0[static_cast<size_t>(i) * 2u];
            mono6[i - 256u] = out6[static_cast<size_t>(i) * 2u];
        }

        const double mag0_1k = dftMagAtHz(mono0, 88200.0, 1000.0);
        const double mag6_1k = dftMagAtHz(mono6, 88200.0, 1000.0);
        const double mag6_35k = dftMagAtHz(mono6, 88200.0, 35000.0);
        assert(mag0_1k > 0.35 && mag0_1k < 0.55);
        const double ratio = mag6_1k / mag0_1k;
        assert(std::abs(ratio - 1.99526) < 0.05);
        // Ultrasonic stopband above 24 kHz is heavily attenuated
        assert(mag6_35k < mag6_1k * 0.01);
    }

    // 3. DSD512 (22.5792 MHz) -> 88.2 kHz multi-substep without skipping bytes
    {
        DsdToPcmDecimator dec512;
        assert(dec512.init(22579200u, 88200u, 2u, 0.0f));
        assert(dec512.isExactIntegerBytes());
        assert(dec512.bytesPerOutFrame() == 32u);
        assert(dec512.subStepsPerOut() >= 2u);

        const uint32_t outFrames = 2205u;
        const uint32_t bytesPerCh = outFrames * 32u;
        auto ch0 = generateSigmaDeltaSineMsb(22579200u, 1000.0, 0.45, bytesPerCh);
        std::vector<uint8_t> interleaved(static_cast<size_t>(bytesPerCh * 2u), kDsdSilenceByte);
        for (uint32_t i = 0; i < bytesPerCh; ++i) {
            interleaved[static_cast<size_t>(i) * 2u] = ch0[i];
        }
        std::vector<float> out512(static_cast<size_t>(outFrames * 2u));
        dec512.decimateExact(interleaved.data(), out512.data(), outFrames);
        std::vector<float> mono(outFrames - 128u);
        for (uint32_t i = 128u; i < outFrames; ++i) {
            mono[i - 128u] = out512[static_cast<size_t>(i) * 2u];
        }
        const double mag1k = dftMagAtHz(mono, 88200.0, 1000.0);
        assert(mag1k > 0.35);
    }

    std::printf("[PASS] testDecimatorSilenceSineBoostAndDsd512\n");
}

void testDopAndNativePackers() {
    // 2 frames x 2 ch -> 4 byte-frames interleaved
    const uint8_t dsdIn[8] = {
        0x12, 0xAB, // frame 0 byte 0 (L, R)
        0x34, 0xCD, // frame 0 byte 1 (L, R)
        0x56, 0xEF, // frame 1 byte 0 (L, R)
        0x78, 0x90, // frame 1 byte 1 (L, R)
    };

    // DoP S32
    int32_t dop32[4]{};
    bool toggle = false;
    pack_dop_s32(dsdIn, dop32, 2u, 2u, toggle);
    assert(static_cast<uint32_t>(dop32[0]) == 0x05123400u);
    assert(static_cast<uint32_t>(dop32[1]) == 0x05ABCD00u);
    assert(static_cast<uint32_t>(dop32[2]) == 0xFA567800u);
    assert(static_cast<uint32_t>(dop32[3]) == 0xFAEF9000u);
    assert(toggle == false);

    // DoP S24 LE
    uint8_t dop24[12]{};
    bool toggle24 = false;
    pack_dop_s24(dsdIn, dop24, 2u, 2u, toggle24);
    assert(dop24[0] == 0x34 && dop24[1] == 0x12 && dop24[2] == 0x05);
    assert(dop24[3] == 0xCD && dop24[4] == 0xAB && dop24[5] == 0x05);
    assert(dop24[6] == 0x78 && dop24[7] == 0x56 && dop24[8] == 0xFA);

    // Native DSD S32 (1 frame x 2 ch = 8 bytes interleaved)
    int32_t nat32[2]{};
    pack_native_dsd_s32(dsdIn, nat32, 1u, 2u);
    assert(static_cast<uint32_t>(nat32[0]) == 0x12345678u);
    assert(static_cast<uint32_t>(nat32[1]) == 0xABCDEF90u);

    // Silence fillers
    uint8_t silBuf[16]{};
    fill_native_dsd_silence(silBuf, sizeof(silBuf));
    for (uint8_t b : silBuf) assert(b == kDsdSilenceByte);

    int32_t dopSil32[4]{};
    bool silToggle = false;
    fill_dop_silence_frames(dopSil32, 2u, 2u, ma_format_s32, silToggle);
    assert(static_cast<uint32_t>(dopSil32[0]) == 0x05696900u);
    assert(static_cast<uint32_t>(dopSil32[1]) == 0x05696900u);
    assert(static_cast<uint32_t>(dopSil32[2]) == 0xFA696900u);
    assert(static_cast<uint32_t>(dopSil32[3]) == 0xFA696900u);

    std::printf("[PASS] testDopAndNativePackers\n");
}

void testMiniaudioDsdBackendLifecycle() {
    const char* path = "build/test_backend.dsf";
    const uint32_t bytesPerCh = 44100u; // 0.125s @ DSD64
    auto ch0 = generateSigmaDeltaSineMsb(2822400u, 1000.0, 0.45, bytesPerCh);
    auto ch1 = generateSigmaDeltaSineMsb(2822400u, 1000.0, 0.45, bytesPerCh);
    assert(writeSyntheticDsfFile(path, 2822400u, 2u, 1u, ch0, ch1, nullptr));

    ma_decoding_backend_vtable* customVtables[] = { &g_ma_decoding_backend_vtable_dsd };

    // 1. D2P mode open + read + seek + gain update
    {
        tls_dsd_open_options() = DsdOpenOptions{};
        tls_dsd_open_options().mode = AE_DSD_MODE_D2P;
        tls_dsd_open_options().requestedD2pRate = 88200u;
        tls_dsd_open_options().d2pGainBoostDb = 6.0f;

        ma_decoder_config cfg = ma_decoder_config_init(ma_format_unknown, 0, 0);
        cfg.ppCustomBackendVTables = customVtables;
        cfg.customBackendCount = 1;

        ma_decoder dec{};
        assert(ma_decoder_init_file(path, &cfg, &dec) == MA_SUCCESS);
        assert(tls_dsd_open_options().openedAsDsd);

        AEDsdOutputMode qMode = AE_DSD_MODE_AUTO;
        uint32_t qDsdRate = 0, qOutRate = 0, qCh = 0;
        ma_format qFmt = ma_format_unknown;
        assert(query_dsd_decoder_info(&dec, &qMode, &qDsdRate, &qOutRate, &qFmt, &qCh));
        assert(qMode == AE_DSD_MODE_D2P);
        assert(qDsdRate == 2822400u);
        assert(qOutRate == 88200u);
        assert(qFmt == ma_format_f32);
        assert(qCh == 2u);

        std::vector<float> pcm(1024u * 2u);
        ma_uint64 readCount = 0;
        assert(ma_decoder_read_pcm_frames(&dec, pcm.data(), 1024u, &readCount) == MA_SUCCESS);
        assert(readCount == 1024u);

        assert(ma_decoder_seek_to_pcm_frame(&dec, 4410u) == MA_SUCCESS);
        ma_uint64 cursor = 0;
        assert(ma_decoder_get_cursor_in_pcm_frames(&dec, &cursor) == MA_SUCCESS);
        assert(cursor == 4410u);

        assert(set_dsd_decoder_gain_boost_db(&dec, 0.0f));
        ma_decoder_uninit(&dec);
    }

    // 2. DoP v1.1 mode open + marker check
    {
        tls_dsd_open_options() = DsdOpenOptions{};
        tls_dsd_open_options().mode = AE_DSD_MODE_DOP;
        tls_dsd_open_options().dopFormat = ma_format_s32;

        ma_decoder_config cfg = ma_decoder_config_init(ma_format_unknown, 0, 0);
        cfg.ppCustomBackendVTables = customVtables;
        cfg.customBackendCount = 1;

        ma_decoder dec{};
        assert(ma_decoder_init_file(path, &cfg, &dec) == MA_SUCCESS);

        AEDsdOutputMode qMode = AE_DSD_MODE_AUTO;
        uint32_t qOutRate = 0;
        ma_format qFmt = ma_format_unknown;
        assert(query_dsd_decoder_info(&dec, &qMode, nullptr, &qOutRate, &qFmt, nullptr));
        assert(qMode == AE_DSD_MODE_DOP);
        assert(qOutRate == 176400u);
        assert(qFmt == ma_format_s32);

        int32_t dopBuf[16 * 2]{};
        ma_uint64 readCount = 0;
        assert(ma_decoder_read_pcm_frames(&dec, dopBuf, 16u, &readCount) == MA_SUCCESS);
        assert(readCount == 16u);
        for (int f = 0; f < 16; ++f) {
            uint8_t expectedMarker = (f % 2 == 0) ? 0x05u : 0xFAu;
            uint8_t markerL = static_cast<uint8_t>((static_cast<uint32_t>(dopBuf[f * 2]) >> 24) & 0xFFu);
            uint8_t markerR = static_cast<uint8_t>((static_cast<uint32_t>(dopBuf[f * 2 + 1]) >> 24) & 0xFFu);
            assert(markerL == expectedMarker && markerR == expectedMarker);
        }
        ma_decoder_uninit(&dec);
    }

    // 3. Native DSD mode open + raw packed check
    {
        tls_dsd_open_options() = DsdOpenOptions{};
        tls_dsd_open_options().mode = AE_DSD_MODE_NATIVE;

        ma_decoder_config cfg = ma_decoder_config_init(ma_format_unknown, 0, 0);
        cfg.ppCustomBackendVTables = customVtables;
        cfg.customBackendCount = 1;

        ma_decoder dec{};
        assert(ma_decoder_init_file(path, &cfg, &dec) == MA_SUCCESS);

        AEDsdOutputMode qMode = AE_DSD_MODE_AUTO;
        uint32_t qOutRate = 0;
        ma_format qFmt = ma_format_unknown;
        assert(query_dsd_decoder_info(&dec, &qMode, nullptr, &qOutRate, &qFmt, nullptr));
        assert(qMode == AE_DSD_MODE_NATIVE);
        assert(qOutRate == 88200u);
        assert(qFmt == ma_format_s32);

        int32_t natBuf[4 * 2]{};
        ma_uint64 readCount = 0;
        assert(ma_decoder_read_pcm_frames(&dec, natBuf, 4u, &readCount) == MA_SUCCESS);
        assert(readCount == 4u);
        const uint32_t expected0L =
            (static_cast<uint32_t>(ch0[0]) << 24) |
            (static_cast<uint32_t>(ch0[1]) << 16) |
            (static_cast<uint32_t>(ch0[2]) << 8) |
            static_cast<uint32_t>(ch0[3]);
        assert(static_cast<uint32_t>(natBuf[0]) == expected0L);
        ma_decoder_uninit(&dec);
    }

    std::remove(path);
    std::printf("[PASS] testMiniaudioDsdBackendLifecycle\n");
}

} // namespace

int main() {
    testDsfParsingAndMetadata();
    testDffParsingAndDstRejection();
    testDecimatorSilenceSineBoostAndDsd512();
    testDopAndNativePackers();
    testMiniaudioDsdBackendLifecycle();
    std::printf("ALL DSD PIPELINE TESTS PASSED\n");
    return 0;
}
