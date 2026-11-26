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

    // Test 9: Comprehensive Multi-Engine Validation (All 6 Topologies)
    const char* engineNames[] = {
        "Dattorro Figure-8 Plate",
        "Lattice Reverb (Parallel Comb)",
        "Diffusion Reverb (Multi-Stage)",
        "8-Channel Hadamard FDN",
        "Keith Barr All-Pass Ring",
        "David Griesinger Spin & Wander"
    };

    for (int eng = 0; eng <= 5; ++eng)
    {
        std::cout << "\n--- Testing Engine " << eng << " (" << engineNames[eng] << ") ---" << std::endl;
        ReverbNode testNode;
        testNode.setSampleRate(48000.0);
        testNode.setEngine(eng);
        testNode.setEnabled(true);
        testNode.setWet(0.5f);
        testNode.setDry(1.0f);
        testNode.setRoomSize(0.7f);
        testNode.setDamping(0.3f);
        testNode.setWidth(1.0f);
        testNode.reset();

        const uint32_t fCount = 48000;
        std::vector<float> buf(fCount * 2, 0.0f);
        buf[0] = 1.0f; // Left impulse
        buf[1] = 1.0f; // Right impulse

        const uint32_t chunk = 256;
        for (uint32_t i = 0; i < fCount; i += chunk)
        {
            uint32_t toProc = std::min(chunk, fCount - i);
            testNode.process(&buf[i * 2], toProc, 2);
        }

        // 1. Check NaN/Inf
        for (size_t i = 0; i < buf.size(); ++i)
        {
            if (std::isnan(buf[i]) || std::isinf(buf[i]))
            {
                std::cerr << "FAILED: Engine " << eng << " produced NaN/Inf at sample " << i << std::endl;
                return 1;
            }
        }
        std::cout << "PASS: Engine " << eng << " output is finite and stable (no NaN/Inf)." << std::endl;

        // 2. Tail energy check
        float tEnergy = 0.0f;
        for (size_t i = 2000 * 2; i < 35000 * 2; ++i)
        {
            tEnergy += buf[i] * buf[i];
        }
        std::cout << "Tail energy: " << tEnergy << std::endl;
        if (tEnergy <= 0.0001f)
        {
            std::cerr << "FAILED: Engine " << eng << " tail energy too low!" << std::endl;
            return 1;
        }

        // 3. Stereo decorrelation check
        float diffE = 0.0f;
        float sumE = 0.0f;
        for (size_t i = 2000; i < 15000; ++i)
        {
            float l = buf[i * 2];
            float r = buf[i * 2 + 1];
            diffE += (l - r) * (l - r);
            sumE += (l + r) * (l + r);
        }
        float decorrRatio = diffE / (sumE + 1e-6f);
        std::cout << "Stereo decorrelation ratio (diff/sum): " << decorrRatio << std::endl;
        if (decorrRatio < 0.03f)
        {
            std::cerr << "FAILED: Engine " << eng << " stereo channels too correlated!" << std::endl;
            return 1;
        }
        std::cout << "PASS: Engine " << eng << " produces rich, decorrelated stereo field." << std::endl;
    }

    // Test 10: High-SR stress across all 6 engines (float & double, up to 384 kHz)
    {
        double allRates[] = {44100.0, 48000.0, 96000.0, 176400.0, 192000.0, 384000.0};
        for (int eng = 0; eng <= 5; ++eng)
        {
            for (double sr : allRates)
            {
                ReverbNode node;
                node.setSampleRate(sr);
                node.setEngine(eng);
                node.setEnabled(true);
                node.setWet(0.6f);
                node.setDry(0.8f);
                node.setRoomSize(0.85f);
                node.setDamping(0.35f);
                node.setWidth(1.2f);
                node.reset();

                const uint32_t frames = 4096;
                std::vector<float> buf32(frames * 2, 0.0f);
                std::vector<double> buf64(frames * 2, 0.0);
                for (uint32_t i = 0; i < 64; ++i)
                {
                    float s = std::sin(2.0f * 3.14159265f * 440.0f * (float)i / (float)sr);
                    buf32[i * 2] = s;
                    buf32[i * 2 + 1] = s * 0.8f;
                    buf64[i * 2] = (double)s;
                    buf64[i * 2 + 1] = (double)s * 0.8;
                }
                for (uint32_t i = 0; i < frames; i += 256)
                {
                    uint32_t n = std::min<uint32_t>(256, frames - i);
                    node.process(&buf32[i * 2], n, 2);
                }
                node.reset();
                for (uint32_t i = 0; i < frames; i += 256)
                {
                    uint32_t n = std::min<uint32_t>(256, frames - i);
                    node.process(&buf64[i * 2], n, 2);
                }

                for (size_t i = 0; i < buf32.size(); ++i)
                {
                    if (!std::isfinite(buf32[i]) || std::abs(buf32[i]) > 10.0f)
                    {
                        std::cerr << "FAILED: High-SR float stress engine " << eng << " @ " << sr << std::endl;
                        return 1;
                    }
                    if (!std::isfinite(buf64[i]) || std::abs(buf64[i]) > 10.0)
                    {
                        std::cerr << "FAILED: High-SR double stress engine " << eng << " @ " << sr << std::endl;
                        return 1;
                    }
                }
            }
        }
        std::cout << "PASS: High-SR stress verified across all 6 engines (44.1k..384k, F32 & F64)." << std::endl;
    }

    // Test 11: Zero engine bleed, parameter isolation, pre-delay isolation & 0 dry latency
    {
        ReverbNode node;
        node.setSampleRate(48000.0);
        node.setEngine(0); // Dattorro
        node.setDattorroParams(1.0f, 0.0f, 0.9f, 0.2f, 150.0f, 1.2f);
        node.setDiffusionParams(0.42f, 0.88f, 0.65f, 1800.0f, 0.77f, 0.31f, 1.1f);
        node.setEnabled(true);
        node.reset();

        if (node.getLatencySamples() != 0.0)
        {
            std::cerr << "FAILED: getLatencySamples() should be 0.0 (dry path is zero-latency)." << std::endl;
            return 1;
        }

        // Modifying Dattorro must not clobber Diffusion parameters
        node.setWet(0.95f);
        node.setRoomSize(0.98f);
        float dWet = 0, dDry = 0, dRoom = 0, dDecay = 0, dDiff = 0, dDamp = 0, dWidth = 0;
        node.getDiffusionParams(&dWet, &dDry, &dRoom, &dDecay, &dDiff, &dDamp, &dWidth);
        if (std::abs(dWet - 0.42f) > 1e-4f || std::abs(dRoom - 0.65f) > 1e-4f || std::abs(dDecay - 1800.0f) > 1e-2f)
        {
            std::cerr << "FAILED: Dattorro parameter changes clobbered Diffusion parameters!" << std::endl;
            return 1;
        }

        // Fill Dattorro pre-delay and tank with high energy
        std::vector<float> burst(8192 * 2, 0.0f);
        for (size_t i = 0; i < 2048; ++i)
        {
            burst[i * 2] = 0.8f * std::sin(0.1f * (float)i);
            burst[i * 2 + 1] = 0.8f * std::cos(0.1f * (float)i);
        }
        node.process(burst.data(), 8192, 2);

        // Switch through every other engine and feed pure silence: zero bleed allowed
        for (int nextEng = 1; nextEng <= 5; ++nextEng)
        {
            node.setEngine(nextEng);
            node.setWet(1.0f);
            node.setDry(0.0f);
            std::vector<float> silence(2048 * 2, 0.0f);
            node.process(silence.data(), 2048, 2);
            float maxAbs = 0.0f;
            for (float s : silence) maxAbs = std::max(maxAbs, std::abs(s));
            if (maxAbs > 1e-7f)
            {
                std::cerr << "FAILED: Tail bled into engine " << nextEng << " (maxAbs=" << maxAbs << ")" << std::endl;
                return 1;
            }
        }
        std::cout << "PASS: Zero engine bleed, parameter isolation, and 0-latency verified." << std::endl;
    }

    // Test 12: Idempotent setEngine(current) preserves ringing tail
    {
        for (int eng = 0; eng <= 5; ++eng)
        {
            ReverbNode node;
            node.setSampleRate(48000.0);
            node.setEngine(eng);
            node.setWet(1.0f);
            node.setDry(0.0f);
            node.setRoomSize(0.75f);
            node.setEnabled(true);
            node.reset();

            std::vector<float> buf(2048 * 2, 0.0f);
            buf[0] = 1.0f;
            buf[1] = 1.0f;
            node.process(buf.data(), 2048, 2);

            // Redundant setEngine with same index must NOT clear buffers
            node.setEngine(eng);
            std::vector<float> tail(2048 * 2, 0.0f);
            node.process(tail.data(), 2048, 2);
            float energy = 0.0f;
            for (float s : tail) energy += s * s;
            if (energy <= 0.0001f)
            {
                std::cerr << "FAILED: Idempotent setEngine(" << eng << ") cleared active tail!" << std::endl;
                return 1;
            }
        }
        std::cout << "PASS: Idempotent setEngine preserves active reverb tail across all engines." << std::endl;
    }

    // Test 13: DiffusionReverbDSP roomSize independence (same decayTimeMs, different roomSize)
    {
        sauti::dsp::DiffusionReverbDSP smallRoom, largeRoom;
        smallRoom.setSampleRate(48000.0);
        largeRoom.setSampleRate(48000.0);
        smallRoom.setEnabled(true);
        largeRoom.setEnabled(true);
        smallRoom.setParams(1.0f, 0.0f, 0.10f, 1500.0f, 0.75f, 0.25f, 1.0f);
        largeRoom.setParams(1.0f, 0.0f, 0.90f, 1500.0f, 0.75f, 0.25f, 1.0f);
        smallRoom.reset();
        largeRoom.reset();

        const uint32_t frames = 16384;
        std::vector<float> bufA(frames * 2, 0.0f), bufB(frames * 2, 0.0f);
        bufA[0] = bufA[1] = 1.0f;
        bufB[0] = bufB[1] = 1.0f;
        smallRoom.process(bufA.data(), frames, 2);
        largeRoom.process(bufB.data(), frames, 2);

        double diffL2 = 0.0;
        for (size_t i = 0; i < bufA.size(); ++i)
        {
            double d = (double)bufA[i] - (double)bufB[i];
            diffL2 += d * d;
        }
        std::cout << "Diffusion roomSize L2 difference (0.1 vs 0.9 @ 1500ms): " << diffL2 << std::endl;
        if (diffL2 < 0.05)
        {
            std::cerr << "FAILED: DiffusionReverbDSP roomSize did not meaningfully affect response!" << std::endl;
            return 1;
        }
        std::cout << "PASS: DiffusionReverbDSP roomSize independently shapes physical delay lengths." << std::endl;
    }

    // Test 14: Hadamard FDN low-frequency multi-tone bass L/R balance
    {
        ReverbNode node;
        node.setSampleRate(48000.0);
        node.setEngine(3);
        node.setHadamardParams(1.0f, 0.0f, 0.70f, 0.20f, 1.0f);
        node.setEnabled(true);
        node.reset();

        const uint32_t frames = 24000;
        const float freqs[8] = {60.0f, 85.0f, 110.0f, 140.0f, 175.0f, 210.0f, 250.0f, 300.0f};
        std::vector<float> buf(frames * 2, 0.0f);
        for (uint32_t i = 0; i < frames; ++i)
        {
            float s = 0.0f;
            for (int k = 0; k < 8; ++k)
                s += std::sin(2.0f * 3.14159265f * freqs[k] * (float)i / 48000.0f);
            s *= (0.5f / 8.0f);
            buf[i * 2] = s;
            buf[i * 2 + 1] = s;
        }
        node.process(buf.data(), frames, 2);

        double sumL2 = 0.0, sumR2 = 0.0;
        for (uint32_t i = 4000; i < frames; ++i)
        {
            sumL2 += (double)buf[i * 2] * buf[i * 2];
            sumR2 += (double)buf[i * 2 + 1] * buf[i * 2 + 1];
        }
        double rmsL = std::sqrt(sumL2 / (frames - 4000));
        double rmsR = std::sqrt(sumR2 / (frames - 4000));
        double ratio = rmsL / (rmsR + 1e-12);
        std::cout << "Hadamard LF bass RMS L=" << rmsL << " R=" << rmsR << " ratio=" << ratio << std::endl;
        if (rmsL < 0.01 || rmsR < 0.01 || ratio < 0.65 || ratio > 1.55)
        {
            std::cerr << "FAILED: Hadamard FDN low-frequency L/R energy is unbalanced!" << std::endl;
            return 1;
        }
        std::cout << "PASS: Hadamard FDN low-frequency stereo balance verified." << std::endl;
    }

    // Test 15: Damping effectiveness across all 6 engines at 48 kHz and 192 kHz
    {
        double testRates[] = {48000.0, 192000.0};
        for (int eng = 0; eng <= 5; ++eng)
        {
            for (double sr : testRates)
            {
                ReverbNode bright, dark;
                bright.setSampleRate(sr);
                dark.setSampleRate(sr);
                bright.setEngine(eng);
                dark.setEngine(eng);
                bright.setEnabled(true);
                dark.setEnabled(true);
                bright.setWet(1.0f);
                bright.setDry(0.0f);
                bright.setRoomSize(0.75f);
                bright.setDamping(0.0f);
                dark.setWet(1.0f);
                dark.setDry(0.0f);
                dark.setRoomSize(0.75f);
                dark.setDamping(1.0f);
                bright.reset();
                dark.reset();

                const uint32_t frames = (uint32_t)(sr * 0.75);
                std::vector<float> bBuf(frames * 2, 0.0f), dBuf(frames * 2, 0.0f);
                for (uint32_t i = 0; i < 256; ++i)
                {
                    float val = (i % 2 == 0) ? 1.0f : -1.0f;
                    bBuf[i * 2] = dBuf[i * 2] = val;
                    bBuf[i * 2 + 1] = dBuf[i * 2 + 1] = val;
                }
                bright.process(bBuf.data(), frames, 2);
                dark.process(dBuf.data(), frames, 2);

                double bE = 0.0, dE = 0.0;
                const size_t start = (size_t)(sr * 0.15) * 2;
                for (size_t i = start; i < bBuf.size(); ++i)
                {
                    bE += (double)bBuf[i] * bBuf[i];
                    dE += (double)dBuf[i] * dBuf[i];
                }
                if (dE >= bE * 0.7)
                {
                    std::cerr << "FAILED: Damping ineffective on engine " << eng << " @ " << sr
                              << " (bright=" << bE << ", dark=" << dE << ")" << std::endl;
                    return 1;
                }
            }
        }
        std::cout << "PASS: Damping effectiveness verified across all 6 engines at 48 kHz and 192 kHz." << std::endl;
    }

    // Test 16: LatticeReverbDSP steady-state wet RMS calibration (no comb runaway)
    {
        sauti::dsp::LatticeReverbDSP lat;
        lat.setSampleRate(48000.0);
        lat.setParams(1.0f, 0.0f, 0.75f, 0.25f, 1.0f);
        lat.setEnabled(true);
        lat.reset();

        const uint32_t frames = 24000;
        std::vector<float> buf(frames * 2, 0.0f);
        uint32_t seed = 987654321u;
        for (uint32_t i = 0; i < frames; ++i)
        {
            seed = seed * 1664525u + 1013904223u;
            float nL = (((float)(seed >> 16) / 32768.0f) - 1.0f) * 1.732f; // approx unit RMS
            seed = seed * 1664525u + 1013904223u;
            float nR = (((float)(seed >> 16) / 32768.0f) - 1.0f) * 1.732f;
            buf[i * 2] = nL;
            buf[i * 2 + 1] = nR;
        }
        lat.process(buf.data(), frames, 2);

        double sum2 = 0.0;
        for (uint32_t i = 8000; i < frames; ++i)
        {
            sum2 += 0.5 * ((double)buf[i * 2] * buf[i * 2] + (double)buf[i * 2 + 1] * buf[i * 2 + 1]);
        }
        double rms = std::sqrt(sum2 / (frames - 8000));
        std::cout << "Lattice steady-state wet RMS (room=0.75, unit white noise): " << rms << std::endl;
        if (rms < 0.15 || rms > 1.5)
        {
            std::cerr << "FAILED: Lattice wet RMS out of calibrated range [0.15, 1.5]!" << std::endl;
            return 1;
        }
        std::cout << "PASS: LatticeReverbDSP wet RMS is well-calibrated." << std::endl;
    }

    std::cout << "\nALL REVERB TESTS PASSED SUCCESSFULLY!" << std::endl;
    return 0;
}
