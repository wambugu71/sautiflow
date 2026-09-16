#pragma once

#include <cstdint>
#include <cmath>
#include <algorithm>
#include <cstring>

// =============================================================================
// Platform Architecture Detection
// =============================================================================
#if defined(SAUTI_FORCE_SCALAR) || defined(SAUTI_DISABLE_SIMD)
    #define SAUTI_SIMD_SCALAR 1
#elif defined(__ARM_NEON) || defined(__aarch64__) || defined(_M_ARM64) || (defined(__arm__) && defined(__ARM_NEON__))
    #define SAUTI_SIMD_NEON 1
    #include <arm_neon.h>
#elif defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86) || defined(__SSE2__)
    #define SAUTI_SIMD_SSE 1
    #include <immintrin.h>
#else
    #define SAUTI_SIMD_SCALAR 1
#endif

namespace sauti::dsp {

// =============================================================================
// SimdFloat4: 4-wide 32-bit Single Precision Vector
// =============================================================================
struct SimdFloat4 {
#if defined(SAUTI_SIMD_NEON)
    float32x4_t v;

    inline SimdFloat4() noexcept : v(vdupq_n_f32(0.0f)) {}
    inline SimdFloat4(float32x4_t val) noexcept : v(val) {}
    inline explicit SimdFloat4(float val) noexcept : v(vdupq_n_f32(val)) {}
    inline SimdFloat4(float f0, float f1, float f2, float f3) noexcept {
        alignas(16) float data[4] = {f0, f1, f2, f3};
        v = vld1q_f32(data);
    }

    static inline SimdFloat4 load_u(const float* ptr) noexcept {
        return SimdFloat4(vld1q_f32(ptr));
    }

    static inline SimdFloat4 load_a(const float* ptr) noexcept {
        return SimdFloat4(vld1q_f32(ptr));
    }

    inline void store_u(float* ptr) const noexcept {
        vst1q_f32(ptr, v);
    }

    inline void store_a(float* ptr) const noexcept {
        vst1q_f32(ptr, v);
    }

    inline SimdFloat4 operator+(const SimdFloat4& o) const noexcept { return SimdFloat4(vaddq_f32(v, o.v)); }
    inline SimdFloat4 operator-(const SimdFloat4& o) const noexcept { return SimdFloat4(vsubq_f32(v, o.v)); }
    inline SimdFloat4 operator*(const SimdFloat4& o) const noexcept { return SimdFloat4(vmulq_f32(v, o.v)); }
    inline SimdFloat4 operator/(const SimdFloat4& o) const noexcept {
#if defined(__aarch64__) || defined(_M_ARM64)
        return SimdFloat4(vdivq_f32(v, o.v));
#else
        // 32-bit ARM NEON does not have vdivq_f32; use reciprocal estimate + Newton-Raphson
        float32x4_t rec = vrecpeq_f32(o.v);
        rec = vmulq_f32(vrecpsq_f32(o.v, rec), rec);
        rec = vmulq_f32(vrecpsq_f32(o.v, rec), rec);
        return SimdFloat4(vmulq_f32(v, rec));
#endif
    }

    inline SimdFloat4& operator+=(const SimdFloat4& o) noexcept { v = vaddq_f32(v, o.v); return *this; }
    inline SimdFloat4& operator-=(const SimdFloat4& o) noexcept { v = vsubq_f32(v, o.v); return *this; }
    inline SimdFloat4& operator*=(const SimdFloat4& o) noexcept { v = vmulq_f32(v, o.v); return *this; }

    static inline SimdFloat4 fma(const SimdFloat4& a, const SimdFloat4& b, const SimdFloat4& c) noexcept {
#if defined(__aarch64__) || defined(_M_ARM64) || (defined(__ARM_FEATURE_FMA) && __ARM_FEATURE_FMA)
        return SimdFloat4(vfmaq_f32(c.v, a.v, b.v));
#else
        return SimdFloat4(vaddq_f32(vmulq_f32(a.v, b.v), c.v));
#endif
    }

    static inline SimdFloat4 min(const SimdFloat4& a, const SimdFloat4& b) noexcept {
        return SimdFloat4(vminq_f32(a.v, b.v));
    }

    static inline SimdFloat4 max(const SimdFloat4& a, const SimdFloat4& b) noexcept {
        return SimdFloat4(vmaxq_f32(a.v, b.v));
    }

    static inline SimdFloat4 abs(const SimdFloat4& a) noexcept {
        return SimdFloat4(vabsq_f32(a.v));
    }

    inline float reduce_sum() const noexcept {
#if defined(__aarch64__) || defined(_M_ARM64)
        return vaddvq_f32(v);
#else
        float32x2_t r = vadd_f32(vget_low_f32(v), vget_high_f32(v));
        r = vpadd_f32(r, r);
        return vget_lane_f32(r, 0);
#endif
    }

    inline float get(int lane) const noexcept {
        alignas(16) float data[4];
        vst1q_f32(data, v);
        return data[lane & 3];
    }

#elif defined(SAUTI_SIMD_SSE)
    __m128 v;

    inline SimdFloat4() noexcept : v(_mm_setzero_ps()) {}
    inline SimdFloat4(__m128 val) noexcept : v(val) {}
    inline explicit SimdFloat4(float val) noexcept : v(_mm_set1_ps(val)) {}
    inline SimdFloat4(float f0, float f1, float f2, float f3) noexcept : v(_mm_setr_ps(f0, f1, f2, f3)) {}

    static inline SimdFloat4 load_u(const float* ptr) noexcept {
        return SimdFloat4(_mm_loadu_ps(ptr));
    }

    static inline SimdFloat4 load_a(const float* ptr) noexcept {
        return SimdFloat4(_mm_load_ps(ptr));
    }

    inline void store_u(float* ptr) const noexcept {
        _mm_storeu_ps(ptr, v);
    }

    inline void store_a(float* ptr) const noexcept {
        _mm_store_ps(ptr, v);
    }

    inline SimdFloat4 operator+(const SimdFloat4& o) const noexcept { return SimdFloat4(_mm_add_ps(v, o.v)); }
    inline SimdFloat4 operator-(const SimdFloat4& o) const noexcept { return SimdFloat4(_mm_sub_ps(v, o.v)); }
    inline SimdFloat4 operator*(const SimdFloat4& o) const noexcept { return SimdFloat4(_mm_mul_ps(v, o.v)); }
    inline SimdFloat4 operator/(const SimdFloat4& o) const noexcept { return SimdFloat4(_mm_div_ps(v, o.v)); }

    inline SimdFloat4& operator+=(const SimdFloat4& o) noexcept { v = _mm_add_ps(v, o.v); return *this; }
    inline SimdFloat4& operator-=(const SimdFloat4& o) noexcept { v = _mm_sub_ps(v, o.v); return *this; }
    inline SimdFloat4& operator*=(const SimdFloat4& o) noexcept { v = _mm_mul_ps(v, o.v); return *this; }

    static inline SimdFloat4 fma(const SimdFloat4& a, const SimdFloat4& b, const SimdFloat4& c) noexcept {
#if defined(__FMA__)
        return SimdFloat4(_mm_fmadd_ps(a.v, b.v, c.v));
#else
        return SimdFloat4(_mm_add_ps(_mm_mul_ps(a.v, b.v), c.v));
#endif
    }

    static inline SimdFloat4 min(const SimdFloat4& a, const SimdFloat4& b) noexcept {
        return SimdFloat4(_mm_min_ps(a.v, b.v));
    }

    static inline SimdFloat4 max(const SimdFloat4& a, const SimdFloat4& b) noexcept {
        return SimdFloat4(_mm_max_ps(a.v, b.v));
    }

    static inline SimdFloat4 abs(const SimdFloat4& a) noexcept {
        __m128 mask = _mm_castsi128_ps(_mm_set1_epi32(0x7FFFFFFF));
        return SimdFloat4(_mm_and_ps(a.v, mask));
    }

    inline float reduce_sum() const noexcept {
#if defined(__SSE3__)
        __m128 shuf = _mm_movehdup_ps(v);
        __m128 sums = _mm_add_ps(v, shuf);
        shuf = _mm_movehl_ps(shuf, sums);
        sums = _mm_add_ss(sums, shuf);
        return _mm_cvtss_f32(sums);
#else
        __m128 shuf = _mm_shuffle_ps(v, v, _MM_SHUFFLE(2, 3, 0, 1));
        __m128 sums = _mm_add_ps(v, shuf);
        shuf = _mm_movehl_ps(shuf, sums);
        sums = _mm_add_ss(sums, shuf);
        return _mm_cvtss_f32(sums);
#endif
    }

    inline float get(int lane) const noexcept {
        alignas(16) float data[4];
        _mm_storeu_ps(data, v);
        return data[lane & 3];
    }

#else // Portable IEEE-754 Scalar Fallback
    alignas(16) float d[4];

    inline SimdFloat4() noexcept : d{0.0f, 0.0f, 0.0f, 0.0f} {}
    inline explicit SimdFloat4(float val) noexcept : d{val, val, val, val} {}
    inline SimdFloat4(float f0, float f1, float f2, float f3) noexcept : d{f0, f1, f2, f3} {}

    static inline SimdFloat4 load_u(const float* ptr) noexcept {
        SimdFloat4 r;
        std::memcpy(r.d, ptr, 4 * sizeof(float));
        return r;
    }

    static inline SimdFloat4 load_a(const float* ptr) noexcept {
        return load_u(ptr);
    }

    inline void store_u(float* ptr) const noexcept {
        std::memcpy(ptr, d, 4 * sizeof(float));
    }

    inline void store_a(float* ptr) const noexcept {
        store_u(ptr);
    }

    inline SimdFloat4 operator+(const SimdFloat4& o) const noexcept {
        return SimdFloat4(d[0] + o.d[0], d[1] + o.d[1], d[2] + o.d[2], d[3] + o.d[3]);
    }
    inline SimdFloat4 operator-(const SimdFloat4& o) const noexcept {
        return SimdFloat4(d[0] - o.d[0], d[1] - o.d[1], d[2] - o.d[2], d[3] - o.d[3]);
    }
    inline SimdFloat4 operator*(const SimdFloat4& o) const noexcept {
        return SimdFloat4(d[0] * o.d[0], d[1] * o.d[1], d[2] * o.d[2], d[3] * o.d[3]);
    }
    inline SimdFloat4 operator/(const SimdFloat4& o) const noexcept {
        return SimdFloat4(d[0] / o.d[0], d[1] / o.d[1], d[2] / o.d[2], d[3] / o.d[3]);
    }

    inline SimdFloat4& operator+=(const SimdFloat4& o) noexcept {
        for (int i = 0; i < 4; ++i) d[i] += o.d[i];
        return *this;
    }
    inline SimdFloat4& operator-=(const SimdFloat4& o) noexcept {
        for (int i = 0; i < 4; ++i) d[i] -= o.d[i];
        return *this;
    }
    inline SimdFloat4& operator*=(const SimdFloat4& o) noexcept {
        for (int i = 0; i < 4; ++i) d[i] *= o.d[i];
        return *this;
    }

    static inline SimdFloat4 fma(const SimdFloat4& a, const SimdFloat4& b, const SimdFloat4& c) noexcept {
#if defined(__ARM_FEATURE_FMA) || defined(__FMA__) || defined(__AVX2__)
        return SimdFloat4(std::fma(a.d[0], b.d[0], c.d[0]),
                          std::fma(a.d[1], b.d[1], c.d[1]),
                          std::fma(a.d[2], b.d[2], c.d[2]),
                          std::fma(a.d[3], b.d[3], c.d[3]));
#else
        return SimdFloat4(a.d[0] * b.d[0] + c.d[0],
                          a.d[1] * b.d[1] + c.d[1],
                          a.d[2] * b.d[2] + c.d[2],
                          a.d[3] * b.d[3] + c.d[3]);
#endif
    }

    static inline SimdFloat4 min(const SimdFloat4& a, const SimdFloat4& b) noexcept {
        return SimdFloat4(std::min(a.d[0], b.d[0]),
                          std::min(a.d[1], b.d[1]),
                          std::min(a.d[2], b.d[2]),
                          std::min(a.d[3], b.d[3]));
    }

    static inline SimdFloat4 max(const SimdFloat4& a, const SimdFloat4& b) noexcept {
        return SimdFloat4(std::max(a.d[0], b.d[0]),
                          std::max(a.d[1], b.d[1]),
                          std::max(a.d[2], b.d[2]),
                          std::max(a.d[3], b.d[3]));
    }

    static inline SimdFloat4 abs(const SimdFloat4& a) noexcept {
        return SimdFloat4(std::fabs(a.d[0]),
                          std::fabs(a.d[1]),
                          std::fabs(a.d[2]),
                          std::fabs(a.d[3]));
    }

    inline float reduce_sum() const noexcept {
        return d[0] + d[1] + d[2] + d[3];
    }

    inline float get(int lane) const noexcept {
        return d[lane & 3];
    }
#endif

    // Fast rational Padé approximation for tanh: x * (27 + x^2) / (27 + 9*x^2)
    // Clamped to [-3.0, 3.0] with exact sat limits
    static inline SimdFloat4 fast_tanh(const SimdFloat4& x) noexcept {
        const SimdFloat4 clamp_pos(3.0f);
        const SimdFloat4 clamp_neg(-3.0f);
        SimdFloat4 clamped = SimdFloat4::max(clamp_neg, SimdFloat4::min(clamp_pos, x));
        SimdFloat4 x2 = clamped * clamped;
        SimdFloat4 c27(27.0f);
        SimdFloat4 c9(9.0f);
        SimdFloat4 num = clamped * (c27 + x2);
        SimdFloat4 den = c27 + (c9 * x2);
        return num / den;
    }

    // Multiplies 2 complex numbers [ar0, ai0, ar1, ai1] * [br0, bi0, br1, bi1] and accumulates into acc
    static inline SimdFloat4 complex_mul_accumulate_2(const SimdFloat4& a, const SimdFloat4& b, const SimdFloat4& acc) noexcept {
#if defined(SAUTI_SIMD_NEON)
#if defined(__ARM_FEATURE_COMPLEX)
        float32x4_t res = vcmlaq_f32(acc.v, b.v, a.v);
        res = vcmlaq_rot90_f32(res, b.v, a.v);
        return SimdFloat4(res);
#else
        float32x4_t a_val = a.v;
        float32x4_t b_val = b.v;
        float32x4x2_t a_trn = vtrnq_f32(a_val, a_val);
        float32x4_t ar = a_trn.val[0];
        float32x4_t ai = a_trn.val[1];
        float32x4_t b_rev = vrev64q_f32(b_val);
        alignas(16) static const float mask_data[4] = {-1.0f, 1.0f, -1.0f, 1.0f};
        float32x4_t sign_mask = vld1q_f32(mask_data);
        float32x4_t b_swap = vmulq_f32(b_rev, sign_mask);
        float32x4_t prod = vaddq_f32(vmulq_f32(ar, b_val), vmulq_f32(ai, b_swap));
        return SimdFloat4(vaddq_f32(acc.v, prod));
#endif
#elif defined(SAUTI_SIMD_SSE)
        __m128 ar = _mm_shuffle_ps(a.v, a.v, _MM_SHUFFLE(2, 2, 0, 0));
        __m128 ai = _mm_shuffle_ps(a.v, a.v, _MM_SHUFFLE(3, 3, 1, 1));
        __m128 b_swap = _mm_shuffle_ps(b.v, b.v, _MM_SHUFFLE(2, 3, 0, 1));
#if defined(__SSE3__) || defined(__AVX__)
        __m128 term1 = _mm_mul_ps(ar, b.v);
        __m128 term2 = _mm_mul_ps(ai, b_swap);
        __m128 prod = _mm_addsub_ps(term1, term2);
        return SimdFloat4(_mm_add_ps(acc.v, prod));
#else
        __m128 sign_mask = _mm_setr_ps(-1.0f, 1.0f, -1.0f, 1.0f);
        b_swap = _mm_mul_ps(b_swap, sign_mask);
        __m128 prod = _mm_add_ps(_mm_mul_ps(ar, b.v), _mm_mul_ps(ai, b_swap));
        return SimdFloat4(_mm_add_ps(acc.v, prod));
#endif
#else
        alignas(16) float a_arr[4];
        alignas(16) float b_arr[4];
        alignas(16) float acc_arr[4];
        a.store_u(a_arr);
        b.store_u(b_arr);
        acc.store_u(acc_arr);
        return SimdFloat4(acc_arr[0] + (a_arr[0] * b_arr[0] - a_arr[1] * b_arr[1]),
                          acc_arr[1] + (a_arr[0] * b_arr[1] + a_arr[1] * b_arr[0]),
                          acc_arr[2] + (a_arr[2] * b_arr[2] - a_arr[3] * b_arr[3]),
                          acc_arr[3] + (a_arr[2] * b_arr[3] + a_arr[3] * b_arr[2]));
#endif
    }
};


// =============================================================================
// SimdDouble2: 2-wide 64-bit Double Precision Vector (Stereo Audiophile)
// =============================================================================
struct SimdDouble2 {
#if defined(SAUTI_SIMD_NEON) && (defined(__aarch64__) || defined(_M_ARM64))
    float64x2_t v;

    inline SimdDouble2() noexcept : v(vdupq_n_f64(0.0)) {}
    inline SimdDouble2(float64x2_t val) noexcept : v(val) {}
    inline explicit SimdDouble2(double val) noexcept : v(vdupq_n_f64(val)) {}
    inline SimdDouble2(double d0, double d1) noexcept {
        alignas(16) double data[2] = {d0, d1};
        v = vld1q_f64(data);
    }

    static inline SimdDouble2 load_u(const double* ptr) noexcept {
        return SimdDouble2(vld1q_f64(ptr));
    }

    static inline SimdDouble2 load_a(const double* ptr) noexcept {
        return SimdDouble2(vld1q_f64(ptr));
    }

    inline void store_u(double* ptr) const noexcept {
        vst1q_f64(ptr, v);
    }

    inline void store_a(double* ptr) const noexcept {
        vst1q_f64(ptr, v);
    }

    inline SimdDouble2 operator+(const SimdDouble2& o) const noexcept { return SimdDouble2(vaddq_f64(v, o.v)); }
    inline SimdDouble2 operator-(const SimdDouble2& o) const noexcept { return SimdDouble2(vsubq_f64(v, o.v)); }
    inline SimdDouble2 operator*(const SimdDouble2& o) const noexcept { return SimdDouble2(vmulq_f64(v, o.v)); }
    inline SimdDouble2 operator/(const SimdDouble2& o) const noexcept { return SimdDouble2(vdivq_f64(v, o.v)); }

    inline SimdDouble2& operator+=(const SimdDouble2& o) noexcept { v = vaddq_f64(v, o.v); return *this; }
    inline SimdDouble2& operator-=(const SimdDouble2& o) noexcept { v = vsubq_f64(v, o.v); return *this; }
    inline SimdDouble2& operator*=(const SimdDouble2& o) noexcept { v = vmulq_f64(v, o.v); return *this; }

    static inline SimdDouble2 fma(const SimdDouble2& a, const SimdDouble2& b, const SimdDouble2& c) noexcept {
        return SimdDouble2(vfmaq_f64(c.v, a.v, b.v));
    }

    static inline SimdDouble2 min(const SimdDouble2& a, const SimdDouble2& b) noexcept {
        return SimdDouble2(vminq_f64(a.v, b.v));
    }

    static inline SimdDouble2 max(const SimdDouble2& a, const SimdDouble2& b) noexcept {
        return SimdDouble2(vmaxq_f64(a.v, b.v));
    }

    static inline SimdDouble2 abs(const SimdDouble2& a) noexcept {
        return SimdDouble2(vabsq_f64(a.v));
    }

    inline double reduce_sum() const noexcept {
        return vaddvq_f64(v);
    }

    inline double get_low() const noexcept {
        return vgetq_lane_f64(v, 0);
    }

    inline double get_high() const noexcept {
        return vgetq_lane_f64(v, 1);
    }

    inline double get(int lane) const noexcept {
        alignas(16) double data[2];
        vst1q_f64(data, v);
        return data[lane & 1];
    }

#elif defined(SAUTI_SIMD_SSE)
    __m128d v;

    inline SimdDouble2() noexcept : v(_mm_setzero_pd()) {}
    inline SimdDouble2(__m128d val) noexcept : v(val) {}
    inline explicit SimdDouble2(double val) noexcept : v(_mm_set1_pd(val)) {}
    inline SimdDouble2(double d0, double d1) noexcept : v(_mm_setr_pd(d0, d1)) {}

    static inline SimdDouble2 load_u(const double* ptr) noexcept {
        return SimdDouble2(_mm_loadu_pd(ptr));
    }

    static inline SimdDouble2 load_a(const double* ptr) noexcept {
        return SimdDouble2(_mm_load_pd(ptr));
    }

    inline void store_u(double* ptr) const noexcept {
        _mm_storeu_pd(ptr, v);
    }

    inline void store_a(double* ptr) const noexcept {
        _mm_store_pd(ptr, v);
    }

    inline SimdDouble2 operator+(const SimdDouble2& o) const noexcept { return SimdDouble2(_mm_add_pd(v, o.v)); }
    inline SimdDouble2 operator-(const SimdDouble2& o) const noexcept { return SimdDouble2(_mm_sub_pd(v, o.v)); }
    inline SimdDouble2 operator*(const SimdDouble2& o) const noexcept { return SimdDouble2(_mm_mul_pd(v, o.v)); }
    inline SimdDouble2 operator/(const SimdDouble2& o) const noexcept { return SimdDouble2(_mm_div_pd(v, o.v)); }

    inline SimdDouble2& operator+=(const SimdDouble2& o) noexcept { v = _mm_add_pd(v, o.v); return *this; }
    inline SimdDouble2& operator-=(const SimdDouble2& o) noexcept { v = _mm_sub_pd(v, o.v); return *this; }
    inline SimdDouble2& operator*=(const SimdDouble2& o) noexcept { v = _mm_mul_pd(v, o.v); return *this; }

    static inline SimdDouble2 fma(const SimdDouble2& a, const SimdDouble2& b, const SimdDouble2& c) noexcept {
#if defined(__FMA__)
        return SimdDouble2(_mm_fmadd_pd(a.v, b.v, c.v));
#else
        return SimdDouble2(_mm_add_pd(_mm_mul_pd(a.v, b.v), c.v));
#endif
    }

    static inline SimdDouble2 min(const SimdDouble2& a, const SimdDouble2& b) noexcept {
        return SimdDouble2(_mm_min_pd(a.v, b.v));
    }

    static inline SimdDouble2 max(const SimdDouble2& a, const SimdDouble2& b) noexcept {
        return SimdDouble2(_mm_max_pd(a.v, b.v));
    }

    static inline SimdDouble2 abs(const SimdDouble2& a) noexcept {
        __m128d mask = _mm_castsi128_pd(_mm_set_epi64x(0x7FFFFFFFFFFFFFFFLL, 0x7FFFFFFFFFFFFFFFLL));
        return SimdDouble2(_mm_and_pd(a.v, mask));
    }

    inline double reduce_sum() const noexcept {
        __m128d hi = _mm_unpackhi_pd(v, v);
        return _mm_cvtsd_f64(_mm_add_sd(v, hi));
    }

    inline double get_low() const noexcept {
        return _mm_cvtsd_f64(v);
    }

    inline double get_high() const noexcept {
        __m128d hi = _mm_unpackhi_pd(v, v);
        return _mm_cvtsd_f64(hi);
    }

    inline double get(int lane) const noexcept {
        alignas(16) double data[2];
        _mm_storeu_pd(data, v);
        return data[lane & 1];
    }

#else // ARM 32-bit VFPv3/VFPv4 Hardware Double & Portable IEEE-754 Fallback
    alignas(16) double d[2];

    inline SimdDouble2() noexcept : d{0.0, 0.0} {}
    inline explicit SimdDouble2(double val) noexcept : d{val, val} {}
    inline SimdDouble2(double d0, double d1) noexcept : d{d0, d1} {}

    static inline SimdDouble2 load_u(const double* ptr) noexcept {
        SimdDouble2 r;
        std::memcpy(r.d, ptr, 2 * sizeof(double));
        return r;
    }

    static inline SimdDouble2 load_a(const double* ptr) noexcept {
        return load_u(ptr);
    }

    inline void store_u(double* ptr) const noexcept {
        std::memcpy(ptr, d, 2 * sizeof(double));
    }

    inline void store_a(double* ptr) const noexcept {
        store_u(ptr);
    }

    inline SimdDouble2 operator+(const SimdDouble2& o) const noexcept {
        return SimdDouble2(d[0] + o.d[0], d[1] + o.d[1]);
    }
    inline SimdDouble2 operator-(const SimdDouble2& o) const noexcept {
        return SimdDouble2(d[0] - o.d[0], d[1] - o.d[1]);
    }
    inline SimdDouble2 operator*(const SimdDouble2& o) const noexcept {
        return SimdDouble2(d[0] * o.d[0], d[1] * o.d[1]);
    }
    inline SimdDouble2 operator/(const SimdDouble2& o) const noexcept {
        return SimdDouble2(d[0] / o.d[0], d[1] / o.d[1]);
    }

    inline SimdDouble2& operator+=(const SimdDouble2& o) noexcept {
        d[0] += o.d[0]; d[1] += o.d[1];
        return *this;
    }
    inline SimdDouble2& operator-=(const SimdDouble2& o) noexcept {
        d[0] -= o.d[0]; d[1] -= o.d[1];
        return *this;
    }
    inline SimdDouble2& operator*=(const SimdDouble2& o) noexcept {
        d[0] *= o.d[0]; d[1] *= o.d[1];
        return *this;
    }

    static inline SimdDouble2 fma(const SimdDouble2& a, const SimdDouble2& b, const SimdDouble2& c) noexcept {
#if defined(__ARM_FEATURE_FMA) || defined(__FMA__) || defined(__AVX2__)
        return SimdDouble2(std::fma(a.d[0], b.d[0], c.d[0]),
                           std::fma(a.d[1], b.d[1], c.d[1]));
#else
        return SimdDouble2(a.d[0] * b.d[0] + c.d[0],
                           a.d[1] * b.d[1] + c.d[1]);
#endif
    }

    static inline SimdDouble2 min(const SimdDouble2& a, const SimdDouble2& b) noexcept {
        return SimdDouble2(std::min(a.d[0], b.d[0]), std::min(a.d[1], b.d[1]));
    }

    static inline SimdDouble2 max(const SimdDouble2& a, const SimdDouble2& b) noexcept {
        return SimdDouble2(std::max(a.d[0], b.d[0]), std::max(a.d[1], b.d[1]));
    }

    static inline SimdDouble2 abs(const SimdDouble2& a) noexcept {
        return SimdDouble2(std::fabs(a.d[0]), std::fabs(a.d[1]));
    }

    inline double reduce_sum() const noexcept {
        return d[0] + d[1];
    }

    inline double get_low() const noexcept {
        return d[0];
    }

    inline double get_high() const noexcept {
        return d[1];
    }

    inline double get(int lane) const noexcept {
        return d[lane & 1];
    }
#endif
};

} // namespace sauti::dsp
