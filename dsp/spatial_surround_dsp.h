#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <vector>

// =============================================================================
// SpatialSurroundDSP: Professional Zero-Latency Surround & 3D Spatial Suite
//
// 1. Cinema Matrix 5.1 (Cleanroom Pro Logic II Dematrix -> Binaural Spherical HRTF)
//    - Passive 90-degree quadrature steering networks
//    - Center dialogue focus extraction & LFE channel isolation
//    - Parametric spherical-head HRTF rendering for 5 virtual speaker positions
//
// 2. Binaural HRTF Virtualizer (Reconstructed from Dolby analysis_dlby2)
//    - Headphone HRTF: Contralateral interaural time delay (ITD) buffer
//      (~11 samples @ 48 kHz / 0.23 ms) + 2nd-order Butterworth 3.5 kHz
//      head-shadow lowpass + crossfeed phase cancellation
//    - Multi-Room Acoustic Modeling: 4-tap vector delay lines with early reflection
//      diffusion for Studio (DH1), Cinema (DH2), and Concert Hall (DH3)
//    - Speaker Virtualizer (Dolby Virtual Speaker): Mid/Side soundfield widening,
//      speaker spread angles (Narrow 10 deg, Standard 30 deg, Wide 45 deg),
//      and all-pass decorrelation
//
// 3. 3D Acoustic Stage (Reconstructed from AM3D Zirene re_workspace)
//    - 3D Virtual Surround (0x1356d8 / Category 3): Interaural acoustic cross-talk
//      cancellation for Normal/Studio (D=25000, alpha=0.28) and Wide/Panoramic
//      (D=10000, alpha=0.42) soundstage apertures
//    - Stereo Soundstage Expander (Category 12): Independent 2D soundstage width
//      (0..200%) and depth (0..100%) expansion with cross-channel bleed
//    - High-Frequency Air Presence Contour (Category 11): High-shelf spatial air
//      restoration filter
//    - Sub-bass Fundamental Anchor (Category 13): Low-frequency center mono anchor
//      (20..120 Hz) preventing bass phase cancellation
//
// All modes process interleaved 32-bit float stereo in-place with zero algorithmic
// latency, click-free parameter smoothing, and denormal clamping.
// =============================================================================

namespace sauti::dsp {

enum class SurroundMode {
    Off = 0,
    MatrixSurround = 1,      // Retained Pro Logic II Dematrix -> 5.1 Spherical HRTF
    BinauralVirtualizer = 2, // Reconstructed from analysis_dlby2 (Headphone HRTF + Speaker Virtualizer + Room)
    AcousticStage = 3        // Reconstructed from am3d-zirene-RE (Cross-talk cancellation + M/S Expander + Air Contour)
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

// RBJ peaking EQ
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
inline void surround_set_lowpass(SurroundBiquad &bq, double fs, double f0, double Q = 0.7071)
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

inline void surround_set_highpass(SurroundBiquad &bq, double fs, double f0, double Q = 0.7071)
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

// RBJ high-shelf filter for air presence contouring
inline void surround_set_highshelf(SurroundBiquad &bq, double fs, double f0, double gain_db, double S = 1.0)
{
    constexpr double PI = 3.14159265358979323846;
    double w0 = 2.0 * PI * f0 / fs;
    if (w0 > PI * 0.95) w0 = PI * 0.95;
    if (w0 < 1.0e-4) w0 = 1.0e-4;
    const double A = std::pow(10.0, gain_db / 40.0);
    const double cw = std::cos(w0);
    const double sw = std::sin(w0);
    const double alpha = sw / 2.0 * std::sqrt((A + 1.0 / A) * (1.0 / S - 1.0) + 2.0);
    const double two_sqrt_A_alpha = 2.0 * std::sqrt(A) * alpha;

    const double a0 = (A + 1.0) - (A - 1.0) * cw + two_sqrt_A_alpha;
    bq.b0 = static_cast<float>((A * ((A + 1.0) + (A - 1.0) * cw + two_sqrt_A_alpha)) / a0);
    bq.b1 = static_cast<float>((-2.0 * A * ((A - 1.0) + (A + 1.0) * cw)) / a0);
    bq.b2 = static_cast<float>((A * ((A + 1.0) + (A - 1.0) * cw - two_sqrt_A_alpha)) / a0);
    bq.a1 = static_cast<float>((2.0 * ((A - 1.0) - (A + 1.0) * cw)) / a0);
    bq.a2 = static_cast<float>(((A + 1.0) - (A - 1.0) * cw - two_sqrt_A_alpha) / a0);
}

// First-order head-shadow shelf (Brown & Duda structural HRTF)
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

// Fractional delay line with linear interpolation
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

    inline float pushAndRead(float d, float x)
    {
        buf[w] = x;
        const uint32_t n = static_cast<uint32_t>(buf.size());
        float di = d; if (di < 1.0f) di = 1.0f;
        if (di > maxDelay()) di = maxDelay();
        const uint32_t i0 = static_cast<uint32_t>(di);
        const float frac = di - static_cast<float>(i0);
        const uint32_t r0 = (w + n - i0) % n;
        const uint32_t r1 = (r0 + n - 1) % n;
        w = (w + 1) % n;
        return buf[r0] + frac * (buf[r1] - buf[r0]);
    }

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

// Cascaded first-order all-pass (quadrature phase networks)
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

// Schroeder-style all-pass diffuser with delay D
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
// Parametric spherical-head HRTF source (used for Pro Logic II 5.1 binauralization)
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

        if (!delay_.buf.empty() && last_radius_ != head_radius_cm_) {
            delay_.init(128);
        } else if (delay_.buf.empty()) {
            delay_.init(128);
        }
        last_radius_ = head_radius_cm_;
    }

    void reset()
    {
        shelf_ipsi_.reset();
        shelf_contra_.reset();
        pinna_ipsi_.reset();
        pinna_contra_.reset();
        delay_.clear();
    }

    inline void process(float in, float gain, float &out_l, float &out_r)
    {
        const float s = in * gain;
        float s_contra = delay_.pushAndRead(itd_samples_, s);

        float ipsi   = pinna_ipsi_.process(shelf_ipsi_.process(s));
        float contra = pinna_contra_.process(shelf_contra_.process(s_contra));

        if (azimuth_ >= 0.0f) {
            // Source on the right
            out_r += ipsi;
            out_l += contra;
        } else {
            // Source on the left
            out_l += ipsi;
            out_r += contra;
        }
    }

private:
    void update()
    {
        constexpr double PI = 3.14159265358979323846;
        constexpr double C_SOUND = 343.0; // m/s

        const double theta = std::fabs(azimuth_) * (PI / 180.0);
        const double a = head_radius_cm_ * 0.01;
        const double T = 1.0 / sample_rate_;
        const double tau0 = a / C_SOUND;

        const double alpha_ipsi   = 1.0 + 0.5 * std::cos(theta);
        const double alpha_contra = 1.0 - 0.5 * std::cos(theta);
        shelf_ipsi_.setShadow(alpha_ipsi, tau0, T);
        shelf_contra_.setShadow(alpha_contra, tau0, T);

        const double delta_t = (a / C_SOUND) * (theta + std::sin(theta));
        itd_samples_ = static_cast<float>(std::max(1.0, delta_t * sample_rate_));

        const double f_pinna = 6500.0 + 3500.0 * (elevation_ / 90.0);
        const double notch_gain_db = -4.0 * pinna_strength_;
        surround_set_peaking(pinna_ipsi_, sample_rate_, f_pinna, 3.0, notch_gain_db);
        surround_set_peaking(pinna_contra_, sample_rate_, f_pinna * 0.92, 2.5, notch_gain_db * 0.7);
    }

    float sample_rate_ = 48000.0f;
    float azimuth_ = 0.0f;
    float elevation_ = 0.0f;
    float pinna_strength_ = 0.7f;
    float head_radius_cm_ = 8.75f;
    float last_radius_ = 0.0f;
    float itd_samples_ = 1.0f;

    SurroundShelf1 shelf_ipsi_, shelf_contra_;
    SurroundBiquad pinna_ipsi_, pinna_contra_;
    SurroundDelay  delay_;
};

// =============================================================================
// SpatialSurroundDSP Engine Class
// =============================================================================
class SpatialSurroundDSP {
public:
    SpatialSurroundDSP()
    {
        setSampleRate(48000.0f);
    }

    void setSampleRate(float sample_rate)
    {
        if (sample_rate <= 0.0f) sample_rate = 48000.0f;
        if (std::fabs(sample_rate_ - sample_rate) < 1.0f) return;

        sample_rate_ = sample_rate;
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

    // --- Mode 1: Cinema Matrix 5.1 Parameters ---
    void setCenterFocus(float focus)         { center_focus_ = clampf(focus, 0.0f, 1.0f); }
    void setSurroundBoost(float boost)       { surround_boost_ = clampf(boost, 0.0f, 2.0f); }
    void setSurroundDelayMs(float ms)        { surround_delay_ms_ = clampf(ms, 5.0f, 30.0f); }
    void setHeadRadiusCm(float cm)           { head_radius_cm_ = clampf(cm, 6.0f, 12.0f); reconfigureHrtf(); }

    // --- Mode 2: Binaural HRTF Virtualizer Parameters (from analysis_dlby2) ---
    void setBinauralMode(int mode)           { binaural_mode_ = clampi(mode, 0, 1); } // 0=Headphone HRTF, 1=Speaker Field
    void setBinauralBoost(float boost)       { binaural_boost_ = clampf(boost, 0.0f, 1.0f); }
    void setBinauralRoomPreset(int preset)   { binaural_room_preset_ = clampi(preset, 1, 3); updateRoomDelays(); }
    void setBinauralRoomMix(float mix)       { binaural_room_mix_ = clampf(mix, 0.0f, 1.0f); }
    void setBinauralSpeakerAngle(int angle)  { binaural_speaker_angle_ = clampi(angle, 0, 2); } // 0=Narrow (10), 1=Standard (30), 2=Wide (45)
    void setBinauralShadowCutoff(float hz)   { binaural_shadow_cutoff_ = clampf(hz, 2000.0f, 6000.0f); need_filter_update_ = true; }

    // --- Mode 3: 3D Acoustic Stage Parameters (from am3d-zirene-RE) ---
    void setStageProfile(int profile)        { stage_profile_ = clampi(profile, 0, 1); } // 0=Headset, 1=Speaker
    void setStageMode(int mode)              { stage_mode_ = clampi(mode, 0, 1); } // 0=Studio (Normal), 1=Panoramic (Wide)
    void setStageWidth(float width)          { stage_width_ = clampf(width, 0.0f, 2.0f); }
    void setStageDepth(float depth)          { stage_depth_ = clampf(depth, 0.0f, 1.0f); }
    void setStageCancellation(float c)       { stage_cancellation_ = clampf(c, 0.0f, 1.0f); }
    void setStageAirPresence(float air)      { stage_air_presence_ = clampf(air, 0.0f, 1.0f); need_filter_update_ = true; }
    void setStageBassAnchorHz(float hz)      { stage_bass_anchor_hz_ = clampf(hz, 20.0f, 120.0f); need_filter_update_ = true; }

    // Unified / compatibility getters
    float getSampleRate() const              { return sample_rate_; }
    float getCenterFocus() const             { return center_focus_; }
    float getSurroundBoost() const           { return surround_boost_; }
    float getSurroundDelayMs() const         { return surround_delay_ms_; }
    float getHeadRadiusCm() const            { return head_radius_cm_; }

    int   getBinauralMode() const            { return binaural_mode_; }
    float getBinauralBoost() const           { return binaural_boost_; }
    int   getBinauralRoomPreset() const      { return binaural_room_preset_; }
    float getBinauralRoomMix() const         { return binaural_room_mix_; }
    int   getBinauralSpeakerAngle() const    { return binaural_speaker_angle_; }
    float getBinauralShadowCutoff() const    { return binaural_shadow_cutoff_; }

    int   getStageProfile() const            { return stage_profile_; }
    int   getStageMode() const               { return stage_mode_; }
    float getStageWidth() const              { return stage_width_; }
    float getStageDepth() const              { return stage_depth_; }
    float getStageCancellation() const       { return stage_cancellation_; }
    float getStageAirPresence() const        { return stage_air_presence_; }
    float getStageBassAnchorHz() const       { return stage_bass_anchor_hz_; }

    // ---------------- State Reset ----------------
    void reset()
    {
        // Cinema Matrix
        for (auto &src : matrix_sources_) src.reset();
        for (auto &ap : quad_chain_la_) ap.reset();
        for (auto &ap : quad_chain_lb_) ap.reset();
        for (auto &ap : quad_chain_ra_) ap.reset();
        for (auto &ap : quad_chain_rb_) ap.reset();
        center_hp_.reset(); center_lp_.reset(); lfe_lpf_.reset();
        rear_line_l_.clear(); rear_line_r_.clear();

        // Binaural Virtualizer
        binaural_itd_l_.clear(); binaural_itd_r_.clear();
        binaural_shadow_l_.reset(); binaural_shadow_r_.reset();
        for (int i = 0; i < 4; ++i) {
            binaural_room_delays_[i].clear();
        }
        binaural_diffuser_l_.reset(); binaural_diffuser_r_.reset();
        binaural_reverb_state_l_ = 0.0f;
        binaural_reverb_state_r_ = 0.0f;

        // 3D Acoustic Stage
        stage_air_l_.reset(); stage_air_r_.reset();
        stage_bass_lp_.reset();
        stage_bass_hp_l_.reset(); stage_bass_hp_r_.reset();

        // Parameter smoothing state
        smooth_center_focus_   = center_focus_;
        smooth_surround_boost_ = surround_boost_;
        smooth_binaural_boost_ = binaural_boost_;
        smooth_binaural_room_  = binaural_room_mix_;
        smooth_stage_width_    = stage_width_;
        smooth_stage_depth_    = stage_depth_;
        smooth_stage_cancel_   = stage_cancellation_;

        anti_pop_ = 0.0f;
    }

    // ---------------- Processing ----------------
    void process(float *interleaved, uint32_t frame_count)
    {
        if (!enabled_ || frame_count == 0 || !interleaved) return;
        if (mode_ == SurroundMode::Off) return;

        if (need_filter_update_) {
            updateFilters();
            need_filter_update_ = false;
        }

        switch (mode_) {
            case SurroundMode::MatrixSurround:
                processMatrix(interleaved, frame_count);
                break;
            case SurroundMode::BinauralVirtualizer:
                processBinaural(interleaved, frame_count);
                break;
            case SurroundMode::AcousticStage:
                processStage(interleaved, frame_count);
                break;
            default:
                break;
        }

        // Anti-pop fade-in when first engaged (~50 ms per-sample ramp)
        if (anti_pop_ < 1.0f) {
            const float inc = 20.0f / sample_rate_;
            const uint32_t n = frame_count * 2u;
            for (uint32_t i = 0; i < n; ++i) {
                interleaved[i] *= anti_pop_;
                anti_pop_ = std::min(1.0f, anti_pop_ + inc);
            }
        }
    }

private:
    static float clampf(float v, float lo, float hi) { return std::clamp(v, lo, hi); }
    static int clampi(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }
    float srScale() const { return sample_rate_ / 48000.0f; }

    // -------------------------------------------------------------------------
    // Mode 1: Cinema Matrix 5.1 (Dolby Pro Logic II Cleanroom)
    // -------------------------------------------------------------------------
    void processMatrix(float *s, uint32_t frames)
    {
        for (uint32_t i = 0; i < frames; ++i) {
            smooth_center_focus_   += smoothing_coeff_ * (center_focus_ - smooth_center_focus_);
            smooth_surround_boost_ += smoothing_coeff_ * (surround_boost_ - smooth_surround_boost_);

            const float l_in = s[2 * i];
            const float r_in = s[2 * i + 1];

            // Quadrature networks (wideband 90-degree pairs)
            float ql_l = l_in, qr_l = l_in;
            float ql_r = r_in, qr_r = r_in;
            for (int k = 0; k < 3; ++k) {
                ql_l = quad_chain_la_[k].process(ql_l);
                qr_l = quad_chain_rb_[k].process(qr_l);
                ql_r = quad_chain_lb_[k].process(ql_r);
                qr_r = quad_chain_ra_[k].process(qr_r);
            }

            // Passive-matrix surrounds: difference signal, opposite polarity Ls/Rs
            const float q = (ql_l - qr_r);
            const float rear_delay_samples = surround_delay_ms_ * 0.001f * sample_rate_;
            const float ls = rear_line_l_.pushAndRead(rear_delay_samples, +q);
            const float rs = rear_line_r_.pushAndRead(rear_delay_samples, -q);

            // Center dialogue & LFE isolation
            const float mono = (l_in + r_in) * 0.5f;
            const float c_band = center_lp_.process(center_hp_.process(mono * 1.41421356f));
            const float c = c_band * smooth_center_focus_;
            const float lfe = lfe_lpf_.process(mono);

            // Front channels: subtract center to maintain vocal separation
            const float fl = l_in - 0.5f * c;
            const float fr = r_in - 0.5f * c;

            // Render 5 virtual speaker positions through parametric HRTF
            float out_l = 0.0f, out_r = 0.0f;
            matrix_sources_[0].process(c,  0.55f * (0.4f + 0.6f * smooth_center_focus_), out_l, out_r); // Center @ 0 deg
            matrix_sources_[1].process(fl, 0.62f, out_l, out_r);                                        // Left @ -30 deg
            matrix_sources_[2].process(fr, 0.62f, out_l, out_r);                                        // Right @ +30 deg
            const float rb = 0.55f * smooth_surround_boost_;
            matrix_sources_[3].process(ls, rb, out_l, out_r);                                           // Left Surround @ -110 deg
            matrix_sources_[4].process(rs, rb, out_l, out_r);                                           // Right Surround @ +110 deg

            // Dual-mono LFE sum
            const float lfe_out = 0.5f * lfe;
            out_l += lfe_out;
            out_r += lfe_out;

            s[2 * i]     = surround_sanitize(out_l * 1.10f);
            s[2 * i + 1] = surround_sanitize(out_r * 1.10f);
        }
    }

    // -------------------------------------------------------------------------
    // Mode 2: Binaural HRTF Virtualizer (Reconstructed from analysis_dlby2)
    // -------------------------------------------------------------------------
    void processBinaural(float *s, uint32_t frames)
    {
        // ITD delay length scaled to current sample rate (~11 samples @ 48 kHz = 0.23 ms)
        const float itd_samples = std::max(1.0f, 11.0f * srScale());

        for (uint32_t i = 0; i < frames; ++i) {
            smooth_binaural_boost_ += smoothing_coeff_ * (binaural_boost_ - smooth_binaural_boost_);
            smooth_binaural_room_  += smoothing_coeff_ * (binaural_room_mix_ - smooth_binaural_room_);

            const float l_in = s[2 * i];
            const float r_in = s[2 * i + 1];

            float out_l = l_in;
            float out_r = r_in;

            if (binaural_mode_ == 0) {
                // --- Headphone HRTF Spatializer ---
                // Push into contralateral interaural delay lines
                const float del_r = binaural_itd_r_.pushAndRead(itd_samples, r_in);
                const float del_l = binaural_itd_l_.pushAndRead(itd_samples, l_in);

                // Contralateral head-shadow filter (2nd order Butterworth lowpass at 3.5 kHz)
                const float shadow_r = binaural_shadow_r_.process(del_r);
                const float shadow_l = binaural_shadow_l_.process(del_l);

                // Binaural crossfeed injection
                const float b = smooth_binaural_boost_;
                const float l_binaural = l_in * (1.0f - 0.20f * b) + shadow_r * (0.38f * b);
                const float r_binaural = r_in * (1.0f - 0.20f * b) + shadow_l * (0.38f * b);

                // Interaural phase cancellation (dlb_virtualizer.c)
                const float cross_gain = b * 0.35f;
                const float boost_gain = 1.0f + b * 0.25f;
                out_l = boost_gain * l_binaural - cross_gain * shadow_r;
                out_r = boost_gain * r_binaural - cross_gain * shadow_l;

                // Dolby Headphone 4-tap Room Acoustics Reverb (dh_reverb)
                if (smooth_binaural_room_ > 0.001f) {
                    float refl_l = 0.0f;
                    float refl_r = 0.0f;

                    // Push current frame into 4-tap vector delay lines
                    binaural_room_delays_[0].push(l_in);
                    binaural_room_delays_[1].push(r_in);
                    binaural_room_delays_[2].push(l_in + 0.5f * r_in);
                    binaural_room_delays_[3].push(r_in + 0.5f * l_in);

                    refl_l += 0.35f * binaural_room_delays_[0].read(room_delay_samples_[0]);
                    refl_l += 0.25f * binaural_room_delays_[2].read(room_delay_samples_[2]);
                    refl_r += 0.35f * binaural_room_delays_[1].read(room_delay_samples_[1]);
                    refl_r += 0.25f * binaural_room_delays_[3].read(room_delay_samples_[3]);

                    // One-pole HF air damping on reflections
                    const float damp_a = 0.70f;
                    const float damp_b = 0.30f;
                    binaural_reverb_state_l_ = damp_a * refl_l + damp_b * binaural_reverb_state_l_;
                    binaural_reverb_state_r_ = damp_a * refl_r + damp_b * binaural_reverb_state_r_;

                    const float room_wet = smooth_binaural_room_ * 0.45f;
                    out_l += room_wet * binaural_reverb_state_l_;
                    out_r += room_wet * binaural_reverb_state_r_;
                }
            } else {
                // --- Speaker Soundfield Virtualizer (Dolby Virtual Speaker dvs_*) ---
                const float b = smooth_binaural_boost_;

                // Speaker spread angle multiplier: Narrow (10 deg), Standard (30 deg), Wide (45 deg)
                float angle_mult = 1.4f;
                if (binaural_speaker_angle_ == 0) angle_mult = 0.9f;
                else if (binaural_speaker_angle_ == 2) angle_mult = 2.0f;

                const float mid  = 0.5f * (l_in + r_in);
                float side = 0.5f * (l_in - r_in);

                // Side band all-pass phase decorrelation (dvs_decorrelate / ngcs_diffuse)
                side = binaural_diffuser_l_.process(side);
                side *= (1.0f + b * angle_mult);

                // Speaker interaural cross-cancellation
                const float cross_gain = b * 0.45f;
                const float boost_gain = 1.0f + b * 0.35f;

                out_l = boost_gain * (mid + side) - cross_gain * r_in;
                out_r = boost_gain * (mid - side) - cross_gain * l_in;
            }

            s[2 * i]     = surround_sanitize(out_l);
            s[2 * i + 1] = surround_sanitize(out_r);
        }
    }

    // -------------------------------------------------------------------------
    // Mode 3: 3D Acoustic Stage (Reconstructed from am3d-zirene-RE)
    // -------------------------------------------------------------------------
    void processStage(float *s, uint32_t frames)
    {
        for (uint32_t i = 0; i < frames; ++i) {
            smooth_stage_width_  += smoothing_coeff_ * (stage_width_ - smooth_stage_width_);
            smooth_stage_depth_  += smoothing_coeff_ * (stage_depth_ - smooth_stage_depth_);
            smooth_stage_cancel_ += smoothing_coeff_ * (stage_cancellation_ - smooth_stage_cancel_);

            const float l_in = s[2 * i];
            const float r_in = s[2 * i + 1];

            // 1. Interaural Acoustic Cross-Talk Cancellation (zirene_dsp.c 0x1356d8)
            // Normal (Studio, D=25000): base alpha = 0.28. Wide (Panoramic, D=10000): base alpha = 0.42.
            const float base_alpha = (stage_mode_ == 1) ? 0.42f : 0.28f;
            const float cross_coeff = base_alpha * (0.4f + 0.9f * smooth_stage_cancel_);

            float l_stage = (1.0f + cross_coeff * 0.30f) * l_in - cross_coeff * r_in;
            float r_stage = (1.0f + cross_coeff * 0.30f) * r_in - cross_coeff * l_in;

            // 2. Stereo Soundstage Expander (Category 12)
            const float width_factor = smooth_stage_width_;
            const float depth_cross  = 0.12f * smooth_stage_depth_;

            const float mid  = 0.5f * (l_stage + r_stage);
            const float side = 0.5f * (l_stage - r_stage) * width_factor;

            float out_l = mid + side - depth_cross * r_stage;
            float out_r = mid - side - depth_cross * l_stage;

            // 3. Sub-bass Fundamental Anchor (Category 13)
            // Low-pass mono anchor guarantees center punch and zero bass cancellation
            const float mono_raw = 0.5f * (l_in + r_in);
            const float anchor_bass = stage_bass_lp_.process(mono_raw);
            out_l = stage_bass_hp_l_.process(out_l) + anchor_bass;
            out_r = stage_bass_hp_r_.process(out_r) + anchor_bass;

            // 4. High-Frequency Air Presence Contour (Category 11)
            // Restores airy highs and spatial micro-dynamics
            out_l = stage_air_l_.process(out_l);
            out_r = stage_air_r_.process(out_r);

            s[2 * i]     = surround_sanitize(out_l);
            s[2 * i + 1] = surround_sanitize(out_r);
        }
    }

    // ---------------- Delay Lines & Filter Design ----------------
    void buildDelayLines()
    {
        const float sr_scale = srScale();

        // Matrix rear surrounds
        rear_line_l_.init(static_cast<uint32_t>(35.0f * 0.001f * sample_rate_) + 16u);
        rear_line_r_.init(static_cast<uint32_t>(35.0f * 0.001f * sample_rate_) + 16u);

        // Binaural Virtualizer ITD delay lines (up to ~64 samples)
        binaural_itd_l_.init(64);
        binaural_itd_r_.init(64);

        // Binaural Virtualizer Room 4-tap delay lines (delays ~8..35 ms)
        for (int i = 0; i < 4; ++i) {
            binaural_room_delays_[i].init(static_cast<uint32_t>(40.0f * 0.001f * sample_rate_) + 16u);
        }
        updateRoomDelays();

        // Speaker decorrelator diffuser
        binaural_diffuser_l_.init(14.0f, sr_scale);
        binaural_diffuser_r_.init(19.0f, sr_scale);
    }

    void updateRoomDelays()
    {
        // Delays for Studio (DH1), Cinema (DH2), and Concert Hall (DH3)
        // Reference delays in milliseconds
        float d_ms[4] = { 10.0f, 14.0f, 13.0f, 17.0f };
        if (binaural_room_preset_ == 1) {
            // Studio: tighter, shorter reflections
            d_ms[0] = 6.5f; d_ms[1] = 9.0f; d_ms[2] = 8.0f; d_ms[3] = 11.5f;
        } else if (binaural_room_preset_ == 3) {
            // Concert Hall: expansive reverberation
            d_ms[0] = 16.0f; d_ms[1] = 22.0f; d_ms[2] = 20.0f; d_ms[3] = 28.0f;
        }

        for (int i = 0; i < 4; ++i) {
            room_delay_samples_[i] = d_ms[i] * 0.001f * sample_rate_;
        }
    }

    void updateFilters()
    {
        const double fs = sample_rate_;

        // Matrix Pro Logic II center bandpass (200 Hz - 7000 Hz) & LFE (120 Hz)
        surround_set_highpass(center_hp_, fs, 200.0, 0.7071);
        surround_set_lowpass(center_lp_,  fs, 7000.0, 0.7071);
        surround_set_lowpass(lfe_lpf_,    fs, 120.0, 0.7071);

        // Binaural Virtualizer head-shadow lowpass filter (3500 Hz default)
        surround_set_lowpass(binaural_shadow_l_, fs, binaural_shadow_cutoff_, 0.7071);
        surround_set_lowpass(binaural_shadow_r_, fs, binaural_shadow_cutoff_, 0.7071);

        // 3D Acoustic Stage: Sub-bass Anchor (lowpass + highpass crossover)
        surround_set_lowpass(stage_bass_lp_, fs, stage_bass_anchor_hz_, 0.7071);
        surround_set_highpass(stage_bass_hp_l_, fs, stage_bass_anchor_hz_, 0.7071);
        surround_set_highpass(stage_bass_hp_r_, fs, stage_bass_anchor_hz_, 0.7071);

        // 3D Acoustic Stage: High-shelf Air Presence Contour (10 kHz, gain up to +4.5 dB)
        const double air_gain_db = stage_air_presence_ * 4.5;
        surround_set_highshelf(stage_air_l_, fs, 10000.0, air_gain_db);
        surround_set_highshelf(stage_air_r_, fs, 10000.0, air_gain_db);
    }

    void reconfigureHrtf()
    {
        // 5 virtual speaker positions for Cinema Matrix 5.1
        matrix_sources_[0].configure(   0.0f,  0.0f, head_radius_cm_, 0.5f, sample_rate_); // Center
        matrix_sources_[1].configure( -30.0f,  0.0f, head_radius_cm_, 0.7f, sample_rate_); // Left
        matrix_sources_[2].configure(  30.0f,  0.0f, head_radius_cm_, 0.7f, sample_rate_); // Right
        matrix_sources_[3].configure(-110.0f, 10.0f, head_radius_cm_, 0.8f, sample_rate_); // Left Surround
        matrix_sources_[4].configure( 110.0f, 10.0f, head_radius_cm_, 0.8f, sample_rate_); // Right Surround

        // 90-degree wideband quadrature ladder pole frequencies
        constexpr double pole_la[3] = { 43.5, 342.0, 3175.0 };
        constexpr double pole_lb[3] = { 128.0, 990.0, 8920.0 };

        for (int k = 0; k < 3; ++k) {
            const double w_la = 2.0 * 3.14159265358979323846 * pole_la[k] / sample_rate_;
            const double w_lb = 2.0 * 3.14159265358979323846 * pole_lb[k] / sample_rate_;
            quad_chain_la_[k].c = static_cast<float>((1.0 - std::tan(w_la / 2.0)) / (1.0 + std::tan(w_la / 2.0)));
            quad_chain_ra_[k].c = quad_chain_la_[k].c;
            quad_chain_lb_[k].c = static_cast<float>((1.0 - std::tan(w_lb / 2.0)) / (1.0 + std::tan(w_lb / 2.0)));
            quad_chain_rb_[k].c = quad_chain_lb_[k].c;
        }
    }

    // Engine Core State
    bool enabled_ = false;
    SurroundMode mode_ = SurroundMode::Off;
    float sample_rate_ = 0.0f;
    float smoothing_coeff_ = 0.001f;
    bool need_filter_update_ = false;
    float anti_pop_ = 1.0f;

    // --- Mode 1 Parameters ---
    float center_focus_ = 0.6f;
    float surround_boost_ = 1.2f;
    float surround_delay_ms_ = 15.0f;
    float head_radius_cm_ = 8.75f;

    // --- Mode 2 Parameters ---
    int   binaural_mode_ = 0;          // 0=Headphone HRTF, 1=Speaker Field
    float binaural_boost_ = 0.65f;     // 0.0 .. 1.0
    int   binaural_room_preset_ = 2;   // 1=Studio, 2=Cinema, 3=Concert Hall
    float binaural_room_mix_ = 0.35f;  // 0.0 .. 1.0
    int   binaural_speaker_angle_ = 1; // 0=Narrow (10 deg), 1=Standard (30 deg), 2=Wide (45 deg)
    float binaural_shadow_cutoff_ = 3500.0f;

    // --- Mode 3 Parameters ---
    int   stage_profile_ = 0;          // 0=Headset, 1=Speaker
    int   stage_mode_ = 0;             // 0=Studio (Normal), 1=Panoramic (Wide)
    float stage_width_ = 1.2f;         // 0.0 .. 2.0 (120%)
    float stage_depth_ = 0.5f;         // 0.0 .. 1.0 (50%)
    float stage_cancellation_ = 0.60f; // 0.0 .. 1.0
    float stage_air_presence_ = 0.40f; // 0.0 .. 1.0
    float stage_bass_anchor_hz_ = 60.0f;

    // Smoothers
    float smooth_center_focus_ = 0.6f;
    float smooth_surround_boost_ = 1.2f;
    float smooth_binaural_boost_ = 0.65f;
    float smooth_binaural_room_ = 0.35f;
    float smooth_stage_width_ = 1.2f;
    float smooth_stage_depth_ = 0.5f;
    float smooth_stage_cancel_ = 0.60f;

    // Mode 1: Cinema Matrix DSP Nodes
    HrtfSource matrix_sources_[5];
    SurroundAllpass1 quad_chain_la_[3], quad_chain_ra_[3];
    SurroundAllpass1 quad_chain_lb_[3], quad_chain_rb_[3];
    SurroundBiquad center_hp_, center_lp_, lfe_lpf_;
    SurroundDelay  rear_line_l_, rear_line_r_;

    // Mode 2: Binaural Virtualizer DSP Nodes
    SurroundDelay  binaural_itd_l_, binaural_itd_r_;
    SurroundBiquad binaural_shadow_l_, binaural_shadow_r_;
    SurroundDelay  binaural_room_delays_[4];
    float          room_delay_samples_[4] = { 480.0f, 672.0f, 624.0f, 816.0f };
    SurroundDiffuserAP binaural_diffuser_l_, binaural_diffuser_r_;
    float          binaural_reverb_state_l_ = 0.0f;
    float          binaural_reverb_state_r_ = 0.0f;

    // Mode 3: 3D Acoustic Stage DSP Nodes
    SurroundBiquad stage_air_l_, stage_air_r_;
    SurroundBiquad stage_bass_lp_;
    SurroundBiquad stage_bass_hp_l_, stage_bass_hp_r_;
};

} // namespace sauti::dsp
