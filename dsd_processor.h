#pragma once

#include <algorithm>
#include <array>
#include <cctype>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>
#include <vector>

#include "miniaudio.h"

#ifdef _WIN32
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#else
#include <sys/types.h>
#endif

#ifndef AE_DSD_OUTPUT_MODE_DEFINED
#define AE_DSD_OUTPUT_MODE_DEFINED
typedef enum AEDsdOutputMode {
    AE_DSD_MODE_AUTO = 0,   // Prefer Native DSD -> DoP -> D2P
    AE_DSD_MODE_D2P = 1,    // Convert DSD to high-res PCM float (supports full DSP)
    AE_DSD_MODE_DOP = 2,    // DSD over PCM v1.1 (0x05/0xFA markers)
    AE_DSD_MODE_NATIVE = 3  // Raw 1-bit Native DSD (USB Audio Class 2.0)
} AEDsdOutputMode;
#endif

namespace sautiflow {
namespace dsd {

inline constexpr uint8_t kDsdSilenceByte = 0x69u;
inline constexpr int kD2pFilterTaps = 128;
inline constexpr int kD2pFilterBytes = 16; // 128 / 8

// Lookup table reversing bits within a byte (LSB-first <-> MSB-first).
inline constexpr std::array<uint8_t, 256> make_bit_reverse_table() {
    std::array<uint8_t, 256> t{};
    for (int i = 0; i < 256; ++i) {
        uint8_t v = static_cast<uint8_t>(i);
        uint8_t r = 0;
        for (int b = 0; b < 8; ++b) {
            r = static_cast<uint8_t>((r << 1) | (v & 1u));
            v >>= 1;
        }
        t[static_cast<size_t>(i)] = r;
    }
    return t;
}

inline constexpr std::array<uint8_t, 256> kBitReverseTable = make_bit_reverse_table();

inline uint16_t read_le16(const uint8_t* p) {
    return static_cast<uint16_t>(p[0]) |
           (static_cast<uint16_t>(p[1]) << 8);
}

inline uint32_t read_le32(const uint8_t* p) {
    return static_cast<uint32_t>(p[0]) |
           (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16) |
           (static_cast<uint32_t>(p[3]) << 24);
}

inline uint64_t read_le64(const uint8_t* p) {
    return static_cast<uint64_t>(read_le32(p)) |
           (static_cast<uint64_t>(read_le32(p + 4)) << 32);
}

inline uint16_t read_be16(const uint8_t* p) {
    return (static_cast<uint16_t>(p[0]) << 8) |
           static_cast<uint16_t>(p[1]);
}

inline uint32_t read_be32(const uint8_t* p) {
    return (static_cast<uint32_t>(p[0]) << 24) |
           (static_cast<uint32_t>(p[1]) << 16) |
           (static_cast<uint32_t>(p[2]) << 8) |
           static_cast<uint32_t>(p[3]);
}

inline uint64_t read_be64(const uint8_t* p) {
    return (static_cast<uint64_t>(read_be32(p)) << 32) |
           static_cast<uint64_t>(read_be32(p + 4));
}

inline bool seek_64(FILE* fp, int64_t offset, int origin) {
    if (!fp) return false;
#ifdef _WIN32
    return _fseeki64(fp, offset, origin) == 0;
#else
    return fseeko(fp, static_cast<off_t>(offset), origin) == 0;
#endif
}

inline int64_t tell_64(FILE* fp) {
    if (!fp) return -1;
#ifdef _WIN32
    return static_cast<int64_t>(_ftelli64(fp));
#else
    return static_cast<int64_t>(ftello(fp));
#endif
}

inline FILE* open_file_utf8(const char* path) {
    if (!path || !*path) return nullptr;
#ifdef _WIN32
    int len = MultiByteToWideChar(CP_UTF8, 0, path, -1, nullptr, 0);
    if (len <= 0) return nullptr;
    std::wstring wpath(static_cast<size_t>(len), L'\0');
    MultiByteToWideChar(CP_UTF8, 0, path, -1, &wpath[0], len);
    return _wfopen(wpath.c_str(), L"rb");
#else
    return std::fopen(path, "rb");
#endif
}

inline FILE* open_file_w(const wchar_t* wpath) {
    if (!wpath || !*wpath) return nullptr;
#ifdef _WIN32
    return _wfopen(wpath, L"rb");
#else
    (void)wpath;
    return nullptr;
#endif
}

inline bool is_dsd_file_path(const std::string& path) {
    if (path.empty()) return false;
    // Strip query string / fragment if present (e.g. URL/URI)
    size_t end = path.find_first_of("?#");
    if (end == std::string::npos) end = path.size();
    if (end < 4) return false;
    std::string ext = path.substr(end - 4, 4);
    for (char& c : ext) {
        c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }
    return ext == ".dsf" || ext == ".dff";
}

inline bool is_dsd_file_path_w(const std::wstring& wpath) {
    if (wpath.size() < 4) return false;
    size_t end = wpath.find_first_of(L"?#");
    if (end == std::wstring::npos) end = wpath.size();
    if (end < 4) return false;
    std::wstring ext = wpath.substr(end - 4, 4);
    for (wchar_t& c : ext) {
        if (c >= L'A' && c <= L'Z') {
            c = static_cast<wchar_t>(c - L'A' + L'a');
        }
    }
    return ext == L".dsf" || ext == L".dff";
}

inline int dsd_rate_multiplier(uint32_t dsdSampleRate) {
    if (dsdSampleRate == 0) return 0;
    if (dsdSampleRate % 48000u == 0) {
        return static_cast<int>(dsdSampleRate / 48000u);
    }
    return static_cast<int>((dsdSampleRate + 22050u) / 44100u);
}

inline std::string dsd_rate_name(uint32_t dsdSampleRate) {
    int mult = dsd_rate_multiplier(dsdSampleRate);
    if (mult <= 0) return "DSD";
    return "DSD" + std::to_string(mult);
}

inline uint32_t default_d2p_rate_for_dsd(uint32_t dsdSampleRate, uint32_t preferredD2pRate = 0) {
    const bool is48kFamily = (dsdSampleRate % 48000u == 0);
    const uint32_t baseRate = is48kFamily ? 48000u : 44100u;

    if (preferredD2pRate > 0) {
        if (is48kFamily) {
            if (preferredD2pRate == 88200u) return 96000u;
            if (preferredD2pRate == 176400u) return 192000u;
            if (preferredD2pRate == 352800u) return 384000u;
            if (preferredD2pRate == 96000u || preferredD2pRate == 192000u || preferredD2pRate == 384000u) {
                return preferredD2pRate;
            }
        } else {
            if (preferredD2pRate == 96000u) return 88200u;
            if (preferredD2pRate == 192000u) return 176400u;
            if (preferredD2pRate == 384000u) return 352800u;
            if (preferredD2pRate == 88200u || preferredD2pRate == 176400u || preferredD2pRate == 352800u) {
                return preferredD2pRate;
            }
        }
        return preferredD2pRate;
    }

    // Default clean integer decimation:
    // DSD64  -> 88.2k (4 bytes) / 96k
    // DSD128 -> 176.4k (4 bytes) / 192k
    // DSD256+ -> 352.8k / 384k
    uint32_t autoRate = dsdSampleRate / 32u;
    if (autoRate < baseRate * 2u) autoRate = baseRate * 2u;
    if (autoRate > baseRate * 8u) autoRate = baseRate * 8u;
    return autoRate;
}

enum class DsdContainerType {
    None = 0,
    Dsf = 1,
    Dff = 2
};

struct DsdFileHeader {
    bool valid = false;
    DsdContainerType container = DsdContainerType::None;
    bool isDstCompressed = false;
    bool bitsLsbFirst = false;     // DSF bitsPerSample == 1
    bool blockInterleaved = false; // DSF 4096-byte blocks per channel
    uint32_t channels = 0;
    uint32_t dsdSampleRate = 0;
    uint32_t blockSizePerChannel = 0;
    uint64_t fileSize = 0;
    uint64_t dataOffset = 0;
    uint64_t dataByteSize = 0;
    uint64_t totalDsdSamplesPerChannel = 0;
    uint64_t id3Offset = 0;
    uint64_t id3Size = 0;

    uint64_t totalBytesPerChannel() const {
        return (totalDsdSamplesPerChannel + 7ull) / 8ull;
    }

    double durationSeconds() const {
        if (dsdSampleRate == 0) return 0.0;
        return static_cast<double>(totalDsdSamplesPerChannel) /
               static_cast<double>(dsdSampleRate);
    }
};

inline DsdFileHeader parse_dsf_header(FILE* fp, uint64_t fileSize) {
    DsdFileHeader hdr;
    if (!fp || fileSize < 92) return hdr;
    if (!seek_64(fp, 0, SEEK_SET)) return hdr;

    uint8_t dsdChunk[28]{};
    if (std::fread(dsdChunk, 1, 28, fp) != 28) return hdr;
    if (std::memcmp(dsdChunk, "DSD ", 4) != 0) return hdr;

    uint64_t dsdChunkSize = read_le64(dsdChunk + 4);
    uint64_t declaredFileSize = read_le64(dsdChunk + 12);
    uint64_t id3Ptr = read_le64(dsdChunk + 20);
    if (dsdChunkSize < 28 || dsdChunkSize > fileSize) return hdr;
    if (!seek_64(fp, static_cast<int64_t>(dsdChunkSize), SEEK_SET)) return hdr;

    uint8_t fmtHdr[12]{};
    if (std::fread(fmtHdr, 1, 12, fp) != 12) return hdr;
    if (std::memcmp(fmtHdr, "fmt ", 4) != 0) return hdr;
    uint64_t fmtChunkSize = read_le64(fmtHdr + 4);
    if (fmtChunkSize < 52 || dsdChunkSize + fmtChunkSize + 12 > fileSize) return hdr;

    uint8_t fmtBody[40]{};
    if (std::fread(fmtBody, 1, 40, fp) != 40) return hdr;
    uint32_t formatId = read_le32(fmtBody + 4); // 0 = DSD raw
    if (formatId != 0) return hdr;

    hdr.channels = read_le32(fmtBody + 12);
    hdr.dsdSampleRate = read_le32(fmtBody + 16);
    uint32_t bitsPerSample = read_le32(fmtBody + 20);
    hdr.totalDsdSamplesPerChannel = read_le64(fmtBody + 24);
    hdr.blockSizePerChannel = read_le32(fmtBody + 32);

    if (hdr.channels == 0 || hdr.channels > 8) return hdr;
    if (hdr.dsdSampleRate < 1000000u || hdr.blockSizePerChannel == 0) return hdr;
    if (bitsPerSample != 1 && bitsPerSample != 8) return hdr;
    hdr.bitsLsbFirst = (bitsPerSample == 1);
    hdr.blockInterleaved = true;

    const uint64_t dataChunkOffset = dsdChunkSize + fmtChunkSize;
    if (!seek_64(fp, static_cast<int64_t>(dataChunkOffset), SEEK_SET)) return hdr;

    uint8_t dataHdr[12]{};
    if (std::fread(dataHdr, 1, 12, fp) != 12) return hdr;
    if (std::memcmp(dataHdr, "data", 4) != 0) return hdr;

    uint64_t dataChunkSize = read_le64(dataHdr + 4);
    if (dataChunkSize < 12) return hdr;

    hdr.container = DsdContainerType::Dsf;
    hdr.fileSize = (declaredFileSize > 0 && declaredFileSize <= fileSize) ? declaredFileSize : fileSize;
    hdr.dataOffset = dataChunkOffset + 12;
    uint64_t maxAvail = (hdr.dataOffset < fileSize) ? (fileSize - hdr.dataOffset) : 0;
    hdr.dataByteSize = std::min(dataChunkSize - 12, maxAvail);

    if (hdr.totalDsdSamplesPerChannel == 0 && hdr.dataByteSize > 0) {
        hdr.totalDsdSamplesPerChannel = (hdr.dataByteSize / hdr.channels) * 8ull;
    }

    if (id3Ptr >= hdr.dataOffset && id3Ptr < fileSize) {
        hdr.id3Offset = id3Ptr;
        hdr.id3Size = fileSize - id3Ptr;
    }

    hdr.valid = true;
    return hdr;
}

inline DsdFileHeader parse_dff_header_with_optional_diin(
    FILE* fp,
    uint64_t fileSize,
    std::string* outArtist,
    std::string* outTitle
) {
    DsdFileHeader hdr;
    if (!fp || fileSize < 28) return hdr;
    if (!seek_64(fp, 0, SEEK_SET)) return hdr;

    uint8_t frm8[16]{};
    if (std::fread(frm8, 1, 16, fp) != 16) return hdr;
    if (std::memcmp(frm8, "FRM8", 4) != 0 || std::memcmp(frm8 + 12, "DSD ", 4) != 0) {
        return hdr;
    }

    uint64_t frmSize = read_be64(frm8 + 4);
    uint64_t formEnd = std::min(fileSize, 12ull + frmSize);
    uint64_t pos = 16;

    bool gotFs = false;
    bool gotChnl = false;
    bool gotData = false;

    while (pos + 12 <= formEnd) {
        if (!seek_64(fp, static_cast<int64_t>(pos), SEEK_SET)) break;
        uint8_t chHdr[12]{};
        if (std::fread(chHdr, 1, 12, fp) != 12) break;

        uint64_t ckSize = read_be64(chHdr + 4);
        uint64_t dataPos = pos + 12;
        uint64_t nextPos = dataPos + ckSize + (ckSize & 1ull);
        if (ckSize > fileSize || dataPos > fileSize) break;

        if (std::memcmp(chHdr, "PROP", 4) == 0 && ckSize >= 4) {
            uint8_t propType[4]{};
            if (std::fread(propType, 1, 4, fp) == 4 && std::memcmp(propType, "SND ", 4) == 0) {
                uint64_t subPos = dataPos + 4;
                uint64_t propEnd = std::min(fileSize, dataPos + ckSize);
                while (subPos + 12 <= propEnd) {
                    if (!seek_64(fp, static_cast<int64_t>(subPos), SEEK_SET)) break;
                    uint8_t subHdr[12]{};
                    if (std::fread(subHdr, 1, 12, fp) != 12) break;
                    uint64_t subSize = read_be64(subHdr + 4);
                    uint64_t subData = subPos + 12;

                    if (std::memcmp(subHdr, "FS  ", 4) == 0 && subSize >= 4) {
                        uint8_t buf[4]{};
                        if (std::fread(buf, 1, 4, fp) == 4) {
                            hdr.dsdSampleRate = read_be32(buf);
                            gotFs = (hdr.dsdSampleRate >= 1000000u);
                        }
                    } else if (std::memcmp(subHdr, "CHNL", 4) == 0 && subSize >= 2) {
                        uint8_t buf[2]{};
                        if (std::fread(buf, 1, 2, fp) == 2) {
                            hdr.channels = read_be16(buf);
                            gotChnl = (hdr.channels >= 1 && hdr.channels <= 8);
                        }
                    } else if (std::memcmp(subHdr, "CMPR", 4) == 0 && subSize >= 4) {
                        uint8_t cmpr[4]{};
                        if (std::fread(cmpr, 1, 4, fp) == 4) {
                            if (std::memcmp(cmpr, "DST ", 4) == 0) {
                                hdr.isDstCompressed = true;
                            }
                        }
                    }

                    uint64_t adv = 12 + subSize + (subSize & 1ull);
                    if (adv <= 12 && subSize == 0) adv = 12;
                    subPos += adv;
                }
            }
        } else if (std::memcmp(chHdr, "DSD ", 4) == 0 && !gotData) {
            hdr.dataOffset = dataPos;
            uint64_t avail = (dataPos < fileSize) ? (fileSize - dataPos) : 0;
            hdr.dataByteSize = std::min(ckSize, avail);
            gotData = true;
        } else if (std::memcmp(chHdr, "DST ", 4) == 0) {
            hdr.isDstCompressed = true;
        } else if (std::memcmp(chHdr, "ID3 ", 4) == 0) {
            hdr.id3Offset = dataPos;
            uint64_t avail = (dataPos < fileSize) ? (fileSize - dataPos) : 0;
            hdr.id3Size = std::min(ckSize, avail);
        } else if (std::memcmp(chHdr, "DIIN", 4) == 0 && (outArtist || outTitle)) {
            uint64_t subPos = dataPos;
            uint64_t diinEnd = std::min(fileSize, dataPos + ckSize);
            while (subPos + 12 <= diinEnd) {
                if (!seek_64(fp, static_cast<int64_t>(subPos), SEEK_SET)) break;
                uint8_t subHdr[12]{};
                if (std::fread(subHdr, 1, 12, fp) != 12) break;
                uint64_t subSize = read_be64(subHdr + 4);
                bool wantArtist = outArtist && std::memcmp(subHdr, "DIAR", 4) == 0;
                bool wantTitle = outTitle && std::memcmp(subHdr, "DITI", 4) == 0;
                if ((wantArtist || wantTitle) && subSize >= 4 && subSize <= 4096) {
                    uint8_t lenBuf[4]{};
                    if (std::fread(lenBuf, 1, 4, fp) == 4) {
                        uint32_t strLen = read_be32(lenBuf);
                        if (strLen > 0 && strLen <= subSize - 4) {
                            std::string val(strLen, '\0');
                            if (std::fread(&val[0], 1, strLen, fp) == strLen) {
                                while (!val.empty() && val.back() == '\0') val.pop_back();
                                if (wantArtist) *outArtist = val;
                                if (wantTitle) *outTitle = val;
                            }
                        }
                    }
                }
                subPos += 12 + subSize + (subSize & 1ull);
            }
        }

        if (nextPos <= pos) break;
        pos = nextPos;
    }

    // Some taggers append ID3 tag slightly past FRM8 declared end; scan tail if not found yet.
    if (hdr.id3Offset == 0 && formEnd + 10 < fileSize) {
        if (seek_64(fp, static_cast<int64_t>(formEnd), SEEK_SET)) {
            uint8_t tagHdr[12]{};
            if (std::fread(tagHdr, 1, 12, fp) >= 10) {
                if (std::memcmp(tagHdr, "ID3 ", 4) == 0) {
                    uint64_t ckSz = read_be64(tagHdr + 4);
                    hdr.id3Offset = formEnd + 12;
                    hdr.id3Size = std::min(ckSz, fileSize - hdr.id3Offset);
                } else if (std::memcmp(tagHdr, "ID3", 3) == 0) {
                    hdr.id3Offset = formEnd;
                    hdr.id3Size = fileSize - formEnd;
                }
            }
        }
    }

    if (hdr.isDstCompressed) {
        hdr.container = DsdContainerType::Dff;
        hdr.valid = false;
        return hdr;
    }

    if (!gotFs || !gotChnl || !gotData || hdr.dataByteSize == 0) {
        return hdr;
    }

    hdr.container = DsdContainerType::Dff;
    hdr.fileSize = fileSize;
    hdr.bitsLsbFirst = false;
    hdr.blockInterleaved = false;
    hdr.totalDsdSamplesPerChannel = (hdr.dataByteSize / hdr.channels) * 8ull;
    hdr.valid = true;
    return hdr;
}

inline DsdFileHeader parse_dsd_file_header(FILE* fp) {
    DsdFileHeader empty;
    if (!fp) return empty;
    if (!seek_64(fp, 0, SEEK_END)) return empty;
    int64_t fsz = tell_64(fp);
    if (fsz < 28) return empty;
    uint64_t fileSize = static_cast<uint64_t>(fsz);
    if (!seek_64(fp, 0, SEEK_SET)) return empty;

    uint8_t magic[4]{};
    if (std::fread(magic, 1, 4, fp) != 4) return empty;
    if (std::memcmp(magic, "DSD ", 4) == 0) {
        return parse_dsf_header(fp, fileSize);
    }
    if (std::memcmp(magic, "FRM8", 4) == 0) {
        return parse_dff_header_with_optional_diin(fp, fileSize, nullptr, nullptr);
    }
    return empty;
}

inline DsdFileHeader parse_dsd_file_header_utf8(const char* path) {
    FILE* fp = open_file_utf8(path);
    if (!fp) return DsdFileHeader{};
    DsdFileHeader hdr = parse_dsd_file_header(fp);
    std::fclose(fp);
    return hdr;
}

inline DsdFileHeader parse_dsd_file_header_w(const wchar_t* wpath) {
    FILE* fp = open_file_w(wpath);
    if (!fp) return DsdFileHeader{};
    DsdFileHeader hdr = parse_dsd_file_header(fp);
    std::fclose(fp);
    return hdr;
}

// ============================================================================
// Built-in ID3v2.2 / v2.3 / v2.4 + ReplayGain + Cover Art Metadata Reader
// ============================================================================

struct DsdMetadata {
    bool valid = false;
    std::string title;
    std::string artist;
    std::string album;
    std::string albumArtist;
    std::string genre;
    std::string year;
    std::string comment;
    int trackNumber = 0;
    int discNumber = 0;

    bool hasReplayGainTrack = false;
    float replayGainTrackDb = 0.0f;
    float replayGainTrackPeak = 1.0f;
    bool hasReplayGainAlbum = false;
    float replayGainAlbumDb = 0.0f;
    float replayGainAlbumPeak = 1.0f;

    std::vector<uint8_t> pictureData;
    std::string pictureMimeType;
};

namespace detail {

inline uint32_t read_syncsafe32(const uint8_t* p) {
    return (static_cast<uint32_t>(p[0] & 0x7Fu) << 21) |
           (static_cast<uint32_t>(p[1] & 0x7Fu) << 14) |
           (static_cast<uint32_t>(p[2] & 0x7Fu) << 7) |
           static_cast<uint32_t>(p[3] & 0x7Fu);
}

inline void append_utf8_codepoint(uint32_t cp, std::string& out) {
    if (cp <= 0x7Fu) {
        out.push_back(static_cast<char>(cp));
    } else if (cp <= 0x7FFu) {
        out.push_back(static_cast<char>(0xC0u | (cp >> 6)));
        out.push_back(static_cast<char>(0x80u | (cp & 0x3Fu)));
    } else if (cp <= 0xFFFFu) {
        out.push_back(static_cast<char>(0xE0u | (cp >> 12)));
        out.push_back(static_cast<char>(0x80u | ((cp >> 6) & 0x3Fu)));
        out.push_back(static_cast<char>(0x80u | (cp & 0x3Fu)));
    } else if (cp <= 0x10FFFFu) {
        out.push_back(static_cast<char>(0xF0u | (cp >> 18)));
        out.push_back(static_cast<char>(0x80u | ((cp >> 12) & 0x3Fu)));
        out.push_back(static_cast<char>(0x80u | ((cp >> 6) & 0x3Fu)));
        out.push_back(static_cast<char>(0x80u | (cp & 0x3Fu)));
    }
}

inline std::string decode_utf16_bytes(const uint8_t* data, size_t len, bool bigEndian, bool checkBom) {
    if (!data || len < 2) return {};
    size_t pos = 0;
    if (checkBom && len >= 2) {
        if (data[0] == 0xFFu && data[1] == 0xFEu) {
            bigEndian = false;
            pos = 2;
        } else if (data[0] == 0xFEu && data[1] == 0xFFu) {
            bigEndian = true;
            pos = 2;
        }
    }
    std::string out;
    out.reserve(len);
    while (pos + 1 < len) {
        uint16_t u = bigEndian
            ? (static_cast<uint16_t>(data[pos] << 8) | data[pos + 1])
            : (static_cast<uint16_t>(data[pos]) | static_cast<uint16_t>(data[pos + 1] << 8));
        pos += 2;
        if (u == 0) break;
        if (u >= 0xD800u && u <= 0xDBFFu && pos + 1 < len) {
            uint16_t u2 = bigEndian
                ? (static_cast<uint16_t>(data[pos] << 8) | data[pos + 1])
                : (static_cast<uint16_t>(data[pos]) | static_cast<uint16_t>(data[pos + 1] << 8));
            if (u2 >= 0xDC00u && u2 <= 0xDFFFu) {
                pos += 2;
                uint32_t cp = 0x10000u + (((u - 0xD800u) << 10) | (u2 - 0xDC00u));
                append_utf8_codepoint(cp, out);
                continue;
            }
        }
        append_utf8_codepoint(u, out);
    }
    return out;
}

inline std::string decode_id3_string(uint8_t encoding, const uint8_t* data, size_t len, size_t* outConsumed = nullptr) {
    if (!data || len == 0) {
        if (outConsumed) *outConsumed = 0;
        return {};
    }
    if (encoding == 1 || encoding == 2) {
        // UTF-16 terminated by double null (0x00 0x00) on 2-byte boundary
        size_t i = 0;
        while (i + 1 < len) {
            if (data[i] == 0 && data[i + 1] == 0) {
                if (outConsumed) *outConsumed = i + 2;
                return decode_utf16_bytes(data, i, encoding == 2, encoding == 1);
            }
            i += 2;
        }
        if (outConsumed) *outConsumed = len;
        return decode_utf16_bytes(data, len, encoding == 2, encoding == 1);
    }

    // ISO-8859-1 (0) or UTF-8 (3)
    size_t i = 0;
    while (i < len && data[i] != 0) ++i;
    if (outConsumed) *outConsumed = (i < len) ? (i + 1) : len;

    if (encoding == 3) {
        return std::string(reinterpret_cast<const char*>(data), i);
    }
    std::string out;
    out.reserve(i);
    for (size_t k = 0; k < i; ++k) {
        append_utf8_codepoint(data[k], out);
    }
    return out;
}

inline std::string ascii_lower(std::string s) {
    for (char& c : s) {
        c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }
    return s;
}

inline int parse_slash_int(const std::string& s) {
    if (s.empty()) return 0;
    return std::atoi(s.c_str());
}

inline float parse_db_float(const std::string& s, bool* ok = nullptr) {
    if (s.empty()) {
        if (ok) *ok = false;
        return 0.0f;
    }
    char* endPtr = nullptr;
    float v = std::strtof(s.c_str(), &endPtr);
    if (ok) *ok = (endPtr != s.c_str());
    return v;
}

inline void parse_id3v2_blob(const std::vector<uint8_t>& raw, DsdMetadata& meta) {
    if (raw.size() < 10) return;
    if (std::memcmp(raw.data(), "ID3", 3) != 0) return;

    uint8_t majorVer = raw[3];
    if (majorVer < 2 || majorVer > 4) return;
    uint8_t flags = raw[5];
    uint32_t tagBodySize = read_syncsafe32(raw.data() + 6);
    if (tagBodySize == 0) return;

    size_t maxEnd = std::min<size_t>(raw.size(), 10u + tagBodySize);
    size_t pos = 10;

    // Optional extended header (ID3v2.3 / v2.4)
    if (majorVer >= 3 && (flags & 0x40u) != 0 && pos + 4 <= maxEnd) {
        uint32_t extSize = (majorVer == 4)
            ? read_syncsafe32(raw.data() + pos)
            : (4u + read_be32(raw.data() + pos));
        pos += std::min<size_t>(extSize, maxEnd - pos);
    }

    while (pos < maxEnd) {
        if (raw[pos] == 0) break; // Padding reached

        std::string frameId;
        uint32_t frameSize = 0;
        uint16_t frameFlags = 0;
        size_t hdrSize = 0;

        if (majorVer == 2) {
            if (pos + 6 > maxEnd) break;
            frameId.assign(reinterpret_cast<const char*>(raw.data() + pos), 3);
            frameSize = (static_cast<uint32_t>(raw[pos + 3]) << 16) |
                        (static_cast<uint32_t>(raw[pos + 4]) << 8) |
                        static_cast<uint32_t>(raw[pos + 5]);
            hdrSize = 6;
        } else {
            if (pos + 10 > maxEnd) break;
            frameId.assign(reinterpret_cast<const char*>(raw.data() + pos), 4);
            frameSize = (majorVer == 4)
                ? read_syncsafe32(raw.data() + pos + 4)
                : read_be32(raw.data() + pos + 4);
            frameFlags = read_be16(raw.data() + pos + 8);
            hdrSize = 10;
        }

        if (frameSize == 0 || pos + hdrSize + frameSize > maxEnd) break;
        const uint8_t* payload = raw.data() + pos + hdrSize;
        size_t payloadSize = frameSize;
        pos += hdrSize + frameSize;

        // Skip encrypted/compressed frames that lack raw text
        if (majorVer == 3 && (frameFlags & 0x00C0u) != 0) continue;
        if (majorVer == 4 && (frameFlags & 0x000Cu) != 0) continue;
        // Strip ID3v2.4 data length indicator if present
        std::vector<uint8_t> unSyncBuf;
        if (majorVer == 4 && (frameFlags & 0x0001u) != 0 && payloadSize >= 4) {
            payload += 4;
            payloadSize -= 4;
        }
        // Unsynchronise frame if global v2.3 unsync or v2.4 frame unsync flag is set
        bool unsync = ((flags & 0x80u) != 0 && majorVer <= 3) ||
                      (majorVer == 4 && ((frameFlags & 0x0002u) != 0 || (flags & 0x80u) != 0));
        if (unsync && payloadSize > 1) {
            unSyncBuf.reserve(payloadSize);
            for (size_t i = 0; i < payloadSize; ++i) {
                unSyncBuf.push_back(payload[i]);
                if (payload[i] == 0xFFu && i + 1 < payloadSize && payload[i + 1] == 0x00u) {
                    ++i;
                }
            }
            payload = unSyncBuf.data();
            payloadSize = unSyncBuf.size();
        }

        if (payloadSize < 1) continue;

        if (frameId == "TIT2" || frameId == "TT2") {
            std::string v = decode_id3_string(payload[0], payload + 1, payloadSize - 1);
            if (!v.empty()) meta.title = v;
        } else if (frameId == "TPE1" || frameId == "TP1") {
            std::string v = decode_id3_string(payload[0], payload + 1, payloadSize - 1);
            if (!v.empty()) meta.artist = v;
        } else if (frameId == "TALB" || frameId == "TAL") {
            std::string v = decode_id3_string(payload[0], payload + 1, payloadSize - 1);
            if (!v.empty()) meta.album = v;
        } else if (frameId == "TPE2" || frameId == "TP2") {
            std::string v = decode_id3_string(payload[0], payload + 1, payloadSize - 1);
            if (!v.empty()) meta.albumArtist = v;
        } else if (frameId == "TCON" || frameId == "TCO") {
            std::string v = decode_id3_string(payload[0], payload + 1, payloadSize - 1);
            if (!v.empty()) meta.genre = v;
        } else if (frameId == "TDRC" || frameId == "TYER" || frameId == "TYE") {
            std::string v = decode_id3_string(payload[0], payload + 1, payloadSize - 1);
            if (!v.empty()) meta.year = v.substr(0, 4);
        } else if (frameId == "TRCK" || frameId == "TRK") {
            std::string v = decode_id3_string(payload[0], payload + 1, payloadSize - 1);
            int n = parse_slash_int(v);
            if (n > 0) meta.trackNumber = n;
        } else if (frameId == "TPOS" || frameId == "TPA") {
            std::string v = decode_id3_string(payload[0], payload + 1, payloadSize - 1);
            int n = parse_slash_int(v);
            if (n > 0) meta.discNumber = n;
        } else if (frameId == "COMM" && payloadSize > 4) {
            uint8_t enc = payload[0];
            size_t consumed = 0;
            (void)decode_id3_string(enc, payload + 4, payloadSize - 4, &consumed);
            if (4 + consumed < payloadSize) {
                std::string v = decode_id3_string(enc, payload + 4 + consumed, payloadSize - 4 - consumed);
                if (!v.empty()) meta.comment = v;
            }
        } else if (frameId == "TXXX" && payloadSize > 2) {
            uint8_t enc = payload[0];
            size_t consumed = 0;
            std::string desc = ascii_lower(decode_id3_string(enc, payload + 1, payloadSize - 1, &consumed));
            if (1 + consumed < payloadSize) {
                std::string val = decode_id3_string(enc, payload + 1 + consumed, payloadSize - 1 - consumed);
                bool ok = false;
                float fv = parse_db_float(val, &ok);
                if (ok) {
                    if (desc == "replaygain_track_gain") {
                        meta.hasReplayGainTrack = true;
                        meta.replayGainTrackDb = fv;
                    } else if (desc == "replaygain_track_peak") {
                        meta.replayGainTrackPeak = fv;
                    } else if (desc == "replaygain_album_gain") {
                        meta.hasReplayGainAlbum = true;
                        meta.replayGainAlbumDb = fv;
                    } else if (desc == "replaygain_album_peak") {
                        meta.replayGainAlbumPeak = fv;
                    }
                }
            }
        } else if ((frameId == "APIC" || frameId == "PIC") && meta.pictureData.empty() && payloadSize > 4) {
            uint8_t enc = payload[0];
            size_t cur = 1;
            std::string mime;
            if (frameId == "APIC") {
                size_t z = cur;
                while (z < payloadSize && payload[z] != 0) ++z;
                mime.assign(reinterpret_cast<const char*>(payload + cur), z - cur);
                cur = (z < payloadSize) ? (z + 1) : payloadSize;
            } else {
                if (cur + 3 <= payloadSize) {
                    std::string fmt(reinterpret_cast<const char*>(payload + cur), 3);
                    mime = (fmt == "PNG" || fmt == "png") ? "image/png" : "image/jpeg";
                    cur += 3;
                }
            }
            if (cur < payloadSize) {
                ++cur; // picture type byte (prefer first or front cover if available)
                size_t consumed = 0;
                (void)decode_id3_string(enc, payload + cur, payloadSize - cur, &consumed);
                cur += consumed;
                if (cur < payloadSize) {
                    meta.pictureMimeType = mime.empty() ? "image/jpeg" : mime;
                    meta.pictureData.assign(payload + cur, payload + payloadSize);
                }
            }
        }
    }
    meta.valid = true;
}

} // namespace detail

inline DsdMetadata read_dsd_file_metadata(FILE* fp) {
    DsdMetadata meta;
    if (!fp) return meta;
    if (!seek_64(fp, 0, SEEK_END)) return meta;
    int64_t fsz = tell_64(fp);
    if (fsz < 28) return meta;
    uint64_t fileSize = static_cast<uint64_t>(fsz);
    if (!seek_64(fp, 0, SEEK_SET)) return meta;

    uint8_t magic[4]{};
    if (std::fread(magic, 1, 4, fp) != 4) return meta;

    DsdFileHeader hdr;
    std::string diinArtist, diinTitle;
    if (std::memcmp(magic, "DSD ", 4) == 0) {
        hdr = parse_dsf_header(fp, fileSize);
    } else if (std::memcmp(magic, "FRM8", 4) == 0) {
        hdr = parse_dff_header_with_optional_diin(fp, fileSize, &diinArtist, &diinTitle);
    } else {
        return meta;
    }

    if (hdr.id3Offset > 0 && hdr.id3Size >= 10 && hdr.id3Offset + hdr.id3Size <= fileSize) {
        // Cap cover art / ID3 read at 32 MiB to prevent malformed huge reads
        size_t readLen = static_cast<size_t>(std::min<uint64_t>(hdr.id3Size, 32ull * 1024ull * 1024ull));
        if (seek_64(fp, static_cast<int64_t>(hdr.id3Offset), SEEK_SET)) {
            std::vector<uint8_t> raw(readLen);
            size_t got = std::fread(raw.data(), 1, readLen, fp);
            if (got >= 10) {
                raw.resize(got);
                detail::parse_id3v2_blob(raw, meta);
            }
        }
    }

    if (meta.title.empty() && !diinTitle.empty()) {
        meta.title = diinTitle;
        meta.valid = true;
    }
    if (meta.artist.empty() && !diinArtist.empty()) {
        meta.artist = diinArtist;
        meta.valid = true;
    }
    return meta;
}

inline DsdMetadata read_dsd_file_metadata_utf8(const char* path) {
    FILE* fp = open_file_utf8(path);
    if (!fp) return DsdMetadata{};
    DsdMetadata meta = read_dsd_file_metadata(fp);
    std::fclose(fp);
    return meta;
}

// ============================================================================
// DSD Stream Reader (outputs MSB-first, byte-per-channel interleaved frames)
// ============================================================================

class DsdStreamReader {
public:
    DsdStreamReader() = default;
    ~DsdStreamReader() { close(); }

    DsdStreamReader(const DsdStreamReader&) = delete;
    DsdStreamReader& operator=(const DsdStreamReader&) = delete;

    bool open(const char* path) {
        close();
        FILE* fp = open_file_utf8(path);
        return init_with_file(fp);
    }

    bool open_w(const wchar_t* wpath) {
        close();
        FILE* fp = open_file_w(wpath);
        return init_with_file(fp);
    }

    bool attach_header(FILE* fp, const DsdFileHeader& hdr) {
        close();
        if (!fp || !hdr.valid) return false;
        fp_ = fp;
        ownsFile_ = false;
        hdr_ = hdr;
        return post_open_init();
    }

    void close() {
        if (fp_ && ownsFile_) {
            std::fclose(fp_);
        }
        fp_ = nullptr;
        ownsFile_ = false;
        hdr_ = DsdFileHeader{};
        curByteFrame_ = 0;
        dsfLoadedBlockIdx_ = UINT64_MAX;
        dsfBlockBuf_.clear();
        dffReadBuf_.clear();
    }

    const DsdFileHeader& header() const { return hdr_; }
    uint64_t totalByteFrames() const { return totalByteFrames_; }
    uint64_t currentByteFrame() const { return curByteFrame_; }

    bool seekByteFrame(uint64_t byteFrame) {
        if (!fp_ || !hdr_.valid) return false;
        if (byteFrame > totalByteFrames_) byteFrame = totalByteFrames_;
        curByteFrame_ = byteFrame;
        return true;
    }

    // Reads up to `byteFramesToRead` interleaved byte frames (`channels` bytes each).
    // Every output byte is normalized to MSB-first (bit 7 = earliest sample).
    uint64_t readByteFrames(uint8_t* outMsbInterleaved, uint64_t byteFramesToRead) {
        if (!fp_ || !hdr_.valid || !outMsbInterleaved || byteFramesToRead == 0) return 0;
        if (curByteFrame_ >= totalByteFrames_) return 0;

        uint64_t avail = totalByteFrames_ - curByteFrame_;
        uint64_t count = std::min(avail, byteFramesToRead);
        const uint32_t ch = hdr_.channels;

        if (!hdr_.blockInterleaved) {
            // DFF: already channel-interleaved byte-by-byte and MSB-first.
            uint64_t fileOff = hdr_.dataOffset + curByteFrame_ * ch;
            if (!seek_64(fp_, static_cast<int64_t>(fileOff), SEEK_SET)) return 0;
            size_t bytesWanted = static_cast<size_t>(count * ch);
            size_t got = std::fread(outMsbInterleaved, 1, bytesWanted, fp_);
            if (got < bytesWanted) {
                std::memset(outMsbInterleaved + got, kDsdSilenceByte, bytesWanted - got);
            }
            curByteFrame_ += count;
            return count;
        }

        // DSF: blockSizePerChannel bytes per channel in contiguous block sets.
        const uint64_t blkSz = hdr_.blockSizePerChannel;
        uint64_t remaining = count;
        uint8_t* dst = outMsbInterleaved;

        while (remaining > 0) {
            uint64_t blkIdx = curByteFrame_ / blkSz;
            uint64_t inBlkOff = curByteFrame_ % blkSz;
            if (blkIdx != dsfLoadedBlockIdx_) {
                if (!load_dsf_block(blkIdx)) break;
            }

            uint64_t take = std::min(remaining, blkSz - inBlkOff);
            for (uint64_t i = 0; i < take; ++i) {
                uint64_t offInChan = inBlkOff + i;
                for (uint32_t c = 0; c < ch; ++c) {
                    uint8_t rawByte = dsfBlockBuf_[static_cast<size_t>(c * blkSz + offInChan)];
                    dst[i * ch + c] = hdr_.bitsLsbFirst ? kBitReverseTable[rawByte] : rawByte;
                }
            }

            dst += take * ch;
            curByteFrame_ += take;
            remaining -= take;
        }

        return count - remaining;
    }

private:
    bool init_with_file(FILE* fp) {
        if (!fp) return false;
        DsdFileHeader hdr = parse_dsd_file_header(fp);
        if (!hdr.valid) {
            std::fclose(fp);
            return false;
        }
        fp_ = fp;
        ownsFile_ = true;
        hdr_ = hdr;
        return post_open_init();
    }

    bool post_open_init() {
        if (hdr_.channels == 0 || hdr_.dsdSampleRate == 0) return false;
        uint64_t maxFramesByFile = hdr_.dataByteSize / hdr_.channels;
        uint64_t declaredFrames = hdr_.totalBytesPerChannel();
        totalByteFrames_ = (declaredFrames > 0) ? std::min(declaredFrames, maxFramesByFile) : maxFramesByFile;
        curByteFrame_ = 0;
        dsfLoadedBlockIdx_ = UINT64_MAX;
        if (hdr_.blockInterleaved) {
            dsfBlockBuf_.assign(static_cast<size_t>(hdr_.blockSizePerChannel) * hdr_.channels, kDsdSilenceByte);
        }
        return true;
    }

    bool load_dsf_block(uint64_t blkIdx) {
        const uint64_t blkSetBytes = static_cast<uint64_t>(hdr_.blockSizePerChannel) * hdr_.channels;
        uint64_t off = hdr_.dataOffset + blkIdx * blkSetBytes;
        if (!seek_64(fp_, static_cast<int64_t>(off), SEEK_SET)) return false;
        size_t want = static_cast<size_t>(blkSetBytes);
        std::fill(dsfBlockBuf_.begin(), dsfBlockBuf_.end(), hdr_.bitsLsbFirst ? kBitReverseTable[kDsdSilenceByte] : kDsdSilenceByte);
        size_t got = std::fread(dsfBlockBuf_.data(), 1, want, fp_);
        (void)got;
        dsfLoadedBlockIdx_ = blkIdx;
        return true;
    }

    FILE* fp_ = nullptr;
    bool ownsFile_ = false;
    DsdFileHeader hdr_;
    uint64_t totalByteFrames_ = 0;
    uint64_t curByteFrame_ = 0;
    uint64_t dsfLoadedBlockIdx_ = UINT64_MAX;
    std::vector<uint8_t> dsfBlockBuf_;
    std::vector<uint8_t> dffReadBuf_;
};

// ============================================================================
// D2P: 128-tap Blackman-Harris Windowed-Sinc Low-Pass FIR Decimator + 16x256 LUT
// ============================================================================

class DsdToPcmDecimator {
public:
    static inline constexpr double kPi = 3.14159265358979323846;

    bool init(uint32_t dsdSampleRate, uint32_t targetPcmRate, uint32_t channels, float gainBoostDb = 6.0f, float cutoffHz = 24000.0f) {
        if (dsdSampleRate == 0 || targetPcmRate == 0 || channels == 0 || channels > 8) return false;
        dsdRate_ = dsdSampleRate;
        pcmRate_ = targetPcmRate;
        channels_ = channels;
        cutoffHz_ = std::max(16000.0f, cutoffHz);
        gainBoostDb_ = std::max(-12.0f, std::min(12.0f, gainBoostDb));

        const uint32_t dsdBytesPerSec = dsdRate_ / 8u;
        if (dsdBytesPerSec >= pcmRate_ && (dsdBytesPerSec % pcmRate_) == 0) {
            exactIntegerBytes_ = true;
            bytesPerOutFrame_ = dsdBytesPerSec / pcmRate_;
            if (bytesPerOutFrame_ <= static_cast<uint32_t>(kD2pFilterBytes)) {
                subStepBytes_ = std::max(1u, bytesPerOutFrame_);
                subStepsPerOut_ = 1u;
            } else {
                // Keep step <= 16 bytes so zero DSD bytes are skipped on DSD512/1024 -> 88.2k
                uint32_t bestStep = 16u;
                while (bestStep > 1u && (bytesPerOutFrame_ % bestStep) != 0) {
                    --bestStep;
                }
                subStepBytes_ = bestStep;
                subStepsPerOut_ = bytesPerOutFrame_ / bestStep;
            }
        } else {
            // Fractional fallback rate (e.g., 44.1k DSD -> 48k PCM if queried directly)
            exactIntegerBytes_ = false;
            uint32_t cleanRate = default_d2p_rate_for_dsd(dsdRate_, 0);
            uint32_t cleanBytes = (dsdBytesPerSec >= cleanRate && (dsdBytesPerSec % cleanRate) == 0)
                ? (dsdBytesPerSec / cleanRate)
                : 4u;
            subStepBytes_ = std::min<uint32_t>(kD2pFilterBytes, std::max(1u, cleanBytes));
            subStepsPerOut_ = 1u;
            internalRateForInterp_ = static_cast<double>(dsdBytesPerSec) / static_cast<double>(subStepBytes_);
            bytesPerOutFrame_ = subStepBytes_;
        }

        rebuild_filter_lut();
        history_.assign(channels_, std::array<uint8_t, kD2pFilterBytes>{});
        prevInterpSample_.assign(channels_, 0.0f);
        currInterpSample_.assign(channels_, 0.0f);
        interpPhase_ = 1.0;
        hasInterpPrimed_ = false;
        reset();
        return true;
    }

    void reset() {
        for (auto& chHist : history_) {
            chHist.fill(kDsdSilenceByte);
        }
        std::fill(prevInterpSample_.begin(), prevInterpSample_.end(), 0.0f);
        std::fill(currInterpSample_.begin(), currInterpSample_.end(), 0.0f);
        interpPhase_ = 1.0;
        hasInterpPrimed_ = false;
    }

    void setGainBoostDb(float gainBoostDb) {
        float clamped = std::max(-12.0f, std::min(12.0f, gainBoostDb));
        if (std::abs(clamped - gainBoostDb_) > 1e-4f) {
            gainBoostDb_ = clamped;
            rebuild_lut_only();
        }
    }

    float gainBoostDb() const { return gainBoostDb_; }
    uint32_t bytesPerOutFrame() const { return bytesPerOutFrame_; }
    uint32_t subStepBytes() const { return subStepBytes_; }
    uint32_t subStepsPerOut() const { return subStepsPerOut_; }
    bool isExactIntegerBytes() const { return exactIntegerBytes_; }

    // Decimates `pcmFrameCount * bytesPerOutFrame_` interleaved MSB-first DSD byte frames
    // into `pcmFrameCount * channels_` float32 PCM samples (for exact integer-byte mode).
    void decimateExact(const uint8_t* msbDsdBytesInterleaved, float* outFloatPcm, uint64_t pcmFrameCount) {
        if (!msbDsdBytesInterleaved || !outFloatPcm || pcmFrameCount == 0 || !exactIntegerBytes_) return;
        const uint32_t ch = channels_;
        const uint32_t step = subStepBytes_;
        const uint32_t subSteps = subStepsPerOut_;
        const float invSub = 1.0f / static_cast<float>(subSteps);

        const uint8_t* src = msbDsdBytesInterleaved;
        float* dst = outFloatPcm;

        for (uint64_t f = 0; f < pcmFrameCount; ++f) {
            float accum[8]{};
            for (uint32_t s = 0; s < subSteps; ++s) {
                for (uint32_t b = 0; b < step; ++b) {
                    const uint8_t* row = src + static_cast<size_t>(b) * ch;
                    for (uint32_t c = 0; c < ch; ++c) {
                        push_byte(c, row[c]);
                    }
                }
                src += static_cast<size_t>(step) * ch;

                for (uint32_t c = 0; c < ch; ++c) {
                    accum[c] += eval_lut_channel(c);
                }
            }

            for (uint32_t c = 0; c < ch; ++c) {
                float v = (subSteps == 1u) ? accum[c] : (accum[c] * invSub);
                dst[c] = soft_clip(v);
            }
            dst += ch;
        }
    }

    // Convenience helper driving `DsdStreamReader` -> float PCM for both exact and fractional rates.
    uint64_t readAndDecimate(DsdStreamReader& reader, float* outFloatPcm, uint64_t pcmFrameCount) {
        if (!outFloatPcm || pcmFrameCount == 0 || channels_ == 0) return 0;

        if (exactIntegerBytes_) {
            uint64_t dsdByteFramesNeeded = pcmFrameCount * bytesPerOutFrame_;
            scratch_.resize(static_cast<size_t>(dsdByteFramesNeeded * channels_));
            uint64_t gotByteFrames = reader.readByteFrames(scratch_.data(), dsdByteFramesNeeded);
            if (gotByteFrames == 0) return 0;

            uint64_t fullOutFrames = gotByteFrames / bytesPerOutFrame_;
            uint64_t remByteFrames = gotByteFrames % bytesPerOutFrame_;
            if (remByteFrames > 0) {
                // Pad partial tail frame at EOF with DSD silence (0x69) to avoid truncation click
                uint64_t padFrames = bytesPerOutFrame_ - remByteFrames;
                std::memset(
                    scratch_.data() + static_cast<size_t>(gotByteFrames * channels_),
                    kDsdSilenceByte,
                    static_cast<size_t>(padFrames * channels_));
                fullOutFrames += 1;
            }
            if (fullOutFrames > pcmFrameCount) fullOutFrames = pcmFrameCount;
            decimateExact(scratch_.data(), outFloatPcm, fullOutFrames);
            return fullOutFrames;
        }

        // Fractional output rate path: step internal sub-filter & linearly interpolate
        const double stepRatio = internalRateForInterp_ / static_cast<double>(pcmRate_);
        uint64_t produced = 0;
        const uint32_t ch = channels_;
        uint8_t stepBuf[16 * 8]{};

        auto advance_internal = [&]() -> bool {
            uint64_t got = reader.readByteFrames(stepBuf, subStepBytes_);
            if (got == 0) return false;
            if (got < subStepBytes_) {
                std::memset(stepBuf + static_cast<size_t>(got * ch), kDsdSilenceByte, static_cast<size_t>((subStepBytes_ - got) * ch));
            }
            for (uint32_t b = 0; b < subStepBytes_; ++b) {
                for (uint32_t c = 0; c < ch; ++c) {
                    push_byte(c, stepBuf[b * ch + c]);
                }
            }
            for (uint32_t c = 0; c < ch; ++c) {
                prevInterpSample_[c] = currInterpSample_[c];
                currInterpSample_[c] = eval_lut_channel(c);
            }
            return true;
        };

        if (!hasInterpPrimed_) {
            if (!advance_internal()) return 0;
            hasInterpPrimed_ = true;
            interpPhase_ = 0.0;
        }

        while (produced < pcmFrameCount) {
            while (interpPhase_ >= 1.0) {
                if (!advance_internal()) return produced;
                interpPhase_ -= 1.0;
            }
            const float t = static_cast<float>(interpPhase_);
            for (uint32_t c = 0; c < ch; ++c) {
                float v = prevInterpSample_[c] + (currInterpSample_[c] - prevInterpSample_[c]) * t;
                outFloatPcm[produced * ch + c] = soft_clip(v);
            }
            interpPhase_ += stepRatio;
            ++produced;
        }
        return produced;
    }

    static inline float soft_clip(float v) {
        constexpr float kKnee = 0.95f;
        constexpr float kHead = 1.0f - kKnee;
        float av = std::abs(v);
        if (av <= kKnee) return v;
        float sign = (v < 0.0f) ? -1.0f : 1.0f;
        return sign * (kKnee + kHead * std::tanh((av - kKnee) / kHead));
    }

    const std::array<std::array<float, 256>, kD2pFilterBytes>& lut() const { return lut_; }

private:
    void push_byte(uint32_t c, uint8_t b) {
        auto& h = history_[c];
        std::memmove(h.data(), h.data() + 1, kD2pFilterBytes - 1);
        h[kD2pFilterBytes - 1] = b;
    }

    float eval_lut_channel(uint32_t c) const {
        const auto& h = history_[c];
        float sum = 0.0f;
        for (int i = 0; i < kD2pFilterBytes; ++i) {
            sum += lut_[static_cast<size_t>(i)][h[static_cast<size_t>(i)]];
        }
        return sum;
    }

    void rebuild_filter_lut() {
        constexpr int N = kD2pFilterTaps;
        constexpr double a0 = 0.35875;
        constexpr double a1 = 0.48829;
        constexpr double a2 = 0.14128;
        constexpr double a3 = 0.01168;
        const double fcNorm = std::min(0.45, static_cast<double>(cutoffHz_) / static_cast<double>(dsdRate_));
        const double center = 0.5 * static_cast<double>(N - 1);

        double sumW = 0.0;
        for (int n = 0; n < N; ++n) {
            const double w = a0
                - a1 * std::cos(2.0 * kPi * n / (N - 1))
                + a2 * std::cos(4.0 * kPi * n / (N - 1))
                - a3 * std::cos(6.0 * kPi * n / (N - 1));
            const double x = static_cast<double>(n) - center;
            const double sincVal = (std::abs(x) < 1e-12)
                ? 1.0
                : std::sin(2.0 * kPi * fcNorm * x) / (2.0 * kPi * fcNorm * x);
            double coeff = w * sincVal;
            coeffs_[static_cast<size_t>(n)] = coeff;
            sumW += coeff;
        }
        if (sumW > 0.0) {
            for (double& c : coeffs_) c /= sumW;
        }
        rebuild_lut_only();
    }

    void rebuild_lut_only() {
        const double linearGain = std::pow(10.0, static_cast<double>(gainBoostDb_) / 20.0);
        for (int byteIdx = 0; byteIdx < kD2pFilterBytes; ++byteIdx) {
            for (int val = 0; val < 256; ++val) {
                double s = 0.0;
                for (int bit = 0; bit < 8; ++bit) {
                    int tap = byteIdx * 8 + bit;
                    bool one = ((val >> (7 - bit)) & 1) != 0;
                    s += (one ? 1.0 : -1.0) * coeffs_[static_cast<size_t>(tap)];
                }
                lut_[static_cast<size_t>(byteIdx)][static_cast<size_t>(val)] = static_cast<float>(s * linearGain);
            }
        }
    }

    uint32_t dsdRate_ = 2822400;
    uint32_t pcmRate_ = 88200;
    uint32_t channels_ = 2;
    float cutoffHz_ = 24000.0f;
    float gainBoostDb_ = 6.0f;

    bool exactIntegerBytes_ = true;
    uint32_t bytesPerOutFrame_ = 4;
    uint32_t subStepBytes_ = 4;
    uint32_t subStepsPerOut_ = 1;
    double internalRateForInterp_ = 88200.0;

    std::array<double, kD2pFilterTaps> coeffs_{};
    std::array<std::array<float, 256>, kD2pFilterBytes> lut_{};
    std::vector<std::array<uint8_t, kD2pFilterBytes>> history_;
    std::vector<uint8_t> scratch_;

    std::vector<float> prevInterpSample_;
    std::vector<float> currInterpSample_;
    double interpPhase_ = 1.0;
    bool hasInterpPrimed_ = false;
};

// ============================================================================
// DoP v1.1 & Native DSD (32-bit USB UAC2 RAW_DATA) Packers & Silence Helpers
// ============================================================================

// Packs `frameCount` DoP v1.1 frames into 3-byte little-endian packed S24.
// `msbDsdBytesInterleaved` must contain `frameCount * 2 * channels` MSB-first DSD bytes.
inline void pack_dop_s24(
    const uint8_t* msbDsdBytesInterleaved,
    uint8_t* dstOut,
    uint64_t frameCount,
    uint32_t channels,
    bool& markerToggle
) {
    if (!msbDsdBytesInterleaved || !dstOut || frameCount == 0 || channels == 0) return;
    for (uint64_t f = 0; f < frameCount; ++f) {
        const uint8_t marker = markerToggle ? 0xFAu : 0x05u;
        markerToggle = !markerToggle;
        const uint8_t* row0 = msbDsdBytesInterleaved + static_cast<size_t>(f * 2u) * channels;
        const uint8_t* row1 = row0 + channels;
        for (uint32_t c = 0; c < channels; ++c) {
            const uint8_t b0 = row0[c]; // oldest 8 bits -> bits [15:8]
            const uint8_t b1 = row1[c]; // newest 8 bits -> bits [7:0]
            dstOut[0] = b1;
            dstOut[1] = b0;
            dstOut[2] = marker;
            dstOut += 3;
        }
    }
}

// Packs `frameCount` DoP v1.1 frames into 32-bit MSB-aligned S32 (`word << 8`, bits [31:8]).
// `msbDsdBytesInterleaved` must contain `frameCount * 2 * channels` MSB-first DSD bytes.
inline void pack_dop_s32(
    const uint8_t* msbDsdBytesInterleaved,
    int32_t* dstOut,
    uint64_t frameCount,
    uint32_t channels,
    bool& markerToggle
) {
    if (!msbDsdBytesInterleaved || !dstOut || frameCount == 0 || channels == 0) return;
    for (uint64_t f = 0; f < frameCount; ++f) {
        const uint32_t marker = markerToggle ? 0xFAu : 0x05u;
        markerToggle = !markerToggle;
        const uint8_t* row0 = msbDsdBytesInterleaved + static_cast<size_t>(f * 2u) * channels;
        const uint8_t* row1 = row0 + channels;
        for (uint32_t c = 0; c < channels; ++c) {
            const uint32_t b0 = row0[c];
            const uint32_t b1 = row1[c];
            const uint32_t word = (marker << 24) | (b0 << 16) | (b1 << 8);
            *dstOut++ = static_cast<int32_t>(word);
        }
    }
}

// Packs `frameCount` Native DSD 32-bit frames (SNDRV_PCM_FORMAT_DSD_U32_LE).
// `msbDsdBytesInterleaved` must contain `frameCount * 4 * channels` MSB-first DSD bytes.
inline void pack_native_dsd_s32(
    const uint8_t* msbDsdBytesInterleaved,
    int32_t* dstOut,
    uint64_t frameCount,
    uint32_t channels
) {
    if (!msbDsdBytesInterleaved || !dstOut || frameCount == 0 || channels == 0) return;
    for (uint64_t f = 0; f < frameCount; ++f) {
        const uint8_t* base = msbDsdBytesInterleaved + static_cast<size_t>(f * 4u) * channels;
        const uint8_t* r0 = base;
        const uint8_t* r1 = base + channels;
        const uint8_t* r2 = base + static_cast<size_t>(channels) * 2u;
        const uint8_t* r3 = base + static_cast<size_t>(channels) * 3u;
        for (uint32_t c = 0; c < channels; ++c) {
            const uint32_t word =
                (static_cast<uint32_t>(r0[c]) << 24) |
                (static_cast<uint32_t>(r1[c]) << 16) |
                (static_cast<uint32_t>(r2[c]) << 8) |
                static_cast<uint32_t>(r3[c]);
            *dstOut++ = static_cast<int32_t>(word);
        }
    }
}

// Fills raw Native DSD buffer with DSD silence pattern 0x69.
inline void fill_native_dsd_silence(void* dstOut, size_t byteCount) {
    if (!dstOut || byteCount == 0) return;
    std::memset(dstOut, kDsdSilenceByte, byteCount);
}

// Fills DoP buffer (`ma_format_s24` or `ma_format_s32`) with valid DoP silence
// (0x056969 / 0xFA6969 alternating markers) so hardware never drops lock or clicks.
inline void fill_dop_silence_frames(
    void* dstOut,
    uint64_t frameCount,
    uint32_t channels,
    ma_format format,
    bool& markerToggle
) {
    if (!dstOut || frameCount == 0 || channels == 0) return;
    if (format == ma_format_s24) {
        uint8_t* p = static_cast<uint8_t*>(dstOut);
        for (uint64_t f = 0; f < frameCount; ++f) {
            const uint8_t marker = markerToggle ? 0xFAu : 0x05u;
            markerToggle = !markerToggle;
            for (uint32_t c = 0; c < channels; ++c) {
                p[0] = kDsdSilenceByte;
                p[1] = kDsdSilenceByte;
                p[2] = marker;
                p += 3;
            }
        }
    } else if (format == ma_format_s32) {
        int32_t* p = static_cast<int32_t*>(dstOut);
        for (uint64_t f = 0; f < frameCount; ++f) {
            const uint32_t marker = markerToggle ? 0xFAu : 0x05u;
            markerToggle = !markerToggle;
            const int32_t word = static_cast<int32_t>(
                (marker << 24) |
                (static_cast<uint32_t>(kDsdSilenceByte) << 16) |
                (static_cast<uint32_t>(kDsdSilenceByte) << 8));
            for (uint32_t c = 0; c < channels; ++c) {
                *p++ = word;
            }
        }
    } else {
        std::memset(dstOut, 0, static_cast<size_t>(frameCount * channels * ma_get_bytes_per_sample(format)));
    }
}

// ============================================================================
// Custom miniaudio Data Source & Decoding Backend for .dsf / .dff
// ============================================================================

struct DsdOpenOptions {
    AEDsdOutputMode mode = AE_DSD_MODE_D2P;
    uint32_t requestedD2pRate = 0;
    ma_format dopFormat = ma_format_s32;
    float d2pGainBoostDb = 6.0f;
    bool openedAsDsd = false;
    AEDsdOutputMode actualMode = AE_DSD_MODE_D2P;
    uint32_t sourceDsdRate = 0;
    uint32_t outputRate = 0;
    uint32_t outputChannels = 0;
    ma_format outputFormat = ma_format_f32;
};

inline DsdOpenOptions& tls_dsd_open_options() {
    thread_local DsdOpenOptions opts;
    return opts;
}

struct DsdDataSource {
    ma_data_source_base base;
    uint32_t magic = 0x44534453u; // "DSDS"
    DsdStreamReader reader;
    DsdToPcmDecimator decimator;
    AEDsdOutputMode activeMode = AE_DSD_MODE_D2P;
    ma_format outputFormat = ma_format_f32;
    uint32_t outputSampleRate = 88200;
    uint32_t outputChannels = 2;
    float d2pGainBoostDb = 6.0f;
    uint64_t cursorFrames = 0;
    uint64_t totalFrames = 0;
    bool dopMarkerToggle = false;
    std::vector<uint8_t> dsdScratch;
};

inline ma_result dsd_ds_on_read(ma_data_source* pDataSource, void* pFramesOut, ma_uint64 frameCount, ma_uint64* pFramesRead) {
    if (pFramesRead) *pFramesRead = 0;
    auto* ds = reinterpret_cast<DsdDataSource*>(pDataSource);
    if (!ds || ds->magic != 0x44534453u || !pFramesOut || frameCount == 0) {
        return MA_INVALID_ARGS;
    }

    const uint32_t ch = ds->outputChannels;
    uint64_t framesRead = 0;

    if (ds->activeMode == AE_DSD_MODE_D2P) {
        framesRead = ds->decimator.readAndDecimate(ds->reader, static_cast<float*>(pFramesOut), frameCount);
    } else if (ds->activeMode == AE_DSD_MODE_DOP) {
        const uint64_t byteFramesWanted = frameCount * 2ull;
        ds->dsdScratch.resize(static_cast<size_t>(byteFramesWanted * ch));
        uint64_t gotByteFrames = ds->reader.readByteFrames(ds->dsdScratch.data(), byteFramesWanted);
        if (gotByteFrames > 0) {
            uint64_t completeFrames = gotByteFrames / 2ull;
            if ((gotByteFrames % 2ull) != 0) {
                // Odd byte at EOF -> pad missing byte with DSD silence
                std::memset(ds->dsdScratch.data() + static_cast<size_t>(gotByteFrames * ch), kDsdSilenceByte, ch);
                completeFrames += 1;
            }
            if (completeFrames > frameCount) completeFrames = frameCount;
            if (ds->outputFormat == ma_format_s24) {
                pack_dop_s24(ds->dsdScratch.data(), static_cast<uint8_t*>(pFramesOut), completeFrames, ch, ds->dopMarkerToggle);
            } else {
                pack_dop_s32(ds->dsdScratch.data(), static_cast<int32_t*>(pFramesOut), completeFrames, ch, ds->dopMarkerToggle);
            }
            framesRead = completeFrames;
        }
    } else if (ds->activeMode == AE_DSD_MODE_NATIVE) {
        const uint64_t byteFramesWanted = frameCount * 4ull;
        ds->dsdScratch.resize(static_cast<size_t>(byteFramesWanted * ch));
        uint64_t gotByteFrames = ds->reader.readByteFrames(ds->dsdScratch.data(), byteFramesWanted);
        if (gotByteFrames > 0) {
            uint64_t completeFrames = (gotByteFrames + 3ull) / 4ull;
            uint64_t paddedByteFrames = completeFrames * 4ull;
            if (gotByteFrames < paddedByteFrames) {
                std::memset(
                    ds->dsdScratch.data() + static_cast<size_t>(gotByteFrames * ch),
                    kDsdSilenceByte,
                    static_cast<size_t>((paddedByteFrames - gotByteFrames) * ch));
            }
            if (completeFrames > frameCount) completeFrames = frameCount;
            pack_native_dsd_s32(ds->dsdScratch.data(), static_cast<int32_t*>(pFramesOut), completeFrames, ch);
            framesRead = completeFrames;
        }
    }

    ds->cursorFrames += framesRead;
    if (pFramesRead) *pFramesRead = framesRead;
    if (framesRead == 0) return MA_AT_END;
    return MA_SUCCESS;
}

inline ma_result dsd_ds_on_seek(ma_data_source* pDataSource, ma_uint64 frameIndex) {
    auto* ds = reinterpret_cast<DsdDataSource*>(pDataSource);
    if (!ds || ds->magic != 0x44534453u) return MA_INVALID_ARGS;

    if (frameIndex > ds->totalFrames) frameIndex = ds->totalFrames;
    const uint32_t dsdRate = ds->reader.header().dsdSampleRate;
    const uint64_t totalByteFrames = ds->reader.totalByteFrames();

    uint64_t targetByteFrame = 0;
    if (ds->activeMode == AE_DSD_MODE_DOP) {
        targetByteFrame = frameIndex * 2ull;
    } else if (ds->activeMode == AE_DSD_MODE_NATIVE) {
        targetByteFrame = frameIndex * 4ull;
    } else {
        const double bytesPerPcmFrame = static_cast<double>(dsdRate) / (8.0 * static_cast<double>(ds->outputSampleRate));
        targetByteFrame = static_cast<uint64_t>(static_cast<double>(frameIndex) * bytesPerPcmFrame + 0.5);
        ds->decimator.reset();
    }

    if (targetByteFrame > totalByteFrames) targetByteFrame = totalByteFrames;
    if (!ds->reader.seekByteFrame(targetByteFrame)) return MA_IO_ERROR;
    ds->cursorFrames = frameIndex;
    ds->dopMarkerToggle = ((frameIndex & 1ull) != 0);
    return MA_SUCCESS;
}

inline ma_result dsd_ds_on_get_data_format(
    ma_data_source* pDataSource,
    ma_format* pFormat,
    ma_uint32* pChannels,
    ma_uint32* pSampleRate,
    ma_channel* pChannelMap,
    size_t channelMapCap
) {
    auto* ds = reinterpret_cast<DsdDataSource*>(pDataSource);
    if (!ds || ds->magic != 0x44534453u) return MA_INVALID_ARGS;

    if (pFormat) *pFormat = ds->outputFormat;
    if (pChannels) *pChannels = ds->outputChannels;
    if (pSampleRate) *pSampleRate = ds->outputSampleRate;
    if (pChannelMap && channelMapCap > 0) {
        ma_channel_map_init_standard(ma_standard_channel_map_default, pChannelMap, channelMapCap, ds->outputChannels);
    }
    return MA_SUCCESS;
}

inline ma_result dsd_ds_on_get_cursor(ma_data_source* pDataSource, ma_uint64* pCursor) {
    auto* ds = reinterpret_cast<DsdDataSource*>(pDataSource);
    if (!ds || ds->magic != 0x44534453u || !pCursor) return MA_INVALID_ARGS;
    *pCursor = ds->cursorFrames;
    return MA_SUCCESS;
}

inline ma_result dsd_ds_on_get_length(ma_data_source* pDataSource, ma_uint64* pLength) {
    auto* ds = reinterpret_cast<DsdDataSource*>(pDataSource);
    if (!ds || ds->magic != 0x44534453u || !pLength) return MA_INVALID_ARGS;
    *pLength = ds->totalFrames;
    return MA_SUCCESS;
}

inline ma_data_source_vtable g_dsd_data_source_vtable = {
    dsd_ds_on_read,
    dsd_ds_on_seek,
    dsd_ds_on_get_data_format,
    dsd_ds_on_get_cursor,
    dsd_ds_on_get_length,
    nullptr, // onSetLooping (handled by ma_data_source_base / ma_decoder)
    0
};

inline bool configure_dsd_data_source(
    DsdDataSource* ds,
    AEDsdOutputMode mode,
    ma_format dopFormat,
    uint32_t requestedD2pRate,
    float gainBoostDb
) {
    if (!ds) return false;
    const DsdFileHeader& hdr = ds->reader.header();
    if (!hdr.valid || hdr.channels == 0 || hdr.dsdSampleRate == 0) return false;

    const AEDsdOutputMode effectiveMode = (mode == AE_DSD_MODE_AUTO) ? AE_DSD_MODE_D2P : mode;
    const uint64_t byteFrames = ds->reader.totalByteFrames();

    ds->activeMode = effectiveMode;
    ds->outputChannels = hdr.channels;
    ds->d2pGainBoostDb = gainBoostDb;
    ds->dopMarkerToggle = false;

    if (effectiveMode == AE_DSD_MODE_NATIVE) {
        ds->outputFormat = ma_format_s32;
        ds->outputSampleRate = hdr.dsdSampleRate / 32u;
        ds->totalFrames = byteFrames / 4ull;
    } else if (effectiveMode == AE_DSD_MODE_DOP) {
        ds->outputFormat = (dopFormat == ma_format_s24) ? ma_format_s24 : ma_format_s32;
        ds->outputSampleRate = hdr.dsdSampleRate / 16u;
        ds->totalFrames = byteFrames / 2ull;
    } else {
        ds->activeMode = AE_DSD_MODE_D2P;
        ds->outputFormat = ma_format_f32;
        ds->outputSampleRate = default_d2p_rate_for_dsd(hdr.dsdSampleRate, requestedD2pRate);
        if (!ds->decimator.init(hdr.dsdSampleRate, ds->outputSampleRate, hdr.channels, gainBoostDb)) {
            return false;
        }
        const double ratio = static_cast<double>(ds->outputSampleRate) / static_cast<double>(hdr.dsdSampleRate);
        ds->totalFrames = static_cast<uint64_t>(static_cast<double>(hdr.totalDsdSamplesPerChannel) * ratio + 0.5);
    }

    ds->cursorFrames = 0;
    ds->reader.seekByteFrame(0);
    return ds->outputSampleRate > 0;
}

inline ma_result init_dsd_data_source_common(
    DsdDataSource* ds,
    const ma_decoding_backend_config* pConfig
) {
    (void)pConfig;
    DsdOpenOptions& opts = tls_dsd_open_options();
    ma_format dopFmt = (opts.dopFormat == ma_format_s24 || opts.dopFormat == ma_format_s32)
        ? opts.dopFormat
        : ma_format_s32;
    if (!configure_dsd_data_source(ds, opts.mode, dopFmt, opts.requestedD2pRate, opts.d2pGainBoostDb)) {
        return MA_INVALID_FILE;
    }

    ma_data_source_config dsCfg = ma_data_source_config_init();
    dsCfg.vtable = &g_dsd_data_source_vtable;
    ma_result r = ma_data_source_init(&dsCfg, &ds->base);
    if (r != MA_SUCCESS) return r;

    opts.openedAsDsd = true;
    opts.actualMode = ds->activeMode;
    opts.sourceDsdRate = ds->reader.header().dsdSampleRate;
    opts.outputRate = ds->outputSampleRate;
    opts.outputChannels = ds->outputChannels;
    opts.outputFormat = ds->outputFormat;
    return MA_SUCCESS;
}

inline ma_result dsd_backend_on_init_file(
    void* pUserData,
    const char* pFilePath,
    const ma_decoding_backend_config* pConfig,
    const ma_allocation_callbacks* pAllocationCallbacks,
    ma_data_source** ppBackend
) {
    (void)pUserData;
    (void)pAllocationCallbacks;
    if (!ppBackend || !pFilePath) return MA_INVALID_ARGS;
    *ppBackend = nullptr;

    if (!is_dsd_file_path(pFilePath)) {
        return MA_NO_BACKEND;
    }

    auto* ds = new (std::nothrow) DsdDataSource();
    if (!ds) return MA_OUT_OF_MEMORY;

    if (!ds->reader.open(pFilePath)) {
        delete ds;
        return MA_NO_BACKEND;
    }

    ma_result r = init_dsd_data_source_common(ds, pConfig);
    if (r != MA_SUCCESS) {
        delete ds;
        return r;
    }

    *ppBackend = &ds->base;
    return MA_SUCCESS;
}

inline ma_result dsd_backend_on_init_file_w(
    void* pUserData,
    const wchar_t* pFilePath,
    const ma_decoding_backend_config* pConfig,
    const ma_allocation_callbacks* pAllocationCallbacks,
    ma_data_source** ppBackend
) {
    (void)pUserData;
    (void)pAllocationCallbacks;
    if (!ppBackend || !pFilePath) return MA_INVALID_ARGS;
    *ppBackend = nullptr;

    if (!is_dsd_file_path_w(pFilePath)) {
        return MA_NO_BACKEND;
    }

    auto* ds = new (std::nothrow) DsdDataSource();
    if (!ds) return MA_OUT_OF_MEMORY;

    if (!ds->reader.open_w(pFilePath)) {
        delete ds;
        return MA_NO_BACKEND;
    }

    ma_result r = init_dsd_data_source_common(ds, pConfig);
    if (r != MA_SUCCESS) {
        delete ds;
        return r;
    }

    *ppBackend = &ds->base;
    return MA_SUCCESS;
}

inline void dsd_backend_on_uninit(
    void* pUserData,
    ma_data_source* pBackend,
    const ma_allocation_callbacks* pAllocationCallbacks
) {
    (void)pUserData;
    (void)pAllocationCallbacks;
    if (!pBackend) return;
    auto* ds = reinterpret_cast<DsdDataSource*>(pBackend);
    if (ds->magic == 0x44534453u) {
        ma_data_source_uninit(&ds->base);
        ds->magic = 0;
        delete ds;
    }
}

inline ma_decoding_backend_vtable g_ma_decoding_backend_vtable_dsd = {
    nullptr, // onInit (stream callbacks not needed for local .dsf/.dff files)
    dsd_backend_on_init_file,
    dsd_backend_on_init_file_w,
    nullptr, // onInitMemory
    dsd_backend_on_uninit
};

inline DsdDataSource* try_get_dsd_data_source(ma_decoder* dec) {
    if (!dec || !dec->pBackend) return nullptr;
    const auto* base = reinterpret_cast<const ma_data_source_base*>(dec->pBackend);
    if (base->vtable != &g_dsd_data_source_vtable) return nullptr;
    auto* ds = reinterpret_cast<DsdDataSource*>(dec->pBackend);
    return (ds->magic == 0x44534453u) ? ds : nullptr;
}

inline bool query_dsd_decoder_info(
    ma_decoder* dec,
    AEDsdOutputMode* outActiveMode = nullptr,
    uint32_t* outSourceDsdRate = nullptr,
    uint32_t* outOutputRate = nullptr,
    ma_format* outOutputFormat = nullptr,
    uint32_t* outChannels = nullptr
) {
    DsdDataSource* ds = try_get_dsd_data_source(dec);
    if (!ds) return false;
    if (outActiveMode) *outActiveMode = ds->activeMode;
    if (outSourceDsdRate) *outSourceDsdRate = ds->reader.header().dsdSampleRate;
    if (outOutputRate) *outOutputRate = ds->outputSampleRate;
    if (outOutputFormat) *outOutputFormat = ds->outputFormat;
    if (outChannels) *outChannels = ds->outputChannels;
    return true;
}

inline bool set_dsd_decoder_gain_boost_db(ma_decoder* dec, float gainBoostDb) {
    DsdDataSource* ds = try_get_dsd_data_source(dec);
    if (!ds) return false;
    ds->d2pGainBoostDb = gainBoostDb;
    if (ds->activeMode == AE_DSD_MODE_D2P) {
        ds->decimator.setGainBoostDb(gainBoostDb);
    }
    return true;
}

// Reconfigures a DSD data source in place (note: if the parent ma_decoder had a format/rate
// converter active, reload via load_decoder_for_path to rebuild ma_data_converter).
inline bool reconfigure_dsd_decoder_to_d2p(
    ma_decoder* dec,
    uint32_t targetD2pRate,
    float gainBoostDb
) {
    DsdDataSource* ds = try_get_dsd_data_source(dec);
    if (!ds) return false;
    return configure_dsd_data_source(ds, AE_DSD_MODE_D2P, ma_format_s32, targetD2pRate, gainBoostDb);
}

} // namespace dsd
} // namespace sautiflow
