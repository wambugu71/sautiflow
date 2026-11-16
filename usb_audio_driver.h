#pragma once

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <vector>

#include "audio_engine.h"
#include "third_party/libusb/libusb.h"

namespace sautiflow {
namespace usb {

// USB Audio Class (UAC) Descriptor Constants
static constexpr uint8_t USB_CLASS_AUDIO = 0x01;
static constexpr uint8_t USB_SUBCLASS_AUDIOCONTROL = 0x01;
static constexpr uint8_t USB_SUBCLASS_AUDIOSTREAMING = 0x02;
static constexpr uint8_t USB_PROTOCOL_UAC1 = 0x00;
static constexpr uint8_t USB_PROTOCOL_UAC2 = 0x20;

static constexpr uint8_t UAC_DT_CS_INTERFACE = 0x24;
static constexpr uint8_t UAC_DT_CS_ENDPOINT = 0x25;

// AudioControl Subtypes
static constexpr uint8_t UAC_AC_HEADER = 0x01;
static constexpr uint8_t UAC_AC_INPUT_TERMINAL = 0x02;
static constexpr uint8_t UAC_AC_OUTPUT_TERMINAL = 0x03;
static constexpr uint8_t UAC_AC_FEATURE_UNIT = 0x06;
static constexpr uint8_t UAC2_AC_CLOCK_SOURCE = 0x0A;
static constexpr uint8_t UAC2_AC_CLOCK_SELECTOR = 0x0B;
static constexpr uint8_t UAC2_AC_CLOCK_MULTIPLIER = 0x0C;

// AudioStreaming Subtypes
static constexpr uint8_t UAC_AS_GENERAL = 0x01;
static constexpr uint8_t UAC_AS_FORMAT_TYPE = 0x02;

// Format Type & Format Tags
static constexpr uint8_t UAC_FORMAT_TYPE_I = 0x01;
static constexpr uint16_t UAC1_FORMAT_PCM = 0x0001;
static constexpr uint16_t UAC1_FORMAT_IEEE_FLOAT = 0x0003;
static constexpr uint32_t UAC2_FORMAT_PCM = 0x00000001u;
static constexpr uint32_t UAC2_FORMAT_PCM8 = 0x00000002u;
static constexpr uint32_t UAC2_FORMAT_IEEE_FLOAT = 0x00000004u;

// USB Audio Class Requests
static constexpr uint8_t UAC1_SET_CUR = 0x01;
static constexpr uint8_t UAC1_GET_CUR = 0x81;
static constexpr uint8_t UAC2_CS_CUR = 0x01;
static constexpr uint8_t UAC2_CS_RANGE = 0x02;

static constexpr uint8_t UAC_CS_SAM_FREQ_CONTROL = 0x01;
static constexpr uint8_t UAC_FU_MUTE_CONTROL = 0x01;
static constexpr uint8_t UAC2_CX_CLOCK_SELECTOR_CONTROL = 0x01;

struct UsbClockSource {
    uint8_t clockId = 0;
    uint8_t attributes = 0;
    uint8_t controls = 0;
    uint8_t assocTerminal = 0;
};

struct UsbClockSelector {
    uint8_t selectorId = 0;
    uint8_t controls = 0;
    std::vector<uint8_t> inputClockIds;
};

struct UsbClockMultiplier {
    uint8_t multiplierId = 0;
    uint8_t clockInId = 0;
    uint8_t controls = 0;
};

struct UsbAudioTerminal {
    uint8_t terminalId = 0;
    bool isInput = false;
    uint16_t terminalType = 0;
    uint8_t sourceId = 0;
    uint8_t clockSourceId = 0;
};

struct UsbFeatureUnit {
    uint8_t unitId = 0;
    uint8_t sourceId = 0;
    bool hasMuteControl = false;
};

struct UsbAudioAltSetting {
    uint8_t interfaceNumber = 0;
    uint8_t altSetting = 0;
    int uacVersion = 1; // 1 = UAC 1.0, 2 = UAC 2.0

    uint8_t terminalLink = 0;
    uint8_t clockSourceId = 0;

    bool isFloat = false;
    uint8_t channels = 2;
    uint8_t subslotSize = 2;    // Bytes per sample on USB wire (1, 2, 3, or 4)
    uint8_t bitResolution = 16; // Valid audio bits (8, 16, 24, or 32)

    uint8_t epOutAddr = 0;
    uint16_t epOutMaxPacketSize = 0;
    uint8_t epOutInterval = 1;
    uint8_t epOutSyncType = 0; // 1=Async, 2=Adaptive, 3=Sync
    bool uac1EndpointFreqControl = false;

    uint8_t epFeedbackInAddr = 0;
    uint16_t epFeedbackMaxPacketSize = 0;
    uint8_t epFeedbackInterval = 1;

    std::vector<int> supportedSampleRates;
    int continuousRateMin = 0;
    int continuousRateMax = 0;
};

struct UsbAudioDeviceProfile {
    uint16_t vendorId = 0;
    uint16_t productId = 0;
    int uacVersion = 1;
    int acInterfaceNumber = -1;
    bool valid = false;

    std::vector<UsbClockSource> clockSources;
    std::vector<UsbClockSelector> clockSelectors;
    std::vector<UsbClockMultiplier> clockMultipliers;
    std::vector<UsbAudioTerminal> terminals;
    std::vector<UsbFeatureUnit> featureUnits;
    std::vector<UsbAudioAltSetting> altSettings;
};

inline uint16_t read_le16(const uint8_t *p) {
    return static_cast<uint16_t>(p[0]) | (static_cast<uint16_t>(p[1]) << 8);
}

inline uint32_t read_le24(const uint8_t *p) {
    return static_cast<uint32_t>(p[0]) |
           (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16);
}

inline uint32_t read_le32(const uint8_t *p) {
    return static_cast<uint32_t>(p[0]) |
           (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16) |
           (static_cast<uint32_t>(p[3]) << 24);
}

inline uint8_t resolve_effective_clock_id(const UsbAudioDeviceProfile &profile, uint8_t terminalId, uint8_t fallbackClockId = 0) {
    uint8_t cid = fallbackClockId;
    for (const auto &t : profile.terminals) {
        if (t.terminalId == terminalId && t.clockSourceId != 0) {
            cid = t.clockSourceId;
            break;
        }
    }
    // Follow clock selector or multiplier up to a leaf Clock Source (bounded depth).
    for (int hop = 0; hop < 4 && cid != 0; ++hop) {
        bool followed = false;
        for (const auto &sel : profile.clockSelectors) {
            if (sel.selectorId == cid && !sel.inputClockIds.empty()) {
                cid = sel.inputClockIds[0];
                followed = true;
                break;
            }
        }
        if (followed) continue;
        for (const auto &mul : profile.clockMultipliers) {
            if (mul.multiplierId == cid && mul.clockInId != 0) {
                cid = mul.clockInId;
                followed = true;
                break;
            }
        }
        if (!followed) break;
    }
    if (cid == 0 && !profile.clockSources.empty()) {
        cid = profile.clockSources[0].clockId;
    }
    return cid;
}

inline UsbAudioDeviceProfile parse_uac_descriptors(const uint8_t *data, size_t len) {
    UsbAudioDeviceProfile profile;
    if (!data || len < 9) {
        return profile;
    }

    int curIfaceClass = -1;
    int curIfaceSubClass = -1;
    int curIfaceProtocol = -1;
    int curIfaceNum = -1;
    int curAltSetting = -1;

    bool haveActiveAlt = false;
    UsbAudioAltSetting curAlt{};
    bool curAltSupportedFormat = false;
    uint8_t lastEndpointAddr = 0;

    auto flushCurrentAlt = [&]() {
        if (haveActiveAlt && curAltSupportedFormat && curAlt.epOutAddr != 0 && curAlt.channels > 0 && curAlt.subslotSize > 0) {
            if (curAlt.uacVersion == 2) {
                curAlt.clockSourceId = resolve_effective_clock_id(profile, curAlt.terminalLink);
            }
            profile.altSettings.push_back(curAlt);
        }
        haveActiveAlt = false;
        curAltSupportedFormat = false;
        curAlt = UsbAudioAltSetting{};
    };

    size_t pos = 0;
    while (pos + 2 <= len) {
        uint8_t bLen = data[pos];
        uint8_t bType = data[pos + 1];
        if (bLen < 2 || pos + bLen > len) {
            break;
        }
        const uint8_t *d = data + pos;

        if (bType == LIBUSB_DT_DEVICE && bLen >= 18) {
            profile.vendorId = read_le16(d + 8);
            profile.productId = read_le16(d + 10);
        } else if (bType == LIBUSB_DT_INTERFACE && bLen >= 9) {
            flushCurrentAlt();

            curIfaceNum = d[2];
            curAltSetting = d[3];
            curIfaceClass = d[5];
            curIfaceSubClass = d[6];
            curIfaceProtocol = d[7];
            lastEndpointAddr = 0;

            if (curIfaceClass == USB_CLASS_AUDIO && curIfaceSubClass == USB_SUBCLASS_AUDIOCONTROL) {
                if (profile.acInterfaceNumber < 0) {
                    profile.acInterfaceNumber = curIfaceNum;
                    profile.uacVersion = (curIfaceProtocol == USB_PROTOCOL_UAC2) ? 2 : 1;
                }
            } else if (curIfaceClass == USB_CLASS_AUDIO && curIfaceSubClass == USB_SUBCLASS_AUDIOSTREAMING && curAltSetting > 0) {
                haveActiveAlt = true;
                curAlt = UsbAudioAltSetting{};
                curAlt.interfaceNumber = static_cast<uint8_t>(curIfaceNum);
                curAlt.altSetting = static_cast<uint8_t>(curAltSetting);
                curAlt.uacVersion = (curIfaceProtocol == USB_PROTOCOL_UAC2 || profile.uacVersion == 2) ? 2 : 1;
            }
        } else if (bType == UAC_DT_CS_INTERFACE && bLen >= 4) {
            uint8_t subtype = d[2];
            if (curIfaceClass == USB_CLASS_AUDIO && curIfaceSubClass == USB_SUBCLASS_AUDIOCONTROL) {
                bool isUac2 = (curIfaceProtocol == USB_PROTOCOL_UAC2 || profile.uacVersion == 2);
                if (subtype == UAC_AC_HEADER && bLen >= 6) {
                    uint16_t bcdADC = read_le16(d + 3);
                    if (bcdADC >= 0x0200) {
                        profile.uacVersion = 2;
                    }
                } else if (isUac2 && subtype == UAC2_AC_CLOCK_SOURCE && bLen >= 8) {
                    UsbClockSource cs;
                    cs.clockId = d[3];
                    cs.attributes = d[4];
                    cs.controls = d[5];
                    cs.assocTerminal = d[6];
                    profile.clockSources.push_back(cs);
                } else if (isUac2 && subtype == UAC2_AC_CLOCK_SELECTOR && bLen >= 7) {
                    UsbClockSelector sel;
                    sel.selectorId = d[3];
                    uint8_t nrPins = d[4];
                    if (static_cast<size_t>(5 + nrPins) < bLen) {
                        for (uint8_t p = 0; p < nrPins; ++p) {
                            sel.inputClockIds.push_back(d[5 + p]);
                        }
                        sel.controls = d[5 + nrPins];
                    }
                    profile.clockSelectors.push_back(sel);
                } else if (isUac2 && subtype == UAC2_AC_CLOCK_MULTIPLIER && bLen >= 7) {
                    UsbClockMultiplier mul;
                    mul.multiplierId = d[3];
                    mul.clockInId = d[4];
                    mul.controls = d[5];
                    profile.clockMultipliers.push_back(mul);
                } else if (subtype == UAC_AC_INPUT_TERMINAL && bLen >= 12) {
                    UsbAudioTerminal term;
                    term.isInput = true;
                    term.terminalId = d[3];
                    term.terminalType = read_le16(d + 4);
                    if (isUac2 && bLen >= 17) {
                        term.clockSourceId = d[7];
                    }
                    profile.terminals.push_back(term);
                } else if (subtype == UAC_AC_OUTPUT_TERMINAL && bLen >= 9) {
                    UsbAudioTerminal term;
                    term.isInput = false;
                    term.terminalId = d[3];
                    term.terminalType = read_le16(d + 4);
                    term.sourceId = d[7];
                    if (isUac2 && bLen >= 12) {
                        term.clockSourceId = d[8];
                    }
                    profile.terminals.push_back(term);
                } else if (subtype == UAC_AC_FEATURE_UNIT && bLen >= 6) {
                    UsbFeatureUnit fu;
                    fu.unitId = d[3];
                    fu.sourceId = d[4];
                    if (isUac2 && bLen >= 9) {
                        uint32_t ch0Controls = read_le32(d + 5);
                        fu.hasMuteControl = ((ch0Controls & 0x03u) == 0x03u);
                    } else if (!isUac2 && bLen >= 7) {
                        uint8_t ctrlSize = d[5];
                        if (ctrlSize >= 1 && bLen >= static_cast<uint8_t>(6 + ctrlSize)) {
                            fu.hasMuteControl = ((d[6] & 0x01u) != 0);
                        }
                    }
                    profile.featureUnits.push_back(fu);
                }
            } else if (haveActiveAlt) {
                if (subtype == UAC_AS_GENERAL) {
                    if (curAlt.uacVersion == 2 && bLen >= 16) {
                        curAlt.terminalLink = d[3];
                        uint8_t fmtType = d[5];
                        uint32_t bmFormats = read_le32(d + 6);
                        curAlt.channels = d[10];
                        if (fmtType == UAC_FORMAT_TYPE_I) {
                            if (bmFormats & UAC2_FORMAT_PCM) {
                                curAlt.isFloat = false;
                                curAltSupportedFormat = true;
                            } else if (bmFormats & UAC2_FORMAT_IEEE_FLOAT) {
                                curAlt.isFloat = true;
                                curAltSupportedFormat = true;
                            } else if (bmFormats & UAC2_FORMAT_PCM8) {
                                curAlt.isFloat = false;
                                curAltSupportedFormat = true;
                            }
                        }
                    } else if (bLen >= 7) {
                        curAlt.uacVersion = 1;
                        curAlt.terminalLink = d[3];
                        uint16_t wFormatTag = read_le16(d + 5);
                        if (wFormatTag == UAC1_FORMAT_PCM) {
                            curAlt.isFloat = false;
                            curAltSupportedFormat = true;
                        } else if (wFormatTag == UAC1_FORMAT_IEEE_FLOAT) {
                            curAlt.isFloat = true;
                            curAltSupportedFormat = true;
                        }
                    }
                } else if (subtype == UAC_AS_FORMAT_TYPE) {
                    uint8_t fmtType = d[3];
                    if (fmtType == UAC_FORMAT_TYPE_I) {
                        if (curAlt.uacVersion == 2 && bLen >= 6) {
                            curAlt.subslotSize = d[4];
                            curAlt.bitResolution = d[5];
                        } else if (curAlt.uacVersion == 1 && bLen >= 11) {
                            curAlt.channels = d[4];
                            curAlt.subslotSize = d[5];
                            curAlt.bitResolution = d[6];
                            uint8_t samFreqType = d[7];
                            if (samFreqType == 0 && bLen >= 14) {
                                curAlt.continuousRateMin = static_cast<int>(read_le24(d + 8));
                                curAlt.continuousRateMax = static_cast<int>(read_le24(d + 11));
                            } else if (samFreqType > 0) {
                                for (uint8_t r = 0; r < samFreqType; ++r) {
                                    size_t off = 8u + static_cast<size_t>(r) * 3u;
                                    if (off + 3u <= bLen) {
                                        int rate = static_cast<int>(read_le24(d + off));
                                        if (rate > 0) {
                                            curAlt.supportedSampleRates.push_back(rate);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        } else if (bType == LIBUSB_DT_ENDPOINT && bLen >= 7) {
            if (haveActiveAlt) {
                uint8_t epAddr = d[2];
                uint8_t bmAttr = d[3];
                uint16_t rawMaxPkt = read_le16(d + 4);
                uint16_t baseMaxPkt = static_cast<uint16_t>(rawMaxPkt & 0x07FFu);
                uint16_t mult = static_cast<uint16_t>(1u + ((rawMaxPkt >> 11) & 0x03u));
                uint16_t effMaxPkt = static_cast<uint16_t>(baseMaxPkt * mult);
                uint8_t interval = std::max<uint8_t>(1, d[6]);
                uint8_t xferType = bmAttr & 0x03u;
                uint8_t syncType = (bmAttr >> 2) & 0x03u;
                uint8_t usageType = (bmAttr >> 4) & 0x03u;

                lastEndpointAddr = epAddr;
                if (xferType == 0x01u) { // Isochronous
                    if ((epAddr & LIBUSB_ENDPOINT_IN) == 0) {
                        curAlt.epOutAddr = epAddr;
                        curAlt.epOutMaxPacketSize = effMaxPkt;
                        curAlt.epOutInterval = interval;
                        curAlt.epOutSyncType = syncType;
                    } else if (usageType == 0x01u || baseMaxPkt <= 8u) {
                        curAlt.epFeedbackInAddr = epAddr;
                        curAlt.epFeedbackMaxPacketSize = effMaxPkt;
                        curAlt.epFeedbackInterval = interval;
                    }
                }
            }
        } else if (bType == UAC_DT_CS_ENDPOINT && bLen >= 7) {
            if (haveActiveAlt && curAlt.uacVersion == 1 && lastEndpointAddr == curAlt.epOutAddr && d[2] == 0x01) {
                curAlt.uac1EndpointFreqControl = ((d[3] & 0x01u) != 0);
            }
        }

        pos += bLen;
    }

    flushCurrentAlt();

    // Update UAC2 alt-settings clockId after all AudioControl descriptors are collected.
    for (auto &alt : profile.altSettings) {
        if (alt.uacVersion == 2) {
            alt.clockSourceId = resolve_effective_clock_id(profile, alt.terminalLink, alt.clockSourceId);
        }
    }

    profile.valid = (profile.acInterfaceNumber >= 0 && !profile.altSettings.empty());
    return profile;
}

inline int query_uac2_clock_rates(
    libusb_device_handle *handle,
    const UsbAudioDeviceProfile &profile,
    uint8_t clockId,
    std::vector<int> &outRates
) {
    outRates.clear();
    if (!handle || profile.acInterfaceNumber < 0 || clockId == 0) {
        return LIBUSB_ERROR_INVALID_PARAM;
    }

    static constexpr int kStandardRates[] = {
        44100, 48000, 88200, 96000, 176400, 192000, 352800, 384000, 705600, 768000
    };

    std::vector<uint8_t> buf(512, 0);
    const uint16_t wValue = static_cast<uint16_t>(UAC_CS_SAM_FREQ_CONTROL) << 8;
    const uint16_t wIndex = (static_cast<uint16_t>(clockId) << 8) | static_cast<uint16_t>(profile.acInterfaceNumber);

    int rc = libusb_control_transfer(
        handle,
        0xA1, // Device-to-Host | Class | Interface
        UAC2_CS_RANGE,
        wValue,
        wIndex,
        buf.data(),
        static_cast<uint16_t>(buf.size()),
        1000
    );

    if (rc >= 2) {
        uint16_t numSubRanges = read_le16(buf.data());
        size_t needed = 2u + static_cast<size_t>(numSubRanges) * 12u;
        if (needed > buf.size() && needed <= 4096u) {
            buf.assign(needed, 0);
            rc = libusb_control_transfer(
                handle,
                0xA1,
                UAC2_CS_RANGE,
                wValue,
                wIndex,
                buf.data(),
                static_cast<uint16_t>(buf.size()),
                1000
            );
        }
        if (rc >= 2) {
            size_t availRanges = static_cast<size_t>(rc - 2) / 12u;
            size_t count = std::min<size_t>(numSubRanges, availRanges);
            for (size_t i = 0; i < count; ++i) {
                const uint8_t *r = buf.data() + 2 + i * 12;
                uint32_t dMin = read_le32(r + 0);
                uint32_t dMax = read_le32(r + 4);
                uint32_t dRes = read_le32(r + 8);
                if (dMin == 0 || dMax < dMin) {
                    continue;
                }
                if (dMin == dMax || dRes == 0) {
                    outRates.push_back(static_cast<int>(dMin));
                } else {
                    for (int cand : kStandardRates) {
                        uint32_t uc = static_cast<uint32_t>(cand);
                        if (uc >= dMin && uc <= dMax && ((uc - dMin) % dRes == 0)) {
                            outRates.push_back(cand);
                        }
                    }
                    if (outRates.empty()) {
                        outRates.push_back(static_cast<int>(dMin));
                        if (dMax != dMin) {
                            outRates.push_back(static_cast<int>(dMax));
                        }
                    }
                }
            }
        }
    }

    // Fallback: query current frequency if RANGE is unsupported (e.g., fixed internal clock).
    if (outRates.empty()) {
        uint8_t curBuf[4] = {0, 0, 0, 0};
        int curRc = libusb_control_transfer(
            handle,
            0xA1,
            UAC2_CS_CUR,
            wValue,
            wIndex,
            curBuf,
            sizeof(curBuf),
            1000
        );
        if (curRc >= 4) {
            uint32_t curRate = read_le32(curBuf);
            if (curRate > 0) {
                outRates.push_back(static_cast<int>(curRate));
            }
        }
    }

    std::sort(outRates.begin(), outRates.end());
    outRates.erase(std::unique(outRates.begin(), outRates.end()), outRates.end());
    return outRates.empty() ? LIBUSB_ERROR_NOT_FOUND : LIBUSB_SUCCESS;
}

inline int pick_best_sample_rate(
    const std::vector<int> &discreteRates,
    int continuousMin,
    int continuousMax,
    int targetRate
) {
    if (targetRate <= 0) {
        targetRate = 48000;
    }
    if (continuousMin > 0 && continuousMax >= continuousMin) {
        return std::clamp(targetRate, continuousMin, continuousMax);
    }
    if (discreteRates.empty()) {
        return targetRate;
    }

    // 1. Exact match
    for (int r : discreteRates) {
        if (r == targetRate) {
            return r;
        }
    }

    // 2. Integer multiple upsample (2x, 4x, 8x, ...) preferring smallest clean multiple
    int bestMultiple = 0;
    for (int r : discreteRates) {
        if (r > targetRate && (r % targetRate == 0)) {
            if (bestMultiple == 0 || r < bestMultiple) {
                bestMultiple = r;
            }
        }
    }
    if (bestMultiple > 0) {
        return bestMultiple;
    }

    // 3. Same rate family (44.1k family vs 48k family) preferring highest available >= target or max
    const bool target441 = (targetRate % 11025 == 0);
    int bestFamilyAbove = 0;
    int bestFamilyBelow = 0;
    for (int r : discreteRates) {
        const bool is441 = (r % 11025 == 0);
        if (is441 == target441) {
            if (r >= targetRate && (bestFamilyAbove == 0 || r < bestFamilyAbove)) {
                bestFamilyAbove = r;
            }
            if (r < targetRate && r > bestFamilyBelow) {
                bestFamilyBelow = r;
            }
        }
    }
    if (bestFamilyAbove > 0) return bestFamilyAbove;
    if (bestFamilyBelow > 0) return bestFamilyBelow;

    // 4. Nearest higher rate, else highest supported rate
    int nearestHigher = 0;
    int highest = discreteRates[0];
    for (int r : discreteRates) {
        if (r > highest) highest = r;
        if (r >= targetRate && (nearestHigher == 0 || r < nearestHigher)) {
            nearestHigher = r;
        }
    }
    return (nearestHigher > 0) ? nearestHigher : highest;
}

inline AEAudioFormat uac_alt_to_ae_format(const UsbAudioAltSetting &alt) {
    if (alt.isFloat && alt.subslotSize == 4) {
        return AE_FORMAT_F32;
    }
    if (alt.subslotSize == 1) {
        return AE_FORMAT_U8;
    }
    if (alt.subslotSize == 2) {
        return AE_FORMAT_S16;
    }
    if (alt.subslotSize == 3) {
        return AE_FORMAT_S24;
    }
    return AE_FORMAT_S32;
}

inline ma_format ae_to_ma_format_usb(AEAudioFormat fmt) {
    switch (fmt) {
    case AE_FORMAT_U8:  return ma_format_u8;
    case AE_FORMAT_S16: return ma_format_s16;
    case AE_FORMAT_S24: return ma_format_s24;
    case AE_FORMAT_S32: return ma_format_s32;
    case AE_FORMAT_F32:
    default:            return ma_format_f32;
    }
}

struct UsbSelectedConfig {
    bool found = false;
    UsbAudioAltSetting alt{};
    int sampleRate = 48000;
};

inline UsbSelectedConfig select_best_uac_alt_setting(
    const UsbAudioDeviceProfile &profile,
    int targetSampleRate,
    int targetChannels,
    AEAudioFormat preferredFormat,
    bool explicitFormat,
    const std::vector<int> *uac2ClockRates = nullptr
) {
    UsbSelectedConfig best;
    if (!profile.valid || profile.altSettings.empty()) {
        return best;
    }

    int desiredChannels = (targetChannels > 0) ? targetChannels : 2;
    int preferredBits = 32;
    bool preferFloat = false;
    switch (preferredFormat) {
    case AE_FORMAT_U8:  preferredBits = 8; break;
    case AE_FORMAT_S16: preferredBits = 16; break;
    case AE_FORMAT_S24: preferredBits = 24; break;
    case AE_FORMAT_S32: preferredBits = 32; break;
    case AE_FORMAT_F32:
    default:            preferredBits = 32; preferFloat = true; break;
    }

    int bestScore = -1000000;
    for (const auto &alt : profile.altSettings) {
        const std::vector<int> &rates =
            (alt.uacVersion == 2 && uac2ClockRates && !uac2ClockRates->empty())
                ? *uac2ClockRates
                : alt.supportedSampleRates;

        int chosenRate = pick_best_sample_rate(rates, alt.continuousRateMin, alt.continuousRateMax, targetSampleRate);
        if (chosenRate <= 0) {
            chosenRate = targetSampleRate > 0 ? targetSampleRate : 48000;
        }

        int score = 0;

        // Channel match
        if (alt.channels == desiredChannels) {
            score += 50000;
        } else if (alt.channels == 2) {
            score += 20000;
        }

        // Sample rate match quality
        if (chosenRate == targetSampleRate) {
            score += 40000;
        } else if (targetSampleRate > 0 && chosenRate > targetSampleRate && (chosenRate % targetSampleRate == 0)) {
            score += 25000;
        } else if (chosenRate > 0) {
            score += 5000;
        }

        // Bit depth / format preference
        if (explicitFormat) {
            if (preferFloat && alt.isFloat) {
                score += 15000;
            } else if (!preferFloat && !alt.isFloat && alt.bitResolution == preferredBits) {
                score += 15000;
            } else if (!alt.isFloat && alt.bitResolution >= preferredBits) {
                score += 8000 + alt.bitResolution * 10;
            } else {
                score += alt.bitResolution * 10;
            }
        } else {
            // Default audiophile preference: integer PCM 32 -> 24 -> 16 -> float
            if (!alt.isFloat) {
                score += 10000;
            }
            score += static_cast<int>(alt.bitResolution) * 100;
            score += static_cast<int>(alt.subslotSize) * 10;
        }

        // Prefer UAC2 & asynchronous endpoint if tied
        if (alt.uacVersion == 2) score += 200;
        if (alt.epOutSyncType == 1) score += 50;

        if (!best.found || score > bestScore) {
            bestScore = score;
            best.found = true;
            best.alt = alt;
            best.sampleRate = chosenRate;
        }
    }

    return best;
}

inline int configure_uac_hardware(
    libusb_device_handle *handle,
    const UsbAudioDeviceProfile &profile,
    const UsbAudioAltSetting &alt,
    int sampleRate
) {
    if (!handle || profile.acInterfaceNumber < 0) {
        return LIBUSB_ERROR_INVALID_PARAM;
    }

    (void)libusb_set_auto_detach_kernel_driver(handle, 1);

    int rc = libusb_claim_interface(handle, profile.acInterfaceNumber);
    if (rc != LIBUSB_SUCCESS) {
        return rc;
    }
    if (alt.interfaceNumber != profile.acInterfaceNumber) {
        rc = libusb_claim_interface(handle, alt.interfaceNumber);
        if (rc != LIBUSB_SUCCESS) {
            return rc;
        }
    }

    // Reset AudioStreaming interface to zero-bandwidth alt 0 before switching to target altSetting.
    (void)libusb_set_interface_alt_setting(handle, alt.interfaceNumber, 0);
    rc = libusb_set_interface_alt_setting(handle, alt.interfaceNumber, alt.altSetting);
    if (rc != LIBUSB_SUCCESS) {
        return rc;
    }

    if (alt.uacVersion == 2) {
        // Ensure clock selector (if any) points to pin 1.
        for (const auto &t : profile.terminals) {
            if (t.terminalId == alt.terminalLink && t.clockSourceId != 0) {
                for (const auto &sel : profile.clockSelectors) {
                    if (sel.selectorId == t.clockSourceId && !sel.inputClockIds.empty()) {
                        uint8_t pin = 1;
                        for (size_t idx = 0; idx < sel.inputClockIds.size(); ++idx) {
                            if (sel.inputClockIds[idx] == alt.clockSourceId) {
                                pin = static_cast<uint8_t>(idx + 1);
                                break;
                            }
                        }
                        uint16_t selIndex = (static_cast<uint16_t>(sel.selectorId) << 8) | static_cast<uint16_t>(profile.acInterfaceNumber);
                        (void)libusb_control_transfer(
                            handle, 0x21, UAC2_CS_CUR,
                            static_cast<uint16_t>(UAC2_CX_CLOCK_SELECTOR_CONTROL) << 8,
                            selIndex, &pin, 1, 1000
                        );
                    }
                }
                break;
            }
        }

        if (alt.clockSourceId != 0) {
            uint8_t rateBytes[4] = {
                static_cast<uint8_t>(sampleRate & 0xFF),
                static_cast<uint8_t>((sampleRate >> 8) & 0xFF),
                static_cast<uint8_t>((sampleRate >> 16) & 0xFF),
                static_cast<uint8_t>((sampleRate >> 24) & 0xFF)
            };
            const uint16_t wValue = static_cast<uint16_t>(UAC_CS_SAM_FREQ_CONTROL) << 8;
            const uint16_t wIndex = (static_cast<uint16_t>(alt.clockSourceId) << 8) | static_cast<uint16_t>(profile.acInterfaceNumber);
            rc = libusb_control_transfer(handle, 0x21, UAC2_CS_CUR, wValue, wIndex, rateBytes, sizeof(rateBytes), 1000);
            if (rc < 0) {
                // Allow fixed-clock DACs if current rate already matches.
                uint8_t readBack[4] = {0};
                int readRc = libusb_control_transfer(handle, 0xA1, UAC2_CS_CUR, wValue, wIndex, readBack, sizeof(readBack), 1000);
                if (readRc < 4 || static_cast<int>(read_le32(readBack)) != sampleRate) {
                    return rc;
                }
            }
        }
    } else {
        // UAC 1.0 endpoint sampling frequency SET_CUR (3-byte LE)
        if (alt.uac1EndpointFreqControl || alt.supportedSampleRates.size() > 1 || alt.continuousRateMax > 0) {
            uint8_t rateBytes[3] = {
                static_cast<uint8_t>(sampleRate & 0xFF),
                static_cast<uint8_t>((sampleRate >> 8) & 0xFF),
                static_cast<uint8_t>((sampleRate >> 16) & 0xFF)
            };
            rc = libusb_control_transfer(
                handle,
                0x22, // Host-to-Device | Class | Endpoint
                UAC1_SET_CUR,
                static_cast<uint16_t>(UAC_CS_SAM_FREQ_CONTROL) << 8,
                alt.epOutAddr,
                rateBytes,
                sizeof(rateBytes),
                1000
            );
            if (rc < 0 && alt.uac1EndpointFreqControl) {
                return rc;
            }
        }
    }

    // Best-effort unmute on Feature Units that expose mute control.
    for (const auto &fu : profile.featureUnits) {
        if (fu.hasMuteControl) {
            uint8_t muteOff = 0;
            uint16_t fuIndex = (static_cast<uint16_t>(fu.unitId) << 8) | static_cast<uint16_t>(profile.acInterfaceNumber);
            (void)libusb_control_transfer(
                handle, 0x21, UAC2_CS_CUR,
                static_cast<uint16_t>(UAC_FU_MUTE_CONTROL) << 8,
                fuIndex, &muteOff, 1, 500
            );
        }
    }

    return LIBUSB_SUCCESS;
}

class UsbIsoPacketPlanner {
public:
    void configure(int sampleRate, int channels, int bytesPerSample, int deviceSpeed, uint8_t epInterval, uint16_t epMaxPacketSize) {
        sampleRate_ = std::max(8000, sampleRate);
        channels_ = std::max(1, channels);
        bytesPerFrame_ = std::max(1, channels_ * bytesPerSample);
        maxPacketBytes_ = epMaxPacketSize;

        int shift = std::clamp(static_cast<int>(epInterval) - 1, 0, 15);
        if (deviceSpeed == LIBUSB_SPEED_FULL || deviceSpeed == LIBUSB_SPEED_LOW) {
            packetsPerSecond_ = std::max<uint32_t>(1u, 1000u / std::max<uint32_t>(1u, epInterval));
        } else {
            packetsPerSecond_ = std::max<uint32_t>(1u, 8000u >> shift);
        }

        const uint64_t scaled = static_cast<uint64_t>(sampleRate_) << 16;
        nominalStepQ16_ = static_cast<uint32_t>(scaled / packetsPerSecond_);
        nominalSubRem_ = static_cast<uint32_t>(scaled % packetsPerSecond_);
        currentStepQ16_ = nominalStepQ16_;

        minStepQ16_ = static_cast<uint32_t>((static_cast<uint64_t>(nominalStepQ16_) * 98u) / 100u);
        maxStepQ16_ = static_cast<uint32_t>((static_cast<uint64_t>(nominalStepQ16_) * 102u) / 100u);
        if (minStepQ16_ == 0) minStepQ16_ = 1;

        phaseAccum_ = 0;
        subFracAccum_ = 0;
        hasFeedback_ = false;
    }

    uint32_t packetsPerSecond() const { return packetsPerSecond_; }
    uint32_t nominalStepQ16() const { return nominalStepQ16_; }
    uint32_t currentStepQ16() const { return currentStepQ16_; }

    // Parses explicit USB Audio feedback packet:
    // - 3 bytes: UAC1 Full-Speed 10.14 fixed point (shifted << 2 to 16.16)
    // - 4 bytes: UAC2 High-Speed 16.16 fixed point
    bool applyFeedbackBytes(const uint8_t *data, size_t len) {
        if (!data || (len != 3 && len < 4)) {
            return false;
        }
        uint32_t q16 = 0;
        if (len == 3) {
            uint32_t q10_14 = read_le24(data);
            q16 = q10_14 << 2;
        } else {
            q16 = read_le32(data);
        }
        if (q16 == 0) {
            return false;
        }
        currentStepQ16_ = std::clamp(q16, minStepQ16_, maxStepQ16_);
        hasFeedback_ = true;
        return true;
    }

    uint32_t nextPacketFrames() {
        phaseAccum_ += currentStepQ16_;
        if (!hasFeedback_ && nominalSubRem_ > 0) {
            subFracAccum_ += nominalSubRem_;
            if (subFracAccum_ >= packetsPerSecond_) {
                subFracAccum_ -= packetsPerSecond_;
                phaseAccum_ += 1u;
            }
        }
        uint32_t frames = phaseAccum_ >> 16;
        phaseAccum_ &= 0xFFFFu;

        if (maxPacketBytes_ > 0) {
            uint32_t maxFrames = maxPacketBytes_ / static_cast<uint32_t>(bytesPerFrame_);
            if (frames > maxFrames) {
                frames = maxFrames;
            }
        }
        return frames;
    }

private:
    int sampleRate_ = 48000;
    int channels_ = 2;
    int bytesPerFrame_ = 4;
    uint16_t maxPacketBytes_ = 0;

    uint32_t packetsPerSecond_ = 8000;
    uint32_t nominalStepQ16_ = 0;
    uint32_t nominalSubRem_ = 0;
    uint32_t currentStepQ16_ = 0;
    uint32_t minStepQ16_ = 0;
    uint32_t maxStepQ16_ = 0;

    uint32_t phaseAccum_ = 0;
    uint32_t subFracAccum_ = 0;
    bool hasFeedback_ = false;
};

} // namespace usb
} // namespace sautiflow
