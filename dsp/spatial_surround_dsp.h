#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <vector>

// =============================================================================
// SpatialSurroundDSP: Zero-Latency Surround / Spatial Suite
//
// Implements the algorithms specified in surround.md:
//   1. Parametric Spherical-Head HRTF (Brown & Duda structural model)
//   2. ViPER Headphone Surround+ (crossfeed + 6-tap early reflection room)
//   3. Frequency-Split Field Surround (M/S expander + all-pass diffuser)
//   4. Differential Haas Spatializer (comb-suppressed cross-injection)
//   5. Matrix 5.1 Decoder -> Binaural Virtualizer (Pro Logic II cleanroom)
//
// All modes process interleaved 32-bit float stereo in-place with zero
// algorithmic latency, click-free parameter smoothing and denormal clamping.
// =============================================================================

namespace sauti::dsp {

enum class SurroundMode {
    Off = 0,
    FieldExpander = 1,      // Frequency-Split M/S Expander + Schroeder Diffuser
    DifferentialHaas = 2,   // Haas precedence-effect spatializer
    ViperHeadphone = 3,     // VHS+ room crossfeed & early reflections
    Matrix51Hrtf = 4        // Pro Logic II dematrix -> binaural HRTF
};

inline float surround_sanitize(float v)
{
    return (std::fabs(v) < 1.0e-15f) ? 0.0f : v;
}

// ---------------------------------------------------------------------------
// Direct Form I biquad
// ---------------------------------------------------------------------------
struct SurroundBiquad {
    float b0 = 1.0f, b1 = 0.0f, b2 = 0.0f;
    float a1 = 0.0f, a2 = 0.0f;
    float x1 = 0.0f, x2 = 0.0f, y1 = 0.0f, y2 = 0.0f;

    void reset() { x1 = x2 = y1 = y2 = 0.0f; }

    inline float process(float x)
    {
        const float y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        x2 = x1; x1 = x;
        y2 = y1; y1 = surround_sanitize(y);
        return y1;
    }
};

// RBJ peaking EQ (used for the pinna notch: negative gain => dip)
inline void surround_set_peaking(SurroundBiquad &bq, double fs, double f0, double Q, double gain_db)
{
    constexpr double PI = 3.14159265358979323846;
    double w0 = 2.0 * PI * f0 / fs;
    if (w0 > PI * 0.95) w0 = PI * 0.95;
    if (w0 < 1.0e-4) w0 = 1.0e-4;
    const double A = std::pow(10.0, gain_db / 40.0);
    const double cw = std::cos(w0);
    const double alpha = std::sin(w0) / (2.0 * Q);

    const double a0 = 1.0 + alpha / A;
    bq.b0 = static_cast<float>((1.0 + alpha * A) / a0);
    bq.b1 = static_cast<float>((-2.0 * cw) / a0);
    bq.b2 = static_cast<float>((1.0 - alpha * A) / a0);
    bq.a1 = static_cast<float>((-2.0 * cw) / a0);
    bq.a2 = static_cast<float>((1.0 - alpha / A) / a0);
}

// RBJ 2nd-order Butterworth low/high pass (Q = 0.7071)
inline void surround_set_lowpass(SurroundBiquad &bq, double fs, double f0, double Q)
{
    constexpr double PI = 3.14159265358979323846;
    double w0 = 2.0 * PI * f0 / fs;
    if (w0 > PI * 0.95) w0 = PI * 0.95;
    if (w0 < 1.0e-4) w0 = 1.0e-4;
    const double cw = std::cos(w0);
    const double alpha = std::sin(w0) / (2.0 * Q);

    const double a0 = 1.0 + alpha;
    bq.b0 = static_cast<float>(((1.0 - cw) / 2.0) / a0);
    bq.b1 = static_cast<float>((1.0 - cw) / a0);
    bq.b2 = static_cast<float>(((1.0 - cw) / 2.0) / a0);
    bq.a1 = static_cast<float>((-2.0 * cw) / a0);
    bq.a2 = static_cast<float>((1.0 - alpha) / a0);
}

inline void surround_set_highpass(SurroundBiquad &bq, double fs, double f0, double Q)
{
    constexpr double PI = 3.14159265358979323846;
    double w0 = 2.0 * PI * f0 / fs;
    if (w0 > PI * 0.95) w0 = PI * 0.95;
    if (w0 < 1.0e-4) w0 = 1.0e-4;
    const double cw = std::cos(w0);
    const double alpha = std::sin(w0) / (2.0 * Q);

    const double a0 = 1.0 + alpha;
    bq.b0 = static_cast<float>(((1.0 + cw) / 2.0) / a0);
    bq.b1 = static_cast<float>(-(1.0 + cw) / a0);
    bq.b2 = static_cast<float>(((1.0 + cw) / 2.0) / a0);
    bq.a1 = static_cast<float>((-2.0 * cw) / a0);
    bq.a2 = static_cast<float>((1.0 - alpha) / a0);
}

// First-order head-shadow shelf (Brown & Duda), bilinear transform of
//   H(s) = (1 + alpha*tau0*s) / (1 + tau0*s)
struct SurroundShelf1 {
    float b0 = 1.0f, b1 = 0.0f, a1 = 0.0f;
    float x1 = 0.0f, y1 = 0.0f;

    void reset() { x1 = y1 = 0.0f; }

    void setShadow(double alpha, double tau0, double T)
    {
        const double a0 = 2.0 * tau0 + T;
        b0 = static_cast<float>((2.0 * alpha * tau0 + T) / a0);
        b1 = static_cast<float>((T - 2.0 * alpha * tau0) / a0);
        a1 = static_cast<float>((T - 2.0 * tau0) / a0);
    }

    inline float process(float x)
    {
        const float y = b0 * x + b1 * x1 - a1 * y1;
        x1 = x;
        y1 = surround_sanitize(y);
        return y1;
    }
};

// Fractional delay line with linear interpolation (ITD <= ~32 samples @48k,
// so linear interpolation error is well below audibility for ITD purposes).
struct SurroundDelay {
    std::vector<float> buf;
    uint32_t w = 0;

    void init(uint32_t max_samples)
    {
        buf.assign(max_samples + 4, 0.0f);
        w = 0;
    }

    void clear() { std::fill(buf.begin(), buf.end(), 0.0f); w = 0; }

    inline float maxDelay() const { return static_cast<float>(buf.size() - 3); }

    // Push x, read value delayed by `d` samples (1 <= d <= maxDelay).
    inline float pushAndRead(float d, float x)
    {
        buf[w] = x;
        const uint32_t n = static_cast<uint32_t>(buf.size());
        float di = d; if (di < 1.0f) di = 1.0f;
        if (di > maxDelay()) di = maxDelay();
        // read index walks backwards from write position
        const uint32_t i0 = static_cast<uint32_t>(di);
        const float frac = di - static_cast<float>(i0);
        const uint32_t r0 = (w + n - i0) % n;
        const uint32_t r1 = (r0 + n - 1) % n;
        w = (w + 1) % n;
        return buf[r0] + frac * (buf[r1] - buf[r0]);
    }

    // Read-only peek at integer+fractional delay without writing.
    inline float read(float d) const
    {
        const uint32_t n = static_cast<uint32_t>(buf.size());
        float di = d; if (di < 1.0f) di = 1.0f;
        if (di > maxDelay()) di = maxDelay();
        const uint32_t i0 = static_cast<uint32_t>(di);
        const float frac = di - static_cast<float>(i0);
        const uint32_t r0 = (w + n - 1 - i0 + n) % n;
        const uint32_t r1 = (r0 + n - 1) % n;
        return buf[r0] + frac * (buf[r1] - buf[r0]);
    }

    inline void push(float x)
    {
        buf[w] = x;
        w = (w + 1) % static_cast<uint32_t>(buf.size());
    }
};

// Cascaded first-order all-pass (Schroeder diffuser stage / quadrature phase)
struct SurroundAllpass1 {
    float c = 0.0f;
    float x1 = 0.0f, y1 = 0.0f;

    void reset() { x1 = y1 = 0.0f; }
    inline float process(float x)
    {
        const float y = c * x + x1 - c * y1;
        x1 = x;
        y1 = surround_sanitize(y);
        return y1;
    }
};

// Schroeder-style all-pass with delay D: y[n] = -g*x[n] + x[n-D] + g*y[n-D]
struct SurroundDiffuserAP {
    float g = 0.5f;
    float delay_samples = 1.0f;
    SurroundDelay in_line, out_line;

    void init(float delay_samples_ref48k, float sr_scale)
    {
        g = 0.5f;
        delay_samples = std::max(1.0f, delay_samples_ref48k * sr_scale);
        in_line.init(static_cast<uint32_t>(delay_samples) + 8u);
        out_line.init(static_cast<uint32_t>(delay_samples) + 8u);
    }
    void reset()
    {
        in_line.clear();
        out_line.clear();
    }
    inline float process(float x)
    {
        const float xd = in_line.read(delay_samples);
        const float yd = out_line.read(delay_samples);
        const float y = -g * x + xd + g * yd;
        in_line.push(x);
        out_line.push(surround_sanitize(y));
        return y;
    }
};

// ---------------------------------------------------------------------------
// Algorithm 1 core: Parametric spherical-head HRTF source.
// Configures ITD + head shadow + pinna notch for one virtual speaker at a
// fixed azimuth/elevation, renders mono input into stereo contributions.
// ---------------------------------------------------------------------------
class HrtfSource {
public:
    void configure(float azimuth_deg, float elevation_deg,
                   float head_radius_cm, float pinna_strength, float sample_rate)
    {
        sample_rate_ = sample_rate;
        azimuth_ = azimuth_deg;
        elevation_ = elevation_deg;
        pinna_strength_ = pinna_strength;
        head_radius_cm_ = head_radius_cm;
        update();

        if (!delay_.initialized || last_radius_ != head_radius_cm_) {
            delay_.init(64);
            delay_.initialized = true;
            last_radius_ = head_radius_cm_;
        }
    }

    void reset()
    {
        delay_.clear();
        shadow_l_.reset(); shadow_r_.reset();
        notch_l_.reset();  notch_r_.reset();
    }

    // Process one mono input sample, accumulate into stereo accumulators.
    inline void process(float x, float src_gain, float &out_l, float &out_r)
    {
        float near_sig = x;
        float far_sig = x;
        if (itd_samples_ > 0.05f) {
            far_sig = delay_.pushAndRead(itd_samples_, x);
        } else if (delay_.initialized && delay_.maxDelay() > 0.0f) {
            delay_.push(x);
        }

        const float l_raw = (near_side_ < 0) ? near_sig : far_sig;
        const float r_raw = (near_side_ > 0) ? near_sig : far_sig;

        const float l = shadow_l_.process(notch_l_.process(l_raw));
        const float r = shadow_r_.process(notch_r_.process(r_raw));

        out_l += src_gain * l;
        out_r += src_gain * r;
    }

private:
    struct DelayWrap : public SurroundDelay { bool initialized = false; };
    DelayWrap delay_;
    float last_radius_ = -1.0f;

    SurroundShelf1 shadow_l_, shadow_r_;
    SurroundBiquad notch_l_, notch_r_;
    float itd_samples_ = 0.0f;
    int near_side_ = 0;

    float sample_rate_ = 48000.0f;
    float azimuth_ = 0.0f, elevation_ = 0.0f;
    float pinna_strength_ = 1.0f;
    float head_radius_cm_ = 8.75f;

    void update()
    {
        const double c = 343.0;
        const double a = static_cast<double>(head_radius_cm_) * 0.01;
        const double T = 1.0 / static_cast<double>(sample_rate_);
        const double tau0 = 2.0 * a / c;

        const double theta_s = static_cast<double>(azimuth_) * 3.14159265358979323846 / 180.0;

        // ITD (Woodworth): far ear only. Near ear receives direct arrival.
        const double thm = std::min(std::fabs(theta_s), 3.14159265358979323846);
        itd_samples_ = static_cast<float>((a / c) * (thm + std::sin(thm)) / T);
        near_side_ = (azimuth_ > 0.5f) ? 1 : ((azimuth_ < -0.5f) ? -1 : 0);

        // Head shadow factor per ear: angle between source direction and ear
        // direction (ears at +/-90 deg). alpha = 1 + cos(theta_rel).
        auto ear_alpha = [&](double ear_azimuth_deg) {
            double rel = std::fabs(static_cast<double>(azimuth_) - ear_azimuth_deg);
            if (rel > 180.0) rel = 360.0 - rel;
            return 1.0 + std::cos(rel * 3.14159265358979323846 / 180.0);
        };

        shadow_l_.setShadow(ear_alpha(-90.0), tau0, T);
        shadow_r_.setShadow(ear_alpha(+90.0), tau0, T);

        // Pinna concha notch (peaking dip, depth scaled by pinna strength).
        const double phi = static_cast<double>(elevation_);
        const double f_notch = 6500.0 + 3500.0 *
            std::sin(((phi + 90.0) / 180.0) * (3.14159265358979323846 / 2.0));
        const double fs = static_cast<double>(sample_rate_);
        surround_set_peaking(notch_l_, fs, f_notch, 3.5, -8.0 * static_cast<double>(pinna_strength_));
        surround_set_peaking(notch_r_, fs, f_notch, 3.5, -8.0 * static_cast<double>(pinna_strength_));
    }
};

// =============================================================================
// SpatialSurroundDSP main class
// =============================================================================
class SpatialSurroundDSP {
public:
    SpatialSurroundDSP() {
        setSampleRate(48000.0f);
        reset();
    }

    // ---------------- Configuration ----------------

    void setSampleRate(float sampleRate)
    {
        if (sampleRate <= 0.0f) sampleRate = 48000.0f;
        if (std::abs(sample_rate_ - sampleRate) < 0.1f) return;
        sample_rate_ = sampleRate;
        smoothing_coeff_ = 1.0f - std::exp(-1.0f / (0.035f * sample_rate_));
        buildDelayLines();
        updateFilters();
        reconfigureHrtf();
        reset();
    }

    void setEnabled(bool enabled) { enabled_ = enabled; }
    bool isEnabled() const { return enabled_; }

    void setMode(SurroundMode mode)
    {
        if (mode_ != mode) {
            mode_ = mode;
            reset();
        }
    }
    SurroundMode getMode() const { return mode_; }

    // Field Expander parameters
    void setFieldWidth(float width)          { field_width_ = clampf(width, 0.0f, 2.5f); }
    void setFieldCrossoverHz(float hz)       { field_crossover_hz_ = clampf(hz, 60.0f, 400.0f); need_filter_update_ = true; }
    void setFieldDiffuserMix(float mix)      { field_diffuser_mix_ = clampf(mix, 0.0f, 1.0f); }
    void setBassAnchor(float anchor)         { bass_anchor_ = clampf(anchor, 0.0f, 1.0f); }

    // Differential Haas parameters
    void setHaasDelayMs(float ms)            { haas_delay_ms_ = clampf(ms, 1.0f, 25.0f); need_filter_update_ = true; }
    void setHaasDepth(float depth)           { haas_depth_ = clampf(depth, 0.0f, 0.8f); }
    void setHaasDampingHz(float hz)          { haas_damping_hz_ = clampf(hz, 1000.0f, 12000.0f); need_filter_update_ = true; }

    // VHS+ parameters
    void setVhsRoomPreset(int preset)        { vhs_room_preset_ = clampi(preset, 1, 5); }
    void setVhsReflectionGain(float gain)    { vhs_reflection_gain_ = clampf(gain, 0.0f, 1.0f); }
    void setVhsDamping(float damping)        { vhs_damping_ = clampf(damping, 0.0f, 1.0f); need_filter_update_ = true; }

    // Matrix 5.1 parameters
    void setCenterFocus(float focus)         { center_focus_ = clampf(focus, 0.0f, 1.0f); }
    void setSurroundBoost(float boost)       { surround_boost_ = clampf(boost, 0.0f, 2.0f); }
    void setSurroundDelayMs(float ms)        { surround_delay_ms_ = clampf(ms, 5.0f, 30.0f); }

    // Shared HRTF parameter
    void setHeadRadiusCm(float cm)
    {
        head_radius_cm_ = clampf(cm, 6.0f, 12.0f);
        reconfigureHrtf();
    }

    float getSampleRate() const { return sample_rate_; }

    float getFieldWidth() const { return field_width_; }
    float getFieldCrossoverHz() const { return field_crossover_hz_; }
    float getFieldDiffuserMix() const { return field_diffuser_mix_; }
    float getBassAnchor() const { return bass_anchor_; }
    float getHaasDelayMs() const { return haas_delay_ms_; }
    float getHaasDepth() const { return haas_depth_; }
    float getHaasDampingHz() const { return haas_damping_hz_; }
    int getVhsRoomPreset() const { return vhs_room_preset_; }
    float getVhsReflectionGain() const { return vhs_reflection_gain_; }
    float getVhsDamping() const { return vhs_damping_; }
    float getCenterFocus() const { return center_focus_; }
    float getSurroundBoost() const { return surround_boost_; }
    float getSurroundDelayMs() const { return surround_delay_ms_; }
    float getHeadRadiusCm() const { return head_radius_cm_; }

    // ---------------- State ----------------

    void reset()
    {
        // Field
        for (auto &bq : field_lp_) bq.reset();
        for (auto &bq : field_hp_) bq.reset();
        field_ap1_.reset(); field_ap2_.reset();
        smooth_width_ = field_width_;
        smooth_diff_mix_ = field_diffuser_mix_;
        smooth_bass_anchor_ = bass_anchor_;

        // Haas
        haas_line_l_.clear(); haas_line_r_.clear();
        haas_lpf_l_.reset();  haas_lpf_r_.reset();
        haas_lfo_phase_ = 0.0f;
        smooth_haas_depth_ = haas_depth_;

        // VHS
        vhs_line_l_.clear(); vhs_line_r_.clear();
        vhs_cross_lpf_l_.reset(); vhs_cross_lpf_r_.reset();
        vhs_damp_state_l_ = 0.0f; vhs_damp_state_r_ = 0.0f;
        vhs_beta_ = 0.25f;
        smooth_vhs_wet_ = current_vhs_wet();

        // Matrix
        for (auto &src : matrix_sources_) src.reset();
        for (auto &ap : quad_chain_la_) ap.reset();
        for (auto &ap : quad_chain_lb_) ap.reset();
        for (auto &ap : quad_chain_ra_) ap.reset();
        for (auto &ap : quad_chain_rb_) ap.reset();
        center_hp_.reset(); center_lp_.reset(); lfe_lpf_.reset();
        rear_line_l_.clear(); rear_line_r_.clear();
        smooth_center_focus_ = center_focus_;
        smooth_surround_boost_ = surround_boost_;

        anti_pop_ = 0.0f;
    }

    // ---------------- Processing ----------------

    // Interleaved stereo in-place: [L0, R0, L1, R1, ...]
    void process(float *interleaved, uint32_t frame_count)
    {
        if (!enabled_ || frame_count == 0 || !interleaved) return;
        if (mode_ == SurroundMode::Off) return;

        if (need_filter_update_) {
            updateFilters();
            need_filter_update_ = false;
        }

        switch (mode_) {
            case SurroundMode::FieldExpander:   processField(interleaved, frame_count); break;
            case SurroundMode::DifferentialHaas: processHaas(interleaved, frame_count); break;
            case SurroundMode::ViperHeadphone:  processVhs(interleaved, frame_count); break;
            case SurroundMode::Matrix51Hrtf:    processMatrix(interleaved, frame_count); break;
            default: break;
        }

        // Anti-pop fade-in when first engaged.
        if (anti_pop_ < 1.0f) {
            anti_pop_ = std::min(1.0f, anti_pop_ + (1.0f / sample_rate_) * 200.0f); // ~5 ms ramp
            const float k = anti_pop_;
            for (uint32_t i = 0; i < frame_count; ++i) {
                interleaved[2 * i]     *= k;
                interleaved[2 * i + 1] *= k;
            }
        }
    }

private:
    static float clampf(float v, float lo, float hi) { return std::clamp(v, lo, hi); }
    static int clampi(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }

    bool enabled_ = false;
    SurroundMode mode_ = SurroundMode::Off;
    float sample_rate_ = 0.0f; // forces first setSampleRate() to fully initialize
    float smoothing_coeff_ = 0.001f;
    bool need_filter_update_ = false;
    float anti_pop_ = 1.0f;

    // Parameters
    float field_width_ = 1.4f;
    float field_crossover_hz_ = 160.0f;
    float field_diffuser_mix_ = 0.5f;
    float bass_anchor_ = 0.9f;

    float haas_delay_ms_ = 5.5f;
    float haas_depth_ = 0.4f;
    float haas_damping_hz_ = 5000.0f;

    int vhs_room_preset_ = 2;
    float vhs_reflection_gain_ = 0.45f;
    float vhs_damping_ = 0.25f;

    float center_focus_ = 0.6f;
    float surround_boost_ = 1.2f;
    float surround_delay_ms_ = 15.0f;
    float head_radius_cm_ = 8.75f;

    // Smoothed values
    float smooth_width_ = 1.4f;
    float smooth_diff_mix_ = 0.5f;
    float smooth_bass_anchor_ = 0.9f;
    float smooth_haas_depth_ = 0.4f;
    float smooth_vhs_wet_ = 0.4f;
    float smooth_center_focus_ = 0.6f;
    float smooth_surround_boost_ = 1.2f;

    // ---- Field Expander state ----
    SurroundBiquad field_lp_[2];   // cascaded Butterworth LP on Side
    SurroundBiquad field_hp_[2];   // complementary HP on Side
    SurroundDiffuserAP field_ap1_, field_ap2_;

    // ---- Haas state ----
    SurroundDelay haas_line_l_, haas_line_r_;
    SurroundBiquad haas_lpf_l_, haas_lpf_r_;
    float haas_lfo_phase_ = 0.0f;

    // ---- VHS state ----
    SurroundDelay vhs_line_l_, vhs_line_r_;
    SurroundBiquad vhs_cross_lpf_l_, vhs_cross_lpf_r_;
    float vhs_damp_state_l_ = 0.0f, vhs_damp_state_r_ = 0.0f;
    float vhs_beta_ = 0.25f;

    // Reflection tap spec (@48 kHz reference)
    static constexpr int VHS_TAPS = 6;
    static constexpr float vhs_tap_ms[VHS_TAPS] = {1.7f, 3.4f, 6.1f, 8.9f, 12.3f, 16.7f};
    static constexpr float vhs_tap_gain[VHS_TAPS] = {0.220f, -0.180f, 0.140f, -0.110f, 0.085f, 0.060f};

    // ---- Matrix 5.1 state ----
    HrtfSource matrix_sources_[5];   // C, L, R, Ls, Rs
    SurroundAllpass1 quad_chain_la_[3], quad_chain_ra_[3];
    SurroundAllpass1 quad_chain_lb_[3], quad_chain_rb_[3];
    SurroundBiquad center_hp_, center_lp_, lfe_lpf_;
    SurroundDelay rear_line_l_, rear_line_r_;

    // Steiglitz wideband +/-45 deg quadrature approximation of the 90 deg pair
    // (~90 deg +/- small error across the audible band).
    static constexpr float quad_coeffs_a[3] = {0.479400865589f, 0.876218493539f, 0.976597589508f};
    static constexpr float quad_coeffs_b[3] = {0.6923878f, 0.9360654322959f, 0.98822952f};

    // ------------------------------------------------------------------

    float srScale() const { return sample_rate_ / 48000.0f; }

    float current_vhs_wet() const
    {
        constexpr float mixes[5] = {0.25f, 0.40f, 0.55f, 0.70f, 0.85f};
        return mixes[clampi(vhs_room_preset_ - 1, 0, 4)];
    }

    float current_vhs_delay_scale() const
    {
        constexpr float scales[5] = {0.65f, 1.00f, 1.40f, 1.85f, 2.40f};
        const int i0 = clampi(vhs_room_preset_ - 1, 0, 4);
        return scales[i0];
    }

    void buildDelayLines()
    {
        const uint32_t n = static_cast<uint32_t>(sample_rate_);

        // Haas: 25 ms base + 0.6 ms LFO swing + margin
        haas_line_l_.init(n / 1000u * 26u + 64u);
        haas_line_r_.init(n / 1000u * 26u + 64u);

        // VHS: longest reflection 16.7 ms * max scale 2.4 = ~41 ms
        vhs_line_l_.init(static_cast<uint32_t>(0.041f * n) + 64u);
        vhs_line_r_.init(static_cast<uint32_t>(0.041f * n) + 64u);

        // Rear channel delay up to 30 ms
        rear_line_l_.init(static_cast<uint32_t>(0.031f * n) + 64u);
        rear_line_r_.init(static_cast<uint32_t>(0.031f * n) + 64u);

        const float scale = srScale();
        field_ap1_.init(2.1f * 0.001f * 48000.0f, scale);  // 101 samples @48k ref
        field_ap2_.init(4.7f * 0.001f * 48000.0f, scale);  // 226 samples @48k ref

        // HRTF ITD lines are allocated lazily inside HrtfSource.
    }

    void reconfigureHrtf()
    {
        // ITU-R BS.775 virtual speaker placement (azimuth, elevation, gain)
        matrix_sources_[0].configure(0.0f, 0.0f, head_radius_cm_, 1.0f, sample_rate_);    // Center
        matrix_sources_[1].configure(-30.0f, 0.0f, head_radius_cm_, 1.0f, sample_rate_);  // Front Left
        matrix_sources_[2].configure(+30.0f, 0.0f, head_radius_cm_, 1.0f, sample_rate_);  // Front Right
        matrix_sources_[3].configure(-110.0f, 10.0f, head_radius_cm_, 1.0f, sample_rate_);// Surround Left
        matrix_sources_[4].configure(+110.0f, 10.0f, head_radius_cm_, 1.0f, sample_rate_);// Surround Right
    }

    void updateFilters()
    {
        const double fs = static_cast<double>(sample_rate_);

        // Field LR2 crossover (two cascaded Butterworth sections each way)
        for (int k = 0; k < 2; ++k) {
            surround_set_lowpass(field_lp_[k], fs, field_crossover_hz_, 0.7071);
            surround_set_highpass(field_hp_[k], fs, field_crossover_hz_, 0.7071);
        }

        // Haas damping LPF
        surround_set_lowpass(haas_lpf_l_, fs, haas_damping_hz_, 0.7071);
        surround_set_lowpass(haas_lpf_r_, fs, haas_damping_hz_, 0.7071);

        // VHS crossfeed shadow LPF (fixed 3200 Hz, Butterworth)
        surround_set_lowpass(vhs_cross_lpf_l_, fs, 3200.0, 0.7071);
        surround_set_lowpass(vhs_cross_lpf_r_, fs, 3200.0, 0.7071);

        // Matrix center band-pass (200 Hz .. 4500 Hz) & LFE LPF (80 Hz)
        surround_set_highpass(center_hp_, fs, 200.0, 0.7071);
        surround_set_lowpass(center_lp_, fs, 4500.0, 0.7071);
        surround_set_lowpass(lfe_lpf_, fs, 80.0, 0.7071);

        // VHS air-damping one-pole coefficient (wall absorption)
        vhs_beta_ = clampf(0.25f + 0.45f * vhs_damping_, 0.0f, 0.9f);
    }

    // --------------------------------------------------------------
    // Mode 1: Frequency-Split Field Surround
    // --------------------------------------------------------------
    void processField(float *s, uint32_t frames)
    {
        const float inv_sqrt2 = 0.70710678f;

        for (uint32_t i = 0; i < frames; ++i) {
            smooth_width_       += smoothing_coeff_ * (field_width_ - smooth_width_);
            smooth_diff_mix_    += smoothing_coeff_ * (field_diffuser_mix_ - smooth_diff_mix_);
            smooth_bass_anchor_ += smoothing_coeff_ * (bass_anchor_ - smooth_bass_anchor_);

            const float l = s[2 * i];
            const float r = s[2 * i + 1];

            // Blumlein M/S transform (energy-preserving scaling)
            const float m = (l + r) * inv_sqrt2;
            float side = (l - r) * inv_sqrt2;

            // Split side into low/high bands (LR2 crossover)
            float s_lo = side;
            float s_hi = side;
            for (int k = 0; k < 2; ++k) {
                s_lo = field_lp_[k].process(s_lo);
                s_hi = field_hp_[k].process(s_hi);
            }

            // Bass anchoring: collapse low-side energy toward mono
            s_lo *= (1.0f - smooth_bass_anchor_);

            // Diffuse high side through two cascaded all-pass decorrelators
            const float diffused = field_ap2_.process(field_ap1_.process(s_hi));
            const float s_high_processed =
                ((1.0f - smooth_diff_mix_) * s_hi + smooth_diff_mix_ * diffused) * smooth_width_;

            const float s_proc = s_lo + s_high_processed;

            // Inverse M/S synthesis
            s[2 * i]     = surround_sanitize((m + s_proc) * inv_sqrt2);
            s[2 * i + 1] = surround_sanitize((m - s_proc) * inv_sqrt2);
        }
    }

    // --------------------------------------------------------------
    // Mode 2: Differential Haas Spatializer
    // --------------------------------------------------------------
    void processHaas(float *s, uint32_t frames)
    {
        const float lfo_inc = 0.2f / sample_rate_; // 0.2 Hz
        const float max_delay = haas_line_l_.maxDelay();
        const float lfo_depth = std::min(0.3f * 0.001f * 48000.0f * srScale(), max_delay - 2.0f);

        for (uint32_t i = 0; i < frames; ++i) {
            smooth_haas_depth_ += smoothing_coeff_ * (haas_depth_ - smooth_haas_depth_);
            const float alpha = smooth_haas_depth_;

            haas_lfo_phase_ += lfo_inc;
            if (haas_lfo_phase_ >= 1.0f) haas_lfo_phase_ -= 1.0f;
            const float lfo = std::sin(haas_lfo_phase_ * 6.2831853f) * lfo_depth;

            const float l = s[2 * i];
            const float r = s[2 * i + 1];

            const float d_ms = haas_delay_ms_;
            float delay_samples = d_ms * 0.001f * 48000.0f * srScale() + lfo;
            delay_samples = std::clamp(delay_samples, 1.0f, max_delay);

            // Cross-injection with precedence delay + damping LPF
            const float rd = haas_lpf_l_.process(haas_line_r_.pushAndRead(delay_samples, r));
            const float ld = haas_lpf_r_.process(haas_line_l_.pushAndRead(delay_samples, l));

            // RMS energy compensation for uncorrelated addition
            const float gnorm = 1.0f / std::sqrt(1.0f + alpha * alpha);

            s[2 * i]     = surround_sanitize((l - alpha * rd) * gnorm);
            s[2 * i + 1] = surround_sanitize((r - alpha * ld) * gnorm);
        }
    }

    // --------------------------------------------------------------
    // Mode 3: ViPER Headphone Surround+ (VHS+)
    // --------------------------------------------------------------
    void processVhs(float *s, uint32_t frames)
    {
        const float scale = current_vhs_delay_scale() * srScale();
        const float cross_gain = 0.35f;
        const float cross_delay = 13.5f * srScale();
        const float damp_a = 1.0f - vhs_beta_;

        for (uint32_t i = 0; i < frames; ++i) {
            const float target_wet = current_vhs_wet();
            smooth_vhs_wet_ += smoothing_coeff_ * (target_wet - smooth_vhs_wet_);
            const float refl_gain = smooth_vhs_wet_ * vhs_reflection_gain_;

            const float l = s[2 * i];
            const float r = s[2 * i + 1];

            // Push into room delay lines
            vhs_line_l_.push(l);
            vhs_line_r_.push(r);

            // Head-shadowed crossfeed
            const float l_cross = vhs_cross_lpf_l_.process(vhs_line_r_.read(cross_delay)) * cross_gain;
            const float r_cross = vhs_cross_lpf_r_.process(vhs_line_l_.read(cross_delay)) * cross_gain;

            // 6-tap early reflection matrix with air damping
            float early_l = 0.0f, early_r = 0.0f;
            for (int k = 0; k < VHS_TAPS; ++k) {
                const float d = vhs_tap_ms[k] * 0.001f * 48000.0f * scale;
                early_l += vhs_tap_gain[k] * vhs_line_l_.read(d);
                early_r += vhs_tap_gain[k] * vhs_line_r_.read(d);
            }
            // One-pole HF air damping on reflections
            vhs_damp_state_l_ = damp_a * early_l + vhs_beta_ * vhs_damp_state_l_;
            vhs_damp_state_r_ = damp_a * early_r + vhs_beta_ * vhs_damp_state_r_;
            early_l = surround_sanitize(vhs_damp_state_l_);
            early_r = surround_sanitize(vhs_damp_state_r_);

            s[2 * i]     = surround_sanitize(l + refl_gain * (l_cross + early_l));
            s[2 * i + 1] = surround_sanitize(r + refl_gain * (r_cross + early_r));
        }
    }

    // --------------------------------------------------------------
    // Mode 4: Matrix 5.1 Dematrix -> Binaural HRTF Virtualizer
    // --------------------------------------------------------------
    void processMatrix(float *s, uint32_t frames)
    {
        for (uint32_t i = 0; i < frames; ++i) {
            smooth_center_focus_   += smoothing_coeff_ * (center_focus_ - smooth_center_focus_);
            smooth_surround_boost_ += smoothing_coeff_ * (surround_boost_ - smooth_surround_boost_);

            const float l_in = s[2 * i];
            const float r_in = s[2 * i + 1];

            // --- Quadrature networks (wideband 90-degree pairs) ---
            float ql_l = l_in, qr_l = l_in;
            float ql_r = r_in, qr_r = r_in;
            for (int k = 0; k < 3; ++k) {
                ql_l = quad_chain_la_[k].process(ql_l);
                qr_l = quad_chain_rb_[k].process(qr_l);
                ql_r = quad_chain_lb_[k].process(ql_r);
                qr_r = quad_chain_ra_[k].process(qr_r);
            }

            // Passive-matrix surrounds: difference signal, opposite polarity Ls/Rs
            const float q = (ql_l - qr_r);           // H+{L} - H-{R}
            const float rear_delay_samples = surround_delay_ms_ * 0.001f * 48000.0f * srScale();
            const float ls = rear_line_l_.pushAndRead(rear_delay_samples, +q);
            const float rs = rear_line_r_.pushAndRead(rear_delay_samples, -q);

            // --- Center & LFE ---
            const float mono = (l_in + r_in) * 0.5f;
            const float c_band = center_lp_.process(center_hp_.process(mono * 1.41421356f));
            const float c = c_band * smooth_center_focus_;
            const float lfe = lfe_lpf_.process(mono);

            // Front channels: subtract proportional center to avoid vocal doubling
            const float fl = l_in - 0.5f * c;
            const float fr = r_in - 0.5f * c;

            // --- Binaural render through parametric HRTF ---
            float out_l = 0.0f, out_r = 0.0f;
            matrix_sources_[0].process(c,  0.55f * (0.4f + 0.6f * smooth_center_focus_), out_l, out_r); // C @ 0deg
            matrix_sources_[1].process(fl, 0.62f, out_l, out_r);                                        // L @ -30deg
            matrix_sources_[2].process(fr, 0.62f, out_l, out_r);                                        // R @ +30deg
            const float rb = 0.55f * smooth_surround_boost_;
            matrix_sources_[3].process(ls, rb, out_l, out_r);                                           // Ls @ -110deg
            matrix_sources_[4].process(rs, rb, out_l, out_r);                                           // Rs @ +110deg

            // LFE: non-directional dual-mono sum
            const float lfe_out = 0.5f * lfe;
            out_l += lfe_out;
            out_r += lfe_out;

            s[2 * i]     = surround_sanitize(out_l * 1.10f);
            s[2 * i + 1] = surround_sanitize(out_r * 1.10f);
        }
    }
};

} // namespace sauti::dsp
