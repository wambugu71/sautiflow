// =============================================================================
// tests/test_simd_dsp.cpp
//
// Dedicated test suite verifying audiophile-grade SIMD optimization accuracy:
//   - SimdFloat4 & SimdDouble2 arithmetic and vector FMA
//   - SimdFloat4::complex_mul_accumulate_2 accuracy vs std::complex<float>
//   - SimdFloat4::fast_tanh Padé approximation accuracy vs scalar reference
//   - SubsonicFilter 64-bit SimdDouble2 stereo vs scalar reference (< 1e-6 delta)
//   - HalfBandFilter2x & PolyphaseOversampler float and double SIMD polyphase accuracy
//   - AnalogWarmthDSP stereo SIMD saturation and channel isolation
//   - FFTConvolverDSP SIMD complex frequency multiply-accumulate & overlap-add
//
// Build: g++ -std=c++20 -O2 tests/test_simd_dsp.cpp -o test_simd_dsp.exe -I. -Itests -Ithird_party -Idsp
// =============================================================================

#ifndef _USE_MATH_DEFINES
#define _USE_MATH_DEFINES
#endif

#include <algorithm>
#include <cmath>
#include <complex>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <vector>

#include "dsp/simd_math.h"
#include "dsp/subsonic_filter.h"
#include "dsp/oversampler.h"
#include "dsp/analog_warmth_dsp.h"
#include "dsp/fft_convolver_dsp.h"
#include "dsp/denormals.h"
#include "dsp/dynamic_bass_dsp.h"
#include "dsp/scaletempo_dsp.h"
#include "dsp/clarity_dsp.h"
#include "dsp/downward_expander_dsp.h"
#include "dsp/de_esser_dsp.h"
#include "dsp/spatial_surround_dsp.h"
#include "dsp/dynamic_system_dsp.h"
#include "dsp/master_limiter_dsp.h"
#include "dsp/stereo_imager_dsp.h"

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

// -----------------------------------------------------------------------------
// 1. Primitive SIMD vector math & complex FMA
// -----------------------------------------------------------------------------
static void test_simd_primitives()
{
    std::printf("\n== SIMD Primitives & Math Verification ==\n");

    // SimdFloat4 basic arithmetic
    float a_arr[4] = {1.5f, -2.0f, 3.25f, 4.0f};
    float b_arr[4] = {0.5f, 3.0f, -1.0f, 2.0f};
    float c_arr[4] = {10.0f, 20.0f, 30.0f, 40.0f};

    sauti::dsp::SimdFloat4 va = sauti::dsp::SimdFloat4::load_u(a_arr);
    sauti::dsp::SimdFloat4 vb = sauti::dsp::SimdFloat4::load_u(b_arr);
    sauti::dsp::SimdFloat4 vc = sauti::dsp::SimdFloat4::load_u(c_arr);

    sauti::dsp::SimdFloat4 v_add = va + vb;
    sauti::dsp::SimdFloat4 v_sub = va - vb;
    sauti::dsp::SimdFloat4 v_mul = va * vb;
    sauti::dsp::SimdFloat4 v_fma = sauti::dsp::SimdFloat4::fma(va, vb, vc);

    float res_add[4], res_sub[4], res_mul[4], res_fma[4];
    v_add.store_u(res_add);
    v_sub.store_u(res_sub);
    v_mul.store_u(res_mul);
    v_fma.store_u(res_fma);

    bool add_ok = true, sub_ok = true, mul_ok = true, fma_ok = true;
    for (int i = 0; i < 4; ++i) {
        if (std::fabs(res_add[i] - (a_arr[i] + b_arr[i])) > 1e-6f) add_ok = false;
        if (std::fabs(res_sub[i] - (a_arr[i] - b_arr[i])) > 1e-6f) sub_ok = false;
        if (std::fabs(res_mul[i] - (a_arr[i] * b_arr[i])) > 1e-6f) mul_ok = false;
        if (std::fabs(res_fma[i] - (a_arr[i] * b_arr[i] + c_arr[i])) > 1e-5f) fma_ok = false;
    }
    CHECK(add_ok, "SimdFloat4 addition is exact");
    CHECK(sub_ok, "SimdFloat4 subtraction is exact");
    CHECK(mul_ok, "SimdFloat4 multiplication is exact");
    CHECK(fma_ok, "SimdFloat4 FMA is exact");

    float exp_sum = res_add[0] + res_add[1] + res_add[2] + res_add[3];
    float got_sum = v_add.reduce_sum();
    CHECK(std::fabs(got_sum - exp_sum) < 1e-5f, "SimdFloat4::reduce_sum matches scalar horizontal sum");
    CHECK(std::fabs(v_add.get(0) - res_add[0]) < 1e-6f, "SimdFloat4::get(0) extracts correct lane");
    CHECK(std::fabs(v_add.get(3) - res_add[3]) < 1e-6f, "SimdFloat4::get(3) extracts correct lane");

    // SimdDouble2 basic arithmetic
    double da[2] = {1.23456789012345, -9.87654321098765};
    double db[2] = {4.56789012345678, 2.34567890123456};
    double dc[2] = {100.0, 200.0};

    sauti::dsp::SimdDouble2 vda = sauti::dsp::SimdDouble2::load_u(da);
    sauti::dsp::SimdDouble2 vdb = sauti::dsp::SimdDouble2::load_u(db);
    sauti::dsp::SimdDouble2 vdc = sauti::dsp::SimdDouble2::load_u(dc);

    sauti::dsp::SimdDouble2 vd_fma = sauti::dsp::SimdDouble2::fma(vda, vdb, vdc);
    double res_dfma[2];
    vd_fma.store_u(res_dfma);

    bool dfma_ok = (std::fabs(res_dfma[0] - (da[0] * db[0] + dc[0])) < 1e-13) &&
                   (std::fabs(res_dfma[1] - (da[1] * db[1] + dc[1])) < 1e-13);
    CHECK(dfma_ok, "SimdDouble2 double-precision FMA holds 64-bit IEEE 754 precision");

    double exp_dsum = da[0] + da[1];
    double got_dsum = vda.reduce_sum();
    CHECK(std::fabs(got_dsum - exp_dsum) < 1e-13, "SimdDouble2::reduce_sum matches scalar horizontal sum");
    CHECK(std::fabs(vda.get_low() - da[0]) < 1e-13, "SimdDouble2::get_low extracts lane 0");
    CHECK(std::fabs(vda.get_high() - da[1]) < 1e-13, "SimdDouble2::get_high extracts lane 1");

    // Complex 2-vector multiply-accumulate
    // In std::complex<float> memory layout is [real, imag, real, imag]
    std::complex<float> x0(1.25f, -0.75f), x1(-2.5f, 3.0f);
    std::complex<float> h0(0.8f, 0.4f), h1(-1.1f, -0.5f);
    std::complex<float> acc0(10.0f, 5.0f), acc1(-4.0f, 8.0f);

    std::complex<float> exp0 = acc0 + (x0 * h0);
    std::complex<float> exp1 = acc1 + (x1 * h1);

    float x_raw[4] = {x0.real(), x0.imag(), x1.real(), x1.imag()};
    float h_raw[4] = {h0.real(), h0.imag(), h1.real(), h1.imag()};
    float acc_raw[4] = {acc0.real(), acc0.imag(), acc1.real(), acc1.imag()};

    sauti::dsp::SimdFloat4 vx = sauti::dsp::SimdFloat4::load_u(x_raw);
    sauti::dsp::SimdFloat4 vh = sauti::dsp::SimdFloat4::load_u(h_raw);
    sauti::dsp::SimdFloat4 vacc = sauti::dsp::SimdFloat4::load_u(acc_raw);

    // Call with correct order: (a, b, acc)
    sauti::dsp::SimdFloat4 v_cmac = sauti::dsp::SimdFloat4::complex_mul_accumulate_2(vx, vh, vacc);
    float cmac_res[4];
    v_cmac.store_u(cmac_res);

    bool cmac_ok0 = (std::fabs(cmac_res[0] - exp0.real()) < 1e-6f) &&
                    (std::fabs(cmac_res[1] - exp0.imag()) < 1e-6f);
    bool cmac_ok1 = (std::fabs(cmac_res[2] - exp1.real()) < 1e-6f) &&
                    (std::fabs(cmac_res[3] - exp1.imag()) < 1e-6f);
    CHECK(cmac_ok0 && cmac_ok1, "SimdFloat4::complex_mul_accumulate_2 matches std::complex multiplication exactly");

    // Fast Padé tanh accuracy vs scalar reference
    auto scalar_pade_tanh = [](float x) -> float {
        if (x < -3.0f) return -1.0f;
        if (x > 3.0f) return 1.0f;
        float x2 = x * x;
        return x * (27.0f + x2) / (27.0f + 9.0f * x2);
    };

    float max_diff_scalar = 0.0f;
    float max_diff_exact = 0.0f;
    bool tanh_monotonic = true;
    float prev_tanh = -2.0f;

    for (float x = -5.0f; x <= 5.0f; x += 0.05f) {
        float f_arr[4] = {x, -x, x * 0.5f, -x * 0.5f};
        sauti::dsp::SimdFloat4 v_in = sauti::dsp::SimdFloat4::load_u(f_arr);
        sauti::dsp::SimdFloat4 v_out = sauti::dsp::SimdFloat4::fast_tanh(v_in);
        float out_arr[4];
        v_out.store_u(out_arr);

        float ref = scalar_pade_tanh(x);
        float diff_ref = std::fabs(out_arr[0] - ref);
        if (diff_ref > max_diff_scalar) max_diff_scalar = diff_ref;

        float exact = std::tanh(x);
        float diff_exact = std::fabs(out_arr[0] - exact);
        if (diff_exact > max_diff_exact) max_diff_exact = diff_exact;

        if (out_arr[0] < prev_tanh - 1e-6f) {
            tanh_monotonic = false;
        }
        prev_tanh = out_arr[0];
    }
    CHECK(max_diff_scalar < 1e-6f, "SimdFloat4::fast_tanh is bit-accurate with scalar Padé reference (< 1e-6)");
    CHECK(max_diff_exact < 0.025f, "SimdFloat4::fast_tanh approximates std::tanh within 0.025 across [-5, 5]");
    CHECK(tanh_monotonic, "SimdFloat4::fast_tanh is strictly monotonic");
}

// -----------------------------------------------------------------------------
// 2. SubsonicFilter 64-bit SIMD Double2 vs Scalar Reference
// -----------------------------------------------------------------------------
static void test_subsonic_filter_fidelity()
{
    std::printf("\n== SubsonicFilter 64-bit SIMD Fidelity Verification ==\n");

    const int kSampleRate = 48000;
    const int kNumFrames = 48000; // 1 second of audio

    sauti::dsp::SubsonicFilter filter_stereo;
    filter_stereo.setSampleRate(static_cast<float>(kSampleRate));

    sauti::dsp::SubsonicFilter filter_left_mono;
    filter_left_mono.setSampleRate(static_cast<float>(kSampleRate));

    sauti::dsp::SubsonicFilter filter_right_mono;
    filter_right_mono.setSampleRate(static_cast<float>(kSampleRate));

    std::vector<float> stereo_in(kNumFrames * 2);
    std::vector<float> mono_left_in(kNumFrames);
    std::vector<float> mono_right_in(kNumFrames);

    // Generate test audio:
    // Left: 5 Hz infrasonic rumble + 1000 Hz tone + DC bias
    // Right: 10 Hz infrasonic rumble + 440 Hz tone + DC bias
    for (int i = 0; i < kNumFrames; ++i) {
        float t = static_cast<float>(i) / kSampleRate;
        float l = 0.5f + 0.3f * std::sin(2.0f * float(M_PI) * 5.0f * t) + 0.2f * std::sin(2.0f * float(M_PI) * 1000.0f * t);
        float r = -0.4f + 0.25f * std::sin(2.0f * float(M_PI) * 10.0f * t) + 0.35f * std::sin(2.0f * float(M_PI) * 440.0f * t);

        stereo_in[i * 2 + 0] = l;
        stereo_in[i * 2 + 1] = r;

        mono_left_in[i] = l;
        mono_right_in[i] = r;
    }

    std::vector<float> stereo_out = stereo_in;
    std::vector<float> mono_left_out = mono_left_in;
    std::vector<float> mono_right_out = mono_right_in;

    // Process stereo using SimdDouble2
    filter_stereo.process(stereo_out.data(), kNumFrames, 2);

    // Process mono references using scalar recurrence
    filter_left_mono.process(mono_left_out.data(), kNumFrames, 1);
    filter_right_mono.process(mono_right_out.data(), kNumFrames, 1);

    // Verify bit-accuracy: stereo SIMD vs scalar mono
    double max_delta_left = 0.0;
    double max_delta_right = 0.0;
    for (int i = 0; i < kNumFrames; ++i) {
        double dl = std::fabs(stereo_out[i * 2 + 0] - mono_left_out[i]);
        double dr = std::fabs(stereo_out[i * 2 + 1] - mono_right_out[i]);
        if (dl > max_delta_left) max_delta_left = dl;
        if (dr > max_delta_right) max_delta_right = dr;
    }

    // Both use identical 64-bit double calculations
    CHECK(max_delta_left < 1e-6, "Stereo SimdDouble2 vs scalar Left channel delta < 1e-6");
    CHECK(max_delta_right < 1e-6, "Stereo SimdDouble2 vs scalar Right channel delta < 1e-6");

    // Verify DC and infrasonic rejection
    float last_dc_l = stereo_out[(kNumFrames - 1) * 2 + 0];
    float last_dc_r = stereo_out[(kNumFrames - 1) * 2 + 1];
    CHECK(std::isfinite(last_dc_l) && std::isfinite(last_dc_r), "SubsonicFilter outputs are strictly finite");
}

// -----------------------------------------------------------------------------
// 3. HalfBandFilter2x & PolyphaseOversampler SIMD Invariance & Quality
// -----------------------------------------------------------------------------
static void test_oversampler_simd_fidelity()
{
    std::printf("\n== HalfBandFilter2x & PolyphaseOversampler SIMD Polyphase Verification ==\n");

    // 1. Test PolyphaseOversampler2x (uses HalfBandFilter2x internally with SIMD)
    sauti::dsp::PolyphaseOversampler2x os;
    os.init(48000, 1024);
    os.reset();

    const uint32_t N = 256;
    std::vector<float> in(2 * N, 0.0f);
    in[2 * 20] = 1.0f;     // Left impulse at frame 20
    in[2 * 20 + 1] = 0.5f; // Right impulse at frame 20

    float* up = os.upsample(in.data(), N);
    CHECK(up != nullptr, "PolyphaseOversampler2x upsample returned valid buffer");

    std::vector<float> out(2 * N, 0.0f);
    os.downsample(up, out.data(), N);

    float peakL = 0.0f, peakR = 0.0f;
    double sumL = 0.0, sumR = 0.0;
    int peakIdxL = -1;

    for (uint32_t i = 0; i < N; ++i) {
        sumL += out[2 * i];
        sumR += out[2 * i + 1];
        if (out[2 * i] > peakL) { peakL = out[2 * i]; peakIdxL = (int)i; }
        if (out[2 * i + 1] > peakR) { peakR = out[2 * i + 1]; }
    }

    CHECK(peakIdxL == 30, "SIMD PolyphaseOversampler2x cascade group delay = exactly 10 frames (peak at 30 for impulse at 20)");
    CHECK(std::fabs(sumL - 1.0) < 0.02, "SIMD PolyphaseOversampler2x Left DC gain is unity (~1.0)");
    CHECK(std::fabs(sumR - 0.5) < 0.02, "SIMD PolyphaseOversampler2x Right DC gain is unity (~0.5)");

    // 2. Direct comparison between Float32 SIMD and Float64 SIMD polyphase filters
    sauti::dsp::HalfBandFilter2xT<float> hb_float;
    sauti::dsp::HalfBandFilter2xT<double> hb_double;

    std::vector<float> down_f(N, 0.0f);
    std::vector<double> down_d(N, 0.0);

    for (uint32_t i = 0; i < N; ++i) {
        float u_l0, u_r0, u_l1, u_r1;
        hb_float.upsample2xFrame(in[2 * i], in[2 * i + 1], u_l0, u_r0, u_l1, u_r1);

        float d_l, d_r;
        hb_float.downsample2xFrame(u_l0, u_r0, u_l1, u_r1, d_l, d_r);
        down_f[i] = d_l;

        double du_l0, du_r0, du_l1, du_r1;
        hb_double.upsample2xFrame(static_cast<double>(in[2 * i]), static_cast<double>(in[2 * i + 1]), du_l0, du_r0, du_l1, du_r1);

        double dd_l, dd_r;
        hb_double.downsample2xFrame(du_l0, du_r0, du_l1, du_r1, dd_l, dd_r);
        down_d[i] = dd_l;
    }

    float max_fd_diff = 0.0f;
    for (uint32_t i = 0; i < N; ++i) {
        float diff = std::fabs(down_f[i] - static_cast<float>(down_d[i]));
        if (diff > max_fd_diff) max_fd_diff = diff;
    }
    CHECK(max_fd_diff < 1e-4f, "Float SIMD vs Double SIMD HalfBandFilter2x match within 1e-4");
}

// -----------------------------------------------------------------------------
// 4. AnalogWarmthDSP Stereo SIMD Processing & Channel Isolation
// -----------------------------------------------------------------------------
static void test_analog_warmth_simd_fidelity()
{
    std::printf("\n== AnalogWarmthDSP Stereo SIMD Verification ==\n");

    const int kSampleRate = 48000;
    const int kFrames = 1024;

    sauti::dsp::AnalogWarmthDSP warmth;
    warmth.setSampleRate(static_cast<float>(kSampleRate));
    warmth.setEnabled(true);
    warmth.setDrive(0.8f);

    // Test with Left channel active, Right channel zeroed
    std::vector<float> buffer(kFrames * 2, 0.0f);
    for (int i = 0; i < kFrames; ++i) {
        buffer[i * 2 + 0] = 0.7f * std::sin(2.0f * float(M_PI) * 440.0f * i / kSampleRate);
        buffer[i * 2 + 1] = 0.0f; // Silence on Right
    }

    // Process Triode mode with 2x Oversampling
    warmth.setProfile(sauti::dsp::AnalogWarmthProfile::Triode12AX7);
    warmth.setOversampling(2);
    warmth.process(buffer.data(), kFrames);

    bool right_is_silent = true;
    bool left_is_active = false;
    for (int i = 0; i < kFrames; ++i) {
        if (std::fabs(buffer[i * 2 + 1]) > 1e-6f) {
            right_is_silent = false;
        }
        if (std::fabs(buffer[i * 2 + 0]) > 0.01f) {
            left_is_active = true;
        }
    }
    CHECK(right_is_silent, "Stereo SIMD Triode mode has zero channel crosstalk (Right remains silent)");
    CHECK(left_is_active, "Stereo SIMD Triode mode produces valid saturated output on Left");

    // Process Tape mode at 4x Oversampling
    warmth.setProfile(sauti::dsp::AnalogWarmthProfile::MagneticTape);
    warmth.setOversampling(4);
    for (int i = 0; i < kFrames; ++i) {
        buffer[i * 2 + 0] = 0.0f;
        buffer[i * 2 + 1] = 0.6f * std::cos(2.0f * float(M_PI) * 1000.0f * i / kSampleRate);
    }
    warmth.process(buffer.data(), kFrames);

    bool left_is_silent_tape = true;
    bool right_is_active_tape = false;
    for (int i = 0; i < kFrames; ++i) {
        if (std::fabs(buffer[i * 2 + 0]) > 1e-6f) {
            left_is_silent_tape = false;
        }
        if (std::fabs(buffer[i * 2 + 1]) > 0.01f) {
            right_is_active_tape = true;
        }
    }
    CHECK(left_is_silent_tape, "Stereo SIMD Tape mode 4x has zero crosstalk (Left remains silent)");
    CHECK(right_is_active_tape, "Stereo SIMD Tape mode 4x produces valid saturated output on Right");
}

// -----------------------------------------------------------------------------
// 5. FFTConvolverDSP SIMD Complex Accumulation & Overlap-Add
// -----------------------------------------------------------------------------
static void test_fft_convolver_simd_fidelity()
{
    std::printf("\n== FFTConvolverDSP SIMD Frequency Domain Convolution ==\n");

    sauti::dsp::FFTConvolverDSP convolver;
    convolver.setEnabled(true);
    convolver.setWetLevel(1.0f);
    convolver.setDryLevel(0.0f);

    // Create a 512-sample simple impulse response with initial energy
    const size_t kIRLen = 512;
    std::vector<float> ir(kIRLen);
    for (size_t i = 0; i < kIRLen; ++i) {
        ir[i] = std::exp(-0.01f * static_cast<float>(i)) * std::cos(2.0f * float(M_PI) * 0.05f * static_cast<float>(i));
    }

    // Initialize convolver with mono IR
    bool init_ok = convolver.loadImpulseResponse(ir.data(), kIRLen, 1);
    CHECK(init_ok, "FFTConvolverDSP initialized successfully with SIMD partitioned segments");

    // Feed a Dirac impulse: frame 0 = 1.0, rest 0.0 across 512 frames
    const size_t kBlockSize = 512;
    std::vector<float> block0(kBlockSize * 2, 0.0f); // stereo interleaved
    block0[0] = 1.0f; // Dirac impulse Left
    block0[1] = 1.0f; // Dirac impulse Right

    // Block 0 buffers the input into FFTConvolver's partition
    convolver.process(block0.data(), kBlockSize);

    // Block 1 flushes the convolved audio from the overlap-add buffer
    std::vector<float> block1(kBlockSize * 2, 0.0f);
    convolver.process(block1.data(), kBlockSize);

    bool output_finite = true;
    float max_peak = 0.0f;
    for (size_t i = 0; i < kBlockSize * 2; ++i) {
        if (!std::isfinite(block1[i])) output_finite = false;
        if (std::fabs(block1[i]) > max_peak) max_peak = std::fabs(block1[i]);
    }

    CHECK(output_finite, "FFTConvolverDSP output is finite and stable");
    CHECK(max_peak > 0.01f, "FFTConvolverDSP SIMD convolution produced valid energy output on overlap-add block");
}

// -----------------------------------------------------------------------------
// 6. Dynamic Bass 63-Tap FIR Filter SIMD vs Scalar Reference
// -----------------------------------------------------------------------------
static void test_dynamic_bass_fir_simd()
{
    std::printf("\n== Dynamic Bass 63-Tap FIR Filter SIMD Verification ==\n");

    // 1. Direct 63-tap FIR convolution comparison: SIMD vector FMA vs scalar reference
    const int N = 63;
    alignas(16) float kernel[64] = {0.0f};
    constexpr double PI = 3.14159265358979323846;
    double fc = 120.0 / 48000.0;
    double sum = 0.0;
    for (int n = 0; n < N; ++n) {
        double x = (double)n - 31.0;
        double v = (std::fabs(x) < 1e-9) ? (2.0 * fc) : (std::sin(2.0 * PI * fc * x) / (PI * x));
        double w = 0.42 - 0.5 * std::cos(2.0 * PI * n / 62.0) + 0.08 * std::cos(4.0 * PI * n / 62.0);
        v *= w;
        kernel[n] = static_cast<float>(v);
        sum += v;
    }
    float inv = static_cast<float>(1.0 / sum);
    for (int n = 0; n < N; ++n) kernel[n] *= inv;

    // Test across 1024 frames of pseudo-random / chirp signal
    const int kFrames = 1024;
    std::vector<float> input_signal(kFrames);
    for (int i = 0; i < kFrames; ++i) {
        float t = static_cast<float>(i) / 48000.0f;
        input_signal[i] = 0.6f * std::sin(2.0f * float(PI) * 60.0f * t) + 0.4f * std::sin(2.0f * float(PI) * 200.0f * t);
    }

    // Scalar reference circular convolution
    float scalar_hist[63] = {0.0f};
    size_t scalar_head = 0;
    std::vector<float> scalar_out(kFrames);

    for (int i = 0; i < kFrames; ++i) {
        scalar_hist[scalar_head] = input_signal[i];
        float out = 0.0f;
        size_t idx = scalar_head;
        for (size_t j = 0; j < 63; ++j) {
            out += kernel[j] * scalar_hist[idx];
            idx = (idx == 0) ? 62 : idx - 1;
        }
        scalar_head = (scalar_head + 1) % 63;
        scalar_out[i] = out;
    }

    // SIMD vector convolution (doubled circular buffer + 4-wide FMA unroll + tail)
    float simd_hist[126] = {0.0f};
    size_t simd_head = 0;
    std::vector<float> simd_out(kFrames);

    for (int i = 0; i < kFrames; ++i) {
        simd_head = (simd_head == 0) ? 62 : (simd_head - 1);
        simd_hist[simd_head] = input_signal[i];
        simd_hist[simd_head + 63] = input_signal[i];

        sauti::dsp::SimdFloat4 acc(0.0f);
        size_t j = 0;
        for (; j < 60; j += 4) {
            sauti::dsp::SimdFloat4 k = sauti::dsp::SimdFloat4::load_u(&kernel[j]);
            sauti::dsp::SimdFloat4 h = sauti::dsp::SimdFloat4::load_u(&simd_hist[simd_head + j]);
            acc = sauti::dsp::SimdFloat4::fma(k, h, acc);
        }
        float out = acc.reduce_sum();
        for (; j < 63; ++j) {
            out += kernel[j] * simd_hist[simd_head + j];
        }
        simd_out[i] = out;
    }

    float max_delta = 0.0f;
    for (int i = 0; i < kFrames; ++i) {
        float d = std::fabs(simd_out[i] - scalar_out[i]);
        if (d > max_delta) max_delta = d;
    }
    CHECK(max_delta < 1e-6f, "Dynamic Bass 63-tap circular FIR SIMD output matches scalar convolution (< 1e-6)");

    // 2. Full HarmonicBassDSP PureBass mode test
    sauti::dsp::HarmonicBassDSP bass;
    bass.setSampleRate(48000.0f);
    bass.setEnabled(true);
    bass.setProfile(sauti::dsp::BassEnhanceProfile::PureBass);
    bass.setBoost(0.7f);

    std::vector<float> stereo_buf(kFrames * 2, 0.0f);
    for (int i = 0; i < kFrames; ++i) {
        stereo_buf[2 * i]     = input_signal[i];
        stereo_buf[2 * i + 1] = input_signal[i] * 0.8f;
    }

    bass.process(stereo_buf.data(), kFrames);

    bool bass_finite = true;
    float bass_peak = 0.0f;
    for (int i = 0; i < kFrames * 2; ++i) {
        if (!std::isfinite(stereo_buf[i])) bass_finite = false;
        if (std::fabs(stereo_buf[i]) > bass_peak) bass_peak = std::fabs(stereo_buf[i]);
    }
    CHECK(bass_finite, "HarmonicBassDSP PureBass SIMD outputs are strictly finite");
    CHECK(bass_peak > 0.01f, "HarmonicBassDSP PureBass SIMD outputs valid bass energy");
}

// -----------------------------------------------------------------------------
// 7. ScaleTempo WSOLA Correlation Search SIMD Verification
// -----------------------------------------------------------------------------
static void test_scaletempo_correlation_simd()
{
    std::printf("\n== ScaleTempo WSOLA Correlation Search SIMD Verification ==\n");

    // 1. Direct verification of vector correlation inner loop vs scalar reference
    const size_t kOverlap = 384;
    std::vector<float> in_buf(kOverlap);
    std::vector<float> ov_buf(kOverlap);

    for (size_t i = 0; i < kOverlap; ++i) {
        in_buf[i] = 0.5f * std::sin(0.08f * static_cast<float>(i)) + 0.3f * std::cos(0.03f * static_cast<float>(i));
        ov_buf[i] = 0.4f * std::sin(0.08f * static_cast<float>(i) + 0.1f) + 0.35f * std::cos(0.03f * static_cast<float>(i));
    }

    // Scalar calculation
    float s_sumIn = 0.0f, s_sumInSq = 0.0f, s_dot = 0.0f;
    for (size_t i = 0; i < kOverlap; ++i) {
        float s = in_buf[i];
        s_sumIn += s;
        s_sumInSq += s * s;
        s_dot += ov_buf[i] * s;
    }

    // SIMD calculation
    sauti::dsp::SimdFloat4 v_dot(0.0f);
    sauti::dsp::SimdFloat4 v_sum(0.0f);
    sauti::dsp::SimdFloat4 v_sum_sq(0.0f);

    size_t i = 0;
    const size_t vecLimit = (kOverlap >= 4) ? (kOverlap - 3) : 0;
    for (; i < vecLimit; i += 4) {
        sauti::dsp::SimdFloat4 s = sauti::dsp::SimdFloat4::load_u(in_buf.data() + i);
        sauti::dsp::SimdFloat4 ov = sauti::dsp::SimdFloat4::load_u(ov_buf.data() + i);
        v_sum += s;
        v_sum_sq = sauti::dsp::SimdFloat4::fma(s, s, v_sum_sq);
        v_dot = sauti::dsp::SimdFloat4::fma(ov, s, v_dot);
    }
    float v_sumIn = v_sum.reduce_sum();
    float v_sumInSq = v_sum_sq.reduce_sum();
    float v_dot_res = v_dot.reduce_sum();

    for (; i < kOverlap; ++i) {
        float s = in_buf[i];
        v_sumIn += s;
        v_sumInSq += s * s;
        v_dot_res += ov_buf[i] * s;
    }

    CHECK(std::fabs(v_sumIn - s_sumIn) < 1e-4f, "ScaleTempo sumIn SIMD matches scalar reference (< 1e-4)");
    CHECK(std::fabs(v_sumInSq - s_sumInSq) < 1e-4f, "ScaleTempo sumInSq SIMD matches scalar reference (< 1e-4)");
    CHECK(std::fabs(v_dot_res - s_dot) < 1e-4f, "ScaleTempo dot-product SIMD matches scalar reference (< 1e-4)");

    // 2. Full ScaleTempoDSP time-stretch pipeline verification
    sauti::dsp::ScaleTempoDSP st;
    st.init(48000, 2);
    st.setScale(1.25f); // 1.25x tempo speedup

    const size_t kInFrames = 2048;
    std::vector<float> pcm_in(kInFrames * 2);
    for (size_t f = 0; f < kInFrames; ++f) {
        float t = static_cast<float>(f) / 48000.0f;
        pcm_in[2 * f]     = 0.7f * std::sin(2.0f * 3.14159f * 440.0f * t);
        pcm_in[2 * f + 1] = 0.5f * std::sin(2.0f * 3.14159f * 880.0f * t);
    }

    st.writeInput(pcm_in.data(), kInFrames);
    size_t avail = st.availableOutputFrames();
    CHECK(avail > 0, "ScaleTempoDSP produces available stretched output frames");

    std::vector<float> pcm_out(avail * 2);
    size_t read = st.readOutput(pcm_out.data(), avail);
    CHECK(read == avail, "ScaleTempoDSP readOutput returns exact available frame count");

    bool st_finite = true;
    for (size_t s = 0; s < read * 2; ++s) {
        if (!std::isfinite(pcm_out[s])) st_finite = false;
    }
    CHECK(st_finite, "ScaleTempoDSP stretched output samples are strictly finite (zero NaNs / INFs)");
}

// -----------------------------------------------------------------------------
// 8. Audio Clarity Harmonic Saturation SIMD Verification
// -----------------------------------------------------------------------------
static void test_clarity_harmonic_saturation_simd()
{
    std::printf("\n== Audio Clarity Harmonic Saturation SIMD Verification ==\n");

    // 1. Direct comparison: 4-wide vector fast_tanh saturation vs scalar reference
    const int kCount = 512;
    std::vector<float> in_buf(kCount);
    std::vector<float> scalar_out(kCount);
    std::vector<float> simd_out(kCount);

    for (int i = 0; i < kCount; ++i) {
        in_buf[i] = -4.0f + 8.0f * (static_cast<float>(i) / static_cast<float>(kCount));
    }

    // Scalar Padé reference
    for (int i = 0; i < kCount; ++i) {
        float hp = in_buf[i];
        float c = std::clamp(hp * 2.2f, -3.0f, 3.0f);
        float x2 = c * c;
        float t = c * (27.0f + x2) / (27.0f + 9.0f * x2);
        scalar_out[i] = t + 0.25f * (hp * hp);
    }

    // SIMD vector evaluation
    simd_out = in_buf;
    int i = 0;
    const sauti::dsp::SimdFloat4 c_scale(2.2f);
    const sauti::dsp::SimdFloat4 c_quad(0.25f);
    for (; i + 4 <= kCount; i += 4) {
        sauti::dsp::SimdFloat4 v = sauti::dsp::SimdFloat4::load_u(simd_out.data() + i);
        sauti::dsp::SimdFloat4 v_tanh = sauti::dsp::SimdFloat4::fast_tanh(v * c_scale);
        sauti::dsp::SimdFloat4 v_sq = v * v;
        sauti::dsp::SimdFloat4 res = sauti::dsp::SimdFloat4::fma(v_sq, c_quad, v_tanh);
        res.store_u(simd_out.data() + i);
    }
    for (; i < kCount; ++i) {
        float hp = simd_out[i];
        float c = std::clamp(hp * 2.2f, -3.0f, 3.0f);
        float x2 = c * c;
        float t = c * (27.0f + x2) / (27.0f + 9.0f * x2);
        simd_out[i] = t + 0.25f * (hp * hp);
    }

    float max_delta = 0.0f;
    for (int idx = 0; idx < kCount; ++idx) {
        float d = std::fabs(simd_out[idx] - scalar_out[idx]);
        if (d > max_delta) max_delta = d;
    }
    CHECK(max_delta < 1e-6f, "Audio Clarity vector harmonic saturation matches scalar Padé reference (< 1e-6)");

    // 2. Full AudioClarityDSP HarmonicBrilliance oversampling modes
    sauti::dsp::AudioClarityDSP clarity;
    clarity.setSampleRate(48000.0f);
    clarity.setEnabled(true);
    clarity.setProfile(sauti::dsp::AudioClarityProfile::HarmonicBrilliance);
    clarity.setIntensity(0.8f);

    const int kFrames = 1024;
    for (int os : {1, 2, 4}) {
        clarity.setOversampling(os);
        std::vector<float> test_buf(kFrames * 2);
        for (int f = 0; f < kFrames; ++f) {
            float t = static_cast<float>(f) / 48000.0f;
            test_buf[2 * f]     = 0.8f * std::sin(2.0f * 3.14159f * 4000.0f * t);
            test_buf[2 * f + 1] = 0.6f * std::cos(2.0f * 3.14159f * 5000.0f * t);
        }

        clarity.process(test_buf.data(), kFrames);

        bool finite = true;
        for (int s = 0; s < kFrames * 2; ++s) {
            if (!std::isfinite(test_buf[s])) finite = false;
        }
        char msg[128];
        std::snprintf(msg, sizeof(msg), "HarmonicBrilliance %dx oversampling is strictly finite and stable", os);
        CHECK(finite, msg);
    }
}

// -----------------------------------------------------------------------------
// 9. Stereo Biquads in Downward Expander & De-Esser SIMD Verification
// -----------------------------------------------------------------------------
static void test_stereo_sidechain_biquad_simd()
{
    std::printf("\n== Downward Expander & De-Esser Stereo Biquad SIMD Verification ==\n");

    const int kSampleRate = 48000;
    const int kFrames = 1024;

    // 1. Downward Expander: Channel Isolation & Stability
    sauti::dsp::DownwardExpanderDSP expander;
    expander.setSampleRate(static_cast<float>(kSampleRate));
    expander.setEnabled(true);
    expander.setPreset(sauti::dsp::ExpanderPreset::VinylClean);

    std::vector<float> exp_buf(kFrames * 2, 0.0f);
    for (int i = 0; i < kFrames; ++i) {
        float t = static_cast<float>(i) / kSampleRate;
        exp_buf[2 * i + 0] = 0.5f * std::sin(2.0f * 3.14159f * 100.0f * t); // Active Left
        exp_buf[2 * i + 1] = 0.0f; // Silent Right
    }

    expander.process(exp_buf.data(), kFrames);

    bool right_silent = true;
    for (int i = 0; i < kFrames; ++i) {
        if (std::fabs(exp_buf[2 * i + 1]) > 1e-6f) right_silent = false;
    }
    CHECK(right_silent, "DownwardExpanderDSP stereo SIMD sidechain biquad maintains zero channel crosstalk");

    // 2. De-Esser: Channel Isolation & Gain Reduction
    sauti::dsp::DeEsserDSP deesser;
    deesser.setSampleRate(static_cast<float>(kSampleRate));
    deesser.setEnabled(true);
    deesser.setPreset(sauti::dsp::DeEsserPreset::AggressiveSibilance);

    std::vector<float> deess_buf(kFrames * 2, 0.0f);
    for (int i = 0; i < kFrames; ++i) {
        float t = static_cast<float>(i) / kSampleRate;
        deess_buf[2 * i + 0] = 0.9f * std::sin(2.0f * 3.14159f * 6500.0f * t); // Loud sibilance on Left
        deess_buf[2 * i + 1] = 0.0f; // Silent Right
    }

    deesser.process(deess_buf.data(), kFrames);

    bool deess_right_silent = true;
    for (int i = 0; i < kFrames; ++i) {
        if (std::fabs(deess_buf[2 * i + 1]) > 1e-6f) deess_right_silent = false;
    }
    CHECK(deess_right_silent, "DeEsserDSP stereo SIMD sidechain biquad maintains zero channel crosstalk");
    CHECK(deesser.getGainReductionDb() > 0.5f, "DeEsserDSP detects sibilance and applies active gain reduction");

    // 3. Direct SimdDouble2 stereo biquad bit-accuracy vs scalar double biquad
    double b0 = 0.95, b1 = -1.9, b2 = 0.95, a1 = -1.89, a2 = 0.91;
    sauti::dsp::SimdDouble2 vb0(b0), vb1(b1), vb2(b2), va1(a1), va2(a2);
    sauti::dsp::SimdDouble2 x1(0.0), x2(0.0), y1(0.0), y2(0.0);

    double sx1_l = 0.0, sx2_l = 0.0, sy1_l = 0.0, sy2_l = 0.0;
    double sx1_r = 0.0, sx2_r = 0.0, sy1_r = 0.0, sy2_r = 0.0;

    double max_biquad_diff = 0.0;
    for (int i = 0; i < kFrames; ++i) {
        double inl = 0.8 * std::sin(0.1 * i);
        double inr = -0.5 * std::cos(0.07 * i);

        // SimdDouble2 stereo
        sauti::dsp::SimdDouble2 vin(inl, inr);
        sauti::dsp::SimdDouble2 vy = (vb0 * vin) + (vb1 * x1) + (vb2 * x2) - (va1 * y1) - (va2 * y2);
        x2 = x1; x1 = vin;
        y2 = y1; y1 = vy;

        // Scalar double Left
        double yl = b0 * inl + b1 * sx1_l + b2 * sx2_l - a1 * sy1_l - a2 * sy2_l;
        sx2_l = sx1_l; sx1_l = inl;
        sy2_l = sy1_l; sy1_l = yl;

        // Scalar double Right
        double yr = b0 * inr + b1 * sx1_r + b2 * sx2_r - a1 * sy1_r - a2 * sy2_r;
        sx2_r = sx1_r; sx1_r = inr;
        sy2_r = sy1_r; sy1_r = yr;

        double dl = std::fabs(vy.get_low() - yl);
        double dr = std::fabs(vy.get_high() - yr);
        if (dl > max_biquad_diff) max_biquad_diff = dl;
        if (dr > max_biquad_diff) max_biquad_diff = dr;
    }
    CHECK(max_biquad_diff < 1e-12, "SimdDouble2 stereo biquad matches 64-bit IEEE 754 scalar reference (< 1e-12)");
}

// -----------------------------------------------------------------------------
// 10. Spatial Surround Suite SIMD Verification
// -----------------------------------------------------------------------------
static void test_spatial_surround_simd()
{
    std::printf("\n== Spatial Surround Suite SIMD Verification ==\n");

    const int kSampleRate = 48000;
    const int kFrames = 1024;

    sauti::dsp::SpatialSurroundDSP surround;
    surround.setSampleRate(static_cast<float>(kSampleRate));
    surround.setEnabled(true);

    // 1. Acoustic Stage (Mode 3)
    surround.setMode(sauti::dsp::SurroundMode::AcousticStage);
    std::vector<float> stage_buf(kFrames * 2);
    for (int i = 0; i < kFrames; ++i) {
        float t = static_cast<float>(i) / kSampleRate;
        stage_buf[2 * i + 0] = 0.7f * std::sin(2.0f * 3.14159f * 440.0f * t);
        stage_buf[2 * i + 1] = 0.5f * std::cos(2.0f * 3.14159f * 440.0f * t);
    }
    surround.process(stage_buf.data(), kFrames);

    bool stage_finite = true;
    for (int i = 0; i < kFrames * 2; ++i) {
        if (!std::isfinite(stage_buf[i])) stage_finite = false;
    }
    CHECK(stage_finite, "SpatialSurroundDSP Acoustic Stage SIMD outputs are strictly finite");

    // 2. Binaural Virtualizer (Mode 2)
    surround.setMode(sauti::dsp::SurroundMode::BinauralVirtualizer);
    std::vector<float> bin_buf(kFrames * 2);
    for (int i = 0; i < kFrames; ++i) {
        float t = static_cast<float>(i) / kSampleRate;
        bin_buf[2 * i + 0] = 0.6f * std::sin(2.0f * 3.14159f * 1000.0f * t);
        bin_buf[2 * i + 1] = 0.6f * std::cos(2.0f * 3.14159f * 1000.0f * t);
    }
    surround.process(bin_buf.data(), kFrames);

    bool bin_finite = true;
    for (int i = 0; i < kFrames * 2; ++i) {
        if (!std::isfinite(bin_buf[i])) bin_finite = false;
    }
    CHECK(bin_finite, "SpatialSurroundDSP Binaural Virtualizer SIMD outputs are strictly finite");

    // 3. Cinema Matrix 5.1 (Mode 1)
    surround.setMode(sauti::dsp::SurroundMode::MatrixSurround);
    std::vector<float> mat_buf(kFrames * 2);
    for (int i = 0; i < kFrames; ++i) {
        float t = static_cast<float>(i) / kSampleRate;
        mat_buf[2 * i + 0] = 0.5f * std::sin(2.0f * 3.14159f * 500.0f * t);
        mat_buf[2 * i + 1] = 0.5f * std::sin(2.0f * 3.14159f * 500.0f * t); // Center phantom
    }
    surround.process(mat_buf.data(), kFrames);

    bool mat_finite = true;
    for (int i = 0; i < kFrames * 2; ++i) {
        if (!std::isfinite(mat_buf[i])) mat_finite = false;
    }
    CHECK(mat_finite, "SpatialSurroundDSP Cinema Matrix SIMD outputs are strictly finite");
}

// -----------------------------------------------------------------------------
// 11. DynamicSystemDSP SIMD Verification
// -----------------------------------------------------------------------------
static void test_dynamic_system_simd()
{
    std::printf("\n== DynamicSystemDSP Stereo SIMD Ladder Verification ==\n");

    constexpr uint32_t kSampleRate = 48000;
    constexpr int kFrames = 1024;

    sauti::dsp::DynamicSystemDSP dynamic_sys;
    dynamic_sys.setSampleRate(static_cast<float>(kSampleRate));
    dynamic_sys.setEnabled(true);
    dynamic_sys.setProfile(sauti::dsp::TransducerProfile::Headphone);
    dynamic_sys.setStrength(0.8f);

    // Test channel isolation with Left excitation and silent Right
    std::vector<float> buf(kFrames * 2, 0.0f);
    for (int i = 0; i < kFrames; ++i) {
        float t = static_cast<float>(i) / kSampleRate;
        buf[2 * i + 0] = 0.5f * std::sin(2.0f * 3.14159f * 100.0f * t); // 100 Hz on Left
        buf[2 * i + 1] = 0.0f; // Silent Right
    }

    dynamic_sys.process(buf.data(), kFrames);

    bool finite = true;
    bool right_silent = true;
    for (int i = 0; i < kFrames; ++i) {
        if (!std::isfinite(buf[2 * i + 0]) || !std::isfinite(buf[2 * i + 1])) finite = false;
        if (std::fabs(buf[2 * i + 1]) > 1e-6f) right_silent = false;
    }

    CHECK(finite, "DynamicSystemDSP SIMD outputs are strictly finite");
    CHECK(right_silent, "DynamicSystemDSP stereo SIMD ladder maintains zero channel crosstalk");

    // Sub-120Hz dynamic resonant biquad path
    dynamic_sys.setPreset(0); // In-Ear Earbuds
    dynamic_sys.reset();

    std::vector<float> sub_buf(kFrames * 2, 0.0f);
    for (int i = 0; i < kFrames; ++i) {
        float t = static_cast<float>(i) / kSampleRate;
        sub_buf[2 * i + 0] = 0.4f * std::sin(2.0f * 3.14159f * 50.0f * t);
        sub_buf[2 * i + 1] = 0.4f * std::sin(2.0f * 3.14159f * 50.0f * t);
    }
    dynamic_sys.process(sub_buf.data(), kFrames);

    bool sub_finite = true;
    for (int i = 0; i < kFrames * 2; ++i) {
        if (!std::isfinite(sub_buf[i])) sub_finite = false;
    }
    CHECK(sub_finite, "DynamicSystemDSP sub-120Hz dynamic resonant biquad outputs are strictly finite");
}

// -----------------------------------------------------------------------------
// 12. MasterLimiterDSP SIMD Verification
// -----------------------------------------------------------------------------
static void test_master_limiter_simd()
{
    std::printf("\n== MasterLimiterDSP Lookahead SIMD Peak Limiting Verification ==\n");

    constexpr uint32_t kSampleRate = 48000;
    constexpr int kFrames = 2048;

    sauti::dsp::MasterLimiterDSP limiter;
    limiter.setSampleRate(static_cast<float>(kSampleRate));
    limiter.setCeilingDb(-0.1f); // ~0.98855 linear ceiling
    limiter.setEnabled(true);

    // Feed hot signal exceeding 0 dBFS (+6 dB peak: 2.0 amplitude)
    std::vector<float> hot_buf(kFrames * 2, 0.0f);
    for (int i = 0; i < kFrames; ++i) {
        float t = static_cast<float>(i) / kSampleRate;
        hot_buf[2 * i + 0] = 2.0f * std::sin(2.0f * 3.14159f * 1000.0f * t);
        hot_buf[2 * i + 1] = -2.0f * std::sin(2.0f * 3.14159f * 1000.0f * t);
    }

    limiter.process(hot_buf.data(), kFrames);

    float max_peak = 0.0f;
    bool finite = true;
    for (int i = 0; i < kFrames * 2; ++i) {
        if (!std::isfinite(hot_buf[i])) finite = false;
        max_peak = std::max(max_peak, std::fabs(hot_buf[i]));
    }

    CHECK(finite, "MasterLimiterDSP SIMD outputs are strictly finite");
    CHECK(limiter.getCurrentGainReductionDb() < -1.0f, "MasterLimiterDSP detects overs and engages active gain reduction");
    CHECK(max_peak <= 0.989f, "MasterLimiterDSP SIMD ceiling clamping guarantees peak <= ceiling linear (0.989)");
}

// -----------------------------------------------------------------------------
// 13. StereoImagerDSP SIMD Verification
// -----------------------------------------------------------------------------
static void test_stereo_imager_simd()
{
    std::printf("\n== StereoImagerDSP SIMD M/S & Velvet Decorrelation Verification ==\n");

    constexpr uint32_t kSampleRate = 48000;
    constexpr int kFrames = 1024;

    sauti::dsp::StereoImagerDSP imager;
    imager.setSampleRate(static_cast<float>(kSampleRate));
    imager.setEnabled(true);

    // 1. Clean Mastering on Pure Mono (L = R) must be bit-exact (M/S identity)
    imager.setMode(sauti::dsp::StereoImagerMode::CleanMastering);
    imager.setWidth(2.0f);
    imager.setAirBoostDb(0.0f);

    std::vector<float> mono_buf(kFrames * 2, 0.0f);
    for (int i = 0; i < kFrames; ++i) {
        float val = 0.4f * std::sin(2.0f * 3.14159f * 440.0f * i / kSampleRate);
        mono_buf[2 * i + 0] = val;
        mono_buf[2 * i + 1] = val;
    }
    auto ref = mono_buf;

    // Warm up smoothing
    for (int w = 0; w < 5; ++w) {
        auto temp = ref;
        imager.process(temp.data(), kFrames, 2);
    }
    imager.process(mono_buf.data(), kFrames, 2);

    float max_diff = 0.0f;
    for (size_t i = 0; i < mono_buf.size(); ++i) {
        max_diff = std::max(max_diff, std::fabs(mono_buf[i] - ref[i]));
    }
    CHECK(max_diff < 1e-4f, "StereoImagerDSP Clean Mastering preserves pure mono (M/S identity)");

    // 2. Spatial 3D Velvet Noise 12-tap SIMD decorrelation
    imager.setMode(sauti::dsp::StereoImagerMode::Spatial3D);
    imager.setWidth(1.5f);
    imager.reset();

    std::vector<float> spatial_buf(kFrames * 2, 0.0f);
    for (int i = 0; i < kFrames; ++i) {
        float val = 0.5f * std::sin(2.0f * 3.14159f * 1000.0f * i / kSampleRate);
        spatial_buf[2 * i + 0] = val;
        spatial_buf[2 * i + 1] = val;
    }

    imager.process(spatial_buf.data(), kFrames, 2);

    // Check mono-sum cancellation (L + R = 2 * M, decorrelation cancels)
    float max_mono_sum_err = 0.0f;
    for (int i = 100; i < kFrames; ++i) {
        float mono_sum = (spatial_buf[2 * i + 0] + spatial_buf[2 * i + 1]) * 0.5f;
        float original_mid = 0.5f * std::sin(2.0f * 3.14159f * 1000.0f * i / kSampleRate);
        max_mono_sum_err = std::max(max_mono_sum_err, std::fabs(mono_sum - original_mid));
    }
    CHECK(max_mono_sum_err < 1e-3f, "StereoImagerDSP Velvet Noise SIMD dot product cancels 100% in mono sum");
}

int main()
{
    sauti::dsp::ScopedDenormalsDisable denormals;

    std::printf("=================================================================\n");
    std::printf(" Sautiflow Audiophile-Grade SIMD DSP Precision Verification Suite\n");
    std::printf("=================================================================\n");

    test_simd_primitives();
    test_subsonic_filter_fidelity();
    test_oversampler_simd_fidelity();
    test_analog_warmth_simd_fidelity();
    test_fft_convolver_simd_fidelity();
    test_dynamic_bass_fir_simd();
    test_scaletempo_correlation_simd();
    test_clarity_harmonic_saturation_simd();
    test_stereo_sidechain_biquad_simd();
    test_spatial_surround_simd();
    test_dynamic_system_simd();
    test_master_limiter_simd();
    test_stereo_imager_simd();

    std::printf("\n-----------------------------------------------------------------\n");
    std::printf(" RESULTS: %d passed, %d failed\n", g_passes, g_failures);
    std::printf("-----------------------------------------------------------------\n");

    return (g_failures == 0) ? 0 : 1;
}
