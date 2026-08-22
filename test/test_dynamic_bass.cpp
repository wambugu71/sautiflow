#include <iostream>
#include <vector>
#include <cmath>
#include <cassert>
#include "../dsp/dynamic_bass_dsp.h"

int main() {
    std::cout << "Testing Sauti Dynamic Bass & Subwoofer DSP...\n";

    sauti::dsp::HarmonicBassDSP bassDsp;
    bassDsp.setEnabled(true);
    bassDsp.setSampleRate(48000.0f);
    bassDsp.setCutoffFrequency(60.0f);
    bassDsp.setBoost(0.8f);

    const std::vector<sauti::dsp::BassEnhanceProfile> profiles = {
        sauti::dsp::BassEnhanceProfile::NaturalBass,
        sauti::dsp::BassEnhanceProfile::PureBass,
        sauti::dsp::BassEnhanceProfile::Subwoofer,
        sauti::dsp::BassEnhanceProfile::HarmonicExciter,
        sauti::dsp::BassEnhanceProfile::PultecDeep
    };

    for (auto profile : profiles) {
        bassDsp.setProfile(profile);
        bassDsp.reset();

        std::vector<float> buffer(48000 * 2, 0.0f);
        // Generate test stereo tone: 50Hz bass + 1kHz mid
        for (size_t i = 0; i < 48000; i++) {
            float t = (float)i / 48000.0f;
            float s50 = 0.3f * std::sin(2.0f * 3.14159265f * 50.0f * t);
            float s1k = 0.1f * std::sin(2.0f * 3.14159265f * 1000.0f * t);
            buffer[2 * i] = s50 + s1k;
            buffer[2 * i + 1] = s50 + s1k;
        }

        bassDsp.process(buffer.data(), 48000);

        // Verify no NaN or Inf
        float maxVal = 0.0f;
        for (size_t i = 0; i < buffer.size(); i++) {
            assert(!std::isnan(buffer[i]) && "Buffer contains NaN!");
            assert(!std::isinf(buffer[i]) && "Buffer contains Inf!");
            if (std::abs(buffer[i]) > maxVal) maxVal = std::abs(buffer[i]);
        }

        std::cout << "Profile " << (int)profile << " processed successfully. Max peak: " << maxVal << "\n";
    }

    std::cout << "All Sauti Dynamic Bass profiles verified OK!\n";
    return 0;
}
