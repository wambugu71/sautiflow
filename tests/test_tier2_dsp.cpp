// =============================================================================
// tests/test_tier2_dsp.cpp
//
// Unit tests for Tier 2 DSP enhancements:
//   1. BroadcastLevellerDSP (EBU R128 / BS.1770 Slow-Window AGC)
//   2. NoiseGateDSP (Studio Noise Gate with Hysteresis & Hold Time)
// =============================================================================

#include <cmath>
#include <cstdio>
#include <cstdint>
#include <vector>
#include <algorithm>

#include "dsp/broadcast_leveller_dsp.h"
#include "dsp/noise_gate_dsp.h"

static int g_passes = 0;
static int g_failures = 0;

#define CHECK(cond, msg)                                                        \
    do {                                                                        \
        if (cond) {                                                             \
            ++g_passes;                                                         \
            std::printf("  [PASS] %s\n", msg);                                  \
        } else {                                                                \
            ++g_failures;                                                       \
            std::printf("  [FAIL] %s  (%s:%d)\n", msg, __FILE__, __LINE__);     \
        }                                                                       \
    } while (0)

static std::vector<float> generateSine(float freqHz, float sampleRate, size_t frameCount, float amp = 1.0f)
{
    std::vector<float> buf(frameCount * 2);
    for (size_t i = 0; i < frameCount; ++i) {
        float s = amp * std::sin(2.0f * 3.14159265358979323846f * freqHz * (float)i / sampleRate);
        buf[i * 2 + 0] = s;
        buf[i * 2 + 1] = s;
    }
    return buf;
}

// -----------------------------------------------------------------------------
// Test 1: BroadcastLevellerDSP - AGC Tracking & Silence Freeze
// -----------------------------------------------------------------------------
static void test_broadcast_leveller()
{
    std::printf("\n--- Test: BroadcastLevellerDSP ---\n");
    sauti::dsp::BroadcastLevellerDSP agc;
    agc.setSampleRate(48000.0f);
    agc.setParams(-16.0f, 1.0f, 2.0f, 9.0f, 12.0f, -45.0f);

    CHECK(!agc.isEnabled(), "Default state is disabled");

    // 1. Bit-exact bypass when disabled
    {
        auto testBuf = generateSine(1000.0f, 48000.0f, 512, 0.5f);
        auto orig = testBuf;
        agc.process(testBuf.data(), 512, 2, -24.0f);
        bool match = true;
        for (size_t i = 0; i < testBuf.size(); ++i) {
            if (testBuf[i] != orig[i]) { match = false; break; }
        }
        CHECK(match, "Audio passes bit-exact when disabled");
    }

    agc.setEnabled(true);
    CHECK(agc.isEnabled(), "Enabled state is true");

    // 2. Steady signal at target level (-16 LUFS): gain stays at 0 dB
    {
        agc.reset();
        auto testBuf = generateSine(1000.0f, 48000.0f, 4800, 0.5f);
        for (int b = 0; b < 10; ++b) {
            agc.process(testBuf.data(), 4800, 2, -16.0f);
        }
        CHECK(std::abs(agc.getCurrentGainDb()) < 0.05f, "At target loudness (-16 LUFS), gain stays at 0.0 dB");
    }

    // 3. Quiet sustained signal (-22 LUFS vs -16 target): gain should slowly ramp up
    {
        agc.reset();
        auto testBuf = generateSine(1000.0f, 48000.0f, 48000, 0.2f); // 1.0 second block
        // After 1.0 second with max_rise = 1.0 dB/sec, gain should have increased by ~1.0 dB
        agc.process(testBuf.data(), 48000, 2, -22.0f);
        float gain1s = agc.getCurrentGainDb();
        CHECK(gain1s >= 0.85f && gain1s <= 1.15f, "After 1.0s at -22 LUFS, gain rises at ~1.0 dB/s");

        // After another 2 seconds, gain should reach ~3.0 dB
        agc.process(testBuf.data(), 48000, 2, -22.0f);
        agc.process(testBuf.data(), 48000, 2, -22.0f);
        float gain3s = agc.getCurrentGainDb();
        CHECK(gain3s >= 2.8f && gain3s <= 3.2f, "After 3.0s, gain smoothly approaches target error");
    }

    // 4. Loud sustained signal (-10 LUFS vs -16 target): gain should ramp down at fall rate
    {
        agc.reset();
        auto testBuf = generateSine(1000.0f, 48000.0f, 48000, 0.8f);
        // max_fall = 2.0 dB/sec
        agc.process(testBuf.data(), 48000, 2, -10.0f);
        float gainAfter1s = agc.getCurrentGainDb();
        CHECK(gainAfter1s <= -1.8f && gainAfter1s >= -2.2f, "Loud signal ramps down at ~2.0 dB/s");
    }

    // 5. Silence Freeze: when level drops below silence gate (-45 LUFS), gain freezes!
    {
        agc.reset();
        auto testBuf = generateSine(1000.0f, 48000.0f, 48000, 0.2f);
        // Elevate gain to +2.0 dB
        agc.process(testBuf.data(), 48000, 2, -22.0f);
        agc.process(testBuf.data(), 48000, 2, -22.0f);
        float frozenGain = agc.getCurrentGainDb();
        CHECK(frozenGain > 1.5f, "Gain is elevated before silence");

        // Now signal goes silent (speech pause at -60 LUFS)
        auto silentBuf = generateSine(1000.0f, 48000.0f, 48000, 0.0f);
        agc.process(silentBuf.data(), 48000, 2, -60.0f);
        float gainAfterPause = agc.getCurrentGainDb();
        CHECK(std::abs(gainAfterPause - frozenGain) < 0.001f, "Silence freeze preserves gain during speech pauses");
    }

    // 6. 64-bit double processing verification
    {
        agc.reset();
        std::vector<double> buf64(2048 * 2, 0.5);
        agc.process(buf64.data(), 2048, 2, -20.0f);
        bool hasValues = true;
        for (double v : buf64) {
            if (std::isnan(v) || std::isinf(v)) { hasValues = false; break; }
        }
        CHECK(hasValues, "64-bit double processing produces valid, non-NaN output");
    }
}

// -----------------------------------------------------------------------------
// Test 2: NoiseGateDSP - Hysteresis & Hold Time Verification
// -----------------------------------------------------------------------------
static void test_noise_gate()
{
    std::printf("\n--- Test: NoiseGateDSP ---\n");
    sauti::dsp::NoiseGateDSP gate;
    gate.setSampleRate(48000.0f);
    // Open at -40 dB, Close at -46 dB, Hold = 100 ms, Attack = 1ms, Release = 50ms
    gate.setParams(-40.0f, -46.0f, 100.0f, 1.0f, 50.0f, 80.0f, -80.0f);

    CHECK(!gate.isEnabled(), "Default state is disabled");

    // 1. Bit-exact bypass when disabled
    {
        auto testBuf = generateSine(1000.0f, 48000.0f, 512, 0.001f);
        auto orig = testBuf;
        gate.process(testBuf.data(), 512, 2);
        bool match = true;
        for (size_t i = 0; i < testBuf.size(); ++i) {
            if (testBuf[i] != orig[i]) { match = false; break; }
        }
        CHECK(match, "Audio passes bit-exact when disabled");
    }

    gate.setEnabled(true);
    CHECK(gate.isEnabled(), "Enabled state is true");

    // 2. Initial state is Closed; signal below close threshold (-50 dB = 0.00316 amp)
    {
        gate.reset();
        auto lowBuf = generateSine(1000.0f, 48000.0f, 2048, 0.003f); // ~ -50.4 dB
        gate.process(lowBuf.data(), 2048, 2);
        CHECK(gate.getState() == sauti::dsp::NoiseGateDSP::GateState::Closed,
              "Gate remains Closed for signal below close threshold");
        CHECK(gate.getGainReductionDb() < -40.0f, "Heavy gain reduction applied while closed");
    }

    // 3. Hysteresis test: signal between close (-46 dB) and open (-40 dB), e.g. -43 dB = 0.007 amp
    {
        gate.reset();
        auto midBuf = generateSine(1000.0f, 48000.0f, 2048, 0.007f); // ~ -43 dB
        gate.process(midBuf.data(), 2048, 2);
        CHECK(gate.getState() == sauti::dsp::NoiseGateDSP::GateState::Closed,
              "Hysteresis: Signal in window (-43 dB) does NOT open gate");
    }

    // 4. Loud signal (-30 dB = 0.0316 amp) triggers gate to Open
    {
        auto loudBuf = generateSine(1000.0f, 48000.0f, 2048, 0.035f); // ~ -29 dB
        gate.process(loudBuf.data(), 2048, 2);
        CHECK(gate.getState() == sauti::dsp::NoiseGateDSP::GateState::Open,
              "Signal above open threshold (-29 dB) opens the gate");
        CHECK(gate.getGainReductionDb() > -1.0f, "Gate is open with virtually 0 dB gain reduction");

        // Now drop level to -43 dB (inside hysteresis window): gate must STAY Open!
        auto midBuf = generateSine(1000.0f, 48000.0f, 2048, 0.007f);
        gate.process(midBuf.data(), 2048, 2);
        CHECK(gate.getState() == sauti::dsp::NoiseGateDSP::GateState::Open,
              "Hysteresis: Gate remains OPEN when level is inside window (-43 dB)");
    }

    // 5. Hold time test: level drops to -60 dB (below close threshold)
    {
        auto dropBuf = generateSine(1000.0f, 48000.0f, 2400, 0.001f); // 50 ms @ 48 kHz (< 100 ms hold)
        gate.process(dropBuf.data(), 2400, 2);
        CHECK(gate.getState() == sauti::dsp::NoiseGateDSP::GateState::Holding,
              "Gate enters Holding state when level drops below close threshold");
        CHECK(gate.getGainReductionDb() > -1.0f, "Gate maintains unity audio transmission during hold duration");

        // Process another 70 ms (total 120 ms > 100 ms hold): gate transitions to Closed
        auto continueBuf = generateSine(1000.0f, 48000.0f, 3360, 0.001f);
        gate.process(continueBuf.data(), 3360, 2);
        CHECK(gate.getState() == sauti::dsp::NoiseGateDSP::GateState::Closed,
              "Gate transitions to Closed after hold time expires");
    }

    // 6. 64-bit double processing verification
    {
        gate.reset();
        std::vector<double> buf64(1024 * 2, 0.5);
        gate.process(buf64.data(), 1024, 2);
        bool hasValues = true;
        for (double v : buf64) {
            if (std::isnan(v) || std::isinf(v)) { hasValues = false; break; }
        }
        CHECK(hasValues, "64-bit double processing produces valid, non-NaN output");
    }
}

int main()
{
    std::printf("=====================================================\n");
    std::printf("Running Tier 2 DSP Test Suite (Leveller & Noise Gate)\n");
    std::printf("=====================================================\n");

    test_broadcast_leveller();
    test_noise_gate();

    std::printf("\n=====================================================\n");
    std::printf("Results: %d passed, %d failed\n", g_passes, g_failures);
    std::printf("=====================================================\n");

    return (g_failures == 0) ? 0 : 1;
}
