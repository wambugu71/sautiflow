#pragma once

#include <algorithm>
#include <array>
#include <cctype>
#include <cstdint>
#include <cstring>
#include <string>
#include <vector>

#if defined(__ANDROID__)
#include <sys/system_properties.h>
#include <unistd.h>
#endif

namespace sautiflow {
namespace dap {

/// Supported Digital Audio Player (DAP) hardware families.
enum class DapFamily : int {
    Generic = 0,
    Fiio = 1,
    HiBy = 2,
    IBasso = 3,
    Shanling = 4,
    SonyWalkman = 5,
    Cayin = 6,
    AstellKern = 7,
    LgQuadDac = 8,
    TempoTec = 9,
    OnkyoPioneer = 10,
};

/// Hardware capability and driver tuning profile for a selected DAP.
struct DapDriverProfile {
    DapFamily family = DapFamily::Generic;
    const char* vendorName = "Generic Android Hi-Res";
    const char* modelName = "Android Direct Hi-Res";
    const char* dacArchitecture = "Direct PCM Hardware HAL";
    const char* driverName = "Generic Direct Hi-Res HAL";
    int maxSampleRate = 192000;
    int preferredBitDepth = 24;
    bool preferInt32 = false;          // true -> prefer ENCODING_PCM_32BIT (22) over 24BIT_PACKED (21)
    bool supportsDop = true;
    bool supportsNativeDsd = false;
    bool preferApi34BitPerfect = true; // Use AudioManager.setPreferredMixerAttributes (MIXER_BEHAVIOR_BIT_PERFECT)
    const char* audioManagerParams = ""; // Optional vendor AudioManager.setParameters() hint
    int minDirectBufferBytes = 65536;  // Minimum DMA buffer size for jitter-free high-rate playback
};

struct DapDetectionResult {
    bool isDapDetected = false;
    DapDriverProfile profile{};
    bool alsaDirectAccessible = false;
};

namespace detail {

inline std::string toLowerAscii(std::string s) {
    for (char& c : s) {
        c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
    }
    return s;
}

inline bool containsAny(const std::string& haystack, std::initializer_list<const char*> needles) {
    for (const char* needle : needles) {
        if (needle != nullptr && needle[0] != '\0' && haystack.find(needle) != std::string::npos) {
            return true;
        }
    }
    return false;
}

inline DapDriverProfile profileForFamilyDefault(DapFamily family) {
    switch (family) {
        case DapFamily::Fiio:
            return DapDriverProfile{
                DapFamily::Fiio,
                "FiiO",
                "FiiO Hi-Res DAP",
                "FiiO Dual AKM / ESS Sabre Architecture",
                "FiiO Direct Hi-Res HAL",
                384000,
                32,
                true,
                true,
                true,
                true,
                "",
                65536,
            };
        case DapFamily::HiBy:
            return DapDriverProfile{
                DapFamily::HiBy,
                "HiBy",
                "HiBy Hi-Res DAP",
                "HiBy DTA / Darwin R-2R / Dual ESS DAC",
                "HiBy DTA Direct Transport Driver",
                768000,
                32,
                true,
                true,
                true,
                true,
                "hiby_direct=on",
                65536,
            };
        case DapFamily::IBasso:
            return DapDriverProfile{
                DapFamily::IBasso,
                "iBasso",
                "iBasso DX-Series DAP",
                "iBasso Multi-DAC (CS43198 / ES9038PRO / BD34301)",
                "iBasso Mango Direct Hi-Res HAL",
                384000,
                32,
                true,
                true,
                true,
                true,
                "",
                65536,
            };
        case DapFamily::Shanling:
            return DapDriverProfile{
                DapFamily::Shanling,
                "Shanling",
                "Shanling M-Series DAP",
                "Shanling AGLO / AKM & ESS Sabre DAC",
                "Shanling AGLO Direct Lossless Driver",
                768000,
                32,
                true,
                true,
                true,
                true,
                "",
                65536,
            };
        case DapFamily::SonyWalkman:
            return DapDriverProfile{
                DapFamily::SonyWalkman,
                "Sony",
                "Sony Walkman",
                "Sony S-Master HX Full Digital Amplifier",
                "Sony S-Master HX Direct Hi-Res Driver",
                384000,
                32,
                true,
                true,
                true,
                true,
                "",
                65536,
            };
        case DapFamily::Cayin:
            return DapDriverProfile{
                DapFamily::Cayin,
                "Cayin",
                "Cayin N-Series DAP",
                "Cayin DTA / R-2R & ROHM BD34301 DAC",
                "Cayin DTA Direct Hi-Res Driver",
                768000,
                32,
                true,
                true,
                true,
                true,
                "",
                65536,
            };
        case DapFamily::AstellKern:
            return DapDriverProfile{
                DapFamily::AstellKern,
                "Astell&Kern",
                "Astell&Kern DAP",
                "Teraton Alpha / Dual AKM & Quad ESS DAC",
                "Astell&Kern Direct Hi-Res HAL",
                384000,
                32,
                true,
                true,
                true,
                true,
                "",
                65536,
            };
        case DapFamily::LgQuadDac:
            return DapDriverProfile{
                DapFamily::LgQuadDac,
                "LG",
                "LG Hi-Fi Quad DAC",
                "ESS Sabre ES9218P / ES9219P Quad DAC",
                "LG Hi-Fi Quad DAC Direct Driver",
                192000,
                32,
                true,
                true,
                false,
                true,
                "hifi_dac=on",
                49152,
            };
        case DapFamily::TempoTec:
            return DapDriverProfile{
                DapFamily::TempoTec,
                "TempoTec",
                "TempoTec V-Series DAP",
                "Dual AK4493SEQ / CS43131 Hi-Res DAC",
                "TempoTec Direct Hi-Res HAL",
                384000,
                32,
                true,
                true,
                true,
                true,
                "",
                65536,
            };
        case DapFamily::OnkyoPioneer:
            return DapDriverProfile{
                DapFamily::OnkyoPioneer,
                "Onkyo / Pioneer",
                "Onkyo DP / Pioneer XDP DAP",
                "Dual ESS Sabre ES9018K2M + 9601K Amp",
                "Onkyo/Pioneer Direct Hi-Res HAL",
                384000,
                24,
                false,
                true,
                true,
                true,
                "",
                49152,
            };
        case DapFamily::Generic:
        default:
            return DapDriverProfile{};
    }
}

} // namespace detail

/// Returns the default profile for a given [DapFamily].
inline DapDriverProfile getProfileForFamily(int familyId) {
    if (familyId < static_cast<int>(DapFamily::Generic) ||
        familyId > static_cast<int>(DapFamily::OnkyoPioneer)) {
        return DapDriverProfile{};
    }
    return detail::profileForFamilyDefault(static_cast<DapFamily>(familyId));
}

/// Detects a selected Digital Audio Player (DAP) from Android build/system properties.
inline DapDetectionResult detectDapProfile(
    const std::string& manufacturer,
    const std::string& brand,
    const std::string& model,
    const std::string& device,
    const std::string& hardware,
    const std::string& board,
    const std::string& displayId
) {
    DapDetectionResult res{};

    const std::string mfr = detail::toLowerAscii(manufacturer);
    const std::string br = detail::toLowerAscii(brand);
    const std::string mdl = detail::toLowerAscii(model);
    const std::string dev = detail::toLowerAscii(device);
    const std::string hw = detail::toLowerAscii(hardware);
    const std::string brd = detail::toLowerAscii(board);
    const std::string disp = detail::toLowerAscii(displayId);

    const std::string combined = mfr + " " + br + " " + mdl + " " + dev + " " + hw + " " + brd + " " + disp;

    // 1. FiiO Digital Audio Players
    if (detail::containsAny(combined, {"fiio", "jadeaudio"})) {
        res.isDapDetected = true;
        res.profile = detail::profileForFamilyDefault(DapFamily::Fiio);
        if (detail::containsAny(mdl, {"m17"})) {
            res.profile.modelName = "FiiO M17";
            res.profile.dacArchitecture = "Dual ESS ES9038PRO + THX AAA-788+";
            res.profile.maxSampleRate = 768000;
        } else if (detail::containsAny(mdl, {"m15s"})) {
            res.profile.modelName = "FiiO M15S";
            res.profile.dacArchitecture = "ESS ES9038PRO Desktop DAC";
            res.profile.maxSampleRate = 768000;
        } else if (detail::containsAny(mdl, {"m15"})) {
            res.profile.modelName = "FiiO M15";
            res.profile.dacArchitecture = "Dual AK4499EQ";
            res.profile.maxSampleRate = 768000;
        } else if (detail::containsAny(mdl, {"m23"})) {
            res.profile.modelName = "FiiO M23";
            res.profile.dacArchitecture = "AK4191EQ + AK4499EX + THX AAA-78+";
            res.profile.maxSampleRate = 768000;
        } else if (detail::containsAny(mdl, {"m11 plus", "m11plus", "m11_plus"})) {
            res.profile.modelName = "FiiO M11 Plus";
            res.profile.dacArchitecture = "Dual ES9068AS / AK4497EQ + THX AAA-78";
            res.profile.maxSampleRate = 384000;
        } else if (detail::containsAny(mdl, {"m11s"})) {
            res.profile.modelName = "FiiO M11S";
            res.profile.dacArchitecture = "Dual ESS ES9038Q2M";
            res.profile.maxSampleRate = 384000;
        } else if (detail::containsAny(mdl, {"m11"})) {
            res.profile.modelName = "FiiO M11 / M11 Pro";
            res.profile.dacArchitecture = "Dual AK4493EQ / AK4497EQ";
            res.profile.maxSampleRate = 384000;
        } else if (detail::containsAny(mdl, {"r7", "r9"})) {
            res.profile.modelName = "FiiO R7 / R9";
            res.profile.dacArchitecture = "ESS ES9068AS / Dual ES9038PRO Desktop";
            res.profile.maxSampleRate = 768000;
        } else if (detail::containsAny(mdl, {"jm21"})) {
            res.profile.modelName = "FiiO JM21";
            res.profile.dacArchitecture = "Dual Cirrus Logic CS43198";
            res.profile.maxSampleRate = 384000;
        }
        return res;
    }

    // 2. HiBy Digital Audio Players
    if (detail::containsAny(combined, {"hiby"})) {
        res.isDapDetected = true;
        res.profile = detail::profileForFamilyDefault(DapFamily::HiBy);
        if (detail::containsAny(mdl, {"rs8", "rs6"})) {
            res.profile.modelName = "HiBy RS6 / RS8";
            res.profile.dacArchitecture = "HiBy Darwin R-2R Ladder Architecture";
            res.profile.maxSampleRate = 768000;
        } else if (detail::containsAny(mdl, {"r8 ii", "r8ii", "r8"})) {
            res.profile.modelName = "HiBy R8 / R8 II";
            res.profile.dacArchitecture = "Darwin-MPA / Dual AK4497EQ";
            res.profile.maxSampleRate = 768000;
        } else if (detail::containsAny(mdl, {"r6 pro", "r6pro"})) {
            res.profile.modelName = "HiBy R6 Pro II";
            res.profile.dacArchitecture = "Dual AK4499EX + AK4191EQ";
            res.profile.maxSampleRate = 768000;
        } else if (detail::containsAny(mdl, {"r6"})) {
            res.profile.modelName = "HiBy R6 / R6 III";
            res.profile.dacArchitecture = "Dual ESS ES9038Q2M";
            res.profile.maxSampleRate = 768000;
        } else if (detail::containsAny(mdl, {"r5"})) {
            res.profile.modelName = "HiBy R5 / R5 Gen 2";
            res.profile.dacArchitecture = "Dual ESS ES9219C + Class-A Amp";
            res.profile.maxSampleRate = 768000;
        } else if (detail::containsAny(mdl, {"r4"})) {
            res.profile.modelName = "HiBy R4";
            res.profile.dacArchitecture = "Quad ESS ES9018C2M + Class-A Amp";
            res.profile.maxSampleRate = 768000;
        }
        return res;
    }

    // 3. iBasso Digital Audio Players
    if (detail::containsAny(combined, {"ibasso"})) {
        res.isDapDetected = true;
        res.profile = detail::profileForFamilyDefault(DapFamily::IBasso);
        if (detail::containsAny(mdl, {"dx320"})) {
            res.profile.modelName = "iBasso DX320 / MAX";
            res.profile.dacArchitecture = "Dual ROHM BD34301EKV";
            res.profile.maxSampleRate = 768000;
        } else if (detail::containsAny(mdl, {"dx300"})) {
            res.profile.modelName = "iBasso DX300";
            res.profile.dacArchitecture = "Quad Cirrus Logic CS43198";
            res.profile.maxSampleRate = 384000;
        } else if (detail::containsAny(mdl, {"dx260"})) {
            res.profile.modelName = "iBasso DX260";
            res.profile.dacArchitecture = "Octa Cirrus Logic CS43198 Matrix";
            res.profile.maxSampleRate = 768000;
        } else if (detail::containsAny(mdl, {"dx240"})) {
            res.profile.modelName = "iBasso DX240";
            res.profile.dacArchitecture = "ESS Sabre ES9038PRO";
            res.profile.maxSampleRate = 768000;
        } else if (detail::containsAny(mdl, {"dx180"})) {
            res.profile.modelName = "iBasso DX180";
            res.profile.dacArchitecture = "Quad Cirrus Logic CS43131";
            res.profile.maxSampleRate = 384000;
        } else if (detail::containsAny(mdl, {"dx170", "dx160"})) {
            res.profile.modelName = "iBasso DX160 / DX170";
            res.profile.dacArchitecture = "Dual Cirrus Logic CS43131";
            res.profile.maxSampleRate = 384000;
        }
        return res;
    }

    // 4. Shanling Digital Audio Players
    if (detail::containsAny(combined, {"shanling"})) {
        res.isDapDetected = true;
        res.profile = detail::profileForFamilyDefault(DapFamily::Shanling);
        if (detail::containsAny(mdl, {"m9"})) {
            res.profile.modelName = "Shanling M9 / M9 Plus";
            res.profile.dacArchitecture = "Quad AK4499EX + AK4191EQ";
            res.profile.maxSampleRate = 768000;
        } else if (detail::containsAny(mdl, {"m8"})) {
            res.profile.modelName = "Shanling M8";
            res.profile.dacArchitecture = "Dual AK4499EQ";
            res.profile.maxSampleRate = 768000;
        } else if (detail::containsAny(mdl, {"m7"})) {
            res.profile.modelName = "Shanling M7";
            res.profile.dacArchitecture = "ESS ES9038PRO";
            res.profile.maxSampleRate = 768000;
        } else if (detail::containsAny(mdl, {"m6"})) {
            res.profile.modelName = "Shanling M6 / M6 Ultra";
            res.profile.dacArchitecture = "Quad AK4493SEQ / Dual AK4497EQ";
            res.profile.maxSampleRate = 768000;
        } else if (detail::containsAny(mdl, {"m3"})) {
            res.profile.modelName = "Shanling M3X / M3 Ultra";
            res.profile.dacArchitecture = "Dual ESS ES9219C";
            res.profile.maxSampleRate = 384000;
        }
        return res;
    }

    // 5. Sony Walkman (Android NW-A / NW-ZX / NW-WM series)
    if (detail::containsAny(combined, {"sony"}) &&
        detail::containsAny(combined, {"nw-a", "nw-zx", "nw-wm", "walkman"})) {
        res.isDapDetected = true;
        res.profile = detail::profileForFamilyDefault(DapFamily::SonyWalkman);
        if (detail::containsAny(mdl, {"wm1am2", "wm1zm2"})) {
            res.profile.modelName = "Sony NW-WM1AM2 / WM1ZM2";
            res.profile.dacArchitecture = "S-Master HX Signature Digital Amp";
            res.profile.maxSampleRate = 384000;
        } else if (detail::containsAny(mdl, {"zx707", "zx507"})) {
            res.profile.modelName = "Sony NW-ZX507 / ZX707";
            res.profile.dacArchitecture = "S-Master HX Full Digital Amp";
            res.profile.maxSampleRate = 384000;
        } else if (detail::containsAny(mdl, {"a306", "a307", "a105", "a106"})) {
            res.profile.modelName = "Sony NW-A105 / A306 Walkman";
            res.profile.dacArchitecture = "S-Master HX Digital Amp";
            res.profile.maxSampleRate = 384000;
        }
        return res;
    }

    // 6. Cayin Digital Audio Players
    if (detail::containsAny(combined, {"cayin"})) {
        res.isDapDetected = true;
        res.profile = detail::profileForFamilyDefault(DapFamily::Cayin);
        if (detail::containsAny(mdl, {"n8ii"})) {
            res.profile.modelName = "Cayin N8ii";
            res.profile.dacArchitecture = "Dual ROHM BD34301EKV + Nutube 6P1";
            res.profile.maxSampleRate = 768000;
        } else if (detail::containsAny(mdl, {"n7"})) {
            res.profile.modelName = "Cayin N7";
            res.profile.dacArchitecture = "Discrete 1-Bit Resistor Network DAC";
            res.profile.maxSampleRate = 768000;
        } else if (detail::containsAny(mdl, {"n6ii"})) {
            res.profile.modelName = "Cayin N6ii";
            res.profile.dacArchitecture = "Modular Audio Motherboard (R01 R-2R / A02 / E02)";
            res.profile.maxSampleRate = 384000;
        } else if (detail::containsAny(mdl, {"n3ultra"})) {
            res.profile.modelName = "Cayin N3Ultra";
            res.profile.dacArchitecture = "Dual AK4493SEQ + Raytheon JAN6418";
            res.profile.maxSampleRate = 768000;
        }
        return res;
    }

    // 7. Astell&Kern Digital Audio Players
    if (detail::containsAny(combined, {"astell", "iriver"}) ||
        detail::containsAny(mdl, {"sp3000", "sp2000", "se300", "se180", "sr35", "sr25", "kann"})) {
        res.isDapDetected = true;
        res.profile = detail::profileForFamilyDefault(DapFamily::AstellKern);
        if (detail::containsAny(mdl, {"sp3000"})) {
            res.profile.modelName = "Astell&Kern A&ultima SP3000";
            res.profile.dacArchitecture = "Hexa-DAC (2x AK4191EQ + 4x AK4499EX)";
            res.profile.maxSampleRate = 768000;
        } else if (detail::containsAny(mdl, {"se300"})) {
            res.profile.modelName = "Astell&Kern A&futura SE300";
            res.profile.dacArchitecture = "24-bit Discrete R-2R Ladder DAC";
            res.profile.maxSampleRate = 384000;
        } else if (detail::containsAny(mdl, {"sr35", "sr25"})) {
            res.profile.modelName = "Astell&Kern A&norma SR25 / SR35";
            res.profile.dacArchitecture = "Quad Cirrus Logic CS43198";
            res.profile.maxSampleRate = 384000;
        }
        return res;
    }

    // 8. TempoTec
    if (detail::containsAny(combined, {"tempotec"})) {
        res.isDapDetected = true;
        res.profile = detail::profileForFamilyDefault(DapFamily::TempoTec);
        return res;
    }

    // 9. Onkyo / Pioneer DAPs
    if (detail::containsAny(mdl, {"dp-x1", "dp-cmx1", "xdp-100", "xdp-300"})) {
        res.isDapDetected = true;
        res.profile = detail::profileForFamilyDefault(DapFamily::OnkyoPioneer);
        return res;
    }

    // 10. LG Quad DAC series (V20/V30/V40/V50/V60, G7/G8)
    if (detail::containsAny(mfr + " " + br, {"lge", "lg"}) &&
        detail::containsAny(mdl + " " + dev, {"v20", "v30", "v40", "v50", "v60", "g7", "g8", "lm-v", "lm-g", "lg-h9", "lg-us99", "vs99"})) {
        res.isDapDetected = true;
        res.profile = detail::profileForFamilyDefault(DapFamily::LgQuadDac);
        return res;
    }

    return res;
}

/// Checks if /dev/snd PCM playback nodes are directly accessible by this process.
inline bool checkAlsaDirectAccessible() {
#if defined(__ANDROID__) || defined(__linux__)
    static constexpr const char* kCandidates[] = {
        "/dev/snd/pcmC0D0p",
        "/dev/snd/pcmC0D1p",
        "/dev/snd/pcmC1D0p",
    };
    for (const char* path : kCandidates) {
        if (access(path, R_OK | W_OK) == 0) {
            return true;
        }
    }
#endif
    return false;
}

/// Detects the current device's DAP profile (with optional family override: -1 = auto).
inline DapDetectionResult detectCurrentDapProfile(int familyOverride = -1) {
    DapDetectionResult res{};
    res.alsaDirectAccessible = checkAlsaDirectAccessible();

    if (familyOverride > 0) {
        res.isDapDetected = true;
        res.profile = getProfileForFamily(familyOverride);
        return res;
    }
    if (familyOverride == 0) {
        res.isDapDetected = false;
        res.profile = getProfileForFamily(0);
        return res;
    }

#if defined(__ANDROID__)
    char mfr[PROP_VALUE_MAX] = {0};
    char brand[PROP_VALUE_MAX] = {0};
    char model[PROP_VALUE_MAX] = {0};
    char device[PROP_VALUE_MAX] = {0};
    char hw[PROP_VALUE_MAX] = {0};
    char board[PROP_VALUE_MAX] = {0};
    char disp[PROP_VALUE_MAX] = {0};

    __system_property_get("ro.product.manufacturer", mfr);
    __system_property_get("ro.product.brand", brand);
    __system_property_get("ro.product.model", model);
    __system_property_get("ro.product.device", device);
    __system_property_get("ro.hardware", hw);
    __system_property_get("ro.product.board", board);
    __system_property_get("ro.build.display.id", disp);

    auto detected = detectDapProfile(mfr, brand, model, device, hw, board, disp);
    detected.alsaDirectAccessible = res.alsaDirectAccessible;
    return detected;
#else
    return res;
#endif
}

} // namespace dap
} // namespace sautiflow
