#ifndef NOMINMAX
#define NOMINMAX
#endif

#if defined(_WIN32) || defined(_WIN64)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>
#endif

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#include "audio_engine.h"
#include "mp4_aac_decoder.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <numeric>
#include <random>
#include <string>
#include <thread>
#include <vector>

#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
#include <curl/curl.h>
#endif

namespace
{

    static std::mutex g_logMutex;

    static void engine_log(const char *fmt, ...)
    {
        std::lock_guard<std::mutex> lk(g_logMutex);

        const auto now = std::chrono::system_clock::now();
        const auto ms = std::chrono::duration_cast<std::chrono::milliseconds>(now.time_since_epoch()).count();

        std::fprintf(stderr, "[audio_engine %lld] ", (long long)ms);

        va_list args;
        va_start(args, fmt);
        std::vfprintf(stderr, fmt, args);
        va_end(args);

        std::fputc('\n', stderr);
        std::fflush(stderr);
    }

    static bool is_network_url(const std::string &s)
    {
        return s.rfind("http://", 0) == 0 || s.rfind("https://", 0) == 0;
    }

#if defined(_WIN32) || defined(_WIN64)
    // Convert a UTF-8 std::string to a UTF-16 std::wstring for Windows API calls.
    // This allows filenames containing Unicode characters (CJK, fullwidth quotes, emoji…)
    // to be opened correctly via ma_decoder_init_file_w.
    static std::wstring utf8_to_wstring(const std::string &utf8)
    {
        if (utf8.empty())
            return {};
        int len = MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), (int)utf8.size(), nullptr, 0);
        if (len <= 0)
            return {};
        std::wstring wide(len, L'\0');
        MultiByteToWideChar(CP_UTF8, 0, utf8.c_str(), (int)utf8.size(), &wide[0], len);
        return wide;
    }
#endif

    struct PushStreamContext
    {
        ma_rb rb;
        void *rbBuffer; // Raw memory for the ring buffer
        std::atomic<bool> initialized{false};
        std::atomic<bool> isDone{false};
        std::mutex mtx; // Just in case we need coord
    };

    static ma_result push_stream_on_read(ma_decoder *pDecoder, void *pBufferOut, size_t bytesToRead, size_t *pBytesRead)
    {
        auto *ctx = reinterpret_cast<PushStreamContext *>(pDecoder->pUserData);
        if (!ctx || !ctx->initialized)
            return MA_INVALID_ARGS;

        *pBytesRead = 0;

        // Non-blocking read from RB
        size_t available = ma_rb_available_read(&ctx->rb);
        if (available == 0)
        {
            if (ctx->isDone)
            {
                return MA_SUCCESS; // EOF
            }
            // Buffer underrun - just return 0 bytes read, miniaudio might interpret as EOF or silence?
            // If we return 0 bytes and not EOF, decoder might stop.
            // We should block slightly or return silence?
            // Standard behavior: if 0 bytes read, it assumes EOF.
            // workaround: we need to block if not done.
            // But blocking in audio thread is bad.
            // However, this is the DECODING thread usually.
            // If `ma_decoder_read` is called from the audio callback directly, blocking is bad.
            // But we are in a custom `onRead`.

            // For now, let's just wait a tiny bit to see if data arrives
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
            available = ma_rb_available_read(&ctx->rb);
            if (available == 0)
                return MA_SUCCESS; // Still empty
        }

        size_t toRead = (bytesToRead < available) ? bytesToRead : available;
        void *pReadBuf = nullptr;
        if (ma_rb_acquire_read(&ctx->rb, &toRead, &pReadBuf) == MA_SUCCESS)
        {
            std::memcpy(pBufferOut, pReadBuf, toRead);
            ma_rb_commit_read(&ctx->rb, toRead);
            *pBytesRead = toRead;
        }

        return MA_SUCCESS;
    }
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
    struct NetworkStreamState
    {
        ma_rb encodedRB{};
        std::mutex mtx;
        std::condition_variable cv;
        std::atomic<bool> stopRequested{false};
        std::atomic<bool> networkDone{false};
        std::atomic<bool> hasError{false};
        std::string url;
        std::thread networkThread;
    };

    static ma_result stream_on_read(ma_decoder *pDecoder, void *pBufferOut, size_t bytesToRead, size_t *pBytesRead)
    {
        if (pDecoder == nullptr || pBufferOut == nullptr || pBytesRead == nullptr)
            return MA_INVALID_ARGS;

        auto *st = reinterpret_cast<NetworkStreamState *>(pDecoder->pUserData);
        if (st == nullptr)
            return MA_INVALID_ARGS;

        *pBytesRead = 0;
        size_t totalRead = 0;

        while (totalRead < bytesToRead)
        {
            void *pRead = nullptr;
            size_t toRead = bytesToRead - totalRead;

            if (ma_rb_acquire_read(&st->encodedRB, &toRead, &pRead) == MA_SUCCESS && toRead > 0)
            {
                std::memcpy((char *)pBufferOut + totalRead, pRead, toRead);
                ma_rb_commit_read(&st->encodedRB, toRead);
                totalRead += toRead;
                continue;
            }

            if (st->stopRequested || (st->networkDone && ma_rb_available_read(&st->encodedRB) == 0))
                break;

            std::unique_lock<std::mutex> lk(st->mtx);
            st->cv.wait_for(lk, std::chrono::milliseconds(40));
        }

        *pBytesRead = totalRead;
        return MA_SUCCESS;
    }

    static ma_result stream_on_seek(ma_decoder *, ma_int64, ma_seek_origin)
    {
        return MA_NOT_IMPLEMENTED;
    }

    static size_t curl_on_write(char *contents, size_t size, size_t nmemb, void *userp)
    {
        auto *st = reinterpret_cast<NetworkStreamState *>(userp);
        if (st == nullptr)
            return 0;

        const size_t total = size * nmemb;
        size_t written = 0;

        while (written < total && !st->stopRequested)
        {
            void *pWrite = nullptr;
            size_t toWrite = total - written;

            if (ma_rb_acquire_write(&st->encodedRB, &toWrite, &pWrite) == MA_SUCCESS && toWrite > 0)
            {
                std::memcpy(pWrite, contents + written, toWrite);
                ma_rb_commit_write(&st->encodedRB, toWrite);
                written += toWrite;
                st->cv.notify_one();
                continue;
            }

            std::this_thread::sleep_for(std::chrono::milliseconds(2));
        }

        return written;
    }

    static int curl_on_progress(void *clientp, curl_off_t, curl_off_t, curl_off_t, curl_off_t)
    {
        auto *st = reinterpret_cast<NetworkStreamState *>(clientp);
        return (st != nullptr && st->stopRequested) ? 1 : 0;
    }

    static NetworkStreamState *create_network_stream(const std::string &url)
    {
        constexpr size_t kEncodedBufferSize = 2 * 1024 * 1024;

        auto *st = new NetworkStreamState();
        st->url = url;
        if (ma_rb_init(kEncodedBufferSize, nullptr, nullptr, &st->encodedRB) != MA_SUCCESS)
        {
            delete st;
            return nullptr;
        }

        st->networkThread = std::thread([st]()
                                        {
            CURL *curl = curl_easy_init();
            if (curl == nullptr)
            {
                st->hasError = true;
                st->networkDone = true;
                st->cv.notify_all();
                return;
            }

            curl_easy_setopt(curl, CURLOPT_URL, st->url.c_str());
            curl_easy_setopt(curl, CURLOPT_FOLLOWLOCATION, 1L);
            curl_easy_setopt(curl, CURLOPT_CONNECTTIMEOUT, 10L);
            curl_easy_setopt(curl, CURLOPT_TIMEOUT, 0L);
            curl_easy_setopt(curl, CURLOPT_WRITEFUNCTION, curl_on_write);
            curl_easy_setopt(curl, CURLOPT_WRITEDATA, st);
            curl_easy_setopt(curl, CURLOPT_FAILONERROR, 1L);
            curl_easy_setopt(curl, CURLOPT_USERAGENT, "MiniAudioDart/1.0");
            curl_easy_setopt(curl, CURLOPT_ACCEPT_ENCODING, "");
            curl_easy_setopt(curl, CURLOPT_NOPROGRESS, 0L);
            curl_easy_setopt(curl, CURLOPT_XFERINFOFUNCTION, curl_on_progress);
            curl_easy_setopt(curl, CURLOPT_XFERINFODATA, st);

            engine_log("network thread start: %s", st->url.c_str());
            CURLcode rc = curl_easy_perform(curl);
            if (rc != CURLE_OK && !st->stopRequested)
            {
                st->hasError = true;
                engine_log("network thread curl error: %s", curl_easy_strerror(rc));
            }

            curl_easy_cleanup(curl);
            st->networkDone = true;
            st->cv.notify_all();
            engine_log("network thread done: %s", st->url.c_str()); });

        return st;
    }

    static void destroy_network_stream(NetworkStreamState *st)
    {
        if (st == nullptr)
            return;
        st->stopRequested = true;
        st->cv.notify_all();
        if (st->networkThread.joinable())
        {
            st->networkThread.join();
        }
        ma_rb_uninit(&st->encodedRB);
        delete st;
    }
#endif

    static inline float clampf(float v, float lo, float hi)
    {
        return (v < lo) ? lo : ((v > hi) ? hi : v);
    }

    static inline double clampd(double v, double lo, double hi)
    {
        return (v < lo) ? lo : ((v > hi) ? hi : v);
    }

    static inline int clampi(int v, int lo, int hi)
    {
        return (v < lo) ? lo : ((v > hi) ? hi : v);
    }

    struct EqState
    {
        float lowGain = 1.0f;
        float midGain = 1.0f;
        float highGain = 1.0f;

        // Per-channel filter memory (supports up to 8 channels comfortably for desktop/mobile).
        float lowMem[8] = {0};
        float highMem[8] = {0};
        float prevIn[8] = {0};

        float lowAlpha = 0.0f;
        float highAlpha = 0.0f;

        void updateCoefficients(int sampleRate)
        {
            const float lowCut = 220.0f;
            const float highCut = 2200.0f;
            const float twoPi = 6.28318530718f;

            lowAlpha = (twoPi * lowCut) / (twoPi * lowCut + (float)sampleRate);
            // High-pass one-pole: y[n] = a * (y[n-1] + x[n] - x[n-1])
            highAlpha = (float)sampleRate / ((float)sampleRate + twoPi * highCut);
        }

        void process(float *interleaved, ma_uint32 frames, int channels)
        {
            const int ch = std::min(channels, 8);
            for (ma_uint32 i = 0; i < frames; ++i)
            {
                for (int c = 0; c < ch; ++c)
                {
                    const size_t idx = (size_t)i * (size_t)channels + (size_t)c;
                    const float x = interleaved[idx];

                    float low = lowMem[c] + lowAlpha * (x - lowMem[c]);
                    float high = highAlpha * (highMem[c] + x - prevIn[c]);
                    float mid = x - low - high;

                    lowMem[c] = low;
                    highMem[c] = high;
                    prevIn[c] = x;

                    interleaved[idx] = low * lowGain + mid * midGain + high * highGain;
                }
            }
        }
    };

    struct ReverbState
    {
        std::vector<float> delayL;
        std::vector<float> delayR;
        size_t idxL = 0;
        size_t idxR = 0;

        float mix = 0.15f;      // Wet/Dry
        float feedback = 0.65f; // Room decay
        float delayMs = 95.0f;  // Base delay

        void reset(int sampleRate)
        {
            const size_t delaySamples = std::max<size_t>(64, (size_t)((delayMs / 1000.0f) * (float)sampleRate));
            delayL.assign(delaySamples, 0.0f);
            delayR.assign(delaySamples + 137, 0.0f); // Slight decorrelation
            idxL = 0;
            idxR = 0;
        }

        void updateParams(int sampleRate, float newMix, float newFeedback, float newDelayMs)
        {
            mix = clampf(newMix, 0.0f, 1.0f);
            feedback = clampf(newFeedback, 0.0f, 0.98f);
            delayMs = clampf(newDelayMs, 20.0f, 350.0f);
            reset(sampleRate);
        }

        void process(float *interleaved, ma_uint32 frames, int channels)
        {
            if (channels < 1 || delayL.empty() || delayR.empty())
            {
                return;
            }

            const bool stereo = channels >= 2;

            for (ma_uint32 i = 0; i < frames; ++i)
            {
                size_t base = (size_t)i * (size_t)channels;

                float inL = interleaved[base];
                float wetL = delayL[idxL];
                delayL[idxL] = inL + wetL * feedback;
                interleaved[base] = inL * (1.0f - mix) + wetL * mix;
                idxL = (idxL + 1) % delayL.size();

                if (stereo)
                {
                    float inR = interleaved[base + 1];
                    float wetR = delayR[idxR];
                    delayR[idxR] = inR + wetR * feedback;
                    interleaved[base + 1] = inR * (1.0f - mix) + wetR * mix;
                    idxR = (idxR + 1) % delayR.size();
                }
            }
        }
    };

    struct OnePoleState
    {
        float alpha = 0.0f;
        float z[8] = {0};
        float prevIn[8] = {0};

        void setLowpassCutoff(float hz, int sampleRate)
        {
            const float twoPi = 6.28318530718f;
            alpha = clampf((twoPi * hz) / (twoPi * hz + (float)sampleRate), 0.0001f, 0.9999f);
        }

        void setHighpassCutoff(float hz, int sampleRate)
        {
            const float twoPi = 6.28318530718f;
            alpha = clampf((float)sampleRate / ((float)sampleRate + twoPi * hz), 0.0001f, 0.9999f);
        }

        void processLowpass(float *interleaved, ma_uint32 frames, int channels)
        {
            const int ch = std::min(channels, 8);
            for (ma_uint32 i = 0; i < frames; ++i)
            {
                for (int c = 0; c < ch; ++c)
                {
                    const size_t idx = (size_t)i * (size_t)channels + (size_t)c;
                    z[c] = z[c] + alpha * (interleaved[idx] - z[c]);
                    interleaved[idx] = z[c];
                }
            }
        }

        void processHighpass(float *interleaved, ma_uint32 frames, int channels)
        {
            const int ch = std::min(channels, 8);
            for (ma_uint32 i = 0; i < frames; ++i)
            {
                for (int c = 0; c < ch; ++c)
                {
                    const size_t idx = (size_t)i * (size_t)channels + (size_t)c;
                    const float x = interleaved[idx];
                    const float y = alpha * (z[c] + x - prevIn[c]);
                    z[c] = y;
                    prevIn[c] = x;
                    interleaved[idx] = y;
                }
            }
        }
    };

    struct DelayState
    {
        std::vector<float> ring;
        size_t idx = 0;
        float mix = 0.2f;
        float feedback = 0.35f;
        float delayMs = 240.0f;
        int channels = 2;

        void reset(int sampleRate, int ch)
        {
            channels = std::max(1, ch);
            const size_t delaySamples = std::max<size_t>(64, (size_t)((delayMs / 1000.0f) * (float)sampleRate));
            ring.assign(delaySamples * (size_t)channels, 0.0f);
            idx = 0;
        }

        void updateParams(int sampleRate, int ch, float m, float fb, float dMs)
        {
            mix = clampf(m, 0.0f, 1.0f);
            feedback = clampf(fb, 0.0f, 0.98f);
            delayMs = clampf(dMs, 10.0f, 1200.0f);
            reset(sampleRate, ch);
        }

        void process(float *interleaved, ma_uint32 frames, int ch)
        {
            if (ring.empty())
                return;
            const int useCh = std::min(ch, channels);
            const size_t stride = (size_t)channels;

            for (ma_uint32 i = 0; i < frames; ++i)
            {
                for (int c = 0; c < useCh; ++c)
                {
                    const size_t outIdx = (size_t)i * (size_t)ch + (size_t)c;
                    const size_t dIdx = idx + (size_t)c;
                    const float dry = interleaved[outIdx];
                    const float wet = ring[dIdx];
                    ring[dIdx] = dry + wet * feedback;
                    interleaved[outIdx] = dry * (1.0f - mix) + wet * mix;
                }
                idx += stride;
                if (idx >= ring.size())
                    idx = 0;
            }
        }
    };

} // namespace

struct AudioEngineHandle
{
    ma_device device{};

    ma_decoder *currentDecoder = nullptr;
    ma_decoder *nextDecoder = nullptr;
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
    NetworkStreamState *currentStream = nullptr;
    NetworkStreamState *nextStream = nullptr;
#endif
    bool hasCurrent = false;
    bool hasNext = false;
    int nextIndex = -1;

    ma_uint64 currentLengthFrames = 0;
    ma_uint64 nextLengthFrames = 0;

    int sampleRate = 48000;
    int channels = 2;

    std::vector<std::string> playlist;
    int currentIndex = -1;
    std::vector<int> playOrder;
    int orderCursor = -1;
    bool shuffleEnabled = false;
    int loopMode = AE_LOOP_ALL;
    std::mt19937 rng{std::random_device{}()};

    std::mutex playlistMutex;
    std::mutex decoderMutex;

    std::mutex workerMutex;
    std::condition_variable workerCv;
    bool workerExit = false;
    bool preloadRequested = false;
    int requestedIndex = -1;

    std::thread worker;

    std::atomic<bool> isPlaying{false};
    std::atomic<bool> crossfadeEnabled{false};
    std::atomic<int> crossfadeDurationMs{250};
    std::atomic<ma_uint64> transitionFadeInFramesRemaining{0};
    std::atomic<ma_uint64> transitionFadeInFramesTotal{0};
    std::atomic<bool> pendingSeekValid{false};
    std::atomic<ma_uint64> pendingSeekFrame{0};
    std::atomic<int> pendingSeekIndex{-1};

    std::mutex fxMutex;
    bool eqEnabled = false;
    bool reverbEnabled = false;
    bool lowpassEnabled = false;
    bool highpassEnabled = false;
    bool delayEnabled = false;
    bool bandpassEnabled = false;
    bool peakEqEnabled = false;
    bool notchEnabled = false;
    bool lowshelfEnabled = false;
    bool highshelfEnabled = false;
    float gain = 1.0f;
    float pan = 0.0f;
    EqState eq;
    ReverbState reverb;
    OnePoleState lowpass;
    OnePoleState highpass;
    DelayState delay;

    float bandpassCutoffHz = 1000.0f;
    float bandpassQ = 0.707f;
    ma_bpf2 bandpass{};

    float peakGainDb = 0.0f;
    float peakQ = 1.0f;
    float peakFrequencyHz = 1000.0f;
    ma_peak2 peakEq{};

    float notchQ = 1.0f;
    float notchFrequencyHz = 1000.0f;
    ma_notch2 notch{};

    float lowshelfGainDb = 0.0f;
    float lowshelfSlope = 1.0f;
    float lowshelfFrequencyHz = 200.0f;
    ma_loshelf2 lowshelf{};

    float highshelfGainDb = 0.0f;
    float highshelfSlope = 1.0f;
    float highshelfFrequencyHz = 4000.0f;
    ma_hishelf2 highshelf{};

    bool customLpf1Enabled = false;
    double customLpf1Cutoff = 1000.0;
    ma_lpf1 customLpf1{};

    bool customHpf1Enabled = false;
    double customHpf1Cutoff = 80.0;
    ma_hpf1 customHpf1{};

    bool customBiquadEnabled = false;
    double bq_b0 = 1.0, bq_b1 = 0.0, bq_b2 = 0.0, bq_a0 = 1.0, bq_a1 = 0.0, bq_a2 = 0.0;
    ma_biquad customBiquad{};

    // Advanced Audio Features
    AEAudioFormat outputFormat = AE_FORMAT_F32;
    int outputSampleRate = 0; // 0 = native
    int outputChannels = 2;   // default stereo

    bool multibandEqEnabled = false;
    int eqBandCount = 0;
    std::mutex eqMutex; // Protect EQ config changes

    int resampleAlgorithm = 0; // AE_RESAMPLE_ALGORITHM_LINEAR
    int ditherMode = 0;        // AE_DITHER_MODE_NONE

    std::vector<float> eqFrequencies;
    std::vector<float> eqGains;
    std::vector<float> eqQ;
    // Each band has one ma_peak2 filter which handles all channels (interleaved)
    std::vector<ma_peak2> eqFilters;

    struct FxBand
    {
        int type = AE_EQ_BAND_PEAK;
        bool enabled = true;
        float frequencyHz = 1000.0f;
        float q = 1.0f;
        float gainDb = 0.0f;
        float slope = 1.0f;

        ma_peak2 peak{};
        ma_bpf2 bandpass{};
        ma_notch2 notch{};
        ma_loshelf2 lowshelf{};
        ma_hishelf2 highshelf{};
    };

    bool multibandFxEnabled = false;
    std::vector<FxBand> multibandFxBands;

    std::atomic<bool> analyzerEnabled{false};
    int analyzerFrameSize = 512;
    std::vector<float> analyzerAccumulator;
    int analyzerAccumulatorCount = 0;
    std::vector<float> analyzerLatest;
    std::mutex analyzerMutex;
    std::atomic<uint64_t> analyzerDroppedFrames{0};

    void update_eq_filters()
    {
        if (eqBandCount <= 0)
        {
            eqFilters.clear();
            return;
        }
        eqFilters.resize(eqBandCount);
        int sr = outputSampleRate > 0 ? outputSampleRate : 48000;
        int ch = outputChannels > 0 ? outputChannels : 2;

        for (int i = 0; i < eqBandCount; ++i)
        {
            ma_peak2_config config = ma_peak2_config_init(
                ma_format_f32,
                (ma_uint32)ch,
                (ma_uint32)sr,
                eqGains[i],
                eqQ[i],
                eqFrequencies[i]);
            ma_peak2_init(&config, nullptr, &eqFilters[i]);
        }
    }

    void process_multiband_eq(float *frames, ma_uint32 frameCount, int channels)
    {
        for (auto &filter : eqFilters)
        {
            ma_peak2_process_pcm_frames(&filter, frames, frames, (ma_uint64)frameCount);
        }
    }

    void update_multiband_fx_filters()
    {
        const int sr = (outputSampleRate > 0) ? outputSampleRate : ((sampleRate > 0) ? sampleRate : 48000);
        const int ch = (outputChannels > 0) ? outputChannels : ((channels > 0) ? channels : 2);
        const ma_uint32 sampleRateU32 = (ma_uint32)sr;
        const ma_uint32 channelsU32 = (ma_uint32)ch;

        for (auto &band : multibandFxBands)
        {
            const float frequencyHz = clampf(band.frequencyHz, 20.0f, (float)sampleRateU32 * 0.45f);
            const float q = clampf(band.q, 0.1f, 18.0f);
            const float gainDb = clampf(band.gainDb, -24.0f, 24.0f);
            const float slope = clampf(band.slope, 0.1f, 2.0f);

            band.frequencyHz = frequencyHz;
            band.q = q;
            band.gainDb = gainDb;
            band.slope = slope;

            switch (band.type)
            {
            case AE_EQ_BAND_BANDPASS:
            {
                ma_bpf2_config config = ma_bpf2_config_init(
                    ma_format_f32,
                    channelsU32,
                    sampleRateU32,
                    frequencyHz,
                    q);
                (void)ma_bpf2_init(&config, nullptr, &band.bandpass);
                break;
            }
            case AE_EQ_BAND_NOTCH:
            {
                ma_notch2_config config = ma_notch2_config_init(
                    ma_format_f32,
                    channelsU32,
                    sampleRateU32,
                    q,
                    frequencyHz);
                (void)ma_notch2_init(&config, nullptr, &band.notch);
                break;
            }
            case AE_EQ_BAND_LOWSHELF:
            {
                ma_loshelf2_config config = ma_loshelf2_config_init(
                    ma_format_f32,
                    channelsU32,
                    sampleRateU32,
                    gainDb,
                    slope,
                    frequencyHz);
                (void)ma_loshelf2_init(&config, nullptr, &band.lowshelf);
                break;
            }
            case AE_EQ_BAND_HIGHSHELF:
            {
                ma_hishelf2_config config = ma_hishelf2_config_init(
                    ma_format_f32,
                    channelsU32,
                    sampleRateU32,
                    gainDb,
                    slope,
                    frequencyHz);
                (void)ma_hishelf2_init(&config, nullptr, &band.highshelf);
                break;
            }
            case AE_EQ_BAND_PEAK:
            default:
            {
                ma_peak2_config config = ma_peak2_config_init(
                    ma_format_f32,
                    channelsU32,
                    sampleRateU32,
                    gainDb,
                    q,
                    frequencyHz);
                (void)ma_peak2_init(&config, nullptr, &band.peak);
                break;
            }
            }
        }
    }

    void process_multiband_fx(float *frames, ma_uint32 frameCount)
    {
        for (auto &band : multibandFxBands)
        {
            if (!band.enabled)
                continue;

            switch (band.type)
            {
            case AE_EQ_BAND_BANDPASS:
                (void)ma_bpf2_process_pcm_frames(&band.bandpass, frames, frames, (ma_uint64)frameCount);
                break;
            case AE_EQ_BAND_NOTCH:
                (void)ma_notch2_process_pcm_frames(&band.notch, frames, frames, (ma_uint64)frameCount);
                break;
            case AE_EQ_BAND_LOWSHELF:
                (void)ma_loshelf2_process_pcm_frames(&band.lowshelf, frames, frames, (ma_uint64)frameCount);
                break;
            case AE_EQ_BAND_HIGHSHELF:
                (void)ma_hishelf2_process_pcm_frames(&band.highshelf, frames, frames, (ma_uint64)frameCount);
                break;
            case AE_EQ_BAND_PEAK:
            default:
                (void)ma_peak2_process_pcm_frames(&band.peak, frames, frames, (ma_uint64)frameCount);
                break;
            }
        }
    }

    void capture_analyzer_frames(const float *frames, ma_uint32 frameCount, int channels)
    {
        if (!analyzerEnabled.load(std::memory_order_relaxed))
            return;
        if (analyzerFrameSize <= 0 || frameCount == 0 || channels <= 0)
            return;
        if ((int)analyzerAccumulator.size() != analyzerFrameSize)
            return;

        const int ch = std::max(1, channels);
        for (ma_uint32 i = 0; i < frameCount; ++i)
        {
            float mono = 0.0f;
            const size_t base = (size_t)i * (size_t)ch;
            for (int c = 0; c < ch; ++c)
            {
                mono += frames[base + (size_t)c];
            }
            mono /= (float)ch;

            if (analyzerAccumulatorCount < analyzerFrameSize)
            {
                analyzerAccumulator[(size_t)analyzerAccumulatorCount++] = mono;
            }

            if (analyzerAccumulatorCount >= analyzerFrameSize)
            {
                if (analyzerMutex.try_lock())
                {
                    analyzerLatest = analyzerAccumulator;
                    analyzerMutex.unlock();
                }
                else
                {
                    analyzerDroppedFrames.fetch_add(1, std::memory_order_relaxed);
                }
                analyzerAccumulatorCount = 0;
            }
        }
    }

    // Temporary buffer for format conversion/resampling if needed
    std::vector<float> conversionBuffer;

    std::mutex errorMutex;
    std::string lastError;

    // Push stream state
    PushStreamContext pushStreamForCurrent; // Single slot for now, for simplicity
    bool isPushStreamMode = false;
};

static void arm_transition_fade_in(AudioEngineHandle *e)
{
    if (e == nullptr)
        return;

    const bool enabled = e->crossfadeEnabled.load(std::memory_order_relaxed);
    if (!enabled)
    {
        e->transitionFadeInFramesTotal.store(0, std::memory_order_relaxed);
        e->transitionFadeInFramesRemaining.store(0, std::memory_order_relaxed);
        return;
    }

    const int durationMs = clampi(e->crossfadeDurationMs.load(std::memory_order_relaxed), 0, 10000);
    if (durationMs <= 0)
    {
        e->transitionFadeInFramesTotal.store(0, std::memory_order_relaxed);
        e->transitionFadeInFramesRemaining.store(0, std::memory_order_relaxed);
        return;
    }

    const int sr = (e->sampleRate > 0) ? e->sampleRate : 48000;
    const ma_uint64 fadeFrames = (ma_uint64)((double)sr * ((double)durationMs / 1000.0));
    if (fadeFrames == 0)
    {
        e->transitionFadeInFramesTotal.store(0, std::memory_order_relaxed);
        e->transitionFadeInFramesRemaining.store(0, std::memory_order_relaxed);
        return;
    }

    e->transitionFadeInFramesTotal.store(fadeFrames, std::memory_order_relaxed);
    e->transitionFadeInFramesRemaining.store(fadeFrames, std::memory_order_relaxed);
}

static void reinit_advanced_fx_filters(AudioEngineHandle *e)
{
    if (e == nullptr)
        return;

    const ma_uint32 sampleRate = (ma_uint32)((e->sampleRate > 0) ? e->sampleRate : 48000);
    const ma_uint32 channels = (ma_uint32)((e->outputChannels > 0) ? e->outputChannels : 2);

    ma_bpf2_config bpfConfig = ma_bpf2_config_init(
        ma_format_f32,
        channels,
        sampleRate,
        clampf(e->bandpassCutoffHz, 20.0f, (float)sampleRate * 0.45f),
        clampf(e->bandpassQ, 0.1f, 18.0f));
    (void)ma_bpf2_init(&bpfConfig, nullptr, &e->bandpass);

    ma_peak2_config peakConfig = ma_peak2_config_init(
        ma_format_f32,
        channels,
        sampleRate,
        clampf(e->peakGainDb, -24.0f, 24.0f),
        clampf(e->peakQ, 0.1f, 18.0f),
        clampf(e->peakFrequencyHz, 20.0f, (float)sampleRate * 0.45f));
    (void)ma_peak2_init(&peakConfig, nullptr, &e->peakEq);

    ma_notch2_config notchConfig = ma_notch2_config_init(
        ma_format_f32,
        channels,
        sampleRate,
        clampf(e->notchQ, 0.1f, 18.0f),
        clampf(e->notchFrequencyHz, 20.0f, (float)sampleRate * 0.45f));
    (void)ma_notch2_init(&notchConfig, nullptr, &e->notch);

    ma_loshelf2_config lowshelfConfig = ma_loshelf2_config_init(
        ma_format_f32,
        channels,
        sampleRate,
        clampf(e->lowshelfGainDb, -24.0f, 24.0f),
        clampf(e->lowshelfSlope, 0.1f, 2.0f),
        clampf(e->lowshelfFrequencyHz, 20.0f, (float)sampleRate * 0.45f));
    (void)ma_loshelf2_init(&lowshelfConfig, nullptr, &e->lowshelf);

    ma_hishelf2_config highshelfConfig = ma_hishelf2_config_init(
        ma_format_f32,
        channels,
        sampleRate,
        clampf(e->highshelfGainDb, -24.0f, 24.0f),
        clampf(e->highshelfSlope, 0.1f, 2.0f),
        clampf(e->highshelfFrequencyHz, 20.0f, (float)sampleRate * 0.45f));
    (void)ma_hishelf2_init(&highshelfConfig, nullptr, &e->highshelf);

    ma_lpf1_config lpf1Cfg = ma_lpf1_config_init(ma_format_f32, channels, sampleRate, e->customLpf1Cutoff);
    (void)ma_lpf1_init(&lpf1Cfg, nullptr, &e->customLpf1);

    ma_hpf1_config hpf1Cfg = ma_hpf1_config_init(ma_format_f32, channels, sampleRate, e->customHpf1Cutoff);
    (void)ma_hpf1_init(&hpf1Cfg, nullptr, &e->customHpf1);

    ma_biquad_config bqCfg = ma_biquad_config_init(ma_format_f32, channels, e->bq_b0, e->bq_b1, e->bq_b2, e->bq_a0, e->bq_a1, e->bq_a2);
    (void)ma_biquad_init(&bqCfg, nullptr, &e->customBiquad);
}

static void set_last_error(AudioEngineHandle *e, const std::string &message)
{
    if (e == nullptr)
        return;
    std::lock_guard<std::mutex> lk(e->errorMutex);
    e->lastError = message;
    engine_log("ERROR: %s", message.c_str());
}

static void clear_last_error(AudioEngineHandle *e)
{
    if (e == nullptr)
        return;
    std::lock_guard<std::mutex> lk(e->errorMutex);
    e->lastError.clear();
}

static void uninit_decoder_ptr(ma_decoder *&pDecoder)
{
    if (pDecoder != nullptr)
    {
        ma_decoder_uninit(pDecoder);
        delete pDecoder;
        pDecoder = nullptr;
    }
}

static void uninit_decoder_slot(
    ma_decoder *&pDecoder
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
    ,
    NetworkStreamState *&pStream
#endif
)
{
    uninit_decoder_ptr(pDecoder);
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
    destroy_network_stream(pStream);
    pStream = nullptr;
#endif
}

static bool load_decoder_for_path(
    AudioEngineHandle *e,
    const std::string &path,
    ma_decoder **outDecoder,
    ma_uint64 *outLength
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
    ,
    NetworkStreamState **outStream
#endif
)
{
    if (e == nullptr || outDecoder == nullptr || outLength == nullptr)
    {
        return false;
    }

    ma_uint32 outCh = (e->outputChannels > 0) ? (ma_uint32)e->outputChannels : 2;
    ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, outCh, (ma_uint32)e->sampleRate);
    static ma_decoding_backend_vtable *pCustomDecoders[] = {&g_ma_decoding_backend_vtable_mp4_aac};
    cfg.pCustomBackendUserData = nullptr;
    cfg.ppCustomBackendVTables = pCustomDecoders;
    cfg.customBackendCount = 1;

#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
    if (is_network_url(path))
    {
        auto *st = create_network_stream(path);
        if (st == nullptr)
        {
            set_last_error(e, std::string("Failed to initialize network stream: ") + path);
            return false;
        }

        constexpr size_t kInitPrebufferBytes = 64 * 1024;
        while (!st->stopRequested && !st->networkDone && ma_rb_available_read(&st->encodedRB) < kInitPrebufferBytes)
        {
            std::unique_lock<std::mutex> lk(st->mtx);
            st->cv.wait_for(lk, std::chrono::milliseconds(30));
        }

        ma_decoder *tmp = new ma_decoder{};
        engine_log("decoder_init(stream callback): %s", path.c_str());
        ma_result r = ma_decoder_init(stream_on_read, stream_on_seek, st, &cfg, tmp);
        if (r != MA_SUCCESS)
        {
            delete tmp;
            destroy_network_stream(st);
            set_last_error(e, std::string("Failed to initialize stream decoder: ") + path);
            engine_log("decoder_init(stream) failed (ma_result=%d) for: %s", (int)r, path.c_str());
            return false;
        }

        ma_uint64 len = 0;
        (void)ma_decoder_get_length_in_pcm_frames(tmp, &len);

        *outDecoder = tmp;
        *outLength = len;
        if (outStream != nullptr)
            *outStream = st;
        clear_last_error(e);
        engine_log("decoder_init(stream) success: %s", path.c_str());
        return true;
    }
#else
    if (is_network_url(path))
    {
        set_last_error(e, std::string("Network URL playback not enabled in this build: ") + path);
        return false;
    }
#endif

    ma_decoder *tmp = new ma_decoder{};
    engine_log("decoder_init_file: %s", path.c_str());
#if defined(_WIN32) || defined(_WIN64)
    // Use the wide-character API so that Unicode paths (fullwidth chars, CJK,
    // emoji, etc.) are opened correctly by the Windows filesystem.
    std::wstring wpath = utf8_to_wstring(path);
    ma_result r = ma_decoder_init_file_w(wpath.c_str(), &cfg, tmp);
#else
    ma_result r = ma_decoder_init_file(path.c_str(), &cfg, tmp);
#endif
    if (r != MA_SUCCESS)
    {
        set_last_error(e, std::string("Failed to decode file: ") + path);
        engine_log("decoder_init_file failed (ma_result=%d) for: %s", (int)r, path.c_str());
        delete tmp;
        return false;
    }

    ma_uint64 len = 0;
    (void)ma_decoder_get_length_in_pcm_frames(tmp, &len);

    *outDecoder = tmp;
    *outLength = len;
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
    if (outStream != nullptr)
        *outStream = nullptr;
#endif
    engine_log("decoder_init_file success: %s (frames=%llu)", path.c_str(), (unsigned long long)len);
    clear_last_error(e);
    return true;
}

static void rebuild_play_order_locked(AudioEngineHandle *e)
{
    e->playOrder.resize(e->playlist.size());
    std::iota(e->playOrder.begin(), e->playOrder.end(), 0);

    if (e->shuffleEnabled && e->playOrder.size() > 1)
    {
        std::shuffle(e->playOrder.begin(), e->playOrder.end(), e->rng);
    }

    if (e->currentIndex >= 0 && !e->playOrder.empty())
    {
        auto it = std::find(e->playOrder.begin(), e->playOrder.end(), e->currentIndex);
        e->orderCursor = (it == e->playOrder.end()) ? 0 : (int)std::distance(e->playOrder.begin(), it);
    }
    else
    {
        e->orderCursor = e->playOrder.empty() ? -1 : 0;
    }
}

static int next_index_locked(AudioEngineHandle *e)
{
    if (e->playlist.empty())
        return -1;
    if (e->loopMode == AE_LOOP_ONE && e->currentIndex >= 0)
        return e->currentIndex;

    if (e->playOrder.empty())
    {
        rebuild_play_order_locked(e);
    }
    if (e->playOrder.empty())
        return -1;

    if (e->orderCursor < 0)
    {
        e->orderCursor = 0;
        return e->playOrder[0];
    }

    int nextPos = e->orderCursor + 1;
    if (nextPos >= (int)e->playOrder.size())
    {
        if (e->loopMode == AE_LOOP_OFF)
        {
            return -1;
        }
        nextPos = 0;
    }

    return e->playOrder[nextPos];
}

static int prev_index_locked(AudioEngineHandle *e)
{
    if (e->playlist.empty())
        return -1;
    if (e->loopMode == AE_LOOP_ONE && e->currentIndex >= 0)
        return e->currentIndex;

    if (e->playOrder.empty())
    {
        rebuild_play_order_locked(e);
    }
    if (e->playOrder.empty())
        return -1;

    if (e->orderCursor < 0)
    {
        e->orderCursor = 0;
        return e->playOrder[0];
    }

    int prevPos = e->orderCursor - 1;
    if (prevPos < 0)
    {
        if (e->loopMode == AE_LOOP_OFF)
        {
            return -1;
        }
        prevPos = (int)e->playOrder.size() - 1;
    }
    return e->playOrder[prevPos];
}

static void set_order_cursor_for_index_locked(AudioEngineHandle *e, int index)
{
    if (e->playOrder.empty())
    {
        rebuild_play_order_locked(e);
    }
    auto it = std::find(e->playOrder.begin(), e->playOrder.end(), index);
    e->orderCursor = (it == e->playOrder.end()) ? -1 : (int)std::distance(e->playOrder.begin(), it);
}

static void request_preload(AudioEngineHandle *e)
{
    std::lock_guard<std::mutex> lk(e->workerMutex);
    e->preloadRequested = true;
    e->workerCv.notify_one();
}

static void request_jump(AudioEngineHandle *e, int idx)
{
    std::lock_guard<std::mutex> lk(e->workerMutex);
    e->requestedIndex = idx;
    e->workerCv.notify_one();
}

static void worker_loop(AudioEngineHandle *e)
{
    while (true)
    {
        int jumpIndex = -1;
        bool doPreload = false;

        {
            std::unique_lock<std::mutex> lk(e->workerMutex);
            e->workerCv.wait(lk, [&]()
                             { return e->workerExit || e->requestedIndex >= 0 || e->preloadRequested; });

            if (e->workerExit)
            {
                return;
            }

            jumpIndex = e->requestedIndex;
            doPreload = e->preloadRequested;
            e->requestedIndex = -1;
            e->preloadRequested = false;
        }

        if (jumpIndex >= 0)
        {
            std::string path;
            int playlistCount = 0;
            {
                std::lock_guard<std::mutex> pl(e->playlistMutex);
                playlistCount = (int)e->playlist.size();
                if (jumpIndex < 0 || jumpIndex >= playlistCount)
                {
                    continue;
                }
                path = e->playlist[(size_t)jumpIndex];
            }

            ma_decoder *newCurrent = nullptr;
            ma_uint64 newCurrentLen = 0;
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
            NetworkStreamState *newCurrentStream = nullptr;
#endif
            engine_log("worker jump request -> index=%d", jumpIndex);
            if (!load_decoder_for_path(
                    e,
                    path,
                    &newCurrent,
                    &newCurrentLen
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                    ,
                    &newCurrentStream
#endif
                    ))
            {
                engine_log("worker jump failed to load index=%d", jumpIndex);
                continue;
            }

            int computedNextIndex = -1;

            {
                std::lock_guard<std::mutex> pl(e->playlistMutex);
                e->currentIndex = jumpIndex;
                set_order_cursor_for_index_locked(e, jumpIndex);
                computedNextIndex = next_index_locked(e);
            }

            {
                std::lock_guard<std::mutex> d(e->decoderMutex);
                if (e->hasCurrent)
                {
                    uninit_decoder_slot(
                        e->currentDecoder
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                        ,
                        e->currentStream
#endif
                    );
                    e->hasCurrent = false;
                }
                if (e->hasNext)
                {
                    uninit_decoder_slot(
                        e->nextDecoder
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                        ,
                        e->nextStream
#endif
                    );
                    e->hasNext = false;
                }

                e->currentDecoder = newCurrent;
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                e->currentStream = newCurrentStream;
#endif
                e->currentLengthFrames = newCurrentLen;
                e->currentIndex = jumpIndex;
                e->hasCurrent = true;
                arm_transition_fade_in(e);

                if (e->pendingSeekValid.load(std::memory_order_acquire) &&
                    e->pendingSeekIndex.load(std::memory_order_acquire) == jumpIndex)
                {
                    const ma_uint64 frame = e->pendingSeekFrame.load(std::memory_order_acquire);
                    const ma_result seekRc = ma_decoder_seek_to_pcm_frame(e->currentDecoder, frame);
                    if (seekRc != MA_SUCCESS)
                    {
                        engine_log("worker pending seek failed (ma_result=%d) index=%d", (int)seekRc, jumpIndex);
                        set_last_error(e, "Seek failed after jump.");
                    }
                    e->pendingSeekValid.store(false, std::memory_order_release);
                    e->pendingSeekIndex.store(-1, std::memory_order_release);
                }

#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                e->nextStream = nullptr;
#endif
                e->nextDecoder = nullptr;
                e->nextIndex = -1;
                e->nextLengthFrames = 0;
                e->hasNext = false;
            }

            request_preload(e);
            engine_log("worker jump complete -> current=%d next=%d", jumpIndex, computedNextIndex);
        }

        if (doPreload)
        {
            int localCurrentIndex = -1;
            {
                std::lock_guard<std::mutex> d(e->decoderMutex);
                localCurrentIndex = e->currentIndex;
                if (!e->hasCurrent || e->hasNext)
                {
                    continue;
                }
            }

            std::string nextPath;
            int nextIdx = -1;
            {
                std::lock_guard<std::mutex> pl(e->playlistMutex);
                if (e->playlist.size() <= 1 || localCurrentIndex < 0)
                {
                    continue;
                }
                set_order_cursor_for_index_locked(e, localCurrentIndex);
                nextIdx = next_index_locked(e);
                if (nextIdx < 0 || nextIdx == localCurrentIndex)
                {
                    continue;
                }
                nextPath = e->playlist[(size_t)nextIdx];
            }

            ma_decoder *decoded = nullptr;
            ma_uint64 len = 0;
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
            NetworkStreamState *decodedStream = nullptr;
#endif
            if (!load_decoder_for_path(
                    e,
                    nextPath,
                    &decoded,
                    &len
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                    ,
                    &decodedStream
#endif
                    ))
            {
                engine_log("worker preload failed -> nextIndex=%d", nextIdx);
                continue;
            }

            {
                std::lock_guard<std::mutex> d(e->decoderMutex);
                if (!e->hasNext)
                {
                    e->nextDecoder = decoded;
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                    e->nextStream = decodedStream;
#endif
                    e->nextLengthFrames = len;
                    e->nextIndex = nextIdx;
                    e->hasNext = true;
                }
                else
                {
                    uninit_decoder_slot(
                        decoded
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                        ,
                        decodedStream
#endif
                    );
                }
            }

            engine_log("worker preload complete -> nextIndex=%d", nextIdx);
        }
    }
}

static void data_callback(ma_device *pDevice, void *pOutput, const void *, ma_uint32 frameCount)
{
    AudioEngineHandle *e = reinterpret_cast<AudioEngineHandle *>(pDevice->pUserData);

    float *processBuffer = nullptr;
    ma_uint32 totalSamples = frameCount * (ma_uint32)e->outputChannels;

    if (e->outputFormat == AE_FORMAT_F32)
    {
        processBuffer = reinterpret_cast<float *>(pOutput);
    }
    else
    {
        if (e->conversionBuffer.size() < totalSamples)
        {
            e->conversionBuffer.resize(totalSamples);
        }
        processBuffer = e->conversionBuffer.data();
    }

    // Zero out buffer (silence)
    std::memset(processBuffer, 0, totalSamples * sizeof(float));

    if (!e->isPlaying.load(std::memory_order_relaxed))
    {
        // If stopping, just return silence (already zeroed above)
        // If format is not F32, we need to zero pOutput too? No, conversion later handles it.
        // Wait, if not playing, we return so silence.
        // If format != F32, we must ensure pOutput is zeroed.
        if (e->outputFormat != AE_FORMAT_F32)
        {
            size_t bytesPerSample = 1;
            if (e->outputFormat == AE_FORMAT_S16)
                bytesPerSample = 2;
            else if (e->outputFormat == AE_FORMAT_S24)
                bytesPerSample = 3;
            else if (e->outputFormat == AE_FORMAT_S32)
                bytesPerSample = 4;

            std::memset(pOutput, 0, totalSamples * bytesPerSample);
        }
        return;
    }

    ma_uint32 produced = 0;

    {
        std::lock_guard<std::mutex> d(e->decoderMutex);

        while (produced < frameCount)
        {
            // Lazy-init push stream decoder if needed (and we have enough data)
            if (e->isPushStreamMode && e->currentDecoder == nullptr && e->pushStreamForCurrent.initialized)
            {
                // Check if we have enough data to likely succeed with header detection
                // 4KB is usually plenty for mp3/wav headers.
                if (ma_rb_available_read(&e->pushStreamForCurrent.rb) >= 4096)
                {
                    ma_format configFormat = ma_format_f32;
                    if (e->outputFormat == AE_FORMAT_S16)
                        configFormat = ma_format_s16;
                    else if (e->outputFormat == AE_FORMAT_U8)
                        configFormat = ma_format_u8;
                    else if (e->outputFormat == AE_FORMAT_S24)
                        configFormat = ma_format_s24;
                    else if (e->outputFormat == AE_FORMAT_S32)
                        configFormat = ma_format_s32;

                    ma_uint32 outCh = (e->outputChannels > 0) ? (ma_uint32)e->outputChannels : 2;
                    ma_decoder_config config = ma_decoder_config_init(configFormat, outCh, (ma_uint32)e->sampleRate);

                    // ma_decoder must be zero-initialized before init.
                    // Using default-initialization here can leave garbage fields
                    // and cause rare crashes on some Android devices.
                    auto *newDecoder = new ma_decoder{};
                    ma_result result = ma_decoder_init(push_stream_on_read, nullptr, &e->pushStreamForCurrent, &config, newDecoder);
                    if (result == MA_SUCCESS)
                    {
                        e->currentDecoder = newDecoder;
                        e->hasCurrent = true;
                    }
                    else
                    {
                        // Failed to init, maybe bad data or not enough?
                        // If we fail, we probably should stop trying appropriately, but for now just cleanup
                        delete newDecoder;
                        break; // Will output silence this frame
                    }
                }
                else
                {
                    // Wait for more data
                    break;
                }
            }

            if (!e->hasCurrent || e->currentDecoder == nullptr)
            {
                break;
            }

            ma_uint64 framesRead = 0;
            ma_result r = ma_decoder_read_pcm_frames(
                e->currentDecoder,
                processBuffer + ((size_t)produced * (size_t)e->outputChannels),
                (ma_uint64)(frameCount - produced),
                &framesRead);

            // If framesRead > 0, we have data.
            produced += (ma_uint32)framesRead;

            if (framesRead == 0 || r == MA_AT_END)
            {
                // Try next track
                if (e->hasNext)
                {
                    uninit_decoder_slot(
                        e->currentDecoder
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                        ,
                        e->currentStream
#endif
                    );
                    e->currentDecoder = e->nextDecoder;
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                    e->currentStream = e->nextStream;
#endif
                    e->currentLengthFrames = e->nextLengthFrames;
                    e->currentIndex = e->nextIndex;
                    e->hasCurrent = true;

                    {
                        std::lock_guard<std::mutex> pl(e->playlistMutex);
                        set_order_cursor_for_index_locked(e, e->currentIndex);
                    }

                    e->hasNext = false;
                    e->nextDecoder = nullptr;
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                    e->nextStream = nullptr;
#endif
                    e->nextIndex = -1;
                    e->nextLengthFrames = 0;
                    arm_transition_fade_in(e);

                    request_preload(e);
                    continue;
                }

                if (e->loopMode == AE_LOOP_ONE && e->hasCurrent)
                {
                    (void)ma_decoder_seek_to_pcm_frame(e->currentDecoder, 0);
                    continue;
                }

                // End of playlist
                e->isPlaying.store(false, std::memory_order_relaxed);
                break;
            }

            if (r != MA_SUCCESS)
            {
                engine_log("decoder_read_pcm_frames failed (ma_result=%d), stopping playback", (int)r);
                e->isPlaying.store(false, std::memory_order_relaxed);
                break;
            }
        }
    }

    if (produced > 0)
    {
        ma_uint64 fadeRemaining = e->transitionFadeInFramesRemaining.load(std::memory_order_relaxed);
        const ma_uint64 fadeTotal = e->transitionFadeInFramesTotal.load(std::memory_order_relaxed);
        if (fadeRemaining > 0 && fadeTotal > 0)
        {
            ma_uint64 processed = (fadeTotal > fadeRemaining) ? (fadeTotal - fadeRemaining) : 0;
            for (ma_uint32 i = 0; i < produced && fadeRemaining > 0; ++i)
            {
                const float t = clampf((float)(processed + (ma_uint64)i) / (float)fadeTotal, 0.0f, 1.0f);
                const size_t base = (size_t)i * (size_t)e->outputChannels;
                for (int c = 0; c < e->outputChannels; ++c)
                {
                    processBuffer[base + (size_t)c] *= t;
                }
                fadeRemaining -= 1;
            }
            e->transitionFadeInFramesRemaining.store(fadeRemaining, std::memory_order_relaxed);
        }

        std::lock_guard<std::mutex> fx(e->fxMutex);

        // Volume
        if (e->gain != 1.0f)
        {
            float vol = e->gain;
            for (size_t i = 0; i < produced * e->outputChannels; ++i)
                processBuffer[i] *= vol;
        }

        // Pan (Assume Stereo or more)
        if (e->outputChannels >= 2 && e->pan != 0.0f)
        {
            float p = e->pan;
            const float l = clampf(1.0f - std::max(0.0f, p), 0.0f, 1.0f);
            const float r = clampf(1.0f + std::min(0.0f, p), 0.0f, 1.0f);
            for (ma_uint32 i = 0; i < produced; ++i)
            {
                processBuffer[i * e->outputChannels] *= l;
                processBuffer[i * e->outputChannels + 1] *= r;
            }
        }

        // Multiband EQ and mixed multiband FX
        std::lock_guard<std::mutex> eqLock(e->eqMutex);
        if (e->multibandEqEnabled)
        {
            e->process_multiband_eq(processBuffer, produced, e->outputChannels);
        }
        if (e->multibandFxEnabled)
        {
            e->process_multiband_fx(processBuffer, produced);
        }

        // Custom Filter Elements
        if (e->customLpf1Enabled)
            (void)ma_lpf1_process_pcm_frames(&e->customLpf1, processBuffer, processBuffer, produced);
        if (e->customHpf1Enabled)
            (void)ma_hpf1_process_pcm_frames(&e->customHpf1, processBuffer, processBuffer, produced);
        if (e->customBiquadEnabled)
            (void)ma_biquad_process_pcm_frames(&e->customBiquad, processBuffer, processBuffer, produced);

        // Existing Effects
        // Note: passing e->outputChannels instead of e->channels
        if (e->lowpassEnabled)
            e->lowpass.processLowpass(processBuffer, produced, e->outputChannels);
        if (e->highpassEnabled)
            e->highpass.processHighpass(processBuffer, produced, e->outputChannels);
        if (e->bandpassEnabled)
            (void)ma_bpf2_process_pcm_frames(&e->bandpass, processBuffer, processBuffer, (ma_uint64)produced);
        // Delay (Check channel layout support in DelayState - assumes stereo?)
        if (e->delayEnabled)
            e->delay.process(processBuffer, produced, e->outputChannels);
        if (e->peakEqEnabled)
            (void)ma_peak2_process_pcm_frames(&e->peakEq, processBuffer, processBuffer, (ma_uint64)produced);
        if (e->notchEnabled)
            (void)ma_notch2_process_pcm_frames(&e->notch, processBuffer, processBuffer, (ma_uint64)produced);
        if (e->lowshelfEnabled)
            (void)ma_loshelf2_process_pcm_frames(&e->lowshelf, processBuffer, processBuffer, (ma_uint64)produced);
        if (e->highshelfEnabled)
            (void)ma_hishelf2_process_pcm_frames(&e->highshelf, processBuffer, processBuffer, (ma_uint64)produced);
        // Old 3-band EQ
        if (e->eqEnabled)
            e->eq.process(processBuffer, produced, e->outputChannels);
        if (e->reverbEnabled)
            e->reverb.process(processBuffer, produced, e->outputChannels);

        e->capture_analyzer_frames(processBuffer, produced, e->outputChannels);
    }

    // Format Conversion if needed
    ma_dither_mode maDither = ma_dither_mode_none;
    if (e->ditherMode == 1)
        maDither = ma_dither_mode_rectangle;
    else if (e->ditherMode == 2)
        maDither = ma_dither_mode_triangle;

    if (e->outputFormat == AE_FORMAT_S16)
    {
        ma_pcm_f32_to_s16(pOutput, processBuffer, totalSamples, maDither);
    }
    else if (e->outputFormat == AE_FORMAT_U8)
    {
        ma_pcm_f32_to_u8(pOutput, processBuffer, totalSamples, maDither);
    }
    else if (e->outputFormat == AE_FORMAT_S24)
    {
        ma_pcm_f32_to_s24(pOutput, processBuffer, totalSamples, maDither);
    }
    else if (e->outputFormat == AE_FORMAT_S32)
    {
        ma_pcm_f32_to_s32(pOutput, processBuffer, totalSamples, maDither);
    }
    // else F32 -> already in pOutput
}

extern "C"
{

    AE_API AudioEngineHandle *ae_create_engine(int sample_rate, int channels)
    {
        if (sample_rate <= 0)
            sample_rate = 48000;
        if (channels <= 0)
            channels = 2;

#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
        static std::once_flag gCurlInitOnce;
        std::call_once(gCurlInitOnce, []()
                       {
            const auto rc = curl_global_init(CURL_GLOBAL_DEFAULT);
            if (rc != CURLE_OK)
            {
                engine_log("curl_global_init failed: %d", (int)rc);
            } });
#endif

        AudioEngineHandle *e = new AudioEngineHandle();
        e->sampleRate = sample_rate;
        e->channels = channels;

        e->eq.updateCoefficients(sample_rate);
        e->reverb.reset(sample_rate);
        e->lowpass.setLowpassCutoff(12000.0f, sample_rate);
        e->highpass.setHighpassCutoff(80.0f, sample_rate);
        e->delay.reset(sample_rate, channels);
        reinit_advanced_fx_filters(e);

        e->analyzerFrameSize = 512;
        e->analyzerAccumulator.assign((size_t)e->analyzerFrameSize, 0.0f);
        e->analyzerLatest.assign((size_t)e->analyzerFrameSize, 0.0f);
        e->analyzerAccumulatorCount = 0;

        // Initialize advanced settings
        e->outputSampleRate = sample_rate;
        e->outputChannels = channels;
        // Default format is F32
        e->outputFormat = AE_FORMAT_F32;

        ma_device_config cfg = ma_device_config_init(ma_device_type_playback);
        cfg.playback.format = ma_format_f32;
        cfg.playback.channels = (ma_uint32)channels;
        cfg.sampleRate = (ma_uint32)sample_rate;
        cfg.dataCallback = data_callback;
        cfg.pUserData = e;

        if (e->resampleAlgorithm == 1)
        { // AE_RESAMPLE_ALGORITHM_CUSTOM
            cfg.resampling.algorithm = ma_resample_algorithm_custom;
        }
        else
        {
            cfg.resampling.algorithm = ma_resample_algorithm_linear;
        }

        if (ma_device_init(nullptr, &cfg, &e->device) != MA_SUCCESS)
        {
            set_last_error(e, "Failed to initialize playback device.");
            delete e;
            return nullptr;
        }

        if (ma_device_start(&e->device) != MA_SUCCESS)
        {
            set_last_error(e, "Failed to start playback device.");
            ma_device_uninit(&e->device);
            delete e;
            return nullptr;
        }

        engine_log("engine created (sampleRate=%d channels=%d)", sample_rate, channels);
        e->worker = std::thread(worker_loop, e);
        return e;
    }

    AE_API void ae_destroy_engine(AudioEngineHandle *e)
    {
        if (e == nullptr)
            return;

        engine_log("destroy_engine begin");

        {
            std::lock_guard<std::mutex> lk(e->workerMutex);
            e->workerExit = true;
            e->workerCv.notify_one();
        }

        if (e->worker.joinable())
        {
            e->worker.join();
        }

        {
            std::lock_guard<std::mutex> d(e->decoderMutex);
            if (e->hasCurrent)
            {
                uninit_decoder_slot(
                    e->currentDecoder
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                    ,
                    e->currentStream
#endif
                );
                e->hasCurrent = false;
            }
            if (e->hasNext)
            {
                uninit_decoder_slot(
                    e->nextDecoder
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                    ,
                    e->nextStream
#endif
                );
                e->hasNext = false;
            }

            // Cleanup Push Stream if allocated
            if (e->pushStreamForCurrent.initialized)
            {
                ma_rb_uninit(&e->pushStreamForCurrent.rb);
                if (e->pushStreamForCurrent.rbBuffer)
                {
                    std::free(e->pushStreamForCurrent.rbBuffer);
                    e->pushStreamForCurrent.rbBuffer = nullptr;
                }
                e->pushStreamForCurrent.initialized = false;
            }
        }

        ma_device_uninit(&e->device);
        engine_log("destroy_engine end");
        delete e;
    }

    AE_API bool ae_set_playlist(AudioEngineHandle *e, const char **paths, int count)
    {
        if (e == nullptr || paths == nullptr || count <= 0)
        {
            set_last_error(e, "Invalid playlist input.");
            return false;
        }

        std::vector<std::string> incoming;
        incoming.reserve((size_t)count);
        for (int i = 0; i < count; ++i)
        {
            if (paths[i] != nullptr && paths[i][0] != '\0')
            {
                incoming.emplace_back(paths[i]);
            }
        }

        if (incoming.empty())
        {
            set_last_error(e, "Playlist is empty after filtering invalid paths.");
            return false;
        }

        {
            std::lock_guard<std::mutex> pl(e->playlistMutex);
            e->playlist = std::move(incoming);
            e->currentIndex = 0;
            rebuild_play_order_locked(e);
        }

        {
            std::lock_guard<std::mutex> d(e->decoderMutex);
            if (e->hasCurrent)
            {
                uninit_decoder_slot(
                    e->currentDecoder
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                    ,
                    e->currentStream
#endif
                );
                e->hasCurrent = false;
            }
            if (e->hasNext)
            {
                uninit_decoder_slot(
                    e->nextDecoder
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                    ,
                    e->nextStream
#endif
                );
                e->hasNext = false;
            }
            e->nextIndex = -1;
            e->currentLengthFrames = 0;
            e->nextLengthFrames = 0;
        }

        engine_log("set_playlist: count=%d", count);
        // Do not auto-jump here. The caller may immediately request a specific
        // initial index/position; auto-jumping can cause duplicate decoder
        // initialization races.
        clear_last_error(e);
        return true;
    }

    AE_API bool ae_add_to_playlist(AudioEngineHandle *e, const char *path)
    {
        if (e == nullptr || path == nullptr || path[0] == '\0')
        {
            set_last_error(e, "Invalid path for add_to_playlist.");
            return false;
        }

        std::lock_guard<std::mutex> pl(e->playlistMutex);
        e->playlist.emplace_back(path);
        rebuild_play_order_locked(e);
        if (e->currentIndex < 0)
        {
            e->currentIndex = 0;
            request_jump(e, 0);
        }
        clear_last_error(e);
        return true;
    }

    AE_API bool ae_insert_to_playlist(AudioEngineHandle *e, int index, const char *path)
    {
        if (e == nullptr || path == nullptr || path[0] == '\0')
        {
            set_last_error(e, "Invalid path for insert_to_playlist.");
            return false;
        }

        std::lock_guard<std::mutex> pl(e->playlistMutex);
        if (index < 0)
            index = 0;
        if (index > (int)e->playlist.size())
            index = (int)e->playlist.size();

        e->playlist.insert(e->playlist.begin() + index, std::string(path));
        if (e->currentIndex >= index)
        {
            e->currentIndex += 1;
        }
        if (e->currentIndex < 0)
            e->currentIndex = 0;
        rebuild_play_order_locked(e);
        clear_last_error(e);
        return true;
    }

    AE_API bool ae_remove_from_playlist(AudioEngineHandle *e, int index)
    {
        if (e == nullptr)
        {
            set_last_error(e, "Engine is null in remove_from_playlist.");
            return false;
        }

        bool removedCurrent = false;
        {
            std::lock_guard<std::mutex> pl(e->playlistMutex);
            if (index < 0 || index >= (int)e->playlist.size())
            {
                set_last_error(e, "remove_from_playlist index out of range.");
                return false;
            }

            removedCurrent = (e->currentIndex == index);
            e->playlist.erase(e->playlist.begin() + index);

            if (e->playlist.empty())
            {
                e->currentIndex = -1;
                e->orderCursor = -1;
            }
            else
            {
                if (e->currentIndex > index)
                    e->currentIndex -= 1;
                if (e->currentIndex >= (int)e->playlist.size())
                    e->currentIndex = (int)e->playlist.size() - 1;
                rebuild_play_order_locked(e);
            }
        }

        if (removedCurrent)
        {
            if (e->currentIndex >= 0)
            {
                request_jump(e, e->currentIndex);
            }
            else
            {
                ae_stop(e);
            }
        }
        else
        {
            request_preload(e);
        }
        clear_last_error(e);
        return true;
    }

    AE_API bool ae_move_playlist_item(AudioEngineHandle *e, int from_index, int to_index)
    {
        if (e == nullptr)
        {
            set_last_error(e, "Engine is null in move_playlist_item.");
            return false;
        }

        std::lock_guard<std::mutex> pl(e->playlistMutex);
        const int n = (int)e->playlist.size();
        if (from_index < 0 || from_index >= n || to_index < 0 || to_index >= n)
        {
            set_last_error(e, "move_playlist_item index out of range.");
            return false;
        }
        if (from_index == to_index)
            return true;

        std::string moved = e->playlist[(size_t)from_index];
        e->playlist.erase(e->playlist.begin() + from_index);
        e->playlist.insert(e->playlist.begin() + to_index, moved);

        if (e->currentIndex == from_index)
        {
            e->currentIndex = to_index;
        }
        else if (from_index < e->currentIndex && to_index >= e->currentIndex)
        {
            e->currentIndex -= 1;
        }
        else if (from_index > e->currentIndex && to_index <= e->currentIndex)
        {
            e->currentIndex += 1;
        }

        rebuild_play_order_locked(e);
        clear_last_error(e);
        return true;
    }

    AE_API void ae_clear_playlist(AudioEngineHandle *e)
    {
        if (e == nullptr)
            return;

        engine_log("clear_playlist requested");

        {
            std::lock_guard<std::mutex> pl(e->playlistMutex);
            e->playlist.clear();
            e->currentIndex = -1;
            e->playOrder.clear();
            e->orderCursor = -1;
        }

        std::lock_guard<std::mutex> d(e->decoderMutex);
        if (e->hasCurrent)
        {
            uninit_decoder_slot(
                e->currentDecoder
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                ,
                e->currentStream
#endif
            );
            e->hasCurrent = false;
        }
        if (e->hasNext)
        {
            uninit_decoder_slot(
                e->nextDecoder
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                ,
                e->nextStream
#endif
            );
            e->hasNext = false;
        }
        e->isPlaying.store(false, std::memory_order_relaxed);
        engine_log("clear_playlist completed");
    }

    AE_API bool ae_play(AudioEngineHandle *e)
    {
        if (e == nullptr)
        {
            set_last_error(e, "Engine is null in play.");
            return false;
        }

        bool hasCurrent = false;
        bool isPushMode = false;
        bool pushInitialized = false;
        {
            std::lock_guard<std::mutex> d(e->decoderMutex);
            hasCurrent = e->hasCurrent;
            isPushMode = e->isPushStreamMode;
            pushInitialized = e->pushStreamForCurrent.initialized;
        }

        if (!hasCurrent)
        {
            if (isPushMode && pushInitialized)
            {
                // Push-stream mode may not have an initialized decoder yet.
                // The audio callback will lazy-init it once enough bytes arrive.
                e->isPlaying.store(true, std::memory_order_relaxed);
                engine_log("play requested in push-stream mode (decoder pending)");
                clear_last_error(e);
                return true;
            }

            int idx = 0;
            {
                std::lock_guard<std::mutex> pl(e->playlistMutex);
                if (e->playlist.empty())
                {
                    set_last_error(e, "Cannot play: playlist is empty.");
                    return false;
                }
                idx = (e->currentIndex >= 0) ? e->currentIndex : 0;
            }
            request_jump(e, idx);
        }

        e->isPlaying.store(true, std::memory_order_relaxed);
        engine_log("play requested (currentIndex=%d)", e->currentIndex);
        clear_last_error(e);
        return true;
    }

    AE_API bool ae_pause(AudioEngineHandle *e)
    {
        if (e == nullptr)
        {
            set_last_error(e, "Engine is null in seek.");
            return false;
        }
        e->isPlaying.store(false, std::memory_order_relaxed);
        return true;
    }

    AE_API bool ae_stop(AudioEngineHandle *e)
    {
        if (e == nullptr)
            return false;
        e->isPlaying.store(false, std::memory_order_relaxed);

        std::lock_guard<std::mutex> d(e->decoderMutex);
        if (e->hasCurrent)
        {
            (void)ma_decoder_seek_to_pcm_frame(e->currentDecoder, 0);
        }
        return true;
    }

    AE_API bool ae_seek(AudioEngineHandle *e, double percent_0_to_1)
    {
        if (e == nullptr)
            return false;

        const double p = clampd(percent_0_to_1, 0.0, 1.0);

        std::lock_guard<std::mutex> d(e->decoderMutex);
        if (!e->hasCurrent || e->currentLengthFrames == 0)
        {
            set_last_error(e, "Seek failed: no active track.");
            return false;
        }

        ma_uint64 target = (ma_uint64)((double)e->currentLengthFrames * p);
        const bool ok = ma_decoder_seek_to_pcm_frame(e->currentDecoder, target) == MA_SUCCESS;
        if (!ok)
            set_last_error(e, "Seek failed in decoder.");
        else
            clear_last_error(e);
        return ok;
    }

    AE_API bool ae_next(AudioEngineHandle *e)
    {
        if (e == nullptr)
        {
            set_last_error(e, "Engine is null in next.");
            return false;
        }

        int idx = -1;
        {
            std::lock_guard<std::mutex> pl(e->playlistMutex);
            idx = next_index_locked(e);
        }

        if (idx < 0)
        {
            set_last_error(e, "No next track (loop mode may be off).");
            return false;
        }

        request_jump(e, idx);
        e->isPlaying.store(true, std::memory_order_relaxed);
        clear_last_error(e);
        return true;
    }

    AE_API bool ae_prev(AudioEngineHandle *e)
    {
        if (e == nullptr)
        {
            set_last_error(e, "Engine is null in prev.");
            return false;
        }

        int idx = -1;
        {
            std::lock_guard<std::mutex> pl(e->playlistMutex);
            idx = prev_index_locked(e);
        }

        if (idx < 0)
        {
            set_last_error(e, "No previous track (loop mode may be off).");
            return false;
        }

        request_jump(e, idx);
        e->isPlaying.store(true, std::memory_order_relaxed);
        clear_last_error(e);
        return true;
    }

    AE_API bool ae_jump_to(AudioEngineHandle *e, int index)
    {
        if (e == nullptr || index < 0)
        {
            set_last_error(e, "Invalid jump_to index.");
            return false;
        }

        {
            std::lock_guard<std::mutex> pl(e->playlistMutex);
            if (index >= (int)e->playlist.size())
            {
                set_last_error(e, "jump_to index out of range.");
                return false;
            }
        }

        e->pendingSeekValid.store(false, std::memory_order_release);
        e->pendingSeekIndex.store(-1, std::memory_order_release);
        request_jump(e, index);
        e->isPlaying.store(true, std::memory_order_relaxed);
        engine_log("jump_to requested: index=%d", index);
        clear_last_error(e);
        return true;
    }

    AE_API bool ae_jump_to_with_position(AudioEngineHandle *e, int index, double position_seconds)
    {
        if (e == nullptr || index < 0)
        {
            set_last_error(e, "Invalid jump_to_with_position input.");
            return false;
        }

        {
            std::lock_guard<std::mutex> pl(e->playlistMutex);
            if (index >= (int)e->playlist.size())
            {
                set_last_error(e, "jump_to_with_position index out of range.");
                return false;
            }
        }

        const double pos = std::max(0.0, position_seconds);
        const ma_uint64 frame = (ma_uint64)(pos * (double)e->sampleRate);

        e->pendingSeekFrame.store(frame, std::memory_order_release);
        e->pendingSeekIndex.store(index, std::memory_order_release);
        e->pendingSeekValid.store(true, std::memory_order_release);

        request_jump(e, index);
        e->isPlaying.store(true, std::memory_order_relaxed);
        engine_log("jump_to_with_position requested: index=%d frame=%llu", index, (unsigned long long)frame);
        clear_last_error(e);
        return true;
    }

    AE_API int ae_is_network_streaming_supported(void)
    {
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
        return 1;
#else
        return 0;
#endif
    }

    AE_API void ae_set_loop_mode(AudioEngineHandle *e, int loop_mode)
    {
        if (e == nullptr)
        {
            return;
        }

        std::lock_guard<std::mutex> pl(e->playlistMutex);
        if (loop_mode < AE_LOOP_OFF)
            loop_mode = AE_LOOP_OFF;
        if (loop_mode > AE_LOOP_ONE)
            loop_mode = AE_LOOP_ONE;
        e->loopMode = loop_mode;
    }

    AE_API void ae_set_shuffle_enabled(AudioEngineHandle *e, int enabled)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> pl(e->playlistMutex);
        e->shuffleEnabled = (enabled != 0);
        rebuild_play_order_locked(e);
    }

    AE_API void ae_reshuffle(AudioEngineHandle *e)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> pl(e->playlistMutex);
        rebuild_play_order_locked(e);
    }

    AE_API void ae_set_crossfade_enabled(AudioEngineHandle *e, int enabled)
    {
        if (e == nullptr)
            return;
        e->crossfadeEnabled.store(enabled != 0, std::memory_order_relaxed);
        if (enabled == 0)
        {
            e->transitionFadeInFramesTotal.store(0, std::memory_order_relaxed);
            e->transitionFadeInFramesRemaining.store(0, std::memory_order_relaxed);
        }
    }

    AE_API int ae_get_crossfade_enabled(AudioEngineHandle *e)
    {
        if (e == nullptr)
            return 0;
        return e->crossfadeEnabled.load(std::memory_order_relaxed) ? 1 : 0;
    }

    AE_API void ae_set_crossfade_duration_ms(AudioEngineHandle *e, int duration_ms)
    {
        if (e == nullptr)
            return;
        e->crossfadeDurationMs.store(clampi(duration_ms, 0, 10000), std::memory_order_relaxed);
    }

    AE_API int ae_get_crossfade_duration_ms(AudioEngineHandle *e)
    {
        if (e == nullptr)
            return 0;
        return clampi(e->crossfadeDurationMs.load(std::memory_order_relaxed), 0, 10000);
    }

    AE_API PlayerStatus ae_get_status(AudioEngineHandle *e)
    {
        PlayerStatus s{};
        if (e == nullptr)
            return s;

        s.is_playing = e->isPlaying.load(std::memory_order_relaxed) ? 1 : 0;

        {
            std::lock_guard<std::mutex> pl(e->playlistMutex);
            s.playlist_count = (int)e->playlist.size();
            s.current_index = e->currentIndex;
            s.shuffle_enabled = e->shuffleEnabled ? 1 : 0;
            s.loop_mode = e->loopMode;
        }

        {
            std::lock_guard<std::mutex> d(e->decoderMutex);
            if (e->hasCurrent)
            {
                ma_uint64 cur = 0;
                (void)ma_decoder_get_cursor_in_pcm_frames(e->currentDecoder, &cur);
                ma_uint64 len = e->currentLengthFrames;

                s.position_seconds = (double)cur / (double)e->sampleRate;
                s.duration_seconds = (double)len / (double)e->sampleRate;
            }
        }

        return s;
    }

    AE_API const char *ae_get_last_error(AudioEngineHandle *e)
    {
        static thread_local std::string tlsLastError;
        if (e == nullptr)
            return "";

        std::lock_guard<std::mutex> lk(e->errorMutex);
        tlsLastError = e->lastError;
        return tlsLastError.c_str();
    }

    AE_API void ae_clear_last_error(AudioEngineHandle *e)
    {
        clear_last_error(e);
    }

    AE_API void ae_set_reverb_enabled(AudioEngineHandle *e, int enabled)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->reverbEnabled = (enabled != 0);
    }

    AE_API void ae_set_reverb_params(AudioEngineHandle *e, float mix, float feedback, float delay_ms)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->reverb.updateParams(e->sampleRate, mix, feedback, delay_ms);
    }

    AE_API void ae_set_eq_enabled(AudioEngineHandle *e, int enabled)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->eqEnabled = (enabled != 0);
    }

    AE_API void ae_set_eq_gains(AudioEngineHandle *e, float low_gain, float mid_gain, float high_gain)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->eq.lowGain = clampf(low_gain, 0.0f, 4.0f);
        e->eq.midGain = clampf(mid_gain, 0.0f, 4.0f);
        e->eq.highGain = clampf(high_gain, 0.0f, 4.0f);
    }

    AE_API void ae_set_gain(AudioEngineHandle *e, float gain)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->gain = clampf(gain, 0.0f, 8.0f);
    }

    AE_API void ae_set_pan(AudioEngineHandle *e, float pan_minus1_to_plus1)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->pan = clampf(pan_minus1_to_plus1, -1.0f, 1.0f);
    }

    AE_API void ae_set_lowpass_enabled(AudioEngineHandle *e, int enabled)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->lowpassEnabled = (enabled != 0);
    }

    AE_API void ae_set_lowpass_cutoff(AudioEngineHandle *e, float hz)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->lowpass.setLowpassCutoff(clampf(hz, 20.0f, (float)e->sampleRate * 0.45f), e->sampleRate);
    }

    AE_API void ae_set_highpass_enabled(AudioEngineHandle *e, int enabled)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->highpassEnabled = (enabled != 0);
    }

    AE_API void ae_set_highpass_cutoff(AudioEngineHandle *e, float hz)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->highpass.setHighpassCutoff(clampf(hz, 10.0f, (float)e->sampleRate * 0.45f), e->sampleRate);
    }

    AE_API void ae_set_delay_enabled(AudioEngineHandle *e, int enabled)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->delayEnabled = (enabled != 0);
    }

    AE_API void ae_set_delay_params(AudioEngineHandle *e, float mix, float feedback, float delay_ms)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->delay.updateParams(e->sampleRate, e->channels, mix, feedback, delay_ms);
    }

    AE_API void ae_set_bandpass_enabled(AudioEngineHandle *e, int enabled)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->bandpassEnabled = (enabled != 0);
    }

    AE_API void ae_set_bandpass_params(AudioEngineHandle *e, float cutoff_hz, float q)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->bandpassCutoffHz = clampf(cutoff_hz, 20.0f, (float)e->sampleRate * 0.45f);
        e->bandpassQ = clampf(q, 0.1f, 18.0f);
        reinit_advanced_fx_filters(e);
    }

    AE_API void ae_set_peak_eq_enabled(AudioEngineHandle *e, int enabled)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->peakEqEnabled = (enabled != 0);
    }

    AE_API void ae_set_peak_eq_params(AudioEngineHandle *e, float gain_db, float q, float frequency_hz)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->peakGainDb = clampf(gain_db, -24.0f, 24.0f);
        e->peakQ = clampf(q, 0.1f, 18.0f);
        e->peakFrequencyHz = clampf(frequency_hz, 20.0f, (float)e->sampleRate * 0.45f);
        reinit_advanced_fx_filters(e);
    }

    AE_API void ae_set_notch_enabled(AudioEngineHandle *e, int enabled)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->notchEnabled = (enabled != 0);
    }

    AE_API void ae_set_notch_params(AudioEngineHandle *e, float q, float frequency_hz)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->notchQ = clampf(q, 0.1f, 18.0f);
        e->notchFrequencyHz = clampf(frequency_hz, 20.0f, (float)e->sampleRate * 0.45f);
        reinit_advanced_fx_filters(e);
    }

    AE_API void ae_set_lowshelf_enabled(AudioEngineHandle *e, int enabled)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->lowshelfEnabled = (enabled != 0);
    }

    AE_API void ae_set_lowshelf_params(AudioEngineHandle *e, float gain_db, float slope, float frequency_hz)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->lowshelfGainDb = clampf(gain_db, -24.0f, 24.0f);
        e->lowshelfSlope = clampf(slope, 0.1f, 2.0f);
        e->lowshelfFrequencyHz = clampf(frequency_hz, 20.0f, (float)e->sampleRate * 0.45f);
        reinit_advanced_fx_filters(e);
    }

    AE_API void ae_set_highshelf_enabled(AudioEngineHandle *e, int enabled)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->highshelfEnabled = (enabled != 0);
    }

    AE_API void ae_set_highshelf_params(AudioEngineHandle *e, float gain_db, float slope, float frequency_hz)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->highshelfGainDb = clampf(gain_db, -24.0f, 24.0f);
        e->highshelfSlope = clampf(slope, 0.1f, 2.0f);
        e->highshelfFrequencyHz = clampf(frequency_hz, 20.0f, (float)e->sampleRate * 0.45f);
        reinit_advanced_fx_filters(e);
    }

    AE_API void ae_set_custom_lpf1_params(AudioEngineHandle *e, int enabled, double cutoff_hz)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->customLpf1Enabled = (enabled != 0);
        e->customLpf1Cutoff = cutoff_hz;
        reinit_advanced_fx_filters(e);
    }

    AE_API void ae_set_custom_hpf1_params(AudioEngineHandle *e, int enabled, double cutoff_hz)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->customHpf1Enabled = (enabled != 0);
        e->customHpf1Cutoff = cutoff_hz;
        reinit_advanced_fx_filters(e);
    }

    AE_API void ae_set_custom_biquad_params(AudioEngineHandle *e, int enabled, double b0, double b1, double b2, double a0, double a1, double a2)
    {
        if (e == nullptr)
            return;
        std::lock_guard<std::mutex> fx(e->fxMutex);
        e->customBiquadEnabled = (enabled != 0);
        e->bq_b0 = b0;
        e->bq_b1 = b1;
        e->bq_b2 = b2;
        e->bq_a0 = a0;
        e->bq_a1 = a1;
        e->bq_a2 = a2;
        reinit_advanced_fx_filters(e);
    }

    // Helper to restart device with new config
    static void restart_and_apply_config(AudioEngineHandle *e)
    {
        if (!e)
            return;
        bool wasPlaying = e->isPlaying.load();

        if (ma_device_get_state(&e->device) == ma_device_state_started)
        {
            ma_device_stop(&e->device);
        }
        ma_device_uninit(&e->device);

        int newRate = e->outputSampleRate > 0 ? e->outputSampleRate : 0;
        int newCh = e->outputChannels > 0 ? e->outputChannels : 2;

        const int srForFilterInit = (newRate > 0) ? newRate : ((e->sampleRate > 0) ? e->sampleRate : 48000);
        e->sampleRate = srForFilterInit;
        e->channels = newCh;

        e->update_eq_filters();
        e->update_multiband_fx_filters();
        {
            std::lock_guard<std::mutex> fx(e->fxMutex);
            reinit_advanced_fx_filters(e);
        }

        ma_device_config cfg = ma_device_config_init(ma_device_type_playback);
        switch (e->outputFormat)
        {
        case AE_FORMAT_S16:
            cfg.playback.format = ma_format_s16;
            break;
        case AE_FORMAT_U8:
            cfg.playback.format = ma_format_u8;
            break;
        case AE_FORMAT_S24:
            cfg.playback.format = ma_format_s24;
            break;
        case AE_FORMAT_S32:
            cfg.playback.format = ma_format_s32;
            break;
        default:
            cfg.playback.format = ma_format_f32;
            break;
        }
        cfg.playback.channels = (ma_uint32)newCh;
        cfg.sampleRate = (ma_uint32)newRate; // 0 = native device sample rate.
        cfg.dataCallback = data_callback;
        cfg.pUserData = e;

        if (e->resampleAlgorithm == 1)
        { // AE_RESAMPLE_ALGORITHM_CUSTOM
            cfg.resampling.algorithm = ma_resample_algorithm_custom;
        }
        else
        {
            cfg.resampling.algorithm = ma_resample_algorithm_linear;
        }

        if (ma_device_init(nullptr, &cfg, &e->device) != MA_SUCCESS)
        {
            set_last_error(e, "Failed to re-initialize device with new config.");
            return;
        }

        {
            const int actualRate = (int)e->device.sampleRate;
            e->sampleRate = (actualRate > 0) ? actualRate : ((newRate > 0) ? newRate : 48000);
            e->update_eq_filters();
            e->update_multiband_fx_filters();
            std::lock_guard<std::mutex> fx(e->fxMutex);
            reinit_advanced_fx_filters(e);
        }

        // Re-initialize active decoders to match new outCh so miniaudio downmixes properly
        ma_uint64 resumeFrame = 0;
        int resumeIndex = -1;
        bool hadDecoder = false;
        {
            std::lock_guard<std::mutex> d(e->decoderMutex);
            if (e->hasCurrent && e->currentDecoder)
            {
                hadDecoder = true;
                resumeIndex = e->currentIndex;
                (void)ma_decoder_get_cursor_in_pcm_frames(e->currentDecoder, &resumeFrame);
                uninit_decoder_slot(
                    e->currentDecoder
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                    ,
                    e->currentStream
#endif
                );
                e->currentDecoder = nullptr;
                e->hasCurrent = false;
            }
            if (e->hasNext && e->nextDecoder)
            {
                uninit_decoder_slot(
                    e->nextDecoder
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                    ,
                    e->nextStream
#endif
                );
                e->nextDecoder = nullptr;
                e->hasNext = false;
            }
        }

        if (hadDecoder && resumeIndex >= 0)
        {
            std::string path;
            {
                std::lock_guard<std::mutex> pl(e->playlistMutex);
                if (resumeIndex < (int)e->playlist.size())
                {
                    path = e->playlist[(size_t)resumeIndex];
                }
            }
            if (!path.empty())
            {
                ma_decoder *newDec = nullptr;
                ma_uint64 newLen = 0;
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                NetworkStreamState *newSt = nullptr;
                if (load_decoder_for_path(e, path, &newDec, &newLen, &newSt))
#else
                if (load_decoder_for_path(e, path, &newDec, &newLen))
#endif
                {
                    if (resumeFrame > 0)
                        (void)ma_decoder_seek_to_pcm_frame(newDec, resumeFrame);

                    std::lock_guard<std::mutex> d(e->decoderMutex);
                    e->currentDecoder = newDec;
                    e->currentLengthFrames = newLen;
                    e->currentIndex = resumeIndex;
                    e->hasCurrent = true;
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                    e->currentStream = newSt;
#endif
                }
            }
        }

        if (wasPlaying)
        {
            ma_device_start(&e->device);
        }
    }

    AE_API void ae_set_output_format(AudioEngineHandle *engine, int format)
    {
        if (!engine)
            return;
        engine->outputFormat = (AEAudioFormat)format;
        restart_and_apply_config(engine);
    }

    AE_API int ae_get_output_format(AudioEngineHandle *engine)
    {
        return engine ? (int)engine->outputFormat : 0;
    }

    AE_API void ae_set_output_sample_rate(AudioEngineHandle *engine, int sample_rate)
    {
        if (!engine || sample_rate < 0)
            return;
        engine->outputSampleRate = sample_rate;
        restart_and_apply_config(engine);
    }

    AE_API int ae_get_output_sample_rate(AudioEngineHandle *engine)
    {
        return engine ? engine->outputSampleRate : 0;
    }

    AE_API void ae_set_output_channels(AudioEngineHandle *engine, int channels)
    {
        if (!engine || channels <= 0)
            return;
        engine->outputChannels = channels;
        restart_and_apply_config(engine);
    }

    AE_API int ae_get_output_channels(AudioEngineHandle *engine)
    {
        return engine ? engine->outputChannels : 0;
    }

    AE_API void ae_set_engine_resample_algorithm(AudioEngineHandle *engine, int algorithm)
    {
        if (!engine)
            return;
        engine->resampleAlgorithm = algorithm;
        restart_and_apply_config(engine);
    }

    AE_API int ae_get_engine_resample_algorithm(AudioEngineHandle *engine)
    {
        return engine ? engine->resampleAlgorithm : 0;
    }

    AE_API void ae_set_engine_dither_mode(AudioEngineHandle *engine, int dither_mode)
    {
        if (!engine)
            return;
        engine->ditherMode = dither_mode;
    }

    AE_API int ae_get_engine_dither_mode(AudioEngineHandle *engine)
    {
        return engine ? engine->ditherMode : 0;
    }

    AE_API void ae_init_multiband_eq(AudioEngineHandle *engine, int band_count, float *frequencies, float *q_factors)
    {
        if (!engine || band_count <= 0)
            return;

        std::lock_guard<std::mutex> lk(engine->eqMutex);
        engine->eqBandCount = band_count;
        engine->eqFrequencies.assign(frequencies, frequencies + band_count);
        engine->eqGains.assign(band_count, 0.0f); // 0dB initially

        if (q_factors)
        {
            engine->eqQ.assign(q_factors, q_factors + band_count);
        }
        else
        {
            engine->eqQ.assign(band_count, 1.0f); // Default Q=1.0
        }

        engine->update_eq_filters();
    }

    AE_API void ae_set_multiband_eq_enabled(AudioEngineHandle *engine, int enabled)
    {
        if (!engine)
            return;
        std::lock_guard<std::mutex> lk(engine->eqMutex);
        engine->multibandEqEnabled = (enabled != 0);
    }

    AE_API void ae_set_multiband_eq_gain(AudioEngineHandle *engine, int band_index, float gain_db)
    {
        if (!engine || band_index < 0)
            return;

        std::lock_guard<std::mutex> lk(engine->eqMutex);
        if (band_index < engine->eqBandCount && band_index < (int)engine->eqFilters.size())
        {
            engine->eqGains[band_index] = gain_db;

            int sr = engine->outputSampleRate > 0 ? engine->outputSampleRate : 48000;
            int ch = engine->outputChannels > 0 ? engine->outputChannels : 2;

            ma_peak2_config config = ma_peak2_config_init(
                ma_format_f32,
                (ma_uint32)ch,
                (ma_uint32)sr,
                gain_db,
                engine->eqQ[band_index],
                engine->eqFrequencies[band_index]);

            // Re-init the filter for this band
            // This resets internal state (history), which might cause a click.
            // Ideally we'd update coeffs, but standard miniaudio usage often implies re-init for param changes
            // unless using lower-level coeff API.
            ma_peak2_init(&config, nullptr, &engine->eqFilters[band_index]);
        }
    }

    AE_API float ae_get_multiband_eq_gain(AudioEngineHandle *engine, int band_index)
    {
        if (!engine || band_index < 0 || band_index >= engine->eqBandCount)
            return 0.0f;
        std::lock_guard<std::mutex> lk(engine->eqMutex);
        return engine->eqGains[band_index];
    }

    AE_API void ae_set_multiband_fx_enabled(AudioEngineHandle *engine, int enabled)
    {
        if (!engine)
            return;
        std::lock_guard<std::mutex> lk(engine->eqMutex);
        engine->multibandFxEnabled = (enabled != 0);
    }

    AE_API void ae_set_multiband_fx_bands(
        AudioEngineHandle *engine,
        int band_count,
        const int *types,
        const float *frequencies,
        const float *q_factors,
        const float *gains_db,
        const float *slopes,
        const int *enabled_flags)
    {
        if (!engine || band_count <= 0 || types == nullptr || frequencies == nullptr)
            return;

        std::lock_guard<std::mutex> lk(engine->eqMutex);
        engine->multibandFxBands.clear();
        engine->multibandFxBands.reserve((size_t)band_count);

        for (int i = 0; i < band_count; ++i)
        {
            AudioEngineHandle::FxBand band{};

            int type = types[i];
            if (type < AE_EQ_BAND_PEAK || type > AE_EQ_BAND_HIGHSHELF)
            {
                type = AE_EQ_BAND_PEAK;
            }

            band.type = type;
            band.enabled = (enabled_flags == nullptr) ? true : (enabled_flags[i] != 0);
            band.frequencyHz = frequencies[i];
            band.q = (q_factors == nullptr) ? 1.0f : q_factors[i];
            band.gainDb = (gains_db == nullptr) ? 0.0f : gains_db[i];
            band.slope = (slopes == nullptr) ? 1.0f : slopes[i];

            engine->multibandFxBands.push_back(band);
        }

        engine->update_multiband_fx_filters();
    }

    AE_API void ae_clear_multiband_fx(AudioEngineHandle *engine)
    {
        if (!engine)
            return;
        std::lock_guard<std::mutex> lk(engine->eqMutex);
        engine->multibandFxBands.clear();
        engine->multibandFxEnabled = false;
    }

    AE_API void ae_set_analyzer_enabled(AudioEngineHandle *engine, int enabled)
    {
        if (!engine)
            return;
        engine->analyzerEnabled.store(enabled != 0, std::memory_order_relaxed);
    }

    AE_API void ae_configure_analyzer(AudioEngineHandle *engine, int frame_size)
    {
        if (!engine)
            return;
        const int size = std::max(64, std::min(frame_size, 8192));

        std::lock_guard<std::mutex> fx(engine->fxMutex);
        std::lock_guard<std::mutex> lk(engine->analyzerMutex);
        engine->analyzerFrameSize = size;
        engine->analyzerAccumulator.assign((size_t)size, 0.0f);
        engine->analyzerLatest.assign((size_t)size, 0.0f);
        engine->analyzerAccumulatorCount = 0;
    }

    AE_API int ae_get_analyzer_frame_size(AudioEngineHandle *engine)
    {
        if (!engine)
            return 0;
        return engine->analyzerFrameSize;
    }

    AE_API int ae_poll_analyzer_frame(AudioEngineHandle *engine, float *out_samples, int max_samples)
    {
        if (!engine || out_samples == nullptr || max_samples <= 0)
            return 0;

        std::lock_guard<std::mutex> lk(engine->analyzerMutex);
        if (engine->analyzerLatest.empty())
            return 0;

        const int n = std::min((int)engine->analyzerLatest.size(), max_samples);
        std::memcpy(out_samples, engine->analyzerLatest.data(), (size_t)n * sizeof(float));
        return n;
    }

    AE_API uint64_t ae_get_analyzer_dropped_frames(AudioEngineHandle *engine)
    {
        if (!engine)
            return 0;
        return engine->analyzerDroppedFrames.load(std::memory_order_relaxed);
    }

    AE_API void ae_init_push_stream(AudioEngineHandle *engine)
    {
        if (!engine)
            return;

        // Force stop any current playback first
        if (engine->isPlaying)
        {
            ae_stop(engine);
        }

        // Unload current decoder if any
        {
            std::lock_guard<std::mutex> d(engine->decoderMutex);
            if (engine->currentDecoder)
            {
                uninit_decoder_slot(
                    engine->currentDecoder
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                    ,
                    engine->currentStream
#endif
                );
                engine->currentDecoder = nullptr;
                engine->hasCurrent = false;
            }
        }

        std::lock_guard<std::mutex> lk(engine->pushStreamForCurrent.mtx);

        if (engine->pushStreamForCurrent.initialized)
        {
            // Already initialized, maybe reset?
            // For safety, uninit first
            ma_rb_uninit(&engine->pushStreamForCurrent.rb);
            if (engine->pushStreamForCurrent.rbBuffer)
            {
                std::free(engine->pushStreamForCurrent.rbBuffer);
                engine->pushStreamForCurrent.rbBuffer = nullptr;
            }
            engine->pushStreamForCurrent.initialized = false;
        }

        const size_t bufSize = 1024 * 1024 * 4; // 4MB buffer
        engine->pushStreamForCurrent.rbBuffer = std::malloc(bufSize);
        if (!engine->pushStreamForCurrent.rbBuffer)
            return;

        if (ma_rb_init(bufSize, engine->pushStreamForCurrent.rbBuffer, nullptr, &engine->pushStreamForCurrent.rb) == MA_SUCCESS)
        {
            engine->pushStreamForCurrent.initialized = true;
            engine->pushStreamForCurrent.isDone = false;
        }

        // We do NOT init the decoder here anymore.
        // We set the mode, and let data_callback (or a separate call) init the decoder
        // once data is available.
        // We can add a flag "needsDecoderInit" or just check if currentDecoder is null while isPushStreamMode is true.

        engine->isPushStreamMode = true;

        // Ensure hasCurrent is false so data_callback waits
        {
            std::lock_guard<std::mutex> d(engine->decoderMutex);
            engine->currentDecoder = nullptr;
            engine->hasCurrent = false; // Will trigger decoder init attempts in data_callback
            engine->hasNext = false;
        }
    }

    AE_API void ae_push_stream_chunk(AudioEngineHandle *engine, const unsigned char *data, size_t size)
    {
        if (!engine || !data || size == 0 || !engine->pushStreamForCurrent.initialized)
            return;

        size_t written = 0;
        while (written < size)
        {
            void *pWrite = nullptr;
            size_t toWrite = size - written;

            if (ma_rb_acquire_write(&engine->pushStreamForCurrent.rb, &toWrite, &pWrite) == MA_SUCCESS)
            {
                std::memcpy(pWrite, data + written, toWrite);
                ma_rb_commit_write(&engine->pushStreamForCurrent.rb, toWrite);
                written += toWrite;
                continue;
            }

            // If buffer full, wait a bit
            std::this_thread::sleep_for(std::chrono::milliseconds(2));
        }
    }

    AE_API void ae_end_push_stream(AudioEngineHandle *engine)
    {
        if (!engine || !engine->pushStreamForCurrent.initialized)
            return;
        engine->pushStreamForCurrent.isDone = true;
    }

    AE_API int ae_get_push_stream_buffered_bytes(AudioEngineHandle *engine)
    {
        if (!engine || !engine->pushStreamForCurrent.initialized)
            return 0;
        return (int)ma_rb_available_read(&engine->pushStreamForCurrent.rb);
    }

    // ==========================================
    // Standalone Filters & Resampler (miniaudio direct bindings)
    // ==========================================

    static ma_format ae_format_to_ma(int format)
    {
        switch (format)
        {
        case AE_FORMAT_F32:
            return ma_format_f32;
        case AE_FORMAT_S16:
            return ma_format_s16;
        case AE_FORMAT_U8:
            return ma_format_u8;
        case AE_FORMAT_S24:
            return ma_format_s24;
        case AE_FORMAT_S32:
            return ma_format_s32;
        default:
            return ma_format_unknown;
        }
    }

    struct AELpf1
    {
        ma_lpf1 filter;
    };
    struct AELpf2
    {
        ma_lpf2 filter;
    };
    struct AELpf
    {
        ma_lpf filter;
    };
    struct AEHpf1
    {
        ma_hpf1 filter;
    };
    struct AEHpf2
    {
        ma_hpf2 filter;
    };
    struct AEHpf
    {
        ma_hpf filter;
    };
    struct AEBiquad
    {
        ma_biquad filter;
    };
    struct AEResampler
    {
        ma_resampler filter;
    };

    // LPF1
    AE_API AELpf1 *ae_lpf1_create(int format, int channels, int sample_rate, double cutoff_hz)
    {
        AELpf1 *obj = new AELpf1();
        ma_lpf1_config config = ma_lpf1_config_init(ae_format_to_ma(format), channels, sample_rate, cutoff_hz);
        if (ma_lpf1_init(&config, nullptr, &obj->filter) != MA_SUCCESS)
        {
            delete obj;
            return nullptr;
        }
        return obj;
    }
    AE_API void ae_lpf1_destroy(AELpf1 *obj)
    {
        if (obj)
            delete obj;
    }
    AE_API void ae_lpf1_reinit(AELpf1 *obj, int format, int channels, int sample_rate, double cutoff_hz)
    {
        if (obj)
        {
            ma_lpf1_config config = ma_lpf1_config_init(ae_format_to_ma(format), channels, sample_rate, cutoff_hz);
            ma_lpf1_reinit(&config, &obj->filter);
        }
    }
    AE_API int ae_lpf1_process(AELpf1 *obj, void *out_frames, const void *in_frames, uint64_t frame_count)
    {
        if (!obj)
            return 0;
        return ma_lpf1_process_pcm_frames(&obj->filter, out_frames, in_frames, frame_count) == MA_SUCCESS;
    }

    // LPF2
    AE_API AELpf2 *ae_lpf2_create(int format, int channels, int sample_rate, double cutoff_hz, double q)
    {
        AELpf2 *obj = new AELpf2();
        ma_lpf2_config config = ma_lpf2_config_init(ae_format_to_ma(format), channels, sample_rate, cutoff_hz, q);
        if (ma_lpf2_init(&config, nullptr, &obj->filter) != MA_SUCCESS)
        {
            delete obj;
            return nullptr;
        }
        return obj;
    }
    AE_API void ae_lpf2_destroy(AELpf2 *obj)
    {
        if (obj)
            delete obj;
    }
    AE_API void ae_lpf2_reinit(AELpf2 *obj, int format, int channels, int sample_rate, double cutoff_hz, double q)
    {
        if (obj)
        {
            ma_lpf2_config config = ma_lpf2_config_init(ae_format_to_ma(format), channels, sample_rate, cutoff_hz, q);
            ma_lpf2_reinit(&config, &obj->filter);
        }
    }
    AE_API int ae_lpf2_process(AELpf2 *obj, void *out_frames, const void *in_frames, uint64_t frame_count)
    {
        if (!obj)
            return 0;
        return ma_lpf2_process_pcm_frames(&obj->filter, out_frames, in_frames, frame_count) == MA_SUCCESS;
    }

    // LPF
    AE_API AELpf *ae_lpf_create(int format, int channels, int sample_rate, double cutoff_hz, int order)
    {
        AELpf *obj = new AELpf();
        ma_lpf_config config = ma_lpf_config_init(ae_format_to_ma(format), channels, sample_rate, cutoff_hz, order);
        if (ma_lpf_init(&config, nullptr, &obj->filter) != MA_SUCCESS)
        {
            delete obj;
            return nullptr;
        }
        return obj;
    }
    AE_API void ae_lpf_destroy(AELpf *obj)
    {
        if (obj)
        {
            ma_lpf_uninit(&obj->filter, nullptr);
            delete obj;
        }
    }
    AE_API void ae_lpf_reinit(AELpf *obj, int format, int channels, int sample_rate, double cutoff_hz, int order)
    {
        if (obj)
        {
            ma_lpf_config config = ma_lpf_config_init(ae_format_to_ma(format), channels, sample_rate, cutoff_hz, order);
            ma_lpf_reinit(&config, &obj->filter);
        }
    }
    AE_API int ae_lpf_process(AELpf *obj, void *out_frames, const void *in_frames, uint64_t frame_count)
    {
        if (!obj)
            return 0;
        return ma_lpf_process_pcm_frames(&obj->filter, out_frames, in_frames, frame_count) == MA_SUCCESS;
    }

    // HPF1
    AE_API AEHpf1 *ae_hpf1_create(int format, int channels, int sample_rate, double cutoff_hz)
    {
        AEHpf1 *obj = new AEHpf1();
        ma_hpf1_config config = ma_hpf1_config_init(ae_format_to_ma(format), channels, sample_rate, cutoff_hz);
        if (ma_hpf1_init(&config, nullptr, &obj->filter) != MA_SUCCESS)
        {
            delete obj;
            return nullptr;
        }
        return obj;
    }
    AE_API void ae_hpf1_destroy(AEHpf1 *obj)
    {
        if (obj)
            delete obj;
    }
    AE_API void ae_hpf1_reinit(AEHpf1 *obj, int format, int channels, int sample_rate, double cutoff_hz)
    {
        if (obj)
        {
            ma_hpf1_config config = ma_hpf1_config_init(ae_format_to_ma(format), channels, sample_rate, cutoff_hz);
            ma_hpf1_reinit(&config, &obj->filter);
        }
    }
    AE_API int ae_hpf1_process(AEHpf1 *obj, void *out_frames, const void *in_frames, uint64_t frame_count)
    {
        if (!obj)
            return 0;
        return ma_hpf1_process_pcm_frames(&obj->filter, out_frames, in_frames, frame_count) == MA_SUCCESS;
    }

    // HPF2
    AE_API AEHpf2 *ae_hpf2_create(int format, int channels, int sample_rate, double cutoff_hz, double q)
    {
        AEHpf2 *obj = new AEHpf2();
        ma_hpf2_config config = ma_hpf2_config_init(ae_format_to_ma(format), channels, sample_rate, cutoff_hz, q);
        if (ma_hpf2_init(&config, nullptr, &obj->filter) != MA_SUCCESS)
        {
            delete obj;
            return nullptr;
        }
        return obj;
    }
    AE_API void ae_hpf2_destroy(AEHpf2 *obj)
    {
        if (obj)
            delete obj;
    }
    AE_API void ae_hpf2_reinit(AEHpf2 *obj, int format, int channels, int sample_rate, double cutoff_hz, double q)
    {
        if (obj)
        {
            ma_hpf2_config config = ma_hpf2_config_init(ae_format_to_ma(format), channels, sample_rate, cutoff_hz, q);
            ma_hpf2_reinit(&config, &obj->filter);
        }
    }
    AE_API int ae_hpf2_process(AEHpf2 *obj, void *out_frames, const void *in_frames, uint64_t frame_count)
    {
        if (!obj)
            return 0;
        return ma_hpf2_process_pcm_frames(&obj->filter, out_frames, in_frames, frame_count) == MA_SUCCESS;
    }

    // HPF
    AE_API AEHpf *ae_hpf_create(int format, int channels, int sample_rate, double cutoff_hz, int order)
    {
        AEHpf *obj = new AEHpf();
        ma_hpf_config config = ma_hpf_config_init(ae_format_to_ma(format), channels, sample_rate, cutoff_hz, order);
        if (ma_hpf_init(&config, nullptr, &obj->filter) != MA_SUCCESS)
        {
            delete obj;
            return nullptr;
        }
        return obj;
    }
    AE_API void ae_hpf_destroy(AEHpf *obj)
    {
        if (obj)
        {
            ma_hpf_uninit(&obj->filter, nullptr);
            delete obj;
        }
    }
    AE_API void ae_hpf_reinit(AEHpf *obj, int format, int channels, int sample_rate, double cutoff_hz, int order)
    {
        if (obj)
        {
            ma_hpf_config config = ma_hpf_config_init(ae_format_to_ma(format), channels, sample_rate, cutoff_hz, order);
            ma_hpf_reinit(&config, &obj->filter);
        }
    }
    AE_API int ae_hpf_process(AEHpf *obj, void *out_frames, const void *in_frames, uint64_t frame_count)
    {
        if (!obj)
            return 0;
        return ma_hpf_process_pcm_frames(&obj->filter, out_frames, in_frames, frame_count) == MA_SUCCESS;
    }

    // Biquad
    AE_API AEBiquad *ae_biquad_create(int format, int channels, double b0, double b1, double b2, double a0, double a1, double a2)
    {
        AEBiquad *obj = new AEBiquad();
        ma_biquad_config config = ma_biquad_config_init(ae_format_to_ma(format), channels, b0, b1, b2, a0, a1, a2);
        if (ma_biquad_init(&config, nullptr, &obj->filter) != MA_SUCCESS)
        {
            delete obj;
            return nullptr;
        }
        return obj;
    }
    AE_API void ae_biquad_destroy(AEBiquad *obj)
    {
        if (obj)
        {
            ma_biquad_uninit(&obj->filter, nullptr);
            delete obj;
        }
    }
    AE_API void ae_biquad_reinit(AEBiquad *obj, int format, int channels, double b0, double b1, double b2, double a0, double a1, double a2)
    {
        if (obj)
        {
            ma_biquad_config config = ma_biquad_config_init(ae_format_to_ma(format), channels, b0, b1, b2, a0, a1, a2);
            ma_biquad_reinit(&config, &obj->filter);
        }
    }
    AE_API int ae_biquad_process(AEBiquad *obj, void *out_frames, const void *in_frames, uint64_t frame_count)
    {
        if (!obj)
            return 0;
        return ma_biquad_process_pcm_frames(&obj->filter, out_frames, in_frames, frame_count) == MA_SUCCESS;
    }

    // Resampler
    AE_API AEResampler *ae_resampler_create(int format, int channels, int sample_rate_in, int sample_rate_out, int algorithm, int dither_mode)
    {
        AEResampler *obj = new AEResampler();
        ma_resample_algorithm algo = ma_resample_algorithm_linear;
        if (algorithm == AE_RESAMPLE_ALGORITHM_CUSTOM)
            algo = ma_resample_algorithm_custom;

        ma_resampler_config config = ma_resampler_config_init(ae_format_to_ma(format), channels, sample_rate_in, sample_rate_out, algo);

        // This version of miniaudio (0.11.24) does not support ma_dither_mode natively.
        // We ignore the dither_mode parameter here to maintain FFI ABI stability without compiler errors.

        if (ma_resampler_init(&config, nullptr, &obj->filter) != MA_SUCCESS)
        {
            delete obj;
            return nullptr;
        }
        return obj;
    }
    AE_API void ae_resampler_destroy(AEResampler *obj)
    {
        if (obj)
        {
            ma_resampler_uninit(&obj->filter, nullptr);
            delete obj;
        }
    }
    AE_API int ae_resampler_process(AEResampler *obj, const void *in_frames, uint64_t *in_frame_count, void *out_frames, uint64_t *out_frame_count)
    {
        if (!obj)
            return 0;
        ma_uint64 in_count = in_frame_count ? *in_frame_count : 0;
        ma_uint64 out_count = out_frame_count ? *out_frame_count : 0;
        ma_result result = ma_resampler_process_pcm_frames(&obj->filter, in_frames, &in_count, out_frames, &out_count);
        if (in_frame_count)
            *in_frame_count = in_count;
        if (out_frame_count)
            *out_frame_count = out_count;
        return result == MA_SUCCESS;
    }
    AE_API void ae_resampler_set_rate(AEResampler *obj, int sample_rate_in, int sample_rate_out)
    {
        if (obj)
            ma_resampler_set_rate(&obj->filter, sample_rate_in, sample_rate_out);
    }
    AE_API void ae_resampler_set_rate_ratio(AEResampler *obj, float ratio_in_out)
    {
        if (obj)
            ma_resampler_set_rate_ratio(&obj->filter, ratio_in_out);
    }
    AE_API uint64_t ae_resampler_get_required_input_frame_count(AEResampler *obj, uint64_t out_frame_count)
    {
        if (!obj)
            return 0;
        ma_uint64 in_count = 0;
        ma_resampler_get_required_input_frame_count(&obj->filter, out_frame_count, &in_count);
        return in_count;
    }
    AE_API uint64_t ae_resampler_get_expected_output_frame_count(AEResampler *obj, uint64_t in_frame_count)
    {
        if (!obj)
            return 0;
        ma_uint64 out_count = 0;
        ma_resampler_get_expected_output_frame_count(&obj->filter, in_frame_count, &out_count);
        return out_count;
    }
    AE_API uint64_t ae_resampler_get_input_latency(AEResampler *obj)
    {
        if (!obj)
            return 0;
        return ma_resampler_get_input_latency(&obj->filter);
    }
    AE_API uint64_t ae_resampler_get_output_latency(AEResampler *obj)
    {
        if (!obj)
            return 0;
        return ma_resampler_get_output_latency(&obj->filter);
    }

} // extern "C"
