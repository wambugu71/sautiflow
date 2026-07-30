#include "AdaptiveLoudness.h"

AdaptiveLoudness::AdaptiveLoudness()
    : enable_(false),
      mode_(NATURAL),
      strength_(1.0f),
      attenuation_db_(0.0f),
      sampling_rate_(44100) {
    Reset();
}

void AdaptiveLoudness::Reset() {
    low_shelf_l_.Reset();
    low_shelf_r_.Reset();
    high_shelf_l_.Reset();
    high_shelf_r_.Reset();
    UpdateCoefficients();
}

void AdaptiveLoudness::SetEnable(bool enable) {
    if (enable_ != enable) {
        enable_ = enable;
        if (!enable_) {
            Reset();
        } else {
            UpdateCoefficients();
        }
    }
}

void AdaptiveLoudness::SetMode(AlcMode mode) {
    if (mode_ != mode) {
        mode_ = mode;
        UpdateCoefficients();
    }
}

void AdaptiveLoudness::SetStrength(float strength) {
    float clamped = std::max(0.0f, std::min(1.0f, strength));
    if (std::abs(strength_ - clamped) > 0.001f) {
        strength_ = clamped;
        UpdateCoefficients();
    }
}

void AdaptiveLoudness::SetVolumeAttenuationDb(float attenuation_db) {
    // Attenuation is 0 dB at full volume, negative (e.g. -20 dB) at reduced volume
    float clamped = std::min(0.0f, attenuation_db);
    if (std::abs(attenuation_db_ - clamped) > 0.1f) {
        attenuation_db_ = clamped;
        UpdateCoefficients();
    }
}

void AdaptiveLoudness::SetSamplingRate(uint32_t sampling_rate) {
    if (sampling_rate_ != sampling_rate && sampling_rate > 0) {
        sampling_rate_ = sampling_rate;
        UpdateCoefficients();
    }
}

void AdaptiveLoudness::UpdateCoefficients() {
    if (!enable_) {
        low_shelf_l_.SetLowShelf(100.0f, 0.0f, (float)sampling_rate_);
        low_shelf_r_.SetLowShelf(100.0f, 0.0f, (float)sampling_rate_);
        high_shelf_l_.SetHighShelf(10000.0f, 0.0f, (float)sampling_rate_);
        high_shelf_r_.SetHighShelf(10000.0f, 0.0f, (float)sampling_rate_);
        return;
    }

    // Calculate effective attenuation below reference
    float abs_att = std::abs(attenuation_db_);

    float bass_scale = 0.35f;
    float treble_scale = 0.15f;
    float max_bass_db = 14.0f;
    float max_treble_db = 6.0f;

    switch (mode_) {
        case MILD:
            bass_scale = 0.22f;
            treble_scale = 0.10f;
            max_bass_db = 8.0f;
            max_treble_db = 4.0f;
            break;
        case PUNCHY:
            bass_scale = 0.45f;
            treble_scale = 0.20f;
            max_bass_db = 18.0f;
            max_treble_db = 8.0f;
            break;
        case NATURAL:
        default:
            bass_scale = 0.35f;
            treble_scale = 0.15f;
            max_bass_db = 14.0f;
            max_treble_db = 6.0f;
            break;
    }

    float target_bass_gain = std::min(max_bass_db, abs_att * bass_scale) * strength_;
    float target_treble_gain = std::min(max_treble_db, abs_att * treble_scale) * strength_;

    low_shelf_l_.SetLowShelf(100.0f, target_bass_gain, (float)sampling_rate_);
    low_shelf_r_.SetLowShelf(100.0f, target_bass_gain, (float)sampling_rate_);

    high_shelf_l_.SetHighShelf(10000.0f, target_treble_gain, (float)sampling_rate_);
    high_shelf_r_.SetHighShelf(10000.0f, target_treble_gain, (float)sampling_rate_);
}

void AdaptiveLoudness::Process(float *samples, uint32_t size) {
    if (!enable_ || !samples || size == 0) return;

    for (uint32_t i = 0; i < size; i += 2) {
        double l = samples[i];
        double r = (i + 1 < size) ? samples[i + 1] : l;

        l = low_shelf_l_.Process(l);
        r = low_shelf_r_.Process(r);

        l = high_shelf_l_.Process(l);
        r = high_shelf_r_.Process(r);

        samples[i] = static_cast<float>(l);
        if (i + 1 < size) {
            samples[i + 1] = static_cast<float>(r);
        }
    }
}
