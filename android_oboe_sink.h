#pragma once

#if defined(__ANDROID__)

#include <oboe/Oboe.h>
#include <oboe/OboeExtensions.h>

#include <algorithm>
#include <atomic>
#include <cmath>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <memory>
#include <string>
#include <vector>

namespace sautiflow
{

struct OboeInitParams
{
    int targetBackend = 0; // 0=AUTO, 1=AAUDIO, 2=OPENSL
    int requestedSampleRate = 0;
    int nativeHalRate = 0;
    int channels = 2;
    ma_format requestedFormat = ma_format_f32;
    bool wantLowLatency = false;
    bool wantExclusiveMMap = false;
    bool canMultiRate = false;
    bool isBluetooth = false;
    int userPeriodFrames = 0;
    int userPeriodCount = 0;
};

class AndroidOboeSink
{
public:
    using RenderFn = void (*)(void *enginePtr, void *output, uint32_t frameCount);
    using DisconnectFn = void (*)(void *enginePtr);
    using LogFn = void (*)(void *enginePtr, int level, const char *msg);

    AndroidOboeSink() = default;
    ~AndroidOboeSink() { release(); }

    AndroidOboeSink(const AndroidOboeSink &) = delete;
    AndroidOboeSink &operator=(const AndroidOboeSink &) = delete;

    // Live negotiated properties (valid when initialized == true).
    bool initialized = false;
    int sampleRate = 48000;
    int hardwareSampleRate = 0;
    int channels = 2;
    ma_format format = ma_format_f32;
    int framesPerBurst = 192;
    int bufferSizeFrames = 384;
    int bufferCapacityFrames = 0;
    int periodCount = 2;
    bool isMMap = false;
    bool isExclusive = false;
    bool isLowLatency = false;
    oboe::AudioApi audioApi = oboe::AudioApi::Unspecified;

    void setHooks(void *enginePtr, RenderFn render, DisconnectFn disconnect, LogFn log = nullptr)
    {
        enginePtr_ = enginePtr;
        renderFn_ = render;
        disconnectFn_ = disconnect;
        logFn_ = log;
    }

    bool init(const OboeInitParams &params)
    {
        release();

        if (!renderFn_)
        {
            return false;
        }

        const int ch = (params.channels > 0) ? params.channels : 2;
        const std::vector<oboe::AudioFormat> fmts = buildFormatCandidates(params.requestedFormat);

        if ((params.wantLowLatency || params.wantExclusiveMMap) && !params.isBluetooth && oboe::OboeExtensions::isMMapSupported())
        {
            oboe::OboeExtensions::setMMapEnabled(true);
        }

        const oboe::AudioApi requestedApi = backendToAudioApi(params.targetBackend);
        auto bridge = std::make_shared<CallbackBridge>(enginePtr_, renderFn_, disconnectFn_, logFn_);
        std::shared_ptr<oboe::AudioStream> openedStream;

        auto acceptStream = [&](std::shared_ptr<oboe::AudioStream> &cand, bool allowHwRateMismatch) -> bool {
            if (!cand)
            {
                return false;
            }
            const int32_t hwRate = cand->getHardwareSampleRate();
            const int32_t actualRate = cand->getSampleRate();

            if (!allowHwRateMismatch && hwRate > 0 && actualRate > 0 && hwRate != actualRate)
            {
                logMsg(1, "[Oboe] Rejecting candidate: HAL HW rate mismatch (hw=%d, stream=%d)",
                       hwRate, actualRate);
                cand->close();
                cand.reset();
                return false;
            }

            openedStream = std::move(cand);
            return true;
        };

        auto tryFormats = [&](oboe::AudioApi api,
                              oboe::PerformanceMode perf,
                              oboe::SharingMode sharing,
                              int32_t rate,
                              int32_t chanCount,
                              bool allowHwMismatch,
                              bool enforceExclOrMMapOnNonNative,
                              oboe::Usage usage = oboe::Usage::Media) -> bool {
            for (oboe::AudioFormat fmt : fmts)
            {
                std::shared_ptr<oboe::AudioStream> cand;
                if (!tryOpenCandidate(bridge, api, perf, sharing, rate, chanCount, fmt, false, cand, usage))
                {
                    continue;
                }

                if (enforceExclOrMMapOnNonNative && params.nativeHalRate > 0 &&
                    rate > 0 && rate != params.nativeHalRate)
                {
                    const bool excl = (cand->getSharingMode() == oboe::SharingMode::Exclusive);
                    const bool mmap = (cand->getAudioApi() == oboe::AudioApi::AAudio) &&
                                      oboe::OboeExtensions::isMMapUsed(cand.get());
                    if (!excl && !mmap)
                    {
                        logMsg(1, "[Oboe] Rejecting non-native %d Hz stream: lost Exclusive & MMAP (hal=%d)",
                               rate, params.nativeHalRate);
                        cand->close();
                        continue;
                    }
                }

                if (acceptStream(cand, allowHwMismatch))
                {
                    return true;
                }
            }
            return false;
        };

        auto openAtNativeHwRate = [&](oboe::PerformanceMode perf,
                                      oboe::SharingMode sharing,
                                      oboe::Usage usage = oboe::Usage::Media) -> bool {
            for (oboe::AudioFormat fmt : fmts)
            {
                std::shared_ptr<oboe::AudioStream> cand;
                if (!tryOpenCandidate(bridge,
                                      requestedApi,
                                      perf,
                                      sharing,
                                      oboe::kUnspecified,
                                      ch,
                                      fmt,
                                      false,
                                      cand,
                                      usage))
                {
                    continue;
                }
                const int32_t hwRate = cand->getHardwareSampleRate();
                const int32_t actualRate = cand->getSampleRate();
                if (hwRate > 0 && actualRate > 0 && hwRate != actualRate)
                {
                    // API 34+ exposed true hardware rate; re-open explicitly at hwRate to avoid HAL resampling.
                    cand->close();
                    if (tryFormats(requestedApi, perf, sharing, hwRate, ch, false, false, usage))
                    {
                        return true;
                    }
                }
                else
                {
                    openedStream = std::move(cand);
                    return true;
                }
            }
            return false;
        };

        bool opened = false;

        if (params.isBluetooth)
        {
            if (params.wantLowLatency || params.wantExclusiveMMap)
            {
                // Low-latency Bluetooth: declare Usage::Game (triggers LE Audio / aptX Adaptive low-latency
                // routing on supported headsets) and request PerformanceMode::LowLatency + SharingMode::Exclusive
                // (AAudio downgrades to FastMixer Shared without assigning huge NormalMixer media buffers).
                for (oboe::Usage btUsage : {oboe::Usage::Game, oboe::Usage::Media})
                {
                    for (oboe::SharingMode btSharing : {oboe::SharingMode::Exclusive, oboe::SharingMode::Shared})
                    {
                        if (params.nativeHalRate > 0)
                        {
                            opened = tryFormats(requestedApi,
                                                oboe::PerformanceMode::LowLatency,
                                                btSharing,
                                                params.nativeHalRate,
                                                ch,
                                                false,
                                                false,
                                                btUsage);
                        }
                        if (!opened)
                        {
                            opened = openAtNativeHwRate(oboe::PerformanceMode::LowLatency, btSharing, btUsage);
                        }
                        if (opened)
                        {
                            break;
                        }
                    }
                    if (opened)
                    {
                        break;
                    }
                }
            }

            // Standard Bluetooth Shared fallback (or when low-latency mode is off).
            if (!opened && params.nativeHalRate > 0)
            {
                opened = tryFormats(requestedApi,
                                    oboe::PerformanceMode::None,
                                    oboe::SharingMode::Shared,
                                    params.nativeHalRate,
                                    ch,
                                    false,
                                    false,
                                    oboe::Usage::Media);
            }
            if (!opened)
            {
                opened = openAtNativeHwRate(oboe::PerformanceMode::None,
                                            oboe::SharingMode::Shared,
                                            oboe::Usage::Media);
            }
            if (!opened)
            {
                opened = tryFormats(requestedApi,
                                    oboe::PerformanceMode::None,
                                    oboe::SharingMode::Shared,
                                    oboe::kUnspecified,
                                    ch,
                                    true,
                                    false,
                                    oboe::Usage::Media);
            }
        }
        else if (params.wantLowLatency || params.wantExclusiveMMap)
        {
            // Attempt A (Priority 1): Match song's native rate on LowLatency + Exclusive MMAP FIFO.
            const bool allowSongRate = params.requestedSampleRate > 0 &&
                                       (params.canMultiRate ||
                                        params.nativeHalRate <= 0 ||
                                        params.requestedSampleRate == params.nativeHalRate);
            if (allowSongRate)
            {
                opened = tryFormats(requestedApi,
                                    oboe::PerformanceMode::LowLatency,
                                    oboe::SharingMode::Exclusive,
                                    params.requestedSampleRate,
                                    ch,
                                    false,
                                    true);
            }

            // Attempt B (Priority 2): Locked hardware native rate on MMAP Exclusive (app resamples once via r8brain/SRC).
            if (!opened)
            {
                opened = openAtNativeHwRate(oboe::PerformanceMode::LowLatency, oboe::SharingMode::Exclusive);
            }

            // Attempt C: LowLatency + Shared (FastMixer) when Exclusive is busy/unsupported.
            if (!opened)
            {
                opened = tryFormats(requestedApi,
                                    oboe::PerformanceMode::LowLatency,
                                    oboe::SharingMode::Shared,
                                    oboe::kUnspecified,
                                    ch,
                                    true,
                                    false);
            }
        }

        // Standard Shared fallback: lock to native HAL rate (kUnspecified -> API 34+ hwRate check, or nativeHalRate)
        // so AudioFlinger never receives a non-native rate on API 27-33 and app r8brain/SRC performs single-stage SRC.
        if (!opened && !params.isBluetooth)
        {
            opened = openAtNativeHwRate(oboe::PerformanceMode::None, oboe::SharingMode::Shared);
            if (!opened && params.nativeHalRate > 0)
            {
                opened = tryFormats(requestedApi,
                                    oboe::PerformanceMode::None,
                                    oboe::SharingMode::Shared,
                                    params.nativeHalRate,
                                    ch,
                                    false,
                                    false);
            }
        }

        // Ultimate Failsafe: unspecified API/rate/format with format conversion allowed.
        if (!opened)
        {
            std::shared_ptr<oboe::AudioStream> failsafe;
            if (tryOpenCandidate(bridge,
                                 oboe::AudioApi::Unspecified,
                                 oboe::PerformanceMode::None,
                                 oboe::SharingMode::Shared,
                                 oboe::kUnspecified,
                                 2,
                                 oboe::AudioFormat::Unspecified,
                                 true,
                                 failsafe))
            {
                openedStream = std::move(failsafe);
                opened = true;
            }
        }

        if (!opened || !openedStream)
        {
            logMsg(2, "[Oboe] All open attempts failed (backend=%d, reqRate=%d, ch=%d)",
                   params.targetBackend, params.requestedSampleRate, ch);
            return false;
        }

        const bool streamIsAAudio = (openedStream->getAudioApi() == oboe::AudioApi::AAudio);
        const bool streamIsMMap = streamIsAAudio && oboe::OboeExtensions::isMMapUsed(openedStream.get());

        // Tune MMAP FIFO buffer size right after opening.
        const int32_t burst = std::max<int32_t>(1, openedStream->getFramesPerBurst());
        const int32_t cap = openedStream->getBufferCapacityInFrames();
        int32_t targetBufFrames = 0;
        if (params.userPeriodFrames > 0)
        {
            const int32_t periods = (params.userPeriodCount >= 2) ? params.userPeriodCount : 2;
            targetBufFrames = params.userPeriodFrames * periods;
        }
        else if (params.isBluetooth)
        {
            // On Bluetooth FastMixer/LowLatency, use 3 bursts (~12-15ms) instead of 2 bursts
            // to prevent A2DP packet-scheduler jitter xruns while staying far below NormalMixer's ~80-100ms buffer.
            targetBufFrames = (openedStream->getPerformanceMode() == oboe::PerformanceMode::LowLatency)
                                  ? (burst * 3)
                                  : (burst * 4);
        }
        else if (openedStream->getPerformanceMode() == oboe::PerformanceMode::LowLatency || streamIsMMap)
        {
            targetBufFrames = burst * 2;
        }
        else
        {
            targetBufFrames = burst * 4;
        }

        if (targetBufFrames < burst)
        {
            targetBufFrames = burst;
        }
        if (cap > 0 && targetBufFrames > cap)
        {
            targetBufFrames = cap;
        }
        if (targetBufFrames > 0)
        {
            openedStream->setBufferSizeInFrames(targetBufFrames);
        }

        stream_ = std::move(openedStream);
        bridge_ = std::move(bridge);

        const int32_t hwRate = stream_->getHardwareSampleRate();
        const int32_t streamRate = stream_->getSampleRate();
        sampleRate = (streamRate > 0) ? streamRate : ((hwRate > 0) ? hwRate : 48000);
        hardwareSampleRate = hwRate;
        channels = (stream_->getChannelCount() > 0) ? stream_->getChannelCount() : ch;
        format = oboeToMaFormat(stream_->getFormat());
        framesPerBurst = burst;
        bufferCapacityFrames = (cap > 0) ? cap : 0;
        const int32_t actualBuf = stream_->getBufferSizeInFrames();
        bufferSizeFrames = (actualBuf > 0) ? actualBuf : targetBufFrames;
        periodCount = (burst > 0 && bufferSizeFrames > 0)
                          ? std::max<int32_t>(1, (bufferSizeFrames + burst - 1) / burst)
                          : 2;
        audioApi = stream_->getAudioApi();
        isMMap = streamIsMMap;
        isExclusive = (stream_->getSharingMode() == oboe::SharingMode::Exclusive);
        isLowLatency = (stream_->getPerformanceMode() == oboe::PerformanceMode::LowLatency);
        initialized = true;

        logMsg(0,
               "[Oboe] Opened %s | sr=%d (hw=%d) | ch=%d | fmt=%d | burst=%d | buf=%d/%d | periods=%d | excl=%d | mmap=%d | ll=%d",
               getBackendDisplayName(),
               sampleRate,
               hardwareSampleRate,
               channels,
               (int)format,
               framesPerBurst,
               bufferSizeFrames,
               bufferCapacityFrames,
               periodCount,
               isExclusive ? 1 : 0,
               isMMap ? 1 : 0,
               isLowLatency ? 1 : 0);

        return true;
    }

    bool start()
    {
        if (!initialized || !stream_ || !bridge_)
        {
            return false;
        }
        bridge_->active.store(true, std::memory_order_release);
        const oboe::StreamState st = stream_->getState();
        if (st == oboe::StreamState::Started || st == oboe::StreamState::Starting)
        {
            return true;
        }
        const oboe::Result r = stream_->requestStart();
        if (r != oboe::Result::OK)
        {
            bridge_->active.store(false, std::memory_order_release);
            logMsg(2, "[Oboe] requestStart failed: %s", oboe::convertToText(r));
            return false;
        }
        return true;
    }

    bool stop()
    {
        if (bridge_)
        {
            bridge_->active.store(false, std::memory_order_release);
        }
        if (!initialized || !stream_)
        {
            return true;
        }
        const oboe::StreamState st = stream_->getState();
        if (st == oboe::StreamState::Stopped || st == oboe::StreamState::Stopping ||
            st == oboe::StreamState::Closed || st == oboe::StreamState::Disconnected)
        {
            return true;
        }
        const oboe::Result r = stream_->requestStop();
        if (r != oboe::Result::OK)
        {
            logMsg(1, "[Oboe] requestStop returned: %s", oboe::convertToText(r));
            return false;
        }
        return true;
    }

    void release()
    {
        if (bridge_)
        {
            bridge_->shuttingDown.store(true, std::memory_order_release);
            bridge_->active.store(false, std::memory_order_release);
        }
        if (stream_)
        {
            const oboe::StreamState st = stream_->getState();
            if (st == oboe::StreamState::Started || st == oboe::StreamState::Starting)
            {
                stream_->stop();
            }
            stream_->close();
            stream_.reset();
        }
        bridge_.reset();
        initialized = false;
        hardwareSampleRate = 0;
        isMMap = false;
        isExclusive = false;
        isLowLatency = false;
        audioApi = oboe::AudioApi::Unspecified;
    }

    double getLatencyMs() const
    {
        if (!initialized || !stream_ || sampleRate <= 0)
        {
            return 0.0;
        }
        // Only called from control/inspector thread — never from onAudioReady.
        const oboe::ResultWithValue<double> res = stream_->calculateLatencyMillis();
        if (res && res.value() > 0.0)
        {
            return res.value();
        }
        if (bufferSizeFrames > 0)
        {
            return (static_cast<double>(bufferSizeFrames) / static_cast<double>(sampleRate)) * 1000.0;
        }
        return 0.0;
    }

    uint64_t getXRunCount() const
    {
        if (!initialized || !stream_ || !stream_->isXRunCountSupported())
        {
            return 0;
        }
        const oboe::ResultWithValue<int32_t> res = stream_->getXRunCount();
        if (res && res.value() > 0)
        {
            return static_cast<uint64_t>(res.value());
        }
        return 0;
    }

    bool usesAAudio() const
    {
        return initialized && audioApi == oboe::AudioApi::AAudio;
    }

    const char *getBackendDisplayName() const
    {
        if (audioApi == oboe::AudioApi::AAudio)
        {
            return isMMap ? "Oboe (AAudio MMAP)" : "Oboe (AAudio)";
        }
        if (audioApi == oboe::AudioApi::OpenSLES)
        {
            return "Oboe (OpenSL ES)";
        }
        return "Oboe";
    }

private:
    class CallbackBridge final : public oboe::AudioStreamDataCallback,
                                 public oboe::AudioStreamErrorCallback
    {
    public:
        CallbackBridge(void *enginePtr, RenderFn renderFn, DisconnectFn disconnectFn, LogFn logFn)
            : enginePtr_(enginePtr), renderFn_(renderFn), disconnectFn_(disconnectFn), logFn_(logFn)
        {
        }

        oboe::DataCallbackResult onAudioReady(oboe::AudioStream *audioStream,
                                              void *audioData,
                                              int32_t numFrames) override
        {
            if (audioData == nullptr || numFrames <= 0)
            {
                return oboe::DataCallbackResult::Continue;
            }
            if (!active.load(std::memory_order_acquire) ||
                shuttingDown.load(std::memory_order_acquire) ||
                renderFn_ == nullptr)
            {
                const int32_t bpf = (audioStream != nullptr) ? audioStream->getBytesPerFrame() : 0;
                if (bpf > 0)
                {
                    std::memset(audioData, 0, static_cast<size_t>(numFrames) * static_cast<size_t>(bpf));
                }
                return oboe::DataCallbackResult::Continue;
            }

            renderFn_(enginePtr_, audioData, static_cast<uint32_t>(numFrames));
            return oboe::DataCallbackResult::Continue;
        }

        void onErrorAfterClose(oboe::AudioStream *, oboe::Result error) override
        {
            if (shuttingDown.load(std::memory_order_acquire))
            {
                return;
            }
            if (error == oboe::Result::ErrorDisconnected && disconnectFn_ != nullptr)
            {
                disconnectFn_(enginePtr_);
            }
        }

        std::atomic<bool> active{false};
        std::atomic<bool> shuttingDown{false};

    private:
        void *enginePtr_ = nullptr;
        RenderFn renderFn_ = nullptr;
        DisconnectFn disconnectFn_ = nullptr;
        LogFn logFn_ = nullptr;
    };

    static oboe::AudioApi backendToAudioApi(int backend)
    {
        if (backend == 1) // AE_BACKEND_AAUDIO
        {
            return oboe::AudioApi::AAudio;
        }
        if (backend == 2) // AE_BACKEND_OPENSL
        {
            return oboe::AudioApi::OpenSLES;
        }
        return oboe::AudioApi::Unspecified;
    }

    static std::vector<oboe::AudioFormat> buildFormatCandidates(ma_format req)
    {
        switch (req)
        {
            case ma_format_s32:
                return {oboe::AudioFormat::I32, oboe::AudioFormat::Float, oboe::AudioFormat::I16};
            case ma_format_s24:
                return {oboe::AudioFormat::I24, oboe::AudioFormat::I32, oboe::AudioFormat::Float, oboe::AudioFormat::I16};
            case ma_format_s16:
                return {oboe::AudioFormat::I16, oboe::AudioFormat::Float};
            case ma_format_f32:
            case ma_format_u8:
            default:
                return {oboe::AudioFormat::Float, oboe::AudioFormat::I16};
        }
    }

    static ma_format oboeToMaFormat(oboe::AudioFormat fmt)
    {
        switch (fmt)
        {
            case oboe::AudioFormat::I16:
                return ma_format_s16;
            case oboe::AudioFormat::I24:
                return ma_format_s24;
            case oboe::AudioFormat::I32:
                return ma_format_s32;
            case oboe::AudioFormat::Float:
            default:
                return ma_format_f32;
        }
    }

    bool tryOpenCandidate(const std::shared_ptr<CallbackBridge> &bridge,
                          oboe::AudioApi api,
                          oboe::PerformanceMode perf,
                          oboe::SharingMode sharing,
                          int32_t rate,
                          int32_t chanCount,
                          oboe::AudioFormat fmt,
                          bool allowFormatConv,
                          std::shared_ptr<oboe::AudioStream> &outStream,
                          oboe::Usage usage = oboe::Usage::Media)
    {
        oboe::AudioStreamBuilder builder;
        builder.setDirection(oboe::Direction::Output)
            ->setAudioApi(api)
            ->setPerformanceMode(perf)
            ->setSharingMode(sharing)
            ->setSampleRate(rate)
            ->setChannelCount(chanCount)
            ->setFormat(fmt)
            ->setUsage(usage)
            ->setContentType(oboe::ContentType::Music)
            ->setSampleRateConversionQuality(oboe::SampleRateConversionQuality::None)
            ->setFormatConversionAllowed(allowFormatConv)
            ->setChannelConversionAllowed(false)
            ->setDataCallback(bridge)
            ->setErrorCallback(bridge);

        // Explicitly avoid builder.setFramesPerDataCallback(...) so AAudio MMAP keeps native burst callbacks.

        const oboe::Result r = builder.openStream(outStream);
        if (r != oboe::Result::OK || !outStream)
        {
            outStream.reset();
            return false;
        }
        return true;
    }

    void logMsg(int level, const char *fmt, ...) const
    {
        if (!logFn_)
        {
            return;
        }
        char buf[512];
        va_list args;
        va_start(args, fmt);
        std::vsnprintf(buf, sizeof(buf), fmt, args);
        va_end(args);
        buf[sizeof(buf) - 1] = '\0';
        logFn_(enginePtr_, level, buf);
    }

    void *enginePtr_ = nullptr;
    RenderFn renderFn_ = nullptr;
    DisconnectFn disconnectFn_ = nullptr;
    LogFn logFn_ = nullptr;
    std::shared_ptr<CallbackBridge> bridge_;
    std::shared_ptr<oboe::AudioStream> stream_;
};

} // namespace sautiflow

#endif // __ANDROID__
