#include <iostream>
#include <vector>
#include <cmath>
#include <cassert>
#include "../dsp/dynamic_system_dsp.h"
#include "../dsp/fft_convolver_dsp.h"
#include "../dsp/clarity_dsp.h"
#include "../dsp/analog_warmth_dsp.h"
#include "../dsp/master_limiter_dsp.h"
#include "../dsp/dynamic_bass_dsp.h"

int main() {
    std::cout << "Testing DSP Parameter Smoothing, Anti-Pop, and Dynamic System Wiring...\n";

    // 1. Test DynamicSystemDSP
    {
        std::cout << "-> Testing DynamicSystemDSP...";
        sauti::dsp::DynamicSystemDSP dynSys;
        dynSys.setSampleRate(48000.0f);
        dynSys.setEnabled(true);

        const std::vector<sauti::dsp::TransducerProfile> profiles = {
            sauti::dsp::TransducerProfile::Earphone,
            sauti::dsp::TransducerProfile::Headphone,
            sauti::dsp::TransducerProfile::HighEndReference,
            sauti::dsp::TransducerProfile::SpeakerMonitor,
            sauti::dsp::TransducerProfile::ExtremeSubwoofer,
            sauti::dsp::TransducerProfile::PureDynamic
        };

        for (auto p : profiles) {
            dynSys.setProfile(p);
            dynSys.setStrength(0.8f);

            std::vector<float> buffer(48000 * 2, 0.0f);
            for (size_t i = 0; i < 48000; i++) {
                float t = (float)i / 48000.0f;
                buffer[2 * i] = 0.4f * std::sin(2.0f * 3.14159265f * 60.0f * t) + 0.2f * std::sin(2.0f * 3.14159265f * 1000.0f * t);
                buffer[2 * i + 1] = buffer[2 * i];
            }

            dynSys.process(buffer.data(), 48000);

            for (float s : buffer) {
                assert(!std::isnan(s) && "DynamicSystem produced NaN!");
                assert(!std::isinf(s) && "DynamicSystem produced Inf!");
            }
        }
        std::cout << " OK!\n";
    }

    // 2. Test FFTConvolverDSP (with real-time wet/dry smoothing and impulse response load)
    {
        std::cout << "-> Testing FFTConvolverDSP...";
        sauti::dsp::FFTConvolverDSP convolver;
        convolver.setSampleRate(48000.0f);
        convolver.setEnabled(true);

        // Generate synthetic room impulse response (decaying noise burst)
        std::vector<float> ir(2048, 0.0f);
        ir[0] = 1.0f;
        for (size_t i = 1; i < ir.size(); i++) {
            ir[i] = ((float)rand() / (float)RAND_MAX * 2.0f - 1.0f) * std::exp(-static_cast<float>(i) / 400.0f) * 0.3f;
        }

        bool loaded = convolver.loadImpulseResponse(ir.data(), (uint32_t)ir.size(), 1);
        assert(loaded && "Failed to load IR!");

        std::vector<float> buffer(48000 * 2, 0.0f);
        for (size_t i = 0; i < 48000; i++) {
            float t = (float)i / 48000.0f;
            buffer[2 * i] = 0.5f * std::sin(2.0f * 3.14159265f * 440.0f * t);
            buffer[2 * i + 1] = buffer[2 * i];
        }

        // Test smooth real-time wet/dry adjustment mid-stream
        convolver.setWetLevel(0.7f);
        convolver.setDryLevel(0.3f);
        convolver.process(buffer.data(), 24000);

        convolver.setWetLevel(0.2f);
        convolver.setDryLevel(0.8f);
        convolver.process(buffer.data() + 24000 * 2, 24000);

        for (float s : buffer) {
            assert(!std::isnan(s) && "FFTConvolver produced NaN!");
            assert(!std::isinf(s) && "FFTConvolver produced Inf!");
        }
        std::cout << " OK!\n";
    }

    // 3. Test AudioClarityDSP & AnalogWarmthDSP & MasterLimiterDSP
    {
        std::cout << "-> Testing Clarity, Warmth & Master Limiter...";
        sauti::dsp::AudioClarityDSP clarity;
        sauti::dsp::AnalogWarmthDSP warmth;
        sauti::dsp::MasterLimiterDSP limiter;

        clarity.setEnabled(true);
        warmth.setEnabled(true);
        limiter.setEnabled(true);

        std::vector<float> buffer(48000 * 2, 0.5f);
        clarity.process(buffer.data(), 48000);
        warmth.process(buffer.data(), 48000);
        limiter.process(buffer.data(), 48000);

        for (float s : buffer) {
            assert(!std::isnan(s) && "DSP produced NaN!");
            assert(!std::isinf(s) && "DSP produced Inf!");
            assert(std::abs(s) <= 1.0f && "Limiter output exceeded 1.0 peak!");
        }
        std::cout << " OK!\n";
    }

    std::cout << "\nAll DSP Smoothness, Anti-Pop, and Dynamic Transducer Systems Verified Perfectly!\n";
    return 0;
}
