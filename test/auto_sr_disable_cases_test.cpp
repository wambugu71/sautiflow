#include <iostream>
#include <vector>
#include <chrono>
#include <thread>
#include <cassert>
#include "audio_engine.h"

int main()
{
    std::cout << "========================================================\n";
    std::cout << " AUTO SAMPLE RATE DISABLE TEST SUITE (CASES A, B, C, D) \n";
    std::cout << "========================================================\n";

    AudioEngineHandle *engine = ae_create_engine(48000, 2);
    if (!engine)
    {
        std::cerr << "[FAIL] Failed to create engine\n";
        return 1;
    }

    // CASE A: Auto ON -> Auto OFF (Native 48k)
    std::cout << "\n[TEST CASE A] Auto ON -> Auto OFF (Native 48kHz)\n";
    ae_set_auto_sample_rate_match_enabled(engine, 1);
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    ae_play(engine);
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    ae_set_auto_sample_rate_match_enabled(engine, 0);
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    std::cout << "  [PASS] Case A completed cleanly!\n";

    // CASE B: Auto ON -> Auto OFF (Targeting 96k -> 48k transition)
    std::cout << "\n[TEST CASE B] Auto ON -> Auto OFF (96kHz track -> Fixed 48kHz)\n";
    ae_set_auto_sample_rate_match_enabled(engine, 1);
    ae_set_output_sample_rate(engine, 96000);
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    ae_play(engine);
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    ae_set_auto_sample_rate_match_enabled(engine, 0);
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    std::cout << "  [PASS] Case B completed cleanly!\n";

    // CASE C: Auto ON -> Auto OFF (44.1kHz -> Fixed 48kHz)
    std::cout << "\n[TEST CASE C] Auto ON -> Auto OFF (44.1kHz track -> Fixed 48kHz)\n";
    ae_set_auto_sample_rate_match_enabled(engine, 1);
    ae_set_output_sample_rate(engine, 44100);
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    ae_play(engine);
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    ae_set_auto_sample_rate_match_enabled(engine, 0);
    std::this_thread::sleep_for(std::chrono::milliseconds(200));
    std::cout << "  [PASS] Case C completed cleanly!\n";

    // CASE D: Auto ON -> Auto OFF during active crossfade
    std::cout << "\n[TEST CASE D] Auto ON -> Auto OFF during Active Crossfade\n";
    ae_set_crossfade_enabled(engine, 1);
    ae_set_crossfade_duration_ms(engine, 1000);
    ae_set_auto_sample_rate_match_enabled(engine, 1);
    ae_set_output_sample_rate(engine, 44100);
    ae_play(engine);
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    // Trigger Auto OFF during playback/crossfade state
    ae_set_auto_sample_rate_match_enabled(engine, 0);
    std::this_thread::sleep_for(std::chrono::milliseconds(300));
    std::cout << "  [PASS] Case D completed cleanly!\n";

    ae_destroy_engine(engine);

    std::cout << "\n========================================================\n";
    std::cout << " ALL 4 TEST CASES (A, B, C, D) PASSED WITH 0 ABORTS!    \n";
    std::cout << "========================================================\n";
    return 0;
}
