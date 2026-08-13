#include <iostream>
#include <vector>
#include <cmath>
#include <cassert>
#include "audio_engine.h"

int main()
{
    std::cout << "Running Quality Foundation DSP tests..." << std::endl;

    AudioEngineHandle *engine = ae_create_engine(48000, 2);
    assert(engine != nullptr);

    // 1. Test True-Peak Metering & Look-Ahead Limiter
    ae_set_true_peak_meter_enabled(engine, 1);
    ae_set_lookahead_limiter_enabled(engine, 1);
    ae_set_lookahead_limiter_params(engine, -1.0f, 2.0f, 50.0f);

    float ceiling_dbtp = 0.0f, attack_ms = 0.0f, release_ms = 0.0f;
    ae_get_lookahead_limiter_params(engine, &ceiling_dbtp, &attack_ms, &release_ms);
    assert(std::abs(ceiling_dbtp - (-1.0f)) < 0.01f);
    assert(std::abs(attack_ms - 2.0f) < 0.01f);
    assert(std::abs(release_ms - 50.0f) < 0.01f);

    // Verify look-ahead limiter latency is reported in PDC
    double latencySamples = ae_get_engine_latency_samples(engine);
    std::cout << "Engine Latency Samples (including 2ms lookahead): " << latencySamples << std::endl;
    assert(latencySamples >= 96.0); // 2ms at 48kHz = 96 samples

    // 2. Test Loudness Meter (ITU-R BS.1770-4)
    ae_set_loudness_meter_enabled(engine, 1);
    ae_set_loudness_normalizer_enabled(engine, 1);
    ae_set_loudness_normalizer_target(engine, -14.0f);
    assert(ae_get_loudness_normalizer_enabled(engine) == 1);
    assert(std::abs(ae_get_loudness_normalizer_target(engine) - (-14.0f)) < 0.01f);

    // 3. Test Unified Quality Telemetry Snapshot
    AEQualityTelemetry t = ae_get_quality_telemetry(engine);
    std::cout << "Quality Telemetry Initial Readout:" << std::endl;
    std::cout << "  Momentary LUFS: " << t.momentary_lufs << std::endl;
    std::cout << "  Integrated LUFS: " << t.integrated_lufs << std::endl;
    std::cout << "  True Peak dBTP: " << t.true_peak_dbtp << std::endl;
    std::cout << "  Total Latency ms: " << t.total_engine_latency_ms << std::endl;

    // 4. Test Resampling Policy Info
    AEResamplingPolicyInfo rInfo = ae_get_resampling_policy_info(engine);
    std::cout << "Resampling Policy Info:" << std::endl;
    std::cout << "  Input Rate: " << rInfo.input_sample_rate << " Hz" << std::endl;
    std::cout << "  Engine Rate: " << rInfo.engine_sample_rate << " Hz" << std::endl;
    std::cout << "  Is Bypassed: " << rInfo.is_bypassed << std::endl;
    assert(rInfo.is_bypassed == 1);

    ae_destroy_engine(engine);
    std::cout << "All Quality Foundation DSP tests PASSED successfully!" << std::endl;
    return 0;
}
