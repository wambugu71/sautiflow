#ifndef NOMINMAX
#define NOMINMAX
#endif

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"

#include "audio_engine.h"

#include <algorithm>
#include <atomic>
#include <chrono>
#include <cmath>
#include <condition_variable>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
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

    std::mutex fxMutex;
    bool eqEnabled = false;
    bool reverbEnabled = false;
    bool lowpassEnabled = false;
    bool highpassEnabled = false;
    bool delayEnabled = false;
    float gain = 1.0f;
    float pan = 0.0f;
    EqState eq;
    ReverbState reverb;
    OnePoleState lowpass;
    OnePoleState highpass;
    DelayState delay;

    std::mutex errorMutex;
    std::string lastError;
};

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

    ma_decoder_config cfg = ma_decoder_config_init(ma_format_f32, (ma_uint32)e->channels, (ma_uint32)e->sampleRate);

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
    ma_result r = ma_decoder_init_file(path.c_str(), &cfg, tmp);
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

            ma_decoder *newNext = nullptr;
            ma_uint64 newNextLen = 0;
            bool loadedNext = false;
            int computedNextIndex = -1;
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
            NetworkStreamState *newNextStream = nullptr;
#endif

            {
                std::lock_guard<std::mutex> pl(e->playlistMutex);
                e->currentIndex = jumpIndex;
                set_order_cursor_for_index_locked(e, jumpIndex);
                computedNextIndex = next_index_locked(e);
                if (computedNextIndex >= 0 && computedNextIndex < (int)e->playlist.size())
                {
                    loadedNext = load_decoder_for_path(
                        e,
                        e->playlist[(size_t)computedNextIndex],
                        &newNext,
                        &newNextLen
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                        ,
                        &newNextStream
#endif
                    );
                }
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

                if (loadedNext)
                {
                    e->nextDecoder = newNext;
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                    e->nextStream = newNextStream;
#endif
                    e->nextLengthFrames = newNextLen;
                    e->nextIndex = computedNextIndex;
                    e->hasNext = true;
                }
                else
                {
                    if (newNext != nullptr)
                    {
                        uninit_decoder_slot(
                            newNext
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                            ,
                            newNextStream
#endif
                        );
                    }
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
                    e->nextStream = nullptr;
#endif
                    e->nextIndex = -1;
                    e->nextLengthFrames = 0;
                    e->hasNext = false;
                }
            }

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
    float *out = reinterpret_cast<float *>(pOutput);

    std::memset(out, 0, (size_t)frameCount * (size_t)e->channels * sizeof(float));

    if (!e->isPlaying.load(std::memory_order_relaxed))
    {
        return;
    }

    ma_uint32 produced = 0;

    {
        std::lock_guard<std::mutex> d(e->decoderMutex);

        while (produced < frameCount && e->hasCurrent)
        {
            ma_uint64 framesRead = 0;
            ma_result r = ma_decoder_read_pcm_frames(
                e->currentDecoder,
                out + ((size_t)produced * (size_t)e->channels),
                (ma_uint64)(frameCount - produced),
                &framesRead);

            produced += (ma_uint32)framesRead;

            if (framesRead == 0 || r == MA_AT_END)
            {
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

                    request_preload(e);
                    continue;
                }

                if (e->loopMode == AE_LOOP_ONE && e->hasCurrent)
                {
                    (void)ma_decoder_seek_to_pcm_frame(e->currentDecoder, 0);
                    continue;
                }

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

    if (produced == 0)
    {
        return;
    }

    std::lock_guard<std::mutex> fx(e->fxMutex);
    if (e->gain != 1.0f)
    {
        const size_t n = (size_t)produced * (size_t)e->channels;
        for (size_t i = 0; i < n; ++i)
        {
            out[i] *= e->gain;
        }
    }

    if (e->channels >= 2 && e->pan != 0.0f)
    {
        const float l = clampf(1.0f - std::max(0.0f, e->pan), 0.0f, 1.0f);
        const float rGain = clampf(1.0f + std::min(0.0f, e->pan), 0.0f, 1.0f);
        for (ma_uint32 i = 0; i < produced; ++i)
        {
            out[(size_t)i * (size_t)e->channels] *= l;
            out[(size_t)i * (size_t)e->channels + 1] *= rGain;
        }
    }

    if (e->lowpassEnabled)
    {
        e->lowpass.processLowpass(out, produced, e->channels);
    }
    if (e->highpassEnabled)
    {
        e->highpass.processHighpass(out, produced, e->channels);
    }
    if (e->delayEnabled)
    {
        e->delay.process(out, produced, e->channels);
    }
    if (e->eqEnabled)
    {
        e->eq.process(out, produced, e->channels);
    }
    if (e->reverbEnabled)
    {
        e->reverb.process(out, produced, e->channels);
    }
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

        ma_device_config cfg = ma_device_config_init(ma_device_type_playback);
        cfg.playback.format = ma_format_f32;
        cfg.playback.channels = (ma_uint32)channels;
        cfg.sampleRate = (ma_uint32)sample_rate;
        cfg.dataCallback = data_callback;
        cfg.pUserData = e;

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
        {
            std::lock_guard<std::mutex> d(e->decoderMutex);
            hasCurrent = e->hasCurrent;
        }

        if (!hasCurrent)
        {
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

        request_jump(e, index);
        e->isPlaying.store(true, std::memory_order_relaxed);
        engine_log("jump_to requested: index=%d", index);
        clear_last_error(e);
        return true;
    }

    AE_API bool ae_jump_to_with_position(AudioEngineHandle *e, int index, double position_seconds)
    {
        if (!ae_jump_to(e, index))
        {
            return false;
        }

        const double pos = std::max(0.0, position_seconds);
        const ma_uint64 frame = (ma_uint64)(pos * (double)e->sampleRate);

        std::lock_guard<std::mutex> d(e->decoderMutex);
        if (!e->hasCurrent)
            return false;
        return ma_decoder_seek_to_pcm_frame(e->currentDecoder, frame) == MA_SUCCESS;
    }

    AE_API void ae_set_loop_mode(AudioEngineHandle *e, int loop_mode)
    {
        if (e == nullptr)
            return;
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

} // extern "C"
