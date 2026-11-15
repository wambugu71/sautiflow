#include <cassert>
#include <cstdint>
#include <cstdio>
#include <vector>

#include "miniaudio.h"
#include "usb_audio_driver.h"

using namespace sautiflow::usb;

static void appendDesc(std::vector<uint8_t> &buf, std::initializer_list<uint8_t> bytes) {
    buf.insert(buf.end(), bytes.begin(), bytes.end());
}

static std::vector<uint8_t> buildUac1TestConfigDescriptor() {
    std::vector<uint8_t> d;
    // Configuration descriptor (9 bytes)
    appendDesc(d, {9, 0x02, 0x00, 0x00, 2, 1, 0, 0x80, 50});
    // Interface 0 Alt 0: AudioControl UAC 1.0
    appendDesc(d, {9, 0x04, 0, 0, 0, 0x01, 0x01, 0x00, 0});
    // UAC1 AC Header (9 bytes): bcdADC = 0x0100
    appendDesc(d, {9, 0x24, 0x01, 0x00, 0x01, 30, 0, 1, 1});
    // UAC1 Input Terminal (12 bytes): ID 1, USB Streaming (0x0101)
    appendDesc(d, {12, 0x24, 0x02, 1, 0x01, 0x01, 0, 2, 0x03, 0x00, 0, 0});
    // UAC1 Feature Unit (9 bytes): ID 2, source 1, bControlSize=1, Mute control=0x01
    appendDesc(d, {9, 0x24, 0x06, 2, 1, 1, 0x01, 0x00, 0});
    // UAC1 Output Terminal (9 bytes): ID 3, Speaker (0x0301), source 2
    appendDesc(d, {9, 0x24, 0x03, 3, 0x01, 0x03, 0, 2, 0});

    // Interface 1 Alt 0: Zero-bandwidth AS
    appendDesc(d, {9, 0x04, 1, 0, 0, 0x01, 0x02, 0x00, 0});

    // Interface 1 Alt 1: UAC1 24-bit Stereo PCM with discrete rates 44.1k, 48k, 96k
    appendDesc(d, {9, 0x04, 1, 1, 2, 0x01, 0x02, 0x00, 0});
    // UAC1 AS General: terminalLink=1, delay=1, wFormatTag=0x0001 (PCM)
    appendDesc(d, {7, 0x24, 0x01, 1, 1, 0x01, 0x00});
    // UAC1 Format Type I: ch=2, subslot=3, bitRes=24, samFreqType=3 (44100, 48000, 96000)
    appendDesc(d, {
        17, 0x24, 0x02, 0x01, 2, 3, 24, 3,
        0x44, 0xAC, 0x00, // 44100
        0x80, 0xBB, 0x00, // 48000
        0x00, 0x77, 0x01  // 96000
    });
    // Standard Isoc Async OUT endpoint (0x01), maxPkt=294 (0x0126), bInterval=1, bSynchAddress=0x81
    appendDesc(d, {9, 0x05, 0x01, 0x05, 0x26, 0x01, 1, 0, 0x81});
    // Class-specific AS Iso Audio Data Endpoint: bmAttributes=0x01 (Sampling Frequency control)
    appendDesc(d, {7, 0x25, 0x01, 0x01, 0, 0, 0});
    // Explicit Feedback IN endpoint (0x81), usage=0x10 (Explicit Feedback), maxPkt=3, bInterval=4
    appendDesc(d, {9, 0x05, 0x81, 0x11, 3, 0, 4, 0, 0});

    return d;
}

static std::vector<uint8_t> buildUac2TestConfigDescriptor() {
    std::vector<uint8_t> d;
    // Configuration descriptor (9 bytes)
    appendDesc(d, {9, 0x02, 0x00, 0x00, 2, 1, 0, 0x80, 50});
    // Interface 0 Alt 0: AudioControl UAC 2.0 (protocol 0x20)
    appendDesc(d, {9, 0x04, 0, 0, 0, 0x01, 0x01, 0x20, 0});
    // UAC2 AC Header (9 bytes): bcdADC = 0x0200
    appendDesc(d, {9, 0x24, 0x01, 0x00, 0x02, 0x01, 50, 0, 0});
    // UAC2 Clock Source (8 bytes): bClockID = 0x10
    appendDesc(d, {8, 0x24, 0x0A, 0x10, 0x03, 0x07, 0, 0});
    // UAC2 Clock Selector (8 bytes): bClockID = 0x11, bNrInPins=1, baCSourceID[0]=0x10
    appendDesc(d, {8, 0x24, 0x0B, 0x11, 1, 0x10, 0x03, 0});
    // UAC2 Input Terminal (17 bytes): ID=0x01, USB Streaming, bCSourceID=0x11 at offset d[7]!
    appendDesc(d, {
        17, 0x24, 0x02, 0x01, 0x01, 0x01, 0x00, 0x11,
        2, 0x03, 0x00, 0x00, 0x00, 0, 0x00, 0x00, 0
    });
    // UAC2 Feature Unit (10 bytes): ID=0x05, source=0x01, Mute RW bits (0x03)
    appendDesc(d, {10, 0x24, 0x06, 0x05, 0x01, 0x03, 0x00, 0x00, 0x00, 0});
    // UAC2 Output Terminal (12 bytes): ID=0x02, Speaker, source=0x05, bCSourceID=0x11 at d[8]
    appendDesc(d, {12, 0x24, 0x03, 0x02, 0x01, 0x03, 0, 0x05, 0x11, 0, 0, 0});

    // Interface 1 Alt 0: zero-bandwidth AS UAC 2.0
    appendDesc(d, {9, 0x04, 1, 0, 0, 0x01, 0x02, 0x20, 0});

    // Interface 1 Alt 1: 16-bit PCM Stereo
    appendDesc(d, {9, 0x04, 1, 1, 2, 0x01, 0x02, 0x20, 0});
    // UAC2 AS General (16 bytes): terminalLink=0x01, fmtType=1, bmFormats=PCM(1), bNrChannels=2
    appendDesc(d, {16, 0x24, 0x01, 0x01, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 2, 0x03, 0, 0, 0, 0});
    // UAC2 Format Type I (6 bytes): subslot=2, bitRes=16
    appendDesc(d, {6, 0x24, 0x02, 0x01, 2, 16});
    appendDesc(d, {7, 0x05, 0x01, 0x05, 0x00, 0x02, 1});
    appendDesc(d, {7, 0x05, 0x81, 0x11, 4, 0, 4});

    // Interface 1 Alt 2: 24-in-32bit PCM Stereo
    appendDesc(d, {9, 0x04, 1, 2, 2, 0x01, 0x02, 0x20, 0});
    appendDesc(d, {16, 0x24, 0x01, 0x01, 0x00, 0x01, 0x01, 0x00, 0x00, 0x00, 2, 0x03, 0, 0, 0, 0});
    appendDesc(d, {6, 0x24, 0x02, 0x01, 4, 24});
    appendDesc(d, {7, 0x05, 0x01, 0x05, 0x00, 0x04, 1});
    appendDesc(d, {7, 0x05, 0x81, 0x11, 4, 0, 4});

    return d;
}

static void testUac1DescriptorAndSelection() {
    auto raw = buildUac1TestConfigDescriptor();
    UsbAudioDeviceProfile profile = parse_uac_descriptors(raw.data(), raw.size());
    assert(profile.valid);
    assert(profile.uacVersion == 1);
    assert(profile.acInterfaceNumber == 0);
    assert(profile.altSettings.size() == 1);
    assert(!profile.featureUnits.empty() && profile.featureUnits[0].hasMuteControl);

    const auto &alt = profile.altSettings[0];
    assert(alt.interfaceNumber == 1);
    assert(alt.altSetting == 1);
    assert(alt.channels == 2);
    assert(alt.subslotSize == 3);
    assert(alt.bitResolution == 24);
    assert(alt.epOutAddr == 0x01);
    assert(alt.epOutSyncType == 1);
    assert(alt.epFeedbackInAddr == 0x81);
    assert(alt.epFeedbackMaxPacketSize == 3);
    assert(alt.uac1EndpointFreqControl);
    assert(alt.supportedSampleRates.size() == 3);

    UsbSelectedConfig sel = select_best_uac_alt_setting(profile, 96000, 2, AE_FORMAT_S24, true);
    assert(sel.found);
    assert(sel.sampleRate == 96000);
    assert(uac_alt_to_ae_format(sel.alt) == AE_FORMAT_S24);
    assert(ae_to_ma_format_usb(uac_alt_to_ae_format(sel.alt)) == ma_format_s24);
    std::printf("[PASS] testUac1DescriptorAndSelection\n");
}

static void testUac2DescriptorClockAndAltSelection() {
    auto raw = buildUac2TestConfigDescriptor();
    UsbAudioDeviceProfile profile = parse_uac_descriptors(raw.data(), raw.size());
    assert(profile.valid);
    assert(profile.uacVersion == 2);
    assert(profile.acInterfaceNumber == 0);
    assert(profile.altSettings.size() == 2);
    assert(!profile.terminals.empty());
    // Verify UAC2 INPUT_TERMINAL bCSourceID was read from d[7] (0x11) and resolved through selector to 0x10!
    assert(profile.terminals[0].isInput);
    assert(profile.terminals[0].clockSourceId == 0x11);
    assert(profile.altSettings[0].clockSourceId == 0x10);
    assert(profile.altSettings[1].clockSourceId == 0x10);

    std::vector<int> rates = {44100, 48000, 88200, 96000, 192000, 384000};
    UsbSelectedConfig sel = select_best_uac_alt_setting(profile, 192000, 2, AE_FORMAT_F32, false, &rates);
    assert(sel.found);
    assert(sel.sampleRate == 192000);
    assert(sel.alt.altSetting == 2);
    assert(sel.alt.subslotSize == 4);
    assert(sel.alt.bitResolution == 24);
    assert(uac_alt_to_ae_format(sel.alt) == AE_FORMAT_S32);
    assert(ae_to_ma_format_usb(uac_alt_to_ae_format(sel.alt)) == ma_format_s32);

    // Same-family integer multiple preference when exact rate missing
    std::vector<int> sparseRates = {48000, 96000, 176400};
    UsbSelectedConfig selMult = select_best_uac_alt_setting(profile, 88200, 2, AE_FORMAT_S32, false, &sparseRates);
    assert(selMult.found);
    assert(selMult.sampleRate == 176400);
    std::printf("[PASS] testUac2DescriptorClockAndAltSelection\n");
}

static void testIsoPacketPlannerAndFeedback() {
    // High-Speed 44.1kHz (8000 packets/sec -> exact 44100 frames/sec with Bresenham remainder)
    UsbIsoPacketPlanner hsPlanner;
    hsPlanner.configure(44100, 2, 3, LIBUSB_SPEED_HIGH, 1, 512);
    assert(hsPlanner.packetsPerSecond() == 8000u);

    uint64_t totalHsFrames = 0;
    for (int i = 0; i < 8000; ++i) {
        uint32_t f = hsPlanner.nextPacketFrames();
        assert(f == 5u || f == 6u);
        totalHsFrames += f;
    }
    assert(totalHsFrames == 44100ull);

    // Full-Speed 44.1kHz (1000 packets/sec -> exact 44100 frames/sec: 44/45 pattern)
    UsbIsoPacketPlanner fsPlanner;
    fsPlanner.configure(44100, 2, 2, LIBUSB_SPEED_FULL, 1, 294);
    assert(fsPlanner.packetsPerSecond() == 1000u);

    uint64_t totalFsFrames = 0;
    for (int i = 0; i < 1000; ++i) {
        uint32_t f = fsPlanner.nextPacketFrames();
        assert(f == 44u || f == 45u);
        totalFsFrames += f;
    }
    assert(totalFsFrames == 44100ull);

    // Explicit UAC1 3-byte 10.14 feedback (~44.19 frames/ms = +0.2% skew)
    const uint32_t q10_14_target = static_cast<uint32_t>(44.19 * 16384.0);
    uint8_t fb3[3] = {
        static_cast<uint8_t>(q10_14_target & 0xFFu),
        static_cast<uint8_t>((q10_14_target >> 8) & 0xFFu),
        static_cast<uint8_t>((q10_14_target >> 16) & 0xFFu)
    };
    assert(fsPlanner.applyFeedbackBytes(fb3, sizeof(fb3)));
    assert(fsPlanner.currentStepQ16() == (q10_14_target << 2));

    // Extreme bogus feedback must clamp to +/-2% around nominalStepQ16
    uint8_t bogusHigh[4] = {0x00, 0x00, 0xFF, 0x00}; // 255.0 frames/packet
    assert(hsPlanner.applyFeedbackBytes(bogusHigh, sizeof(bogusHigh)));
    const uint32_t expectedMax = static_cast<uint32_t>((static_cast<uint64_t>(hsPlanner.nominalStepQ16()) * 102u) / 100u);
    assert(hsPlanner.currentStepQ16() == expectedMax);

    uint8_t bogusLow[4] = {0x01, 0x00, 0x00, 0x00};
    assert(hsPlanner.applyFeedbackBytes(bogusLow, sizeof(bogusLow)));
    const uint32_t expectedMin = static_cast<uint32_t>((static_cast<uint64_t>(hsPlanner.nominalStepQ16()) * 98u) / 100u);
    assert(hsPlanner.currentStepQ16() == expectedMin);

    std::printf("[PASS] testIsoPacketPlannerAndFeedback\n");
}

static std::vector<uint8_t> buildUac2NativeDsdTestConfigDescriptor() {
    std::vector<uint8_t> d = buildUac2TestConfigDescriptor();
    // Append Interface 1 Alt 3: Dual PCM | UAC2_FORMAT_SPECIAL_RAW_DATA (0x80000001), 32-bit Stereo
    appendDesc(d, {9, 0x04, 1, 3, 2, 0x01, 0x02, 0x20, 0});
    // UAC2 AS General (16 bytes): terminalLink=0x01, fmtType=1, bmFormats=0x80000001 LE, ch=2
    appendDesc(d, {16, 0x24, 0x01, 0x01, 0x00, 0x01, 0x01, 0x00, 0x00, 0x80, 2, 0x03, 0, 0, 0, 0});
    // UAC2 Format Type I (6 bytes): subslot=4, bitRes=32
    appendDesc(d, {6, 0x24, 0x02, 0x01, 4, 32});
    appendDesc(d, {7, 0x05, 0x01, 0x05, 0x00, 0x04, 1});
    appendDesc(d, {7, 0x05, 0x81, 0x11, 4, 0, 4});
    return d;
}

static void testUac2NativeDsdAndDopDetection() {
    auto raw = buildUac2NativeDsdTestConfigDescriptor();
    UsbAudioDeviceProfile profile = parse_uac_descriptors(raw.data(), raw.size());
    assert(profile.valid);
    assert(profile.uacVersion == 2);
    // Alt 1 (PCM16), Alt 2 (PCM24/32), Alt 3 split into PCM32 + RAW_DATA Native DSD
    assert(profile.altSettings.size() == 4);
    assert(profile_supports_native_dsd(profile));

    std::vector<int> dsdRates = {44100, 48000, 88200, 96000, 176400, 192000, 352800};
    assert(profile_supports_dop(profile, &dsdRates));

    // Request Native DSD (DSD64 -> 2822400/32 = 88200 Hz carrier)
    UsbSelectedConfig selNative = select_best_uac_alt_setting(
        profile, 88200, 2, AE_FORMAT_S32, false, &dsdRates, true);
    assert(selNative.found);
    assert(selNative.alt.isNativeDsd);
    assert(selNative.alt.altSetting == 3);
    assert(selNative.alt.subslotSize == 4);
    assert(selNative.alt.bitResolution == 32);
    assert(selNative.sampleRate == 88200);

    // Request DoP (DSD64 DoP -> 176400 Hz PCM carrier, must NOT select RAW_DATA alt)
    UsbSelectedConfig selDop = select_best_uac_alt_setting(
        profile, 176400, 2, AE_FORMAT_S32, false, &dsdRates, false);
    assert(selDop.found);
    assert(!selDop.alt.isNativeDsd);
    assert(selDop.sampleRate == 176400);
    assert(uac_alt_to_ae_format(selDop.alt) == AE_FORMAT_S32);

    std::printf("[PASS] testUac2NativeDsdAndDopDetection\n");
}

static void testUac2MultichannelNativeDsdSelection() {
    std::vector<int> dsdRates = {44100, 48000, 88200, 96000, 176400, 192000};

    // Stereo-only Native DSD DAC must NOT match a 6-channel Native DSD request when requireExactChannels=true
    auto stereoRaw = buildUac2NativeDsdTestConfigDescriptor();
    UsbAudioDeviceProfile stereoProfile = parse_uac_descriptors(stereoRaw.data(), stereoRaw.size());
    UsbSelectedConfig reject6ch = select_best_uac_alt_setting(
        stereoProfile, 88200, 6, AE_FORMAT_S32, true, &dsdRates, true, true);
    assert(!reject6ch.found);

    // Multi-channel UAC2 DAC exposing 6-channel RAW_DATA alt 4
    std::vector<uint8_t> mcRaw = stereoRaw;
    appendDesc(mcRaw, {9, 0x04, 1, 4, 2, 0x01, 0x02, 0x20, 0});
    appendDesc(mcRaw, {16, 0x24, 0x01, 0x01, 0x00, 0x01, 0x00, 0x00, 0x00, 0x80, 6, 0x3F, 0, 0, 0, 0});
    appendDesc(mcRaw, {6, 0x24, 0x02, 0x01, 4, 32});
    appendDesc(mcRaw, {7, 0x05, 0x01, 0x05, 0x00, 0x04, 1});
    appendDesc(mcRaw, {7, 0x05, 0x81, 0x11, 4, 0, 4});

    UsbAudioDeviceProfile mcProfile = parse_uac_descriptors(mcRaw.data(), mcRaw.size());
    assert(mcProfile.valid);
    UsbSelectedConfig sel6ch = select_best_uac_alt_setting(
        mcProfile, 88200, 6, AE_FORMAT_S32, true, &dsdRates, true, true);
    assert(sel6ch.found);
    assert(sel6ch.alt.isNativeDsd);
    assert(sel6ch.alt.channels == 6);
    assert(sel6ch.alt.altSetting == 4);
    assert(sel6ch.sampleRate == 88200);

    std::printf("[PASS] testUac2MultichannelNativeDsdSelection\n");
}

int main() {
    testUac1DescriptorAndSelection();
    testUac2DescriptorClockAndAltSelection();
    testIsoPacketPlannerAndFeedback();
    testUac2NativeDsdAndDopDetection();
    testUac2MultichannelNativeDsdSelection();
    std::printf("ALL USB AUDIO DRIVER TESTS PASSED\n");
    return 0;
}
