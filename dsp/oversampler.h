#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <vector>
#include <type_traits>
#include "simd_math.h"

namespace sauti::dsp {

// =============================================================================
// Polyphase Half-Band Filter Coefficients & Engine
//
// 55-tap symmetric half-band FIR (Remez equiripple, >= 96 dB stopband attenuation,
// < 0.0003 dB passband ripple).
// Features:
//   - Exactly linear phase (zero phase distortion in audio passband)
//   - Polyphase decomposition: even branch is a pure delay (0 multiplies),
//     odd branch uses symmetric tap folding for maximum throughput.
//   - Zero dynamic heap allocation in the audio render thread (process loop).
// =============================================================================

template <typename T = float>
class HalfBandFilter2xT {
public:
    static constexpr int TAPS = 55;
    static constexpr int NUM_ODD_COEFFS = 14;
    static constexpr int DELAY_NATIVE = 13;
    static constexpr int DELAY_OVERSAMPLED = 27;

    HalfBandFilter2xT() {
        reset();
    }

    void reset() {
        for (int ch = 0; ch < 2; ++ch) {
            std::fill(history_up_[ch], history_up_[ch] + 32, static_cast<T>(0));
            std::fill(history_down_[ch], history_down_[ch] + 64, static_cast<T>(0));
        }
        hist_idx_up_ = 0;
        hist_idx_down_ = 0;
    }

    // Upsample 1 stereo frame (in_l, in_r) -> 2 stereo frames (out_l0, out_r0, out_l1, out_r1)
    inline void upsample2xFrame(T in_l, T in_r,
                                T& out_l0, T& out_r0,
                                T& out_l1, T& out_r1) {
        // Store current native sample in circular history (size 32)
        history_up_[0][hist_idx_up_] = in_l;
        history_up_[1][hist_idx_up_] = in_r;

        // Native sample delayed by 13 native samples (x[n-13], at t = -13.0T)
        const int idx13 = (hist_idx_up_ - 13 + 32) & 31;

        // Symmetric FIR odd interpolation between x[n-13] and x[n-14] (at t = -13.5T)
        const int idx14 = (hist_idx_up_ - 14 + 32) & 31;
        const int idx12 = (hist_idx_up_ - 12 + 32) & 31;
        const int idx15 = (hist_idx_up_ - 15 + 32) & 31;
        const int idx11 = (hist_idx_up_ - 11 + 32) & 31;
        const int idx16 = (hist_idx_up_ - 16 + 32) & 31;
        const int idx10 = (hist_idx_up_ - 10 + 32) & 31;
        const int idx17 = (hist_idx_up_ - 17 + 32) & 31;
        const int idx9  = (hist_idx_up_ - 9  + 32) & 31;
        const int idx18 = (hist_idx_up_ - 18 + 32) & 31;
        const int idx8  = (hist_idx_up_ - 8  + 32) & 31;
        const int idx19 = (hist_idx_up_ - 19 + 32) & 31;
        const int idx7  = (hist_idx_up_ - 7  + 32) & 31;
        const int idx20 = (hist_idx_up_ - 20 + 32) & 31;
        const int idx6  = (hist_idx_up_ - 6  + 32) & 31;
        const int idx21 = (hist_idx_up_ - 21 + 32) & 31;
        const int idx5  = (hist_idx_up_ - 5  + 32) & 31;
        const int idx22 = (hist_idx_up_ - 22 + 32) & 31;
        const int idx4  = (hist_idx_up_ - 4  + 32) & 31;
        const int idx23 = (hist_idx_up_ - 23 + 32) & 31;
        const int idx3  = (hist_idx_up_ - 3  + 32) & 31;
        const int idx24 = (hist_idx_up_ - 24 + 32) & 31;
        const int idx2  = (hist_idx_up_ - 2  + 32) & 31;
        const int idx25 = (hist_idx_up_ - 25 + 32) & 31;
        const int idx1  = (hist_idx_up_ - 1  + 32) & 31;
        const int idx26 = (hist_idx_up_ - 26 + 32) & 31;
        const int idx0  = (hist_idx_up_ - 0  + 32) & 31;
        const int idx27 = (hist_idx_up_ - 27 + 32) & 31;

        // Fast SIMD path for single precision (float)
        if constexpr (std::is_same_v<T, float>) {
            const SimdFloat4 s01(history_up_[0][idx13] + history_up_[0][idx14],
                                 history_up_[1][idx13] + history_up_[1][idx14],
                                 history_up_[0][idx12] + history_up_[0][idx15],
                                 history_up_[1][idx12] + history_up_[1][idx15]);
            const SimdFloat4 s23(history_up_[0][idx11] + history_up_[0][idx16],
                                 history_up_[1][idx11] + history_up_[1][idx16],
                                 history_up_[0][idx10] + history_up_[0][idx17],
                                 history_up_[1][idx10] + history_up_[1][idx17]);
            const SimdFloat4 s45(history_up_[0][idx9]  + history_up_[0][idx18],
                                 history_up_[1][idx9]  + history_up_[1][idx18],
                                 history_up_[0][idx8]  + history_up_[0][idx19],
                                 history_up_[1][idx8]  + history_up_[1][idx19]);
            const SimdFloat4 s67(history_up_[0][idx7]  + history_up_[0][idx20],
                                 history_up_[1][idx7]  + history_up_[1][idx20],
                                 history_up_[0][idx6]  + history_up_[0][idx21],
                                 history_up_[1][idx6]  + history_up_[1][idx21]);
            const SimdFloat4 s89(history_up_[0][idx5]  + history_up_[0][idx22],
                                 history_up_[1][idx5]  + history_up_[1][idx22],
                                 history_up_[0][idx4]  + history_up_[0][idx23],
                                 history_up_[1][idx4]  + history_up_[1][idx23]);
            const SimdFloat4 s1011(history_up_[0][idx3] + history_up_[0][idx24],
                                   history_up_[1][idx3] + history_up_[1][idx24],
                                   history_up_[0][idx2] + history_up_[0][idx25],
                                   history_up_[1][idx2] + history_up_[1][idx25]);
            const SimdFloat4 s1213(history_up_[0][idx1] + history_up_[0][idx26],
                                   history_up_[1][idx1] + history_up_[1][idx26],
                                   history_up_[0][idx0] + history_up_[0][idx27],
                                   history_up_[1][idx0] + history_up_[1][idx27]);

            const SimdFloat4 c01(static_cast<float>(C[0]), static_cast<float>(C[0]),
                                 static_cast<float>(C[1]), static_cast<float>(C[1]));
            const SimdFloat4 c23(static_cast<float>(C[2]), static_cast<float>(C[2]),
                                 static_cast<float>(C[3]), static_cast<float>(C[3]));
            const SimdFloat4 c45(static_cast<float>(C[4]), static_cast<float>(C[4]),
                                 static_cast<float>(C[5]), static_cast<float>(C[5]));
            const SimdFloat4 c67(static_cast<float>(C[6]), static_cast<float>(C[6]),
                                 static_cast<float>(C[7]), static_cast<float>(C[7]));
            const SimdFloat4 c89(static_cast<float>(C[8]), static_cast<float>(C[8]),
                                 static_cast<float>(C[9]), static_cast<float>(C[9]));
            const SimdFloat4 c1011(static_cast<float>(C[10]), static_cast<float>(C[10]),
                                   static_cast<float>(C[11]), static_cast<float>(C[11]));
            const SimdFloat4 c1213(static_cast<float>(C[12]), static_cast<float>(C[12]),
                                   static_cast<float>(C[13]), static_cast<float>(C[13]));

            SimdFloat4 acc = s01 * c01;
            acc = SimdFloat4::fma(s23, c23, acc);
            acc = SimdFloat4::fma(s45, c45, acc);
            acc = SimdFloat4::fma(s67, c67, acc);
            acc = SimdFloat4::fma(s89, c89, acc);
            acc = SimdFloat4::fma(s1011, c1011, acc);
            acc = SimdFloat4::fma(s1213, c1213, acc);

            alignas(16) float res[4];
            acc.store_u(res);

            out_l0 = res[0] + res[2];
            out_r0 = res[1] + res[3];
            out_l1 = history_up_[0][idx13];
            out_r1 = history_up_[1][idx13];

            hist_idx_up_ = (hist_idx_up_ + 1) & 31;
            return;
        }

        // Fast SIMD path for double precision (double)
        if constexpr (std::is_same_v<T, double>) {
            SimdDouble2 acc = SimdDouble2(history_up_[0][idx13] + history_up_[0][idx14],
                                          history_up_[1][idx13] + history_up_[1][idx14]) * SimdDouble2(C[0]);
            acc = SimdDouble2::fma(SimdDouble2(history_up_[0][idx12] + history_up_[0][idx15],
                                               history_up_[1][idx12] + history_up_[1][idx15]), SimdDouble2(C[1]), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_up_[0][idx11] + history_up_[0][idx16],
                                               history_up_[1][idx11] + history_up_[1][idx16]), SimdDouble2(C[2]), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_up_[0][idx10] + history_up_[0][idx17],
                                               history_up_[1][idx10] + history_up_[1][idx17]), SimdDouble2(C[3]), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_up_[0][idx9]  + history_up_[0][idx18],
                                               history_up_[1][idx9]  + history_up_[1][idx18]), SimdDouble2(C[4]), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_up_[0][idx8]  + history_up_[0][idx19],
                                               history_up_[1][idx8]  + history_up_[1][idx19]), SimdDouble2(C[5]), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_up_[0][idx7]  + history_up_[0][idx20],
                                               history_up_[1][idx7]  + history_up_[1][idx20]), SimdDouble2(C[6]), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_up_[0][idx6]  + history_up_[0][idx21],
                                               history_up_[1][idx6]  + history_up_[1][idx21]), SimdDouble2(C[7]), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_up_[0][idx5]  + history_up_[0][idx22],
                                               history_up_[1][idx5]  + history_up_[1][idx22]), SimdDouble2(C[8]), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_up_[0][idx4]  + history_up_[0][idx23],
                                               history_up_[1][idx4]  + history_up_[1][idx23]), SimdDouble2(C[9]), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_up_[0][idx3]  + history_up_[0][idx24],
                                               history_up_[1][idx3]  + history_up_[1][idx24]), SimdDouble2(C[10]), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_up_[0][idx2]  + history_up_[0][idx25],
                                               history_up_[1][idx2]  + history_up_[1][idx25]), SimdDouble2(C[11]), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_up_[0][idx1]  + history_up_[0][idx26],
                                               history_up_[1][idx1]  + history_up_[1][idx26]), SimdDouble2(C[12]), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_up_[0][idx0]  + history_up_[0][idx27],
                                               history_up_[1][idx0]  + history_up_[1][idx27]), SimdDouble2(C[13]), acc);

            alignas(16) double res[2];
            acc.store_u(res);
            out_l0 = res[0];
            out_r0 = res[1];
            out_l1 = history_up_[0][idx13];
            out_r1 = history_up_[1][idx13];

            hist_idx_up_ = (hist_idx_up_ + 1) & 31;
            return;
        }

        T sum_l = static_cast<T>(0);
        T sum_r = static_cast<T>(0);
        for (int k = 0; k < NUM_ODD_COEFFS; ++k) {
            const int ip = (hist_idx_up_ - (13 - k) + 32) & 31;
            const int im = (hist_idx_up_ - (14 + k) + 32) & 31;
            const T ck = static_cast<T>(C[k]);
            sum_l += ck * (history_up_[0][ip] + history_up_[0][im]);
            sum_r += ck * (history_up_[1][ip] + history_up_[1][im]);
        }

        // Chronological order:
        // Midpoint (t = -13.5T) comes before delayed sample (t = -13.0T) in forward time.
        out_l0 = sum_l;
        out_r0 = sum_r;
        out_l1 = history_up_[0][idx13];
        out_r1 = history_up_[1][idx13];

        hist_idx_up_ = (hist_idx_up_ + 1) & 31;
    }

    // Downsample 2 oversampled stereo frames -> 1 decimated stereo frame (out_l, out_r)
    inline void downsample2xFrame(T in_l0, T in_r0,
                                  T in_l1, T in_r1,
                                  T& out_l, T& out_r) {
        // Push 2 oversampled frames into history (size 64)
        history_down_[0][hist_idx_down_] = in_l0;
        history_down_[1][hist_idx_down_] = in_r0;
        hist_idx_down_ = (hist_idx_down_ + 1) & 63;

        history_down_[0][hist_idx_down_] = in_l1;
        history_down_[1][hist_idx_down_] = in_r1;
        hist_idx_down_ = (hist_idx_down_ + 1) & 63;

        // Center tap is delayed by 27 oversampled samples
        const int center = (hist_idx_down_ - 1 - 27 + 64) & 63;
        const T center_l = history_down_[0][center] * static_cast<T>(0.5);
        const T center_r = history_down_[1][center] * static_cast<T>(0.5);

        // Odd taps convolution (scaled by 0.5 for unity decimation gain)
        const int p1  = (center + 1)  & 63; const int m1  = (center - 1  + 64) & 63;
        const int p3  = (center + 3)  & 63; const int m3  = (center - 3  + 64) & 63;
        const int p5  = (center + 5)  & 63; const int m5  = (center - 5  + 64) & 63;
        const int p7  = (center + 7)  & 63; const int m7  = (center - 7  + 64) & 63;
        const int p9  = (center + 9)  & 63; const int m9  = (center - 9  + 64) & 63;
        const int p11 = (center + 11) & 63; const int m11 = (center - 11 + 64) & 63;
        const int p13 = (center + 13) & 63; const int m13 = (center - 13 + 64) & 63;
        const int p15 = (center + 15) & 63; const int m15 = (center - 15 + 64) & 63;
        const int p17 = (center + 17) & 63; const int m17 = (center - 17 + 64) & 63;
        const int p19 = (center + 19) & 63; const int m19 = (center - 19 + 64) & 63;
        const int p21 = (center + 21) & 63; const int m21 = (center - 21 + 64) & 63;
        const int p23 = (center + 23) & 63; const int m23 = (center - 23 + 64) & 63;
        const int p25 = (center + 25) & 63; const int m25 = (center - 25 + 64) & 63;
        const int p27 = (center + 27) & 63; const int m27 = (center - 27 + 64) & 63;

        if constexpr (std::is_same_v<T, float>) {
            const SimdFloat4 s01(history_down_[0][p1]  + history_down_[0][m1],
                                 history_down_[1][p1]  + history_down_[1][m1],
                                 history_down_[0][p3]  + history_down_[0][m3],
                                 history_down_[1][p3]  + history_down_[1][m3]);
            const SimdFloat4 s23(history_down_[0][p5]  + history_down_[0][m5],
                                 history_down_[1][p5]  + history_down_[1][m5],
                                 history_down_[0][p7]  + history_down_[0][m7],
                                 history_down_[1][p7]  + history_down_[1][m7]);
            const SimdFloat4 s45(history_down_[0][p9]  + history_down_[0][m9],
                                 history_down_[1][p9]  + history_down_[1][m9],
                                 history_down_[0][p11] + history_down_[0][m11],
                                 history_down_[1][p11] + history_down_[1][m11]);
            const SimdFloat4 s67(history_down_[0][p13] + history_down_[0][m13],
                                 history_down_[1][p13] + history_down_[1][m13],
                                 history_down_[0][p15] + history_down_[0][m15],
                                 history_down_[1][p15] + history_down_[1][m15]);
            const SimdFloat4 s89(history_down_[0][p17] + history_down_[0][m17],
                                 history_down_[1][p17] + history_down_[1][m17],
                                 history_down_[0][p19] + history_down_[0][m19],
                                 history_down_[1][p19] + history_down_[1][m19]);
            const SimdFloat4 s1011(history_down_[0][p21] + history_down_[0][m21],
                                   history_down_[1][p21] + history_down_[1][m21],
                                   history_down_[0][p23] + history_down_[0][m23],
                                   history_down_[1][p23] + history_down_[1][m23]);
            const SimdFloat4 s1213(history_down_[0][p25] + history_down_[0][m25],
                                   history_down_[1][p25] + history_down_[1][m25],
                                   history_down_[0][p27] + history_down_[0][m27],
                                   history_down_[1][p27] + history_down_[1][m27]);

            const SimdFloat4 c01(static_cast<float>(C[0] * 0.5), static_cast<float>(C[0] * 0.5),
                                 static_cast<float>(C[1] * 0.5), static_cast<float>(C[1] * 0.5));
            const SimdFloat4 c23(static_cast<float>(C[2] * 0.5), static_cast<float>(C[2] * 0.5),
                                 static_cast<float>(C[3] * 0.5), static_cast<float>(C[3] * 0.5));
            const SimdFloat4 c45(static_cast<float>(C[4] * 0.5), static_cast<float>(C[4] * 0.5),
                                 static_cast<float>(C[5] * 0.5), static_cast<float>(C[5] * 0.5));
            const SimdFloat4 c67(static_cast<float>(C[6] * 0.5), static_cast<float>(C[6] * 0.5),
                                 static_cast<float>(C[7] * 0.5), static_cast<float>(C[7] * 0.5));
            const SimdFloat4 c89(static_cast<float>(C[8] * 0.5), static_cast<float>(C[8] * 0.5),
                                 static_cast<float>(C[9] * 0.5), static_cast<float>(C[9] * 0.5));
            const SimdFloat4 c1011(static_cast<float>(C[10] * 0.5), static_cast<float>(C[10] * 0.5),
                                   static_cast<float>(C[11] * 0.5), static_cast<float>(C[11] * 0.5));
            const SimdFloat4 c1213(static_cast<float>(C[12] * 0.5), static_cast<float>(C[12] * 0.5),
                                   static_cast<float>(C[13] * 0.5), static_cast<float>(C[13] * 0.5));

            SimdFloat4 acc = s01 * c01;
            acc = SimdFloat4::fma(s23, c23, acc);
            acc = SimdFloat4::fma(s45, c45, acc);
            acc = SimdFloat4::fma(s67, c67, acc);
            acc = SimdFloat4::fma(s89, c89, acc);
            acc = SimdFloat4::fma(s1011, c1011, acc);
            acc = SimdFloat4::fma(s1213, c1213, acc);

            alignas(16) float res[4];
            acc.store_u(res);

            out_l = center_l + (res[0] + res[2]);
            out_r = center_r + (res[1] + res[3]);
            return;
        }

        if constexpr (std::is_same_v<T, double>) {
            SimdDouble2 acc = SimdDouble2(history_down_[0][p1] + history_down_[0][m1],
                                          history_down_[1][p1] + history_down_[1][m1]) * SimdDouble2(C[0] * 0.5);
            acc = SimdDouble2::fma(SimdDouble2(history_down_[0][p3]  + history_down_[0][m3],
                                               history_down_[1][p3]  + history_down_[1][m3]), SimdDouble2(C[1] * 0.5), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_down_[0][p5]  + history_down_[0][m5],
                                               history_down_[1][p5]  + history_down_[1][m5]), SimdDouble2(C[2] * 0.5), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_down_[0][p7]  + history_down_[0][m7],
                                               history_down_[1][p7]  + history_down_[1][m7]), SimdDouble2(C[3] * 0.5), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_down_[0][p9]  + history_down_[0][m9],
                                               history_down_[1][p9]  + history_down_[1][m9]), SimdDouble2(C[4] * 0.5), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_down_[0][p11] + history_down_[0][m11],
                                               history_down_[1][p11] + history_down_[1][m11]), SimdDouble2(C[5] * 0.5), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_down_[0][p13] + history_down_[0][m13],
                                               history_down_[1][p13] + history_down_[1][m13]), SimdDouble2(C[6] * 0.5), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_down_[0][p15] + history_down_[0][m15],
                                               history_down_[1][p15] + history_down_[1][m15]), SimdDouble2(C[7] * 0.5), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_down_[0][p17] + history_down_[0][m17],
                                               history_down_[1][p17] + history_down_[1][m17]), SimdDouble2(C[8] * 0.5), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_down_[0][p19] + history_down_[0][m19],
                                               history_down_[1][p19] + history_down_[1][m19]), SimdDouble2(C[9] * 0.5), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_down_[0][p21] + history_down_[0][m21],
                                               history_down_[1][p21] + history_down_[1][m21]), SimdDouble2(C[10] * 0.5), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_down_[0][p23] + history_down_[0][m23],
                                               history_down_[1][p23] + history_down_[1][m23]), SimdDouble2(C[11] * 0.5), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_down_[0][p25] + history_down_[0][m25],
                                               history_down_[1][p25] + history_down_[1][m25]), SimdDouble2(C[12] * 0.5), acc);
            acc = SimdDouble2::fma(SimdDouble2(history_down_[0][p27] + history_down_[0][m27],
                                               history_down_[1][p27] + history_down_[1][m27]), SimdDouble2(C[13] * 0.5), acc);

            alignas(16) double res[2];
            acc.store_u(res);
            out_l = center_l + res[0];
            out_r = center_r + res[1];
            return;
        }

        T sum_l = static_cast<T>(0);
        T sum_r = static_cast<T>(0);
        for (int k = 0; k < NUM_ODD_COEFFS; ++k) {
            const int p = (center + (2 * k + 1)) & 63;
            const int m = (center - (2 * k + 1) + 64) & 63;
            const T ck_half = static_cast<T>(C[k] * 0.5);
            sum_l += ck_half * (history_down_[0][p] + history_down_[0][m]);
            sum_r += ck_half * (history_down_[1][p] + history_down_[1][m]);
        }

        out_l = center_l + sum_l;
        out_r = center_r + sum_r;
    }

private:
    // Remez equiripple half-band FIR odd coefficients (exact sum = 0.5 for unity DC gain, <0.0003 dB passband ripple, >= 96 dB stopband attenuation)
    static constexpr double C[NUM_ODD_COEFFS] = {
         0.63325347322776659, // offset +/- 1
        -0.20229304029740469, // offset +/- 3
         0.11141361671711554, // offset +/- 5
        -0.06987882027518606, // offset +/- 7
         0.04556866943326758, // offset +/- 9
        -0.02975924061736543, // offset +/- 11
         0.01906329776408587, // offset +/- 13
        -0.01179311919626298, // offset +/- 15
         0.00695287304654732, // offset +/- 17
        -0.00384251557970565, // offset +/- 19
         0.00195419140138790, // offset +/- 21
        -0.00088244408750492, // offset +/- 23
         0.00033695575785263, // offset +/- 25
        -0.00009389729459378  // offset +/- 27
    };

    T history_up_[2][32] = {};
    T history_down_[2][64] = {};
    int hist_idx_up_ = 0;
    int hist_idx_down_ = 0;
};

// Typedef aliases
using HalfBandFilter2x = HalfBandFilter2xT<float>;
using HalfBandFilter2x64 = HalfBandFilter2xT<double>;

// =============================================================================
// PolyphaseOversampler2x
// Handles upsampling, processing callback, and downsampling with pre-allocated
// stereo buffers for zero-allocation realtime execution.
// =============================================================================

template <typename T = float>
class PolyphaseOversampler2xT {
public:
    PolyphaseOversampler2xT() {
        init(48000, 8192);
    }

    void init(int sampleRate, uint32_t maxFrames = 8192) {
        sampleRate_ = (sampleRate > 0) ? sampleRate : 48000;
        maxFrames_ = std::max(maxFrames, 512u);
        
        // Pre-allocate buffer for 2x frames (interleaved stereo: 2 * maxFrames * 2 samples)
        oversampledBuffer_.resize(maxFrames_ * 4, static_cast<T>(0));
        filter_.reset();
    }

    void reset() {
        filter_.reset();
    }

    int getOversampledRate() const { return sampleRate_ * 2; }
    int getNativeRate() const { return sampleRate_; }

    // Upsample interleaved stereo: in_samples [L0, R0, L1, R1, ...] (frame_count frames)
    // Returns pointer to oversampled interleaved buffer (2 * frame_count frames).
    T* upsample(const T* in_samples, uint32_t frame_count) {
        if (!in_samples || frame_count == 0) return nullptr;

        if (frame_count * 4 > oversampledBuffer_.size()) {
            oversampledBuffer_.resize(frame_count * 4);
        }

        T* out = oversampledBuffer_.data();

        for (uint32_t i = 0; i < frame_count; ++i) {
            T in_l = in_samples[2 * i];
            T in_r = in_samples[2 * i + 1];

            T l0, r0, l1, r1;
            filter_.upsample2xFrame(in_l, in_r, l0, r0, l1, r1);

            out[4 * i]     = l0;
            out[4 * i + 1] = r0;
            out[4 * i + 2] = l1;
            out[4 * i + 3] = r1;
        }

        return out;
    }

    // Downsample oversampled buffer back into native interleaved stereo buffer (frame_count frames)
    void downsample(const T* oversampled_samples, T* out_samples, uint32_t frame_count) {
        if (!oversampled_samples || !out_samples || frame_count == 0) return;

        for (uint32_t i = 0; i < frame_count; ++i) {
            T l0 = oversampled_samples[4 * i];
            T r0 = oversampled_samples[4 * i + 1];
            T l1 = oversampled_samples[4 * i + 2];
            T r1 = oversampled_samples[4 * i + 3];

            T out_l, out_r;
            filter_.downsample2xFrame(l0, r0, l1, r1, out_l, out_r);

            out_samples[2 * i]     = out_l;
            out_samples[2 * i + 1] = out_r;
        }
    }

    template <typename ProcessFunc>
    void process(T* interleaved_samples, uint32_t frame_count, ProcessFunc&& func) {
        if (!interleaved_samples || frame_count == 0) return;

        T* oversampled = upsample(interleaved_samples, frame_count);
        if (oversampled) {
            func(oversampled, frame_count * 2);
            downsample(oversampled, interleaved_samples, frame_count);
        }
    }

private:
    int sampleRate_ = 48000;
    uint32_t maxFrames_ = 4096;
    HalfBandFilter2xT<T> filter_;
    std::vector<T> oversampledBuffer_;
};

using PolyphaseOversampler2x = PolyphaseOversampler2xT<float>;
using PolyphaseOversampler2x64 = PolyphaseOversampler2xT<double>;

// =============================================================================
// PolyphaseOversampler4x
// Cascades two HalfBandFilter2x stages for 4x oversampling.
// =============================================================================

template <typename T = float>
class PolyphaseOversampler4xT {
public:
    PolyphaseOversampler4xT() {
        init(48000, 8192);
    }

    void init(int sampleRate, uint32_t maxFrames = 8192) {
        sampleRate_ = (sampleRate > 0) ? sampleRate : 48000;
        maxFrames_ = std::max(maxFrames, 512u);
        
        stage1_buf_.resize(maxFrames_ * 4, static_cast<T>(0)); // 2x rate
        stage2_buf_.resize(maxFrames_ * 8, static_cast<T>(0)); // 4x rate
        filter1_.reset();
        filter2_.reset();
    }

    void reset() {
        filter1_.reset();
        filter2_.reset();
    }

    int getOversampledRate() const { return sampleRate_ * 4; }
    int getNativeRate() const { return sampleRate_; }

    template <typename ProcessFunc>
    void process(T* interleaved_samples, uint32_t frame_count, ProcessFunc&& func) {
        if (!interleaved_samples || frame_count == 0) return;

        if (frame_count * 8 > stage2_buf_.size()) {
            stage1_buf_.resize(frame_count * 4);
            stage2_buf_.resize(frame_count * 8);
        }

        // Stage 1: 1x -> 2x
        T* s1 = stage1_buf_.data();
        for (uint32_t i = 0; i < frame_count; ++i) {
            T in_l = interleaved_samples[2 * i];
            T in_r = interleaved_samples[2 * i + 1];
            T l0, r0, l1, r1;
            filter1_.upsample2xFrame(in_l, in_r, l0, r0, l1, r1);
            s1[4 * i]     = l0;
            s1[4 * i + 1] = r0;
            s1[4 * i + 2] = l1;
            s1[4 * i + 3] = r1;
        }

        // Stage 2: 2x -> 4x
        const uint32_t frames_2x = frame_count * 2;
        T* s2 = stage2_buf_.data();
        for (uint32_t i = 0; i < frames_2x; ++i) {
            T in_l = s1[2 * i];
            T in_r = s1[2 * i + 1];
            T l0, r0, l1, r1;
            filter2_.upsample2xFrame(in_l, in_r, l0, r0, l1, r1);
            s2[4 * i]     = l0;
            s2[4 * i + 1] = r0;
            s2[4 * i + 2] = l1;
            s2[4 * i + 3] = r1;
        }

        // Non-linear processing at 4x rate
        func(s2, frame_count * 4);

        // Stage 2 downsample: 4x -> 2x
        for (uint32_t i = 0; i < frames_2x; ++i) {
            T l0 = s2[4 * i];
            T r0 = s2[4 * i + 1];
            T l1 = s2[4 * i + 2];
            T r1 = s2[4 * i + 3];
            T out_l, out_r;
            filter2_.downsample2xFrame(l0, r0, l1, r1, out_l, out_r);
            s1[2 * i]     = out_l;
            s1[2 * i + 1] = out_r;
        }

        // Stage 1 downsample: 2x -> 1x
        for (uint32_t i = 0; i < frame_count; ++i) {
            T l0 = s1[4 * i];
            T r0 = s1[4 * i + 1];
            T l1 = s1[4 * i + 2];
            T r1 = s1[4 * i + 3];
            T out_l, out_r;
            filter1_.downsample2xFrame(l0, r0, l1, r1, out_l, out_r);
            interleaved_samples[2 * i]     = out_l;
            interleaved_samples[2 * i + 1] = out_r;
        }
    }

private:
    int sampleRate_ = 48000;
    uint32_t maxFrames_ = 4096;
    HalfBandFilter2xT<T> filter1_;
    HalfBandFilter2xT<T> filter2_;
    std::vector<T> stage1_buf_;
    std::vector<T> stage2_buf_;
};

using PolyphaseOversampler4x = PolyphaseOversampler4xT<float>;
using PolyphaseOversampler4x64 = PolyphaseOversampler4xT<double>;

} // namespace sauti::dsp
