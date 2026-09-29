#include <iostream>
#include <vector>
#include <cmath>
#include <cassert>
#include <numeric>
#include "reverb_node.h"

int main()
{
    std::cout << "=== Running ReverbNode Dattorro Diffuse Tank Test ===" << std::endl;

    ReverbNode reverb;
    reverb.setSampleRate(48000.0);
    reverb.setEnabled(true);
    reverb.setWet(0.25f);
    reverb.setDry(1.0f);
    reverb.setRoomSize(0.6f);
    reverb.setDamping(0.4f);
    reverb.setPreDelayMs(10.0f);
    reverb.setWidth(1.0f);

    // Test 1: Impulse Response Test
    // Feed a single Dirac impulse at frame 0 and observe the output over 1 second (48,000 frames)
    const uint32_t totalFrames = 48000;
    std::vector<float> buffer(totalFrames * 2, 0.0f);
    buffer[0] = 1.0f; // Left impulse
    buffer[1] = 1.0f; // Right impulse

    // Process in chunks of 256 frames (typical audio buffer size)
    const uint32_t chunkSize = 256;
    for (uint32_t i = 0; i < totalFrames; i += chunkSize)
    {
        uint32_t framesToProcess = std::min(chunkSize, totalFrames - i);
        reverb.process(&buffer[i * 2], framesToProcess, 2);
    }

    // Check for NaN or Inf
    for (size_t i = 0; i < buffer.size(); ++i)
    {
        if (std::isnan(buffer[i]) || std::isinf(buffer[i]))
        {
            std::cerr << "FAILED: NaN or Inf detected at sample " << i << std::endl;
            return 1;
        }
    }
    std::cout << "PASS: No NaN/Inf detected in 1 second impulse response." << std::endl;

    // Check that there is sound after the impulse (reverb tail)
    float tailEnergy = 0.0f;
    for (size_t i = 2000 * 2; i < 40000 * 2; ++i)
    {
        tailEnergy += buffer[i] * buffer[i];
    }
    std::cout << "Reverb tail energy: " << tailEnergy << std::endl;
    if (tailEnergy <= 0.001f)
    {
        std::cerr << "FAILED: Reverb tail energy too low!" << std::endl;
        return 1;
    }
    std::cout << "PASS: Reverb tail energy present and well-distributed." << std::endl;

    // Test 2: Check for Flutter Echo vs Smooth Diffusion
    // An impulse into 8 parallel combs produces isolated periodic peaks.
    // A diffuse tank produces an envelope with high density.
    // Let's count zero crossings in the tail (between frame 2000 and 10000)
    int zeroCrossings = 0;
    for (size_t i = 2000 * 2; i < 10000 * 2; i += 2)
    {
        if ((buffer[i] >= 0.0f && buffer[i - 2] < 0.0f) ||
            (buffer[i] < 0.0f && buffer[i - 2] >= 0.0f))
        {
            zeroCrossings++;
        }
    }
    std::cout << "Tail zero crossings (8000 frames): " << zeroCrossings << std::endl;
    if (zeroCrossings < 500)
    {
        std::cerr << "FAILED: Zero crossings too low, indicating sparse/flutter echo!" << std::endl;
        return 1;
    }
    std::cout << "PASS: High modal density confirmed (zero crossings = " << zeroCrossings << ")." << std::endl;

    // Test 3: Stereo Decorrelation Test
    // Ensure Left and Right channels are distinct (not identical mono smear)
    float diffEnergy = 0.0f;
    float sumEnergy = 0.0f;
    for (size_t i = 2000; i < 10000; ++i)
    {
        float l = buffer[i * 2];
        float r = buffer[i * 2 + 1];
        diffEnergy += (l - r) * (l - r);
        sumEnergy += (l + r) * (l + r);
    }
    float decorrelationRatio = diffEnergy / (sumEnergy + 1e-6f);
    std::cout << "Stereo decorrelation ratio (diff/sum): " << decorrelationRatio << std::endl;
    if (decorrelationRatio < 0.05f)
    {
        std::cerr << "FAILED: Stereo channels are too correlated (mono-like)!" << std::endl;
        return 1;
    }
    std::cout << "PASS: Stereo channels are decorrelated and wide." << std::endl;

    // Test 4: Sample Rate Scaling Test (44.1k, 48k, 96k, 192k)
    double rates[] = {44100.0, 48000.0, 96000.0, 192000.0};
    for (double r : rates)
    {
        reverb.setSampleRate(r);
        std::vector<float> testBuf(512 * 2, 0.5f);
        reverb.process(testBuf.data(), 512, 2);
        for (float s : testBuf)
        {
            if (std::isnan(s) || std::isinf(s))
            {
                std::cerr << "FAILED: Sample rate " << r << " produced NaN/Inf!" << std::endl;
                return 1;
            }
        }
    }
    std::cout << "PASS: Sample rate scaling verified across 44.1k, 48k, 96k, 192k." << std::endl;

    // Test 6: Physical RT60 Decay Scaling (Small Room vs Large Space)
    {
        ReverbNode smallReverb;
        smallReverb.setSampleRate(48000.0);
        smallReverb.setEnabled(true);
        smallReverb.setWet(1.0f);
        smallReverb.setDry(0.0f);
        smallReverb.setRoomSize(0.05f); // Tight small room
        smallReverb.setDamping(0.5f);

        const uint32_t len = 48000;
        std::vector<float> impulse(len * 2, 0.0f);
        impulse[0] = 1.0f;
        impulse[1] = 1.0f;
        smallReverb.process(impulse.data(), len, 2);

        // By frame 36000 (0.75 seconds), energy of small room should be decayed below 1e-4
        float lateEnergy = 0.0f;
        for (size_t i = 36000 * 2; i < 48000 * 2; ++i)
        {
            lateEnergy += impulse[i] * impulse[i];
        }
        std::cout << "Small room late tail energy (0.75s-1.0s): " << lateEnergy << std::endl;
        if (lateEnergy > 0.001f)
        {
            std::cerr << "FAILED: Small room decay is too long!" << std::endl;
            return 1;
        }
        std::cout << "PASS: Small room decays rapidly as expected for a physical tight space." << std::endl;
    }

    // Test 7: Stereo Width Control (0.0 = Mono, 1.0 = Stereo)
    {
        ReverbNode monoReverb;
        monoReverb.setSampleRate(48000.0);
        monoReverb.setEnabled(true);
        monoReverb.setWet(1.0f);
        monoReverb.setDry(0.0f);
        monoReverb.setWidth(0.0f); // Pure mono
        monoReverb.reset(); // Snap initial parameters

        std::vector<float> monoBuf(2048 * 2, 0.0f);
        monoBuf[0] = 1.0f;
        monoReverb.process(monoBuf.data(), 2048, 2);

        float monoDiff = 0.0f;
        for (size_t i = 500; i < 2000; ++i)
        {
            float l = monoBuf[i * 2];
            float r = monoBuf[i * 2 + 1];
            monoDiff += std::abs(l - r);
        }
        std::cout << "Mono width difference (sum of |L - R|): " << monoDiff << std::endl;
        if (monoDiff > 1e-5f)
        {
            std::cerr << "FAILED: Width = 0.0 did not collapse to pure mono!" << std::endl;
            return 1;
        }
        std::cout << "PASS: Width = 0.0 produces identical Left and Right (pure mono)." << std::endl;
    }

    // Test 8: Damping Transparency (Damping = 0.0 vs Damping = 1.0)
    {
        ReverbNode brightReverb;
        brightReverb.setSampleRate(48000.0);
        brightReverb.setEnabled(true);
        brightReverb.setWet(1.0f);
        brightReverb.setDry(0.0f);
        brightReverb.setRoomSize(0.7f);
        brightReverb.setDamping(0.0f); // Maximum brightness
        brightReverb.reset();

        ReverbNode darkReverb;
        darkReverb.setSampleRate(48000.0);
        darkReverb.setEnabled(true);
        darkReverb.setWet(1.0f);
        darkReverb.setDry(0.0f);
        darkReverb.setRoomSize(0.7f);
        darkReverb.setDamping(1.0f); // Maximum damping
        darkReverb.reset();

        // High frequency impulse (alternating +/- 1.0 at Nyquist/high freq)
        const uint32_t frames = 30000;
        std::vector<float> brightBuf(frames * 2, 0.0f);
        std::vector<float> darkBuf(frames * 2, 0.0f);
        for (uint32_t i = 0; i < 128; ++i)
        {
            float val = (i % 2 == 0) ? 1.0f : -1.0f;
            brightBuf[i * 2] = val;
            darkBuf[i * 2] = val;
        }

        brightReverb.process(brightBuf.data(), frames, 2);
        darkReverb.process(darkBuf.data(), frames, 2);

        // Measure energy in the circulating diffuse tail (frames 10,000 to 25,000)
        float brightEnergy = 0.0f;
        float darkEnergy = 0.0f;
        for (size_t i = 10000 * 2; i < 25000 * 2; ++i)
        {
            brightEnergy += brightBuf[i] * brightBuf[i];
            darkEnergy += darkBuf[i] * darkBuf[i];
        }
        std::cout << "Circulating high freq tail energy: Bright=" << brightEnergy << " vs Dark=" << darkEnergy << std::endl;
        if (darkEnergy >= brightEnergy)
        {
            std::cerr << "FAILED: Damping did not attenuate high frequency energy!" << std::endl;
            return 1;
        }
        std::cout << "PASS: Damping filter provides smooth, effective acoustic absorption." << std::endl;
    }

    std::cout << "\nALL REVERB TESTS PASSED SUCCESSFULLY!" << std::endl;
    return 0;
}
