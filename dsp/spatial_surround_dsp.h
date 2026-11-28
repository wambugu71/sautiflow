#pragma once

#include <cmath>
#include <cstdint>
#include <algorithm>
#include <vector>
#include "simd_math.h"
#include "cytomic_svf_dsp.h"
#include "sofa_hrtf_dsp.h"
#include "bass_management_dsp.h"

// =============================================================================
// SpatialSurroundDSP: Zero-Latency Surround & 3D Spatial Audio Suite
//
// 1. Cinema Matrix 5.1 (Active-Steered Dematrix -> Folded Spherical HRTF)
//    - LR4 120 Hz LFE crossover with unity dual-mono summing (zero bass bloat)
//    - Correlation-steered center focus extraction & L/R surround balance
//    - 4-stage Olli Niemitalo Hilbert 90-deg quadrature pair (+/- 0.7 deg)
//    - Folded Woodworth ITD + ear-axis Brown & Duda head-shadow + rear pinna cues
//
// 2. Binaural HRTF Virtualizer
//    - Headphone HRTF: Consistent contralateral ITD (0.26 ms) + 1st-order
//      diffraction head-shadow + diffuse-field baffle restoration + symmetric
//      6-tap diffused shoebox early reflections with SR-invariant air damping
//    - Speaker Field: Band-limited recursive crosstalk cancellation (RACE-style)
//      with speaker-angle propagation delays (10/30/45 deg) & adjustable LPF
//
// 3. 3D Acoustic Stage
//    - Headset vs Speaker transducer-aware spatialization (binaural externalizer
//      on Headset, band-limited delayed XTC on Speaker; 0% cancel = clean bypass)
//    - Constant-power soundstage width expansion & diffused early-reflection depth
//    - Unattenuated 64-bit Cytomic LR4 sub-bass anchor + de-cramped HF air shelf
//
// All modes process interleaved 32-bit float or 64-bit double stereo in-place
// with zero algorithmic latency, click-free smoothing, and denormal clamping.
// =============================================================================

namespace sauti::dsp {

enum class SurroundMode {
    Off = 0,
    MatrixSurround = 1,      // Cinema Matrix 5.1 (Active Dematrix -> Spherical HRTF)
    BinauralVirtualizer = 2, // Binaural HRTF (Headphone Room / Speaker XTC)
    AcousticStage = 3        // 3D Acoustic Stage (Profile-aware XTC + Depth + LR4 Bass)
};

inline float surround_sanitize(float v)
{
    return (std::fabs(v) < 1.0e-15f) ? 0.0f : v;
}

inline double surround_sanitize(double v)
{
    return (std::fabs(v) < 1.0e-25) ? 0.0 : v;
}

// ---------------------------------------------------------------------------
// Direct Form I biquad (64-bit double precision, used for HrtfSource pinna cues)
// ---------------------------------------------------------------------------
struct SurroundBiquad {
    double b0 = 1.0, b1 = 0.0, b2 = 0.0;
    double a1 = 0.0, a2 = 0.0;
    double x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0;

    void reset() { x1 = x2 = y1 = y2 = 0.0; }

    void setUnity()
    {
        b0 = 1.0; b1 = 0.0; b2 = 0.0;
        a1 = 0.0; a2 = 0.0;
    }

    inline double process(double xd)
    {
        double y = b0 * xd + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        if (std::fabs(y) < 1.0e-25) y = 0.0;
        x2 = x1; x1 = xd;
        y2 = y1; y1 = y;
        return y1;
    }

    inline float process(float x)
    {
        return surround_sanitize(static_cast<float>(process(static_cast<double>(x))));
    }
};

// RBJ peaking EQ
inline void surround_set_peaking(SurroundBiquad &bq, double fs, double f0, double Q, double gain_db)
{
    constexpr double PI = 3.14159265358979323846;
    if (std::fabs(gain_db) < 1.0e-4 || fs <= 0.0) {
        bq.setUnity();
        return;
    }
    double w0 = 2.0 * PI * f0 / fs;
    if (w0 > PI * 0.95) w0 = PI * 0.95;
    if (w0 < 1.0e-4) w0 = 1.0e-4;
    const double A = std::pow(10.0, gain_db / 40.0);
    const double cw = std::cos(w0);
    const double alpha = std::sin(w0) / (2.0 * Q);

    const double a0 = 1.0 + alpha / A;
    bq.b0 = (1.0 + alpha * A) / a0;
    bq.b1 = (-2.0 * cw) / a0;
    bq.b2 = (1.0 - alpha * A) / a0;
    bq.a1 = (-2.0 * cw) / a0;
    bq.a2 = (1.0 - alpha / A) / a0;
}

// RBJ high-shelf filter
inline void surround_set_highshelf(SurroundBiquad &bq, double fs, double f0, double gain_db, double S = 1.0)
{
    constexpr double PI = 3.14159265358979323846;
    if (std::fabs(gain_db) < 1.0e-4 || fs <= 0.0) {
        bq.setUnity();
        return;
    }
    double w0 = 2.0 * PI * f0 / fs;
    if (w0 > PI * 0.95) w0 = PI * 0.95;
    if (w0 < 1.0e-4) w0 = 1.0e-4;
    const double A = std::pow(10.0, gain_db / 40.0);
    const double cw = std::cos(w0);
    const double sw = std::sin(w0);
    const double alpha = sw / 2.0 * std::sqrt((A + 1.0 / A) * (1.0 / S - 1.0) + 2.0);
    const double two_sqrt_A_alpha = 2.0 * std::sqrt(A) * alpha;

    const double a0 = (A + 1.0) - (A - 1.0) * cw + two_sqrt_A_alpha;
    bq.b0 = (A * ((A + 1.0) + (A - 1.0) * cw + two_sqrt_A_alpha)) / a0;
    bq.b1 = (-2.0 * A * ((A - 1.0) + (A + 1.0) * cw)) / a0;
    bq.b2 = (A * ((A + 1.0) + (A - 1.0) * cw - two_sqrt_A_alpha)) / a0;
    bq.a1 = (2.0 * ((A - 1.0) - (A + 1.0) * cw)) / a0;
    bq.a2 = ((A + 1.0) - (A - 1.0) * cw - two_sqrt_A_alpha) / a0;
}

// First-order head-shadow / diffraction shelf (Brown & Duda structural HRTF, 64-bit precision)
struct SurroundShelf1 {
    double b0 = 1.0, b1 = 0.0, a1 = 0.0;
    double x1 = 0.0, y1 = 0.0;

    void reset() { x1 = y1 = 0.0; }

    void setUnity()
    {
        b0 = 1.0; b1 = 0.0; a1 = 0.0;
    }

    void setShadow(double alpha, double tau0, double T)
    {
        const double a0 = 2.0 * tau0 + T;
        b0 = (2.0 * alpha * tau0 + T) / a0;
        b1 = (T - 2.0 * alpha * tau0) / a0;
        a1 = (T - 2.0 * tau0) / a0;
    }

    inline double process(double x)
    {
        const double y = b0 * x + b1 * x1 - a1 * y1;
        x1 = x;
        y1 = surround_sanitize(y);
        return y1;
    }
};

// Sample-rate-invariant 1-pole lowpass (64-bit precision, for head-shadow & air damping)
struct SurroundLPF1 {
    double coeff = 1.0;
    double y1 = 0.0;

    void reset() { y1 = 0.0; }

    void setCutoff(double fs, double fc)
    {
        constexpr double PI = 3.14159265358979323846;
        if (fs <= 0.0) { coeff = 1.0; return; }
        const double clamped = std::clamp(fc, 50.0, fs * 0.45);
        coeff = 1.0 - std::exp(-2.0 * PI * clamped / fs);
    }

    inline double process(double x)
    {
        y1 = surround_sanitize(y1 + coeff * (x - y1));
        return y1;
    }
};

// Fractional delay line with linear interpolation (64-bit precision)
struct SurroundDelay {
    std::vector<double> buf;
    uint32_t w = 0;

    void init(uint32_t max_samples)
    {
        buf.assign(max_samples + 4, 0.0);
        w = 0;
    }

    void clear() { std::fill(buf.begin(), buf.end(), 0.0); w = 0; }

    inline double maxDelay() const
    {
        return buf.size() > 3 ? static_cast<double>(buf.size() - 3) : 0.0;
    }

    // Writes current sample first, then reads exact delay d >= 0.0 (d=0 returns x)
    inline double pushAndRead(double d, double x)
    {
        if (buf.empty()) return x;
        buf[w] = x;
        const uint32_t n = static_cast<uint32_t>(buf.size());
        double di = std::clamp(d, 0.0, maxDelay());
        const uint32_t i0 = static_cast<uint32_t>(di);
        const double frac = di - static_cast<double>(i0);
        const uint32_t r0 = (w + n - i0) % n;
        const uint32_t r1 = (r0 + n - 1) % n;
        w = (w + 1) % n;
        return buf[r0] + frac * (buf[r1] - buf[r0]);
    }

    // Reads prior samples at exact delay d >= 1.0 before push() is called
    inline double read(double d) const
    {
        if (buf.empty()) return 0.0;
        const uint32_t n = static_cast<uint32_t>(buf.size());
        double di = std::clamp(d, 1.0, maxDelay());
        const uint32_t i0 = static_cast<uint32_t>(di);
        const double frac = di - static_cast<double>(i0);
        const uint32_t r0 = (w + n - i0) % n;
        const uint32_t r1 = (r0 + n - 1) % n;
        return buf[r0] + frac * (buf[r1] - buf[r0]);
    }

    inline void push(double x)
    {
        if (buf.empty()) return;
        buf[w] = x;
        w = (w + 1) % static_cast<uint32_t>(buf.size());
    }
};

// Schroeder all-pass diffuser with delay D (64-bit precision)
struct SurroundDiffuserAP {
    double g = 0.48;
    double delay_samples = 1.0;
    SurroundDelay in_line, out_line;

    void init(float delay_samples_ref48k, float sr_scale, double feedback_g = 0.48)
    {
        g = feedback_g;
        delay_samples = std::max(1.0, static_cast<double>(delay_samples_ref48k) * static_cast<double>(sr_scale));
        in_line.init(static_cast<uint32_t>(delay_samples) + 8u);
        out_line.init(static_cast<uint32_t>(delay_samples) + 8u);
    }

    void reset()
    {
        in_line.clear();
        out_line.clear();
    }

    inline double process(double x)
    {
        const double xd = in_line.read(delay_samples);
        const double yd = out_line.read(delay_samples);
        const double y = surround_sanitize(-g * x + xd + g * yd);
        in_line.push(x);
        out_line.push(y);
        return y;
    }
};

// 4-stage Olli Niemitalo Hilbert Quadrature Pair (64-bit precision)
// Exact +/- 0.7 deg 90-degree phase separation across 40 Hz..18 kHz with 0.00 dB magnitude ripple
struct SurroundHilbert4 {
    struct Section2 {
        double k = 0.0;
        double x1 = 0.0, x2 = 0.0;
        double y1 = 0.0, y2 = 0.0;

        void reset() { x1 = x2 = y1 = y2 = 0.0; }

        inline double process(double x)
        {
            const double y = surround_sanitize(k * (x + y2) - x2);
            x2 = x1;
            x1 = x;
            y2 = y1;
            y1 = y;
            return y;
        }
    };

    Section2 branch_a[4];
    Section2 branch_b[4];
    double delay_a = 0.0;

    SurroundHilbert4()
    {
        constexpr double a_c[4] = {
            0.6923878, 0.9360654322959, 0.9882295226860, 0.9987488452737
        };
        constexpr double b_c[4] = {
            0.4021921162426, 0.8561710882420, 0.9722909545651, 0.9952884791278
        };
        for (int i = 0; i < 4; ++i) {
            branch_a[i].k = a_c[i] * a_c[i];
            branch_b[i].k = b_c[i] * b_c[i];
        }
        reset();
    }

    void reset()
    {
        for (int i = 0; i < 4; ++i) {
            branch_a[i].reset();
            branch_b[i].reset();
        }
        delay_a = 0.0;
    }

    inline void process(double x, double &out_a, double &out_b)
    {
        double a = delay_a;
        delay_a = x;
        double b = x;
        for (int i = 0; i < 4; ++i) {
            a = branch_a[i].process(a);
            b = branch_b[i].process(b);
        }
        out_a = a;
        out_b = b;
    }
};

// ---------------------------------------------------------------------------
// Parametric spherical-head HRTF source (used for Cinema Matrix 5.1 binauralization)
// ---------------------------------------------------------------------------
class HrtfSource {
public:
    void configure(float azimuth_deg, float elevation_deg,
                   float head_radius_cm, float pinna_strength, float sample_rate)
    {
        sample_rate_ = (sample_rate > 0.0f) ? sample_rate : 48000.0f;
        azimuth_ = azimuth_deg;
        elevation_ = elevation_deg;
        pinna_strength_ = pinna_strength;
        head_radius_cm_ = head_radius_cm;
        update();

        // Pre-allocate enough delay capacity up to 192 kHz so radius updates never reallocate
        const uint32_t needed_itd = std::max(512u, static_cast<uint32_t>(sample_rate_ * 0.004f) + 32u);
        if (delay_.buf.size() < needed_itd + 4u) {
            delay_.init(needed_itd);
        }
    }

    void setEarMix(double ipsi_weight, double contra_weight)
    {
        ipsi_weight_ = ipsi_weight;
        contra_weight_ = contra_weight;
    }

    void reset()
    {
        shelf_ipsi_.reset();
        shelf_contra_.reset();
        pinna_ipsi_.reset();
        pinna_contra_.reset();
        delay_.clear();
    }

    inline void process(double in, double gain, double &out_l, double &out_r)
    {
        const double s = in * gain;
        if (is_center_) {
            // Exact 0-degree symmetry: zero ITD and zero L/R head-shadow bias
            out_l += s;
            out_r += s;
            return;
        }

        const double s_contra = delay_.pushAndRead(itd_samples_, s);
        const double ipsi   = pinna_ipsi_.process(shelf_ipsi_.process(s)) * ipsi_weight_;
        const double contra = pinna_contra_.process(shelf_contra_.process(s_contra)) * contra_weight_;

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

    inline void process(float in, float gain, float &out_l, float &out_r)
    {
        double l = static_cast<double>(out_l);
        double r = static_cast<double>(out_r);
        process(static_cast<double>(in), static_cast<double>(gain), l, r);
        out_l = static_cast<float>(l);
        out_r = static_cast<float>(r);
    }

private:
    void update()
    {
        constexpr double PI = 3.14159265358979323846;
        constexpr double C_SOUND = 343.0; // m/s

        const double abs_az = std::clamp(static_cast<double>(std::fabs(azimuth_)), 0.0, 180.0);
        is_center_ = (abs_az < 0.5);

        if (is_center_) {
            itd_samples_ = 0.0;
            shelf_ipsi_.setUnity();
            shelf_contra_.setUnity();
            pinna_ipsi_.setUnity();
            pinna_contra_.setUnity();
            return;
        }

        // Fold azimuth past +/-90 deg across the interaural axis for front-back symmetry
        const double lat_deg = (abs_az <= 90.0) ? abs_az : (180.0 - abs_az);
        const double lat_rad = lat_deg * (PI / 180.0);
        const double a = static_cast<double>(head_radius_cm_) * 0.01;
        const double T = 1.0 / static_cast<double>(sample_rate_);
        const double tau0 = a / (2.0 * C_SOUND); // Brown & Duda (~1248 Hz for a=8.75 cm)

        // Ear-axis head shadow: ipsi mildly boosted (+2.3 dB max), contra attenuated (-9.1 dB max)
        const double sin_lat = std::sin(lat_rad);
        const double alpha_ipsi   = 1.0 + 0.30 * sin_lat;
        const double alpha_contra = 1.0 - 0.65 * sin_lat;
        shelf_ipsi_.setShadow(alpha_ipsi, tau0, T);
        shelf_contra_.setShadow(alpha_contra, tau0, T);

        // Folded Woodworth spherical-head ITD (peaks at +/-90 deg)
        const double delta_t = (a / C_SOUND) * (lat_rad + sin_lat);
        itd_samples_ = std::max(0.0, delta_t * static_cast<double>(sample_rate_));

        // Subtle pinna cues: rear hemisphere gets gentle HF rolloff for front-back differentiation
        if (abs_az > 90.0) {
            surround_set_highshelf(pinna_ipsi_, sample_rate_, 4500.0, -3.5 * pinna_strength_, 0.9);
            surround_set_highshelf(pinna_contra_, sample_rate_, 4200.0, -2.5 * pinna_strength_, 0.9);
        } else {
            const double f_pinna = 7500.0 + 2000.0 * (static_cast<double>(elevation_) / 90.0);
            surround_set_peaking(pinna_ipsi_, sample_rate_, f_pinna, 2.5, -1.5 * pinna_strength_);
            surround_set_peaking(pinna_contra_, sample_rate_, f_pinna * 0.93, 2.5, -1.0 * pinna_strength_);
        }
    }

    float sample_rate_ = 48000.0f;
    float azimuth_ = 0.0f;
    float elevation_ = 0.0f;
    float pinna_strength_ = 0.7f;
    float head_radius_cm_ = 8.75f;
    bool is_center_ = false;
    double itd_samples_ = 0.0;
    double ipsi_weight_ = 1.0;
    double contra_weight_ = 1.0;

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
        const bool srChanged = std::fabs(sample_rate_ - sample_rate) >= 1.0f;
        if (!srChanged && !matrix_mc_scratch_.empty()) return;

        sample_rate_ = sample_rate;
        smoothing_coeff_ = 1.0f - std::exp(-1.0f / (0.035f * sample_rate_));
        matrix_env_coeff_ = 1.0 - std::exp(-1.0 / (0.015 * static_cast<double>(sample_rate_)));
        matrix_mc_scratch_.assign(8192u * 8u, 0.0);
        buildDelayLines();
        updateFilters();
        reconfigureHrtf();
        sofa_hrtf_.setSampleRate(sample_rate_);
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

    // --- Mode 2: Binaural HRTF Virtualizer Parameters ---
    void setBinauralMode(int mode)           { binaural_mode_ = clampi(mode, 0, 1); } // 0=Headphone HRTF, 1=Speaker Field
    void setBinauralBoost(float boost)       { binaural_boost_ = clampf(boost, 0.0f, 1.0f); }
    void setBinauralRoomPreset(int preset)
    {
        binaural_room_preset_ = clampi(preset, 1, 3);
        updateRoomTargets();
        need_filter_update_ = true;
    }
    void setBinauralRoomMix(float mix)       { binaural_room_mix_ = clampf(mix, 0.0f, 1.0f); }
    void setBinauralSpeakerAngle(int angle)
    {
        binaural_speaker_angle_ = clampi(angle, 0, 2); // 0=Narrow (10), 1=Standard (30), 2=Wide (45)
        sofa_hrtf_.setStereoAngleDeg(getTargetSpeakerAngleDeg());
    }
    void setBinauralShadowCutoff(float hz)   { binaural_shadow_cutoff_ = clampf(hz, 2000.0f, 6000.0f); need_filter_update_ = true; }

    // --- Personal SOFA HRTF Controls ---
    bool loadSofaFile(const char *path)
    {
        return sofa_hrtf_.loadFromFile(path, sample_rate_, getTargetSpeakerAngleDeg());
    }
    bool loadSofaMemory(const uint8_t *data, size_t size)
    {
        return sofa_hrtf_.loadFromMemory(data, size, sample_rate_, getTargetSpeakerAngleDeg());
    }
    void clearSofa()                         { sofa_hrtf_.clear(); }
    void setSofaEnabled(bool enabled)        { sofa_hrtf_enabled_ = enabled; }
    bool isSofaEnabled() const               { return sofa_hrtf_enabled_; }
    bool hasSofaLoaded() const               { return sofa_hrtf_.isLoaded(); }
    bool isSofaActive() const                { return sofa_hrtf_enabled_ && sofa_hrtf_.isLoaded(); }
    SofaHrtfMetadata getSofaMetadata() const { return sofa_hrtf_.getMetadata(); }
    void rebuildSofaForSampleRate(float sr)  { sofa_hrtf_.setSampleRate(sr); }
    size_t getLatencySamples() const
    {
        if (!enabled_ || !isSofaActive()) return 0;
        if (mode_ == SurroundMode::MatrixSurround ||
            (mode_ == SurroundMode::BinauralVirtualizer && binaural_mode_ == 0)) {
            return sofa_hrtf_.getLatencySamples();
        }
        return 0;
    }

    // --- Mode 3: 3D Acoustic Stage Parameters ---
    void setStageProfile(int profile)        { stage_profile_ = clampi(profile, 0, 1); } // 0=Headset, 1=Speaker
    void setStageMode(int mode)              { stage_mode_ = clampi(mode, 0, 1); } // 0=Studio, 1=Panoramic
    void setStageWidth(float width)          { stage_width_ = clampf(width, 0.0f, 2.0f); }
    void setStageDepth(float depth)          { stage_depth_ = clampf(depth, 0.0f, 1.0f); }
    void setStageCancellation(float c)       { stage_cancellation_ = clampf(c, 0.0f, 1.0f); }
    void setStageAirPresence(float air)      { stage_air_presence_ = clampf(air, 0.0f, 1.0f); need_filter_update_ = true; }
    void setStageBassAnchorHz(float hz)      { stage_bass_anchor_hz_ = clampf(hz, 20.0f, 120.0f); need_filter_update_ = true; }

    // Unified / compatibility getters
    float getSampleRate() const              { return sample_rate_; }
    float getAntiPop() const                 { return anti_pop_; }
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
        // Cinema Matrix 5.1
        for (auto &src : matrix_sources_) src.reset();
        matrix_lfe_lp1_.reset(); matrix_lfe_lp2_.reset();
        matrix_lfe_hp1_.reset(); matrix_lfe_hp2_.reset();
        matrix_surr_hp_.reset(); matrix_surr_lp_.reset();
        matrix_hilbert_.reset();
        rear_line_l_.clear(); rear_line_r_.clear();
        rear_line_bl_.clear(); rear_line_br_.clear();
        rear_diffuser_l_.reset(); rear_diffuser_r_.reset();
        sofa_hrtf_.reset();
        matrix_env_lr_ = 0.0;
        matrix_env_l2_ = 0.0;
        matrix_env_r2_ = 0.0;

        // Binaural Virtualizer
        binaural_itd_l_.clear(); binaural_itd_r_.clear();
        binaural_shadow_lpf_l_.reset(); binaural_shadow_lpf_r_.reset();
        binaural_baffle_l_.reset(); binaural_baffle_r_.reset();
        for (int i = 0; i < 2; ++i) {
            binaural_room_delays_[i].clear();
        }
        binaural_room_diffuser_l1_.reset(); binaural_room_diffuser_l2_.reset();
        binaural_room_diffuser_r1_.reset(); binaural_room_diffuser_r2_.reset();
        binaural_room_air_l_.reset(); binaural_room_air_r_.reset();
        binaural_xtc_delay_l_.clear(); binaural_xtc_delay_r_.clear();
        binaural_xtc_hp_.reset(); binaural_xtc_lp_.reset();

        // 3D Acoustic Stage
        stage_xtc_delay_l_.clear(); stage_xtc_delay_r_.clear();
        stage_xtc_hp_.reset(); stage_xtc_lp_.reset();
        stage_itd_l_.clear(); stage_itd_r_.clear();
        stage_shadow_lpf_l_.reset(); stage_shadow_lpf_r_.reset();
        stage_baffle_l_.reset(); stage_baffle_r_.reset();
        stage_depth_delay_l_.clear(); stage_depth_delay_r_.clear();
        stage_depth_diff_l1_.reset(); stage_depth_diff_l2_.reset();
        stage_depth_diff_r1_.reset(); stage_depth_diff_r2_.reset();
        stage_depth_air_l_.reset(); stage_depth_air_r_.reset();
        stage_bass_lp1_.reset(); stage_bass_lp2_.reset();
        stage_bass_hp1_.reset(); stage_bass_hp2_.reset();
        stage_air_side_.reset(); stage_air_mid_.reset();

        // Parameter smoothing state
        smooth_center_focus_   = center_focus_;
        smooth_surround_boost_ = surround_boost_;
        smooth_surround_delay_ = surround_delay_ms_;
        smooth_binaural_boost_ = binaural_boost_;
        smooth_binaural_room_  = binaural_room_mix_;
        smooth_room_scale_     = target_room_scale_;
        smooth_xtc_delay_ms_   = getTargetSpeakerDelayMs();
        smooth_stage_width_    = stage_width_;
        smooth_stage_depth_    = stage_depth_;
        smooth_stage_cancel_   = stage_cancellation_;
        smooth_stage_xtc_ms_   = (stage_mode_ == 1) ? 0.085f : 0.140f;
        last_binaural_baffle_b_ = -1.0;
        last_stage_baffle_c_    = -1.0;

        anti_pop_ = 0.0f;
    }

    // ---------------- Processing ----------------
    void process(float *interleaved, uint32_t frame_count)
    {
        processImpl(interleaved, frame_count);
    }

    void process(double *interleaved, uint32_t frame_count)
    {
        processImpl(interleaved, frame_count);
    }

    // Multichannel-aware processing. Returns resulting active channel count
    // (e.g., 6/8 -> 2 when binauralizing discrete 5.1/7.1 to headphones, or
    // 2 -> 6/8 when upmixing stereo to discrete 5.1/7.1 speaker output).
    int processMultichannel(float *interleaved, uint32_t frame_count, int in_channels, int out_channels)
    {
        return processMultichannelImpl(interleaved, frame_count, in_channels, out_channels);
    }

    int processMultichannel(double *interleaved, uint32_t frame_count, int in_channels, int out_channels)
    {
        return processMultichannelImpl(interleaved, frame_count, in_channels, out_channels);
    }

private:
    template <typename T>
    void processImpl(T *interleaved, uint32_t frame_count)
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

        // Anti-pop fade-in when first engaged (~50 ms per-frame ramp)
        // Increments per stereo frame to preserve exact Left/Right stereo balance
        if (anti_pop_ < 1.0f) {
            const float inc = 20.0f / sample_rate_;
            for (uint32_t i = 0; i < frame_count; ++i) {
                const double ap = static_cast<double>(anti_pop_);
                interleaved[2 * i]     = static_cast<T>(static_cast<double>(interleaved[2 * i]) * ap);
                interleaved[2 * i + 1] = static_cast<T>(static_cast<double>(interleaved[2 * i + 1]) * ap);
                anti_pop_ = std::min(1.0f, anti_pop_ + inc);
            }
        }
    }

    static float clampf(float v, float lo, float hi) { return std::clamp(v, lo, hi); }
    static int clampi(int v, int lo, int hi) { return v < lo ? lo : (v > hi ? hi : v); }
    float srScale() const { return sample_rate_ / 48000.0f; }

    float getTargetSpeakerDelayMs() const
    {
        if (binaural_speaker_angle_ == 0) return 0.075f; // Narrow (10 deg)
        if (binaural_speaker_angle_ == 2) return 0.250f; // Wide (45 deg)
        return 0.180f;                                   // Standard (30 deg)
    }

    float getTargetSpeakerAngleDeg() const
    {
        if (binaural_speaker_angle_ == 0) return 10.0f;
        if (binaural_speaker_angle_ == 2) return 45.0f;
        return 30.0f;
    }

    template <typename T>
    void applyAntiPopStereo(T *interleaved, uint32_t frame_count)
    {
        if (anti_pop_ < 1.0f) {
            const float inc = 20.0f / sample_rate_;
            for (uint32_t i = 0; i < frame_count; ++i) {
                const double ap = static_cast<double>(anti_pop_);
                interleaved[2 * i]     = static_cast<T>(static_cast<double>(interleaved[2 * i]) * ap);
                interleaved[2 * i + 1] = static_cast<T>(static_cast<double>(interleaved[2 * i + 1]) * ap);
                anti_pop_ = std::min(1.0f, anti_pop_ + inc);
            }
        }
    }

    template <typename T>
    void applyBinauralRoomReflections(T *s, uint32_t frames)
    {
        const double sr = static_cast<double>(sample_rate_);
        for (uint32_t i = 0; i < frames; ++i) {
            smooth_binaural_room_ += smoothing_coeff_ * (binaural_room_mix_ - smooth_binaural_room_);
            smooth_room_scale_    += smoothing_coeff_ * (target_room_scale_ - smooth_room_scale_);

            const double l_in = static_cast<double>(s[2 * i]);
            const double r_in = static_cast<double>(s[2 * i + 1]);

            if (smooth_binaural_room_ > 1.0e-4) {
                const double scale_ms = 0.001 * sr * static_cast<double>(smooth_room_scale_);
                const double il0 = binaural_room_delays_[0].read(9.3 * scale_ms);
                const double il1 = binaural_room_delays_[0].read(15.7 * scale_ms);
                const double il2 = binaural_room_delays_[0].read(23.9 * scale_ms);
                const double cr0 = binaural_room_delays_[1].read(12.1 * scale_ms);
                const double cr1 = binaural_room_delays_[1].read(19.4 * scale_ms);
                const double cr2 = binaural_room_delays_[1].read(28.3 * scale_ms);

                const double ir0 = binaural_room_delays_[1].read(9.3 * scale_ms);
                const double ir1 = binaural_room_delays_[1].read(15.7 * scale_ms);
                const double ir2 = binaural_room_delays_[1].read(23.9 * scale_ms);
                const double cl0 = binaural_room_delays_[0].read(12.1 * scale_ms);
                const double cl1 = binaural_room_delays_[0].read(19.4 * scale_ms);
                const double cl2 = binaural_room_delays_[0].read(28.3 * scale_ms);

                binaural_room_delays_[0].push(l_in);
                binaural_room_delays_[1].push(r_in);

                const double raw_l = 0.30 * il0 - 0.22 * il1 + 0.16 * il2 + 0.24 * cr0 - 0.18 * cr1 + 0.12 * cr2;
                const double raw_r = 0.30 * ir0 - 0.22 * ir1 + 0.16 * ir2 + 0.24 * cl0 - 0.18 * cl1 + 0.12 * cl2;

                const double diff_l = binaural_room_diffuser_l2_.process(binaural_room_diffuser_l1_.process(raw_l));
                const double diff_r = binaural_room_diffuser_r2_.process(binaural_room_diffuser_r1_.process(raw_r));
                const double wet_l = binaural_room_air_l_.process(diff_l);
                const double wet_r = binaural_room_air_r_.process(diff_r);

                const double room_wet = 0.34 * static_cast<double>(smooth_binaural_room_);
                const double direct_g = 1.0 / std::sqrt(1.0 + 0.5 * room_wet * room_wet);
                s[2 * i]     = static_cast<T>(surround_sanitize(direct_g * l_in + room_wet * wet_l));
                s[2 * i + 1] = static_cast<T>(surround_sanitize(direct_g * r_in + room_wet * wet_r));
            } else {
                binaural_room_delays_[0].push(l_in);
                binaural_room_delays_[1].push(r_in);
            }
        }
    }

    template <typename T>
    int processMultichannelImpl(T *buf, uint32_t frames, int in_channels, int out_channels)
    {
        if (!enabled_ || frames == 0 || !buf || mode_ == SurroundMode::Off) {
            return in_channels;
        }
        if (in_channels == 2 && out_channels == 2) {
            processImpl(buf, frames);
            return 2;
        }
        if (in_channels < 2) {
            return in_channels;
        }

        if (need_filter_update_) {
            updateFilters();
            need_filter_update_ = false;
        }

        // Case A: Discrete 5.1 (6ch) or 7.1 (8ch) -> 2ch Stereo/Headphone output
        if ((in_channels == 6 || in_channels == 8) && out_channels == 2) {
            if (mode_ == SurroundMode::BinauralVirtualizer && binaural_mode_ == 1) {
                // Speaker Field XTC expects 2ch stereo speakers
                ChannelLayoutRouter::convert(buf, frames, in_channels, 2);
                processBinaural(buf, frames);
                applyAntiPopStereo(buf, frames);
                return 2;
            }

            // Optional Matrix surround boost scaling on discrete surround channels before HRTF
            if (mode_ == SurroundMode::MatrixSurround) {
                const double rb = 0.70 * static_cast<double>(surround_boost_);
                const double cf = std::clamp(0.65 + 0.55 * static_cast<double>(center_focus_), 0.5, 1.3);
                for (uint32_t i = 0; i < frames; ++i) {
                    const size_t base = static_cast<size_t>(i) * static_cast<size_t>(in_channels);
                    buf[base + 2] = static_cast<T>(static_cast<double>(buf[base + 2]) * cf);
                    for (int c = 4; c < in_channels; ++c) {
                        buf[base + static_cast<size_t>(c)] = static_cast<T>(static_cast<double>(buf[base + static_cast<size_t>(c)]) * rb);
                    }
                }
            }

            const double wet = (mode_ == SurroundMode::BinauralVirtualizer)
                             ? static_cast<double>(binaural_boost_)
                             : 1.0;

            if (isSofaActive() && sofa_hrtf_.process(buf, frames, in_channels, 0.7071067811865475, wet)) {
                if (mode_ == SurroundMode::BinauralVirtualizer) {
                    applyBinauralRoomReflections(buf, frames);
                }
                applyAntiPopStereo(buf, frames);
                return 2;
            }

            // Parametric spherical-head HRTF rendering of discrete 5.1 / 7.1
            const double dMix = 1.0 - wet;
            for (uint32_t i = 0; i < frames; ++i) {
                const size_t inB = static_cast<size_t>(i) * static_cast<size_t>(in_channels);
                const double fl  = static_cast<double>(buf[inB + 0]);
                const double fr  = static_cast<double>(buf[inB + 1]);
                const double fc  = static_cast<double>(buf[inB + 2]);
                const double lfe = static_cast<double>(buf[inB + 3]);

                double hrtf_l = 0.0, hrtf_r = 0.0;
                matrix_sources_[0].process(fc, 0.7071067811865475, hrtf_l, hrtf_r); // FC @ 0 deg
                matrix_sources_[1].process(fl, 1.0, hrtf_l, hrtf_r);                // FL @ -30 deg
                matrix_sources_[2].process(fr, 1.0, hrtf_l, hrtf_r);                // FR @ +30 deg

                if (in_channels == 6) {
                    const double sl = static_cast<double>(buf[inB + 4]);
                    const double sr = static_cast<double>(buf[inB + 5]);
                    matrix_sources_[3].process(sl, 0.7071067811865475, hrtf_l, hrtf_r); // SL @ -110 deg
                    matrix_sources_[4].process(sr, 0.7071067811865475, hrtf_l, hrtf_r); // SR @ +110 deg
                } else {
                    const double bl = static_cast<double>(buf[inB + 4]);
                    const double br = static_cast<double>(buf[inB + 5]);
                    const double sl = static_cast<double>(buf[inB + 6]);
                    const double sr = static_cast<double>(buf[inB + 7]);
                    matrix_sources_[5].process(bl, 0.65, hrtf_l, hrtf_r); // BL @ -150 deg
                    matrix_sources_[6].process(br, 0.65, hrtf_l, hrtf_r); // BR @ +150 deg
                    matrix_sources_[7].process(sl, 0.70, hrtf_l, hrtf_r); // SL @ -90 deg
                    matrix_sources_[8].process(sr, 0.70, hrtf_l, hrtf_r); // SR @ +90 deg
                }

                // LFE bypasses ITD/pinna head-shadow so sub-bass stays tight & punchy
                hrtf_l += 0.7071067811865475 * lfe;
                hrtf_r += 0.7071067811865475 * lfe;

                const double out_l = dMix * fl + wet * hrtf_l;
                const double out_r = dMix * fr + wet * hrtf_r;
                buf[2 * i]     = static_cast<T>(surround_sanitize(out_l));
                buf[2 * i + 1] = static_cast<T>(surround_sanitize(out_r));
            }
            if (mode_ == SurroundMode::BinauralVirtualizer) {
                applyBinauralRoomReflections(buf, frames);
            }
            applyAntiPopStereo(buf, frames);
            return 2;
        }

        // Case B: 2ch Stereo -> Discrete 5.1 / 7.1 Hardware Output (Matrix Upmix)
        if (in_channels == 2 && (out_channels == 6 || out_channels == 8)) {
            if (mode_ == SurroundMode::MatrixSurround) {
                const double sr = static_cast<double>(sample_rate_);
                if (matrix_mc_scratch_.size() < static_cast<size_t>(frames) * 2u) {
                    matrix_mc_scratch_.resize(static_cast<size_t>(frames) * 2u);
                }
                for (uint32_t i = 0; i < frames; ++i) {
                    matrix_mc_scratch_[2 * i]     = static_cast<double>(buf[2 * i]);
                    matrix_mc_scratch_[2 * i + 1] = static_cast<double>(buf[2 * i + 1]);
                }
                for (uint32_t i = 0; i < frames; ++i) {
                    smooth_center_focus_   += smoothing_coeff_ * (center_focus_ - smooth_center_focus_);
                    smooth_surround_boost_ += smoothing_coeff_ * (surround_boost_ - smooth_surround_boost_);
                    smooth_surround_delay_ += smoothing_coeff_ * (surround_delay_ms_ - smooth_surround_delay_);

                    const double l_in = matrix_mc_scratch_[2 * i];
                    const double r_in = matrix_mc_scratch_[2 * i + 1];

                    const double l_lo = matrix_lfe_lp2_.processSample(matrix_lfe_lp1_.processSample(l_in, 0), 0);
                    const double r_lo = matrix_lfe_lp2_.processSample(matrix_lfe_lp1_.processSample(r_in, 1), 1);
                    const double l_hi = matrix_lfe_hp2_.processSample(matrix_lfe_hp1_.processSample(l_in, 0), 0);
                    const double r_hi = matrix_lfe_hp2_.processSample(matrix_lfe_hp1_.processSample(r_in, 1), 1);
                    const double lfe = 0.5 * (l_lo + r_lo);

                    matrix_env_lr_ += matrix_env_coeff_ * (l_hi * r_hi - matrix_env_lr_);
                    matrix_env_l2_ += matrix_env_coeff_ * (l_hi * l_hi - matrix_env_l2_);
                    matrix_env_r2_ += matrix_env_coeff_ * (r_hi * r_hi - matrix_env_r2_);

                    const double denom_e = std::sqrt(matrix_env_l2_ * matrix_env_r2_) + 1.0e-12;
                    const double corr = std::clamp(matrix_env_lr_ / denom_e, -1.0, 1.0);
                    const double balance = std::clamp((matrix_env_l2_ - matrix_env_r2_) /
                                                      (matrix_env_l2_ + matrix_env_r2_ + 1.0e-12), -1.0, 1.0);
                    const double c_steer = std::clamp(corr, 0.0, 1.0) * (1.0 - std::fabs(balance));

                    const double mid_hi  = 0.5 * (l_hi + r_hi);
                    const double side_hi = 0.5 * (l_hi - r_hi);
                    const double c_amt = static_cast<double>(smooth_center_focus_) * c_steer;
                    const double fc = mid_hi * c_amt * 1.4142135623730951;
                    const double fl = l_hi - mid_hi * c_amt;
                    const double fr = r_hi - mid_hi * c_amt;

                    const double side_band = matrix_surr_lp_.processSample(matrix_surr_hp_.processSample(side_hi, 0), 0);
                    double q_a = 0.0, q_b = 0.0;
                    matrix_hilbert_.process(side_band, q_a, q_b);

                    const double ls_steer = std::clamp(0.5 * (1.0 + 0.70 * balance), 0.15, 0.85);
                    const double rs_steer = 1.0 - ls_steer;
                    const double rear_delay_samples = static_cast<double>(smooth_surround_delay_) * 0.001 * sr;
                    const double rb = 0.50 * static_cast<double>(smooth_surround_boost_);

                    const double ls = rear_diffuser_l_.process(
                        rear_line_l_.pushAndRead(rear_delay_samples, q_a * ls_steer * 1.4142135623730951)) * rb;
                    const double rs = rear_diffuser_r_.process(
                        rear_line_r_.pushAndRead(rear_delay_samples, -q_b * rs_steer * 1.4142135623730951)) * rb;

                    const size_t outB = static_cast<size_t>(i) * static_cast<size_t>(out_channels);
                    buf[outB + 0] = static_cast<T>(surround_sanitize(fl));
                    buf[outB + 1] = static_cast<T>(surround_sanitize(fr));
                    buf[outB + 2] = static_cast<T>(surround_sanitize(fc));
                    buf[outB + 3] = static_cast<T>(surround_sanitize(lfe));
                    if (out_channels == 6) {
                        buf[outB + 4] = static_cast<T>(surround_sanitize(ls));
                        buf[outB + 5] = static_cast<T>(surround_sanitize(rs));
                    } else {
                        const double bl = rear_line_bl_.pushAndRead(rear_delay_samples * 1.25, ls * 0.7071067811865475);
                        const double br = rear_line_br_.pushAndRead(rear_delay_samples * 1.25, rs * 0.7071067811865475);
                        buf[outB + 4] = static_cast<T>(surround_sanitize(bl));
                        buf[outB + 5] = static_cast<T>(surround_sanitize(br));
                        buf[outB + 6] = static_cast<T>(surround_sanitize(ls * 0.85));
                        buf[outB + 7] = static_cast<T>(surround_sanitize(rs * 0.85));
                    }
                }
                return out_channels;
            }
            processImpl(buf, frames);
            return 2;
        }

        // Case C: Discrete 5.1 / 7.1 -> Discrete 5.1 / 7.1 Hardware Output
        if ((in_channels == 6 || in_channels == 8) && (out_channels == 6 || out_channels == 8)) {
            if (mode_ == SurroundMode::MatrixSurround) {
                const double sr = static_cast<double>(sample_rate_);
                for (uint32_t i = 0; i < frames; ++i) {
                    smooth_center_focus_   += smoothing_coeff_ * (center_focus_ - smooth_center_focus_);
                    smooth_surround_boost_ += smoothing_coeff_ * (surround_boost_ - smooth_surround_boost_);
                    smooth_surround_delay_ += smoothing_coeff_ * (surround_delay_ms_ - smooth_surround_delay_);

                    const size_t base = static_cast<size_t>(i) * static_cast<size_t>(in_channels);
                    const double cf = 0.60 + 0.60 * static_cast<double>(smooth_center_focus_);
                    const double sb = static_cast<double>(smooth_surround_boost_);
                    const double dSamp = static_cast<double>(smooth_surround_delay_) * 0.001 * sr;

                    buf[base + 2] = static_cast<T>(surround_sanitize(static_cast<double>(buf[base + 2]) * cf));
                    buf[base + 4] = static_cast<T>(surround_sanitize(rear_line_l_.pushAndRead(dSamp, static_cast<double>(buf[base + 4]) * sb)));
                    buf[base + 5] = static_cast<T>(surround_sanitize(rear_line_r_.pushAndRead(dSamp, static_cast<double>(buf[base + 5]) * sb)));
                    if (in_channels == 8) {
                        buf[base + 6] = static_cast<T>(surround_sanitize(rear_line_bl_.pushAndRead(dSamp, static_cast<double>(buf[base + 6]) * sb)));
                        buf[base + 7] = static_cast<T>(surround_sanitize(rear_line_br_.pushAndRead(dSamp, static_cast<double>(buf[base + 7]) * sb)));
                    }
                }
            }
            if (in_channels != out_channels) {
                ChannelLayoutRouter::convert(buf, frames, in_channels, out_channels);
            }
            return out_channels;
        }

        return in_channels;
    }

    // -------------------------------------------------------------------------
    // Mode 1: Cinema Matrix 5.1 (Active Dematrix -> Folded Spherical HRTF)
    // -------------------------------------------------------------------------
    template <typename T>
    void processMatrix(T *s, uint32_t frames)
    {
        const double sr = static_cast<double>(sample_rate_);
        const bool useSofa = isSofaActive();

        if (useSofa) {
            uint32_t offset = 0;
            while (offset < frames) {
                const uint32_t chunk = std::min<uint32_t>(frames - offset, 8192u);
                if (matrix_mc_scratch_.size() < static_cast<size_t>(chunk) * 6u) {
                    matrix_mc_scratch_.resize(static_cast<size_t>(chunk) * 6u);
                }
                for (uint32_t i = 0; i < chunk; ++i) {
                    smooth_center_focus_   += smoothing_coeff_ * (center_focus_ - smooth_center_focus_);
                    smooth_surround_boost_ += smoothing_coeff_ * (surround_boost_ - smooth_surround_boost_);
                    smooth_surround_delay_ += smoothing_coeff_ * (surround_delay_ms_ - smooth_surround_delay_);

                    const double l_in = static_cast<double>(s[2 * (offset + i)]);
                    const double r_in = static_cast<double>(s[2 * (offset + i) + 1]);

                    const double l_lo = matrix_lfe_lp2_.processSample(matrix_lfe_lp1_.processSample(l_in, 0), 0);
                    const double r_lo = matrix_lfe_lp2_.processSample(matrix_lfe_lp1_.processSample(r_in, 1), 1);
                    const double l_hi = matrix_lfe_hp2_.processSample(matrix_lfe_hp1_.processSample(l_in, 0), 0);
                    const double r_hi = matrix_lfe_hp2_.processSample(matrix_lfe_hp1_.processSample(r_in, 1), 1);
                    const double lfe = 0.5 * (l_lo + r_lo);

                    matrix_env_lr_ += matrix_env_coeff_ * (l_hi * r_hi - matrix_env_lr_);
                    matrix_env_l2_ += matrix_env_coeff_ * (l_hi * l_hi - matrix_env_l2_);
                    matrix_env_r2_ += matrix_env_coeff_ * (r_hi * r_hi - matrix_env_r2_);

                    const double denom_e = std::sqrt(matrix_env_l2_ * matrix_env_r2_) + 1.0e-12;
                    const double corr = std::clamp(matrix_env_lr_ / denom_e, -1.0, 1.0);
                    const double balance = std::clamp((matrix_env_l2_ - matrix_env_r2_) /
                                                      (matrix_env_l2_ + matrix_env_r2_ + 1.0e-12), -1.0, 1.0);
                    const double c_steer = std::clamp(corr, 0.0, 1.0) * (1.0 - std::fabs(balance));

                    const double mid_hi  = 0.5 * (l_hi + r_hi);
                    const double side_hi = 0.5 * (l_hi - r_hi);
                    const double c_amt = static_cast<double>(smooth_center_focus_) * c_steer;
                    const double c  = mid_hi * c_amt;
                    const double fl = l_hi - c;
                    const double fr = r_hi - c;

                    const double side_band = matrix_surr_lp_.processSample(matrix_surr_hp_.processSample(side_hi, 0), 0);
                    double q_a = 0.0, q_b = 0.0;
                    matrix_hilbert_.process(side_band, q_a, q_b);

                    const double ls_steer = std::clamp(0.5 * (1.0 + 0.70 * balance), 0.15, 0.85);
                    const double rs_steer = 1.0 - ls_steer;
                    const double rear_delay_samples = static_cast<double>(smooth_surround_delay_) * 0.001 * sr;
                    const double ls_raw = rear_line_l_.pushAndRead(rear_delay_samples, q_a * ls_steer * 1.4142135623730951);
                    const double rs_raw = rear_line_r_.pushAndRead(rear_delay_samples, -q_b * rs_steer * 1.4142135623730951);
                    const double rb = 0.38 * static_cast<double>(smooth_surround_boost_);
                    const double ls = rear_diffuser_l_.process(ls_raw) * rb;
                    const double rs = rear_diffuser_r_.process(rs_raw) * rb;

                    const size_t mcIdx = static_cast<size_t>(i) * 6u;
                    matrix_mc_scratch_[mcIdx + 0] = fl;
                    matrix_mc_scratch_[mcIdx + 1] = fr;
                    matrix_mc_scratch_[mcIdx + 2] = c;
                    matrix_mc_scratch_[mcIdx + 3] = lfe;
                    matrix_mc_scratch_[mcIdx + 4] = ls;
                    matrix_mc_scratch_[mcIdx + 5] = rs;
                }
                if (sofa_hrtf_.process(matrix_mc_scratch_.data(), chunk, 6, 1.0, 1.0)) {
                    for (uint32_t i = 0; i < chunk; ++i) {
                        s[2 * (offset + i)]     = static_cast<T>(surround_sanitize(matrix_mc_scratch_[2 * i]));
                        s[2 * (offset + i) + 1] = static_cast<T>(surround_sanitize(matrix_mc_scratch_[2 * i + 1]));
                    }
                    offset += chunk;
                    continue;
                }
                break;
            }
            if (offset == frames) return;
        }

        for (uint32_t i = 0; i < frames; ++i) {
            smooth_center_focus_   += smoothing_coeff_ * (center_focus_ - smooth_center_focus_);
            smooth_surround_boost_ += smoothing_coeff_ * (surround_boost_ - smooth_surround_boost_);
            smooth_surround_delay_ += smoothing_coeff_ * (surround_delay_ms_ - smooth_surround_delay_);

            const double l_in = static_cast<double>(s[2 * i]);
            const double r_in = static_cast<double>(s[2 * i + 1]);

            // 1. LR4 120 Hz LFE Crossover (phase-matched LFE + Front/Surround band split)
            const double l_lo = matrix_lfe_lp2_.processSample(matrix_lfe_lp1_.processSample(l_in, 0), 0);
            const double r_lo = matrix_lfe_lp2_.processSample(matrix_lfe_lp1_.processSample(r_in, 1), 1);
            const double l_hi = matrix_lfe_hp2_.processSample(matrix_lfe_hp1_.processSample(l_in, 0), 0);
            const double r_hi = matrix_lfe_hp2_.processSample(matrix_lfe_hp1_.processSample(r_in, 1), 1);

            const double lfe = 0.5 * (l_lo + r_lo);

            // 2. Active correlation & L/R energy steering (>120 Hz)
            matrix_env_lr_ += matrix_env_coeff_ * (l_hi * r_hi - matrix_env_lr_);
            matrix_env_l2_ += matrix_env_coeff_ * (l_hi * l_hi - matrix_env_l2_);
            matrix_env_r2_ += matrix_env_coeff_ * (r_hi * r_hi - matrix_env_r2_);

            const double denom_e = std::sqrt(matrix_env_l2_ * matrix_env_r2_) + 1.0e-12;
            const double corr = std::clamp(matrix_env_lr_ / denom_e, -1.0, 1.0);
            const double balance = std::clamp((matrix_env_l2_ - matrix_env_r2_) /
                                              (matrix_env_l2_ + matrix_env_r2_ + 1.0e-12), -1.0, 1.0);
            const double c_steer = std::clamp(corr, 0.0, 1.0) * (1.0 - std::fabs(balance));

            const double mid_hi  = 0.5 * (l_hi + r_hi);
            const double side_hi = 0.5 * (l_hi - r_hi);

            // Broadband >120 Hz center extraction & exact front subtraction (zero bandpass phase smear)
            const double c_amt = static_cast<double>(smooth_center_focus_) * c_steer;
            const double c  = mid_hi * c_amt;
            const double fl = l_hi - c;
            const double fr = r_hi - c;

            // 3. Band-limited (120 Hz..7 kHz) Hilbert quadrature surround extraction
            const double side_band = matrix_surr_lp_.processSample(matrix_surr_hp_.processSample(side_hi, 0), 0);
            double q_a = 0.0, q_b = 0.0;
            matrix_hilbert_.process(side_band, q_a, q_b);

            const double ls_steer = std::clamp(0.5 * (1.0 + 0.70 * balance), 0.15, 0.85);
            const double rs_steer = 1.0 - ls_steer;

            const double rear_delay_samples = static_cast<double>(smooth_surround_delay_) * 0.001 * sr;
            const double ls_raw = rear_line_l_.pushAndRead(rear_delay_samples, q_a * ls_steer * 1.4142135623730951);
            const double rs_raw = rear_line_r_.pushAndRead(rear_delay_samples, -q_b * rs_steer * 1.4142135623730951);
            const double ls = rear_diffuser_l_.process(ls_raw);
            const double rs = rear_diffuser_r_.process(rs_raw);

            // 4. Unity-normalized 5.1 Spherical HRTF rendering
            double out_l = 0.0, out_r = 0.0;
            matrix_sources_[0].process(c,  1.0, out_l, out_r); // Center @ 0 deg
            matrix_sources_[1].process(fl, 1.0, out_l, out_r); // Left @ -30 deg
            matrix_sources_[2].process(fr, 1.0, out_l, out_r); // Right @ +30 deg
            const double rb = 0.38 * static_cast<double>(smooth_surround_boost_);
            matrix_sources_[3].process(ls, rb, out_l, out_r);  // Left Surround @ -110 deg
            matrix_sources_[4].process(rs, rb, out_l, out_r);  // Right Surround @ +110 deg

            // Single unity LFE sum (LR4 sum with >120 Hz band = exact 0 dB crossover)
            out_l += lfe;
            out_r += lfe;

            s[2 * i]     = static_cast<T>(surround_sanitize(out_l));
            s[2 * i + 1] = static_cast<T>(surround_sanitize(out_r));
        }
    }

    // -------------------------------------------------------------------------
    // Mode 2: Binaural HRTF Virtualizer (Headphone Room HRTF / Speaker XTC)
    // -------------------------------------------------------------------------
    template <typename T>
    void processBinaural(T *s, uint32_t frames)
    {
        if (binaural_mode_ == 0 && isSofaActive()) {
            // Advance intensity smoother over block so wetMix is smooth
            for (uint32_t i = 0; i < frames; ++i) {
                smooth_binaural_boost_ += smoothing_coeff_ * (binaural_boost_ - smooth_binaural_boost_);
            }
            if (sofa_hrtf_.process(s, frames, 2, 0.7071067811865475, static_cast<double>(smooth_binaural_boost_))) {
                applyBinauralRoomReflections(s, frames);
                return;
            }
        }

        constexpr double PI = 3.14159265358979323846;
        const double sr = static_cast<double>(sample_rate_);
        const double itd_samples = std::max(1.0, 0.00026 * sr); // ~30 deg spherical head ITD (0.26 ms)
        const double fc_sh = std::clamp(static_cast<double>(binaural_shadow_cutoff_) * 0.40, 700.0, 2600.0);
        const double tau_sh = 1.0 / (2.0 * PI * fc_sh);
        const double inv_sr = 1.0 / sr;

        for (uint32_t i = 0; i < frames; ++i) {
            smooth_binaural_boost_ += smoothing_coeff_ * (binaural_boost_ - smooth_binaural_boost_);
            smooth_binaural_room_  += smoothing_coeff_ * (binaural_room_mix_ - smooth_binaural_room_);
            smooth_room_scale_     += smoothing_coeff_ * (target_room_scale_ - smooth_room_scale_);
            smooth_xtc_delay_ms_   += smoothing_coeff_ * (getTargetSpeakerDelayMs() - smooth_xtc_delay_ms_);

            const double l_in = static_cast<double>(s[2 * i]);
            const double r_in = static_cast<double>(s[2 * i + 1]);

            double out_l = l_in;
            double out_r = r_in;

            if (binaural_mode_ == 0) {
                // --- Sub-mode 0: Headphone HRTF + Diffused Shoebox Room ---
                const double b = static_cast<double>(smooth_binaural_boost_);
                const double xf = 0.32 * b;
                const double g_ipsi = 1.0 / (1.0 + xf);
                const double g_contra = xf / (1.0 + xf);

                if (std::fabs(b - last_binaural_baffle_b_) > 1.0e-4) {
                    binaural_baffle_l_.setShadow(1.0 + xf, tau_sh, inv_sr);
                    binaural_baffle_r_.setShadow(1.0 + xf, tau_sh, inv_sr);
                    last_binaural_baffle_b_ = b;
                }

                const double del_r = binaural_itd_r_.pushAndRead(itd_samples, r_in);
                const double del_l = binaural_itd_l_.pushAndRead(itd_samples, l_in);

                const double shadow_r = binaural_shadow_lpf_r_.process(del_r);
                const double shadow_l = binaural_shadow_lpf_l_.process(del_l);
                const double ipsi_l = binaural_baffle_l_.process(l_in);
                const double ipsi_r = binaural_baffle_r_.process(r_in);

                out_l = g_ipsi * ipsi_l + g_contra * shadow_r;
                out_r = g_ipsi * ipsi_r + g_contra * shadow_l;

                // Always keep room delay lines continuously fed so toggling mix has zero stale audio
                if (smooth_binaural_room_ > 1.0e-4) {
                    const double scale_ms = 0.001 * sr * static_cast<double>(smooth_room_scale_);
                    // Symmetric 6-tap binaural early reflections (3 ipsilateral + 3 contralateral)
                    const double il0 = binaural_room_delays_[0].read(9.3 * scale_ms);
                    const double il1 = binaural_room_delays_[0].read(15.7 * scale_ms);
                    const double il2 = binaural_room_delays_[0].read(23.9 * scale_ms);
                    const double cr0 = binaural_room_delays_[1].read(12.1 * scale_ms);
                    const double cr1 = binaural_room_delays_[1].read(19.4 * scale_ms);
                    const double cr2 = binaural_room_delays_[1].read(28.3 * scale_ms);

                    const double ir0 = binaural_room_delays_[1].read(9.3 * scale_ms);
                    const double ir1 = binaural_room_delays_[1].read(15.7 * scale_ms);
                    const double ir2 = binaural_room_delays_[1].read(23.9 * scale_ms);
                    const double cl0 = binaural_room_delays_[0].read(12.1 * scale_ms);
                    const double cl1 = binaural_room_delays_[0].read(19.4 * scale_ms);
                    const double cl2 = binaural_room_delays_[0].read(28.3 * scale_ms);

                    binaural_room_delays_[0].push(l_in);
                    binaural_room_delays_[1].push(r_in);

                    const double raw_l = 0.30 * il0 - 0.22 * il1 + 0.16 * il2 + 0.24 * cr0 - 0.18 * cr1 + 0.12 * cr2;
                    const double raw_r = 0.30 * ir0 - 0.22 * ir1 + 0.16 * ir2 + 0.24 * cl0 - 0.18 * cl1 + 0.12 * cl2;

                    const double diff_l = binaural_room_diffuser_l2_.process(binaural_room_diffuser_l1_.process(raw_l));
                    const double diff_r = binaural_room_diffuser_r2_.process(binaural_room_diffuser_r1_.process(raw_r));
                    const double wet_l = binaural_room_air_l_.process(diff_l);
                    const double wet_r = binaural_room_air_r_.process(diff_r);

                    const double room_wet = 0.34 * static_cast<double>(smooth_binaural_room_);
                    const double direct_g = 1.0 / std::sqrt(1.0 + 0.5 * room_wet * room_wet);
                    out_l = direct_g * out_l + room_wet * wet_l;
                    out_r = direct_g * out_r + room_wet * wet_r;
                } else {
                    binaural_room_delays_[0].push(l_in);
                    binaural_room_delays_[1].push(r_in);
                }
            } else {
                // --- Sub-mode 1: Speaker Field (Band-Limited Recursive RACE XTC) ---
                const double alpha = 0.42 * static_cast<double>(smooth_binaural_boost_);
                const double tau_samples = std::max(1.0, static_cast<double>(smooth_xtc_delay_ms_) * 0.001 * sr);

                const double fb_l = binaural_xtc_delay_l_.read(tau_samples);
                const double fb_r = binaural_xtc_delay_r_.read(tau_samples);

                const double bp_l = binaural_xtc_lp_.processSample(binaural_xtc_hp_.processSample(fb_l, 0), 0);
                const double bp_r = binaural_xtc_lp_.processSample(binaural_xtc_hp_.processSample(fb_r, 1), 1);

                const double y_l = l_in - alpha * bp_r;
                const double y_r = r_in - alpha * bp_l;

                binaural_xtc_delay_l_.push(surround_sanitize(y_l));
                binaural_xtc_delay_r_.push(surround_sanitize(y_r));

                const double norm = 1.0 / (1.0 + 0.30 * alpha);
                out_l = y_l * norm;
                out_r = y_r * norm;
            }

            s[2 * i]     = static_cast<T>(surround_sanitize(out_l));
            s[2 * i + 1] = static_cast<T>(surround_sanitize(out_r));
        }
    }

    // -------------------------------------------------------------------------
    // Mode 3: 3D Acoustic Stage (Profile-Aware XTC + Constant-Power Width +
    //         Diffused Early-Reflection Depth + Unattenuated LR4 Bass Anchor)
    // -------------------------------------------------------------------------
    template <typename T>
    void processStage(T *s, uint32_t frames)
    {
        constexpr double PI = 3.14159265358979323846;
        const double sr = static_cast<double>(sample_rate_);
        const double inv_sr = 1.0 / sr;
        const double itd_samples = std::max(1.0, 0.00024 * sr);
        const double tau_stage_sh = 1.0 / (2.0 * PI * 1600.0);

        const float target_xtc_ms = (stage_mode_ == 1) ? 0.085f : 0.140f;

        for (uint32_t i = 0; i < frames; ++i) {
            smooth_stage_width_  += smoothing_coeff_ * (stage_width_ - smooth_stage_width_);
            smooth_stage_depth_  += smoothing_coeff_ * (stage_depth_ - smooth_stage_depth_);
            smooth_stage_cancel_ += smoothing_coeff_ * (stage_cancellation_ - smooth_stage_cancel_);
            smooth_stage_xtc_ms_ += smoothing_coeff_ * (target_xtc_ms - smooth_stage_xtc_ms_);

            const double l_in = static_cast<double>(s[2 * i]);
            const double r_in = static_cast<double>(s[2 * i + 1]);

            // 0. Capture unattenuated mono sub-bass before spatial processing
            const double mono_in = 0.5 * (l_in + r_in);

            // 1. Transducer-aware spatial stage (0% cancellation = 100% clean bypass)
            const double cancel = static_cast<double>(smooth_stage_cancel_);
            double l_stage = l_in;
            double r_stage = r_in;

            if (stage_profile_ == 1) {
                // Speaker profile: band-limited delayed acoustic crosstalk cancellation
                const double alpha = cancel * ((stage_mode_ == 1) ? 0.40 : 0.28);
                const double tau_samples = std::max(1.0, static_cast<double>(smooth_stage_xtc_ms_) * 0.001 * sr);

                const double fb_l = stage_xtc_delay_l_.read(tau_samples);
                const double fb_r = stage_xtc_delay_r_.read(tau_samples);
                const double bp_l = stage_xtc_lp_.processSample(stage_xtc_hp_.processSample(fb_l, 0), 0);
                const double bp_r = stage_xtc_lp_.processSample(stage_xtc_hp_.processSample(fb_r, 1), 1);

                const double y_l = l_in - alpha * bp_r;
                const double y_r = r_in - alpha * bp_l;
                stage_xtc_delay_l_.push(surround_sanitize(y_l));
                stage_xtc_delay_r_.push(surround_sanitize(y_r));

                const double norm = 1.0 / (1.0 + 0.30 * alpha);
                l_stage = y_l * norm;
                r_stage = y_r * norm;
            } else {
                // Headset profile: subtle head-shadowed out-of-head externalizer
                const double xf = cancel * ((stage_mode_ == 1) ? 0.24 : 0.16);
                const double g_i = 1.0 / (1.0 + xf);
                const double g_c = xf / (1.0 + xf);

                if (std::fabs(cancel - last_stage_baffle_c_) > 1.0e-4 || last_stage_mode_ != stage_mode_) {
                    stage_baffle_l_.setShadow(1.0 + xf, tau_stage_sh, inv_sr);
                    stage_baffle_r_.setShadow(1.0 + xf, tau_stage_sh, inv_sr);
                    last_stage_baffle_c_ = cancel;
                    last_stage_mode_ = stage_mode_;
                }

                const double del_r = stage_itd_r_.pushAndRead(itd_samples, r_in);
                const double del_l = stage_itd_l_.pushAndRead(itd_samples, l_in);
                const double sh_r = stage_shadow_lpf_r_.process(del_r);
                const double sh_l = stage_shadow_lpf_l_.process(del_l);
                const double ip_l = stage_baffle_l_.process(l_in);
                const double ip_r = stage_baffle_r_.process(r_in);

                l_stage = g_i * ip_l + g_c * sh_r;
                r_stage = g_i * ip_r + g_c * sh_l;
            }

            // 2. Constant-power Stereo Soundstage Width Expander
            const double w = static_cast<double>(smooth_stage_width_);
            const double gm = (w > 1.0) ? (1.0 / std::sqrt(1.0 + 0.35 * (w * w - 1.0))) : 1.0;
            const double gs = w * gm;

            const double mid_s  = 0.5 * (l_stage + r_stage);
            const double side_s = 0.5 * (l_stage - r_stage);

            double out_l = gm * mid_s + gs * side_s;
            double out_r = gm * mid_s - gs * side_s;

            // 3. Genuine Acoustic Depth via symmetric diffused early reflections
            const double d_ms = 0.001 * sr;
            if (smooth_stage_depth_ > 1.0e-4) {
                const double il0 = stage_depth_delay_l_.read(9.5 * d_ms);
                const double il1 = stage_depth_delay_l_.read(19.8 * d_ms);
                const double cr0 = stage_depth_delay_r_.read(14.2 * d_ms);
                const double cr1 = stage_depth_delay_r_.read(25.6 * d_ms);

                const double ir0 = stage_depth_delay_r_.read(9.5 * d_ms);
                const double ir1 = stage_depth_delay_r_.read(19.8 * d_ms);
                const double cl0 = stage_depth_delay_l_.read(14.2 * d_ms);
                const double cl1 = stage_depth_delay_l_.read(25.6 * d_ms);

                stage_depth_delay_l_.push(out_l);
                stage_depth_delay_r_.push(out_r);

                const double raw_l = 0.32 * il0 - 0.20 * il1 + 0.26 * cr0 - 0.16 * cr1;
                const double raw_r = 0.32 * ir0 - 0.20 * ir1 + 0.26 * cl0 - 0.16 * cl1;

                const double er_l = stage_depth_air_l_.process(stage_depth_diff_l2_.process(stage_depth_diff_l1_.process(raw_l)));
                const double er_r = stage_depth_air_r_.process(stage_depth_diff_r2_.process(stage_depth_diff_r1_.process(raw_r)));

                const double depth_wet = 0.26 * static_cast<double>(smooth_stage_depth_);
                const double direct_g = 1.0 / std::sqrt(1.0 + 0.40 * depth_wet * depth_wet);
                out_l = direct_g * out_l + depth_wet * er_l;
                out_r = direct_g * out_r + depth_wet * er_r;
            } else {
                stage_depth_delay_l_.push(out_l);
                stage_depth_delay_r_.push(out_r);
            }

            // 4. Unattenuated Sub-bass Fundamental Anchor (64-bit Cytomic LR4 crossover)
            const double anchor_bass = stage_bass_lp2_.processSample(stage_bass_lp1_.processSample(mono_in, 0), 0);
            out_l = stage_bass_hp2_.processSample(stage_bass_hp1_.processSample(out_l, 0), 0) + anchor_bass;
            out_r = stage_bass_hp2_.processSample(stage_bass_hp1_.processSample(out_r, 1), 1) + anchor_bass;

            // 5. De-cramped High-Frequency Air Presence Contour (primarily on Side)
            const double mid_final  = stage_air_mid_.processSample(0.5 * (out_l + out_r), 0);
            const double side_final = stage_air_side_.processSample(0.5 * (out_l - out_r), 0);
            out_l = mid_final + side_final;
            out_r = mid_final - side_final;

            s[2 * i]     = static_cast<T>(surround_sanitize(out_l));
            s[2 * i + 1] = static_cast<T>(surround_sanitize(out_r));
        }
    }

    // ---------------- Delay Lines & Filter Design ----------------
    void buildDelayLines()
    {
        const float sr_scale = srScale();
        const double sr = static_cast<double>(sample_rate_);

        // Matrix rear surrounds & short diffusers
        rear_line_l_.init(static_cast<uint32_t>(35.0f * 0.001f * sample_rate_) + 16u);
        rear_line_r_.init(static_cast<uint32_t>(35.0f * 0.001f * sample_rate_) + 16u);
        rear_line_bl_.init(static_cast<uint32_t>(45.0f * 0.001f * sample_rate_) + 16u);
        rear_line_br_.init(static_cast<uint32_t>(45.0f * 0.001f * sample_rate_) + 16u);
        rear_diffuser_l_.init(110.0f, sr_scale, 0.45); // ~2.3 ms @ 48k
        rear_diffuser_r_.init(149.0f, sr_scale, 0.45); // ~3.1 ms @ 48k

        // Binaural Virtualizer ITD & Speaker XTC delay lines
        const uint32_t itd_buf_size = std::max(256u, static_cast<uint32_t>(sample_rate_ * 0.003f) + 16u);
        binaural_itd_l_.init(itd_buf_size);
        binaural_itd_r_.init(itd_buf_size);
        binaural_xtc_delay_l_.init(itd_buf_size);
        binaural_xtc_delay_r_.init(itd_buf_size);

        // Binaural Room delay lines (up to 60 ms for Concert Hall scaled taps)
        const uint32_t room_buf_size = std::max(1024u, static_cast<uint32_t>(0.060 * sr) + 16u);
        for (int i = 0; i < 2; ++i) {
            binaural_room_delays_[i].init(room_buf_size);
        }
        binaural_room_diffuser_l1_.init(178.0f, sr_scale, 0.48); // ~3.7 ms @ 48k
        binaural_room_diffuser_l2_.init(254.0f, sr_scale, 0.48); // ~5.3 ms @ 48k
        binaural_room_diffuser_r1_.init(178.0f, sr_scale, 0.48);
        binaural_room_diffuser_r2_.init(254.0f, sr_scale, 0.48);
        updateRoomTargets();

        // Acoustic Stage XTC, Headset ITD & Depth early reflections
        stage_xtc_delay_l_.init(itd_buf_size);
        stage_xtc_delay_r_.init(itd_buf_size);
        stage_itd_l_.init(itd_buf_size);
        stage_itd_r_.init(itd_buf_size);

        const uint32_t depth_buf_size = std::max(512u, static_cast<uint32_t>(0.035 * sr) + 16u);
        stage_depth_delay_l_.init(depth_buf_size);
        stage_depth_delay_r_.init(depth_buf_size);
        stage_depth_diff_l1_.init(149.0f, sr_scale, 0.45); // ~3.1 ms @ 48k
        stage_depth_diff_l2_.init(226.0f, sr_scale, 0.45); // ~4.7 ms @ 48k
        stage_depth_diff_r1_.init(149.0f, sr_scale, 0.45);
        stage_depth_diff_r2_.init(226.0f, sr_scale, 0.45);
    }

    void updateRoomTargets()
    {
        if (binaural_room_preset_ == 1) {
            target_room_scale_ = 0.68f; // Studio
        } else if (binaural_room_preset_ == 3) {
            target_room_scale_ = 1.48f; // Concert Hall
        } else {
            target_room_scale_ = 1.00f; // Cinema
        }
    }

    void updateFilters()
    {
        const double fs = static_cast<double>(sample_rate_);
        constexpr double Q_BUTTERWORTH = 0.7071067811865475;

        // Mode 1: Cinema Matrix 120 Hz LR4 LFE crossover & 120 Hz..7 kHz surround bandpass
        matrix_lfe_lp1_.setParameters(CytomicSVF::FilterType::LowPass,  fs, 120.0, 0.0, Q_BUTTERWORTH);
        matrix_lfe_lp2_.setParameters(CytomicSVF::FilterType::LowPass,  fs, 120.0, 0.0, Q_BUTTERWORTH);
        matrix_lfe_hp1_.setParameters(CytomicSVF::FilterType::HighPass, fs, 120.0, 0.0, Q_BUTTERWORTH);
        matrix_lfe_hp2_.setParameters(CytomicSVF::FilterType::HighPass, fs, 120.0, 0.0, Q_BUTTERWORTH);
        matrix_surr_hp_.setParameters(CytomicSVF::FilterType::HighPass, fs, 120.0, 0.0, Q_BUTTERWORTH);
        matrix_surr_lp_.setParameters(CytomicSVF::FilterType::LowPass,  fs, 7000.0, 0.0, Q_BUTTERWORTH);

        // Mode 2: Binaural Headphone diffraction LPF, Room air damping, Speaker XTC bandpass
        const double fc_sh = std::clamp(static_cast<double>(binaural_shadow_cutoff_) * 0.40, 700.0, 2600.0);
        binaural_shadow_lpf_l_.setCutoff(fs, fc_sh);
        binaural_shadow_lpf_r_.setCutoff(fs, fc_sh);
        last_binaural_baffle_b_ = -1.0;

        double room_air_fc = 3400.0;
        if (binaural_room_preset_ == 1) room_air_fc = 4800.0;
        else if (binaural_room_preset_ == 3) room_air_fc = 2400.0;
        binaural_room_air_l_.setCutoff(fs, room_air_fc);
        binaural_room_air_r_.setCutoff(fs, room_air_fc);

        binaural_xtc_hp_.setParameters(CytomicSVF::FilterType::HighPass, fs, 200.0, 0.0, Q_BUTTERWORTH);
        binaural_xtc_lp_.setParameters(CytomicSVF::FilterType::LowPass,  fs, static_cast<double>(binaural_shadow_cutoff_), 0.0, Q_BUTTERWORTH);

        // Mode 3: Acoustic Stage XTC bandpass, Headset diffraction LPF, Depth air damping, LR4 Bass, Air Shelf
        stage_xtc_hp_.setParameters(CytomicSVF::FilterType::HighPass, fs, 220.0, 0.0, Q_BUTTERWORTH);
        stage_xtc_lp_.setParameters(CytomicSVF::FilterType::LowPass,  fs, 5500.0, 0.0, Q_BUTTERWORTH);
        stage_shadow_lpf_l_.setCutoff(fs, 1600.0);
        stage_shadow_lpf_r_.setCutoff(fs, 1600.0);
        stage_depth_air_l_.setCutoff(fs, 3500.0);
        stage_depth_air_r_.setCutoff(fs, 3500.0);

        stage_bass_lp1_.setParameters(CytomicSVF::FilterType::LowPass,  fs, static_cast<double>(stage_bass_anchor_hz_), 0.0, Q_BUTTERWORTH);
        stage_bass_lp2_.setParameters(CytomicSVF::FilterType::LowPass,  fs, static_cast<double>(stage_bass_anchor_hz_), 0.0, Q_BUTTERWORTH);
        stage_bass_hp1_.setParameters(CytomicSVF::FilterType::HighPass, fs, static_cast<double>(stage_bass_anchor_hz_), 0.0, Q_BUTTERWORTH);
        stage_bass_hp2_.setParameters(CytomicSVF::FilterType::HighPass, fs, static_cast<double>(stage_bass_anchor_hz_), 0.0, Q_BUTTERWORTH);

        stage_air_side_.setParameters(CytomicSVF::FilterType::HighShelf, fs, 9500.0, static_cast<double>(stage_air_presence_) * 3.5, Q_BUTTERWORTH);
        stage_air_mid_.setParameters(CytomicSVF::FilterType::HighShelf,  fs, 9500.0, static_cast<double>(stage_air_presence_) * 1.2, Q_BUTTERWORTH);
    }

    void reconfigureHrtf()
    {
        // 5 virtual speaker positions for Cinema Matrix 5.1 + 4 extra for discrete 7.1
        matrix_sources_[0].configure(   0.0f,  0.0f, head_radius_cm_, 0.5f, sample_rate_); // Center
        matrix_sources_[0].setEarMix(1.00, 1.00);

        matrix_sources_[1].configure( -30.0f,  0.0f, head_radius_cm_, 0.6f, sample_rate_); // Left
        matrix_sources_[1].setEarMix(0.72, 0.28);

        matrix_sources_[2].configure(  30.0f,  0.0f, head_radius_cm_, 0.6f, sample_rate_); // Right
        matrix_sources_[2].setEarMix(0.72, 0.28);

        matrix_sources_[3].configure(-110.0f, 10.0f, head_radius_cm_, 0.8f, sample_rate_); // 5.1 Left Surround
        matrix_sources_[3].setEarMix(0.78, 0.22);

        matrix_sources_[4].configure( 110.0f, 10.0f, head_radius_cm_, 0.8f, sample_rate_); // 5.1 Right Surround
        matrix_sources_[4].setEarMix(0.78, 0.22);

        matrix_sources_[5].configure(-150.0f, 10.0f, head_radius_cm_, 0.85f, sample_rate_); // 7.1 Back Left
        matrix_sources_[5].setEarMix(0.76, 0.24);

        matrix_sources_[6].configure( 150.0f, 10.0f, head_radius_cm_, 0.85f, sample_rate_); // 7.1 Back Right
        matrix_sources_[6].setEarMix(0.76, 0.24);

        matrix_sources_[7].configure( -90.0f,  0.0f, head_radius_cm_, 0.75f, sample_rate_); // 7.1 Side Left
        matrix_sources_[7].setEarMix(0.80, 0.20);

        matrix_sources_[8].configure(  90.0f,  0.0f, head_radius_cm_, 0.75f, sample_rate_); // 7.1 Side Right
        matrix_sources_[8].setEarMix(0.80, 0.20);
    }

    // Engine Core State
    bool enabled_ = false;
    SurroundMode mode_ = SurroundMode::Off;
    float sample_rate_ = 0.0f;
    float smoothing_coeff_ = 0.001f;
    double matrix_env_coeff_ = 0.0014;
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
    float target_room_scale_ = 1.0f;

    // --- Mode 3 Parameters ---
    int   stage_profile_ = 0;          // 0=Headset, 1=Speaker
    int   stage_mode_ = 0;             // 0=Studio, 1=Panoramic
    float stage_width_ = 1.2f;         // 0.0 .. 2.0
    float stage_depth_ = 0.5f;         // 0.0 .. 1.0
    float stage_cancellation_ = 0.60f; // 0.0 .. 1.0
    float stage_air_presence_ = 0.40f; // 0.0 .. 1.0
    float stage_bass_anchor_hz_ = 60.0f;

    // Smoothers
    float smooth_center_focus_ = 0.6f;
    float smooth_surround_boost_ = 1.2f;
    float smooth_surround_delay_ = 15.0f;
    float smooth_binaural_boost_ = 0.65f;
    float smooth_binaural_room_ = 0.35f;
    float smooth_room_scale_ = 1.0f;
    float smooth_xtc_delay_ms_ = 0.180f;
    float smooth_stage_width_ = 1.2f;
    float smooth_stage_depth_ = 0.5f;
    float smooth_stage_cancel_ = 0.60f;
    float smooth_stage_xtc_ms_ = 0.140f;
    double last_binaural_baffle_b_ = -1.0;
    double last_stage_baffle_c_ = -1.0;
    int last_stage_mode_ = 0;

    // Mode 1: Cinema Matrix DSP Nodes
    HrtfSource matrix_sources_[9];
    CytomicSVF matrix_lfe_lp1_, matrix_lfe_lp2_;
    CytomicSVF matrix_lfe_hp1_, matrix_lfe_hp2_;
    CytomicSVF matrix_surr_hp_, matrix_surr_lp_;
    SurroundHilbert4 matrix_hilbert_;
    SurroundDelay rear_line_l_, rear_line_r_, rear_line_bl_, rear_line_br_;
    SurroundDiffuserAP rear_diffuser_l_, rear_diffuser_r_;
    double matrix_env_lr_ = 0.0;
    double matrix_env_l2_ = 0.0;
    double matrix_env_r2_ = 0.0;
    std::vector<double> matrix_mc_scratch_;

    // Personal SOFA HRTF renderer (overrides fixed spherical model when loaded & enabled)
    SofaHrtfDSP sofa_hrtf_;
    bool sofa_hrtf_enabled_ = true;

    // Mode 2: Binaural Virtualizer DSP Nodes
    SurroundDelay  binaural_itd_l_, binaural_itd_r_;
    SurroundLPF1   binaural_shadow_lpf_l_, binaural_shadow_lpf_r_;
    SurroundShelf1 binaural_baffle_l_, binaural_baffle_r_;
    SurroundDelay  binaural_room_delays_[2];
    SurroundDiffuserAP binaural_room_diffuser_l1_, binaural_room_diffuser_l2_;
    SurroundDiffuserAP binaural_room_diffuser_r1_, binaural_room_diffuser_r2_;
    SurroundLPF1   binaural_room_air_l_, binaural_room_air_r_;
    SurroundDelay  binaural_xtc_delay_l_, binaural_xtc_delay_r_;
    CytomicSVF     binaural_xtc_hp_, binaural_xtc_lp_;

    // Mode 3: 3D Acoustic Stage DSP Nodes
    SurroundDelay  stage_xtc_delay_l_, stage_xtc_delay_r_;
    CytomicSVF     stage_xtc_hp_, stage_xtc_lp_;
    SurroundDelay  stage_itd_l_, stage_itd_r_;
    SurroundLPF1   stage_shadow_lpf_l_, stage_shadow_lpf_r_;
    SurroundShelf1 stage_baffle_l_, stage_baffle_r_;
    SurroundDelay  stage_depth_delay_l_, stage_depth_delay_r_;
    SurroundDiffuserAP stage_depth_diff_l1_, stage_depth_diff_l2_;
    SurroundDiffuserAP stage_depth_diff_r1_, stage_depth_diff_r2_;
    SurroundLPF1   stage_depth_air_l_, stage_depth_air_r_;
    CytomicSVF     stage_bass_lp1_, stage_bass_lp2_;
    CytomicSVF     stage_bass_hp1_, stage_bass_hp2_;
    CytomicSVF     stage_air_side_, stage_air_mid_;
};

} // namespace sauti::dsp
