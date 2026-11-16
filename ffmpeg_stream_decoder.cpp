#include "ffmpeg_stream_decoder.h"

#include <cstring>
#include <chrono>
#include <algorithm>
#include <iostream>
#include <mutex>
#include <future>

#ifdef __ANDROID__
#include <android/log.h>
#define SF_LOG(...) __android_log_print(ANDROID_LOG_INFO, "SautiFlowFFmpeg", __VA_ARGS__)
#define SF_LOGE(...) __android_log_print(ANDROID_LOG_ERROR, "SautiFlowFFmpeg", __VA_ARGS__)
#else
#define SF_LOG(...) do { std::printf(__VA_ARGS__); std::fflush(stdout); } while(0)
#define SF_LOGE(...) do { std::fprintf(stderr, __VA_ARGS__); std::fflush(stderr); } while(0)
#endif

#if defined(SAUTIFLOW_ENABLE_FFMPEG) && SAUTIFLOW_ENABLE_FFMPEG
#ifdef __cplusplus
extern "C" {
#endif
#include <libavformat/avformat.h>
#include <libavformat/avio.h>
#include <libavcodec/avcodec.h>
#include <libswresample/swresample.h>
#include <libavutil/opt.h>
#include <libavutil/dict.h>
#include <libavutil/channel_layout.h>
#include <libavutil/error.h>
#include <libavutil/time.h>
#include <libavutil/replaygain.h>
#include <libavutil/mem.h>
#ifdef __cplusplus
}
#endif

#include "dsp/denormals.h"

#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
#include <curl/curl.h>
#endif

namespace sautiflow {

static bool configure_native_swr_opts(SwrContext* swrCtx, int filterSize = 64) {
    if (!swrCtx) return false;
    swr_close(swrCtx);

    // Native FFmpeg polyphase sinc resampling engine (linear-phase).
    // filter_size >= 64 provides steep transition band roll-off, eliminating
    // aliasing/imaging near Nyquist (20-22 kHz) when resampling 44.1k <-> 48k.
    // cutoff ~0.97 preserves bandwidth up to 21.4 kHz @ 44.1k without high-frequency attenuation.
    // phase_shift 10 sets 1024 polyphase filter phases (2^10) for high phase accuracy.
    int rEngine = av_opt_set_int(swrCtx, "resampler", SWR_ENGINE_SWR, 0);
    int rFilter = av_opt_set_int(swrCtx, "filter_size", filterSize, 0);
    int rCutoff = av_opt_set_double(swrCtx, "cutoff", 0.97, 0);
    int rPhase  = av_opt_set_int(swrCtx, "phase_shift", 10, 0);
    if (rEngine < 0 || rFilter < 0 || rCutoff < 0 || rPhase < 0) {
        return false;
    }
    int rType   = av_opt_set_int(swrCtx, "filter_type", SWR_FILTER_TYPE_KAISER, 0);
    if (rType < 0) {
        av_opt_set_int(swrCtx, "filter_type", SWR_FILTER_TYPE_BLACKMAN_NUTTALL, 0);
    }

    int ret = swr_init(swrCtx);
    return (ret >= 0 && swr_is_initialized(swrCtx));
}

static bool init_swr_context(SwrContext* swrCtx) {
    if (!swrCtx) return false;

    // 1. High-precision native SWR polyphase sinc filter (64 taps, cutoff=0.97, phase_shift=10)
    // Pure native FFmpeg libswresample implementation - zero external libsoxr dependency.
    if (configure_native_swr_opts(swrCtx, 64)) {
        SF_LOG("[ffmpeg] SwrContext initialized with high-precision native SWR engine (64-tap sinc, cutoff=0.97, phase_shift=10)\n");
        return true;
    }

    // 2. Fallback to standard 32-tap SWR engine if 64-tap is not accepted
    if (configure_native_swr_opts(swrCtx, 32)) {
        SF_LOG("[ffmpeg] SwrContext initialized with fallback 32-tap native SWR engine (cutoff=0.97)\n");
        return true;
    }

    // 3. Ultimate fallback to default swresample options
    swr_close(swrCtx);
    av_opt_set_int(swrCtx, "resampler", SWR_ENGINE_SWR, 0);
    int ret = swr_init(swrCtx);
    if (ret >= 0 && swr_is_initialized(swrCtx)) {
        SF_LOG("[ffmpeg] SwrContext initialized with default swresample engine\n");
        return true;
    }

    SF_LOGE("[ffmpeg] Failed to initialize SwrContext with any engine (ret=%d)\n", ret);
    return false;
}


static std::atomic<FFmpegStreamSource*> g_activeStreamSource{nullptr};

static int ffmpeg_interrupt_callback(void* ctx) {
    auto* self = static_cast<FFmpegStreamSource*>(ctx);
    if (!self) return 0;
    return self->is_stop_requested() ? 1 : 0;
}

struct CustomHttpReaderBase {
    virtual ~CustomHttpReaderBase() = default;
    virtual bool seek_to_ms(int64_t /*timestampMs*/) { return false; }
    virtual double get_duration_sec() const { return 0.0; }
};

// Bounded HTTP byte-range reader for YouTube / googlevideo.com streams.
// googlevideo.com rejects open-ended Range: bytes=0- requests (and ranges >= 1 MB)
// on adaptive streams (c=WEB_REMIX, c=WEB, etc.) with HTTP 403 Forbidden,
// whereas bounded 512 KB byte-range chunks (Range: bytes=start-end) return HTTP 206.
struct YouTubeChunkedHttpReader : public CustomHttpReaderBase {
    std::string url;
    std::string userAgent;
    std::string baseHeaders;
    FFmpegStreamSource* owner{nullptr};
    int64_t totalSize{-1};
    int64_t pos{0};
    int64_t chunkSize{524288}; // 512 KB bounded chunks
    std::vector<uint8_t> chunkBuf;
    int64_t chunkStart{-1};
    int64_t chunkEnd{-1}; // exclusive

#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
    CURL* curlHandle{nullptr};

    static size_t curl_write_vec(char* ptr, size_t size, size_t nmemb, void* userdata) {
        auto* vec = static_cast<std::vector<uint8_t>*>(userdata);
        size_t total = size * nmemb;
        if (vec && total > 0) {
            vec->insert(vec->end(), reinterpret_cast<uint8_t*>(ptr), reinterpret_cast<uint8_t*>(ptr) + total);
        }
        return total;
    }

    static int curl_progress_cb(void* clientp, curl_off_t, curl_off_t, curl_off_t, curl_off_t) {
        auto* self = static_cast<YouTubeChunkedHttpReader*>(clientp);
        return (self && self->owner && self->owner->is_stop_requested()) ? 1 : 0;
    }
#endif

    ~YouTubeChunkedHttpReader() override {
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
        if (curlHandle) {
            curl_easy_cleanup(curlHandle);
            curlHandle = nullptr;
        }
#endif
    }

    static int64_t parse_clen(const std::string& u) {
        size_t idx = u.find("clen=");
        if (idx == std::string::npos) return -1;
        idx += 5;
        size_t end = u.find('&', idx);
        std::string sub = (end == std::string::npos) ? u.substr(idx) : u.substr(idx, end - idx);
        try {
            return std::stoll(sub);
        } catch (...) {
            return -1;
        }
    }

    bool fetch_chunk(int64_t startOffset) {
        if (owner && owner->is_stop_requested()) return false;
        if (totalSize > 0 && startOffset >= totalSize) return false;

        // Use a smaller 128 KB initial chunk at byte 0 for ultra-fast startup on slow connections,
        // then 512 KB chunks for sustained streaming.
        int64_t activeChunkSize = (startOffset == 0) ? 131072 : chunkSize;
        int64_t reqEnd = startOffset + activeChunkSize - 1;
        if (totalSize > 0 && reqEnd >= totalSize) {
            reqEnd = totalSize - 1;
        }
        int64_t expectedLen = reqEnd - startOffset + 1;
        if (expectedLen <= 0) return false;

#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
        if (!curlHandle) {
            curlHandle = curl_easy_init();
        }
        if (curlHandle) {
            std::string rangeStr = std::to_string(startOffset) + "-" + std::to_string(reqEnd);
            for (int attempt = 0; attempt < 6; ++attempt) {
                if (owner && owner->is_stop_requested()) return false;
                if (attempt > 0) {
                    int delayMs = std::min(1000, 120 * attempt);
                    for (int waited = 0; waited < delayMs; waited += 40) {
                        if (owner && owner->is_stop_requested()) return false;
                        std::this_thread::sleep_for(std::chrono::milliseconds(40));
                    }
                }
                struct curl_slist* hdrs = nullptr;
                hdrs = curl_slist_append(hdrs, "Referer: https://www.youtube.com/");
                hdrs = curl_slist_append(hdrs, "Origin: https://www.youtube.com");
                hdrs = curl_slist_append(hdrs, "Connection: keep-alive");

                std::vector<uint8_t> temp;
                temp.reserve(static_cast<size_t>(expectedLen));
                curl_easy_setopt(curlHandle, CURLOPT_URL, url.c_str());
                curl_easy_setopt(curlHandle, CURLOPT_RANGE, rangeStr.c_str());
                curl_easy_setopt(curlHandle, CURLOPT_FOLLOWLOCATION, 1L);
                curl_easy_setopt(curlHandle, CURLOPT_CONNECTTIMEOUT, 10L);
                curl_easy_setopt(curlHandle, CURLOPT_TIMEOUT, 20L);
                curl_easy_setopt(curlHandle, CURLOPT_SSL_VERIFYPEER, 0L);
                curl_easy_setopt(curlHandle, CURLOPT_SSL_VERIFYHOST, 0L);
                curl_easy_setopt(curlHandle, CURLOPT_TCP_KEEPALIVE, 1L);
                curl_easy_setopt(curlHandle, CURLOPT_FRESH_CONNECT, (attempt > 0) ? 1L : 0L);
                if (!userAgent.empty()) {
                    curl_easy_setopt(curlHandle, CURLOPT_USERAGENT, userAgent.c_str());
                }
                curl_easy_setopt(curlHandle, CURLOPT_HTTPHEADER, hdrs);
                curl_easy_setopt(curlHandle, CURLOPT_WRITEFUNCTION, &YouTubeChunkedHttpReader::curl_write_vec);
                curl_easy_setopt(curlHandle, CURLOPT_WRITEDATA, &temp);
                curl_easy_setopt(curlHandle, CURLOPT_NOPROGRESS, 0L);
                curl_easy_setopt(curlHandle, CURLOPT_XFERINFOFUNCTION, &YouTubeChunkedHttpReader::curl_progress_cb);
                curl_easy_setopt(curlHandle, CURLOPT_XFERINFODATA, this);

                CURLcode res = curl_easy_perform(curlHandle);
                curl_slist_free_all(hdrs);
                long httpCode = 0;
                curl_easy_getinfo(curlHandle, CURLINFO_RESPONSE_CODE, &httpCode);
                if (res == CURLE_OK && (httpCode == 200 || httpCode == 206) && !temp.empty()) {
                    chunkBuf = std::move(temp);
                    chunkStart = startOffset;
                    chunkEnd = startOffset + static_cast<int64_t>(chunkBuf.size());
                    return true;
                }
            }
        }
#endif

        AVIOInterruptCB intCb{ffmpeg_interrupt_callback, owner};

        for (int attempt = 0; attempt < 3; ++attempt) {
            if (owner && owner->is_stop_requested()) return false;

            AVDictionary* opts = nullptr;
            if (!userAgent.empty()) {
                av_dict_set(&opts, "user_agent", userAgent.c_str(), 0);
            }
            if (!baseHeaders.empty()) {
                av_dict_set(&opts, "headers", baseHeaders.c_str(), 0);
            }
            av_dict_set(&opts, "seekable", "0", 0);
            av_dict_set(&opts, "http_persistent", "0", 0);
            av_dict_set(&opts, "timeout", "10000000", 0);
            av_dict_set(&opts, "rw_timeout", "10000000", 0);
            av_dict_set(&opts, "tls_verify", "0", 0);

            std::string rangedUrl = url + (url.find('?') == std::string::npos ? "?range=" : "&range=") +
                std::to_string(startOffset) + "-" + std::to_string(reqEnd);

            AVIOContext* io = nullptr;
            int ret = avio_open2(&io, rangedUrl.c_str(), AVIO_FLAG_READ, &intCb, &opts);
            if (opts) av_dict_free(&opts);

            if (ret < 0 || !io) {
                if (io) avio_closep(&io);
                continue;
            }

            chunkBuf.resize(static_cast<size_t>(expectedLen));
            int64_t totalRead = 0;
            while (totalRead < expectedLen) {
                if (owner && owner->is_stop_requested()) break;
                int toRead = static_cast<int>(std::min<int64_t>(32768, expectedLen - totalRead));
                int r = avio_read(io, chunkBuf.data() + totalRead, toRead);
                if (r <= 0) break;
                totalRead += r;
            }
            avio_closep(&io);

            if (totalRead > 0) {
                chunkBuf.resize(static_cast<size_t>(totalRead));
                chunkStart = startOffset;
                chunkEnd = startOffset + totalRead;
                return true;
            }
        }
        return false;
    }

    static int read_packet(void* opaque, uint8_t* buf, int buf_size) {
        auto* self = static_cast<YouTubeChunkedHttpReader*>(opaque);
        if (!self || buf_size <= 0) return AVERROR_EOF;
        if (self->owner && self->owner->is_stop_requested()) return AVERROR_EXIT;
        if (self->totalSize > 0 && self->pos >= self->totalSize) return AVERROR_EOF;

        if (self->pos < self->chunkStart || self->pos >= self->chunkEnd) {
            if (!self->fetch_chunk(self->pos)) {
                return AVERROR_EOF;
            }
        }

        int64_t avail = self->chunkEnd - self->pos;
        if (avail <= 0) return AVERROR_EOF;

        int toCopy = static_cast<int>(std::min<int64_t>(buf_size, avail));
        std::memcpy(buf, self->chunkBuf.data() + (self->pos - self->chunkStart), static_cast<size_t>(toCopy));
        self->pos += toCopy;
        return toCopy;
    }

    static int64_t seek(void* opaque, int64_t offset, int whence) {
        auto* self = static_cast<YouTubeChunkedHttpReader*>(opaque);
        if (!self) return -1;

        if (whence & AVSEEK_SIZE) {
            return self->totalSize > 0 ? self->totalSize : -1;
        }

        int baseWhence = whence & ~(AVSEEK_FORCE | AVSEEK_SIZE);
        int64_t target = -1;
        if (baseWhence == SEEK_SET) {
            target = offset;
        } else if (baseWhence == SEEK_CUR) {
            target = self->pos + offset;
        } else if (baseWhence == SEEK_END && self->totalSize > 0) {
            target = self->totalSize + offset;
        } else {
            return -1;
        }

        if (target < 0) target = 0;
        if (self->totalSize > 0 && target > self->totalSize) target = self->totalSize;
        self->pos = target;
        return self->pos;
    }
};

// Resilient MPEG-TS HLS segment reader for YouTube / googlevideo.com HLS streams.
// Fetches the variant .m3u8 playlist once, parses all #EXTINF segment URLs + durations,
// and streams the concatenated .ts segments into FFmpeg's mpegts demuxer with automatic
// multi-attempt retry and exponential backoff on transient TLS handshake drops.
struct YouTubeHlsHttpReader : public CustomHttpReaderBase {
    struct Segment {
        std::string url;
        double durationSec{0.0};
        double startSec{0.0};
    };

    std::string playlistUrl;
    std::string userAgent;
    std::string baseHeaders;
    FFmpegStreamSource* owner{nullptr};
    std::vector<Segment> segments;
    double totalDurationSec{0.0};
    bool playlistLoaded{false};
    bool isFmp4{false};
    std::string initMapUrl;
    std::vector<uint8_t> initMapBytes;

    size_t currentSegIdx{0};
    std::vector<uint8_t> segBuf;
    size_t segOffset{0};

    // Background prefetch of the next .ts segment so decode never waits on network.
    size_t prefetchIdx{static_cast<size_t>(-1)};
    std::vector<uint8_t> prefetchBuf;
    std::future<bool> prefetchFuture;

    void wait_prefetch() {
        if (prefetchFuture.valid()) {
            try { prefetchFuture.get(); } catch (...) {}
        }
    }

    void start_prefetch(size_t idx) {
        if (idx >= segments.size() || prefetchFuture.valid()) return;
        prefetchIdx = idx;
        prefetchBuf.clear();
        std::string u = segments[idx].url;
        prefetchFuture = std::async(std::launch::async, [this, u]() {
            return fetch_url_bytes(u, prefetchBuf, 8, true);
        });
    }

#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
    CURL* curlHandle{nullptr};
    struct curl_slist* curlHeaderList{nullptr};
    CURL* prefetchCurlHandle{nullptr};
    struct curl_slist* prefetchHeaderList{nullptr};

    static size_t curl_write_vec(char* ptr, size_t size, size_t nmemb, void* userdata) {
        auto* vec = static_cast<std::vector<uint8_t>*>(userdata);
        size_t total = size * nmemb;
        if (vec && total > 0) {
            vec->insert(vec->end(), reinterpret_cast<uint8_t*>(ptr), reinterpret_cast<uint8_t*>(ptr) + total);
        }
        return total;
    }

    static int curl_progress_cb(void* clientp, curl_off_t, curl_off_t, curl_off_t, curl_off_t) {
        auto* self = static_cast<YouTubeHlsHttpReader*>(clientp);
        return (self && self->owner && self->owner->is_stop_requested()) ? 1 : 0;
    }
#endif

    ~YouTubeHlsHttpReader() override {
        wait_prefetch();
#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
        if (prefetchHeaderList) { curl_slist_free_all(prefetchHeaderList); prefetchHeaderList = nullptr; }
        if (prefetchCurlHandle) { curl_easy_cleanup(prefetchCurlHandle); prefetchCurlHandle = nullptr; }
        if (curlHeaderList) {
            curl_slist_free_all(curlHeaderList);
            curlHeaderList = nullptr;
        }
        if (curlHandle) {
            curl_easy_cleanup(curlHandle);
            curlHandle = nullptr;
        }
#endif
    }

    double get_duration_sec() const override {
        return totalDurationSec;
    }

    bool fetch_url_bytes(const std::string& targetUrl, std::vector<uint8_t>& outBuf, int maxAttempts = 12, bool usePrefetchHandle = false) {
        outBuf.clear();

#if defined(AE_ENABLE_CURL) && AE_ENABLE_CURL
        CURL*& hRef = usePrefetchHandle ? prefetchCurlHandle : curlHandle;
        struct curl_slist*& hlRef = usePrefetchHandle ? prefetchHeaderList : curlHeaderList;
        if (!hRef) {
            hRef = curl_easy_init();
            if (hRef) {
                hlRef = curl_slist_append(hlRef, "Referer: https://www.youtube.com/");
                hlRef = curl_slist_append(hlRef, "Origin: https://www.youtube.com");
                hlRef = curl_slist_append(hlRef, "Connection: keep-alive");
            }
        }
        if (hRef) {
            for (int attempt = 0; attempt < maxAttempts; ++attempt) {
                if (owner && owner->is_stop_requested()) return false;
                if (attempt > 0) {
                    int delayMs = std::min(1500, 150 * attempt);
                    for (int waited = 0; waited < delayMs; waited += 50) {
                        if (owner && owner->is_stop_requested()) return false;
                        std::this_thread::sleep_for(std::chrono::milliseconds(50));
                    }
                }
                std::vector<uint8_t> temp;
                temp.reserve(262144);
                curl_easy_setopt(hRef, CURLOPT_URL, targetUrl.c_str());
                curl_easy_setopt(hRef, CURLOPT_FOLLOWLOCATION, 1L);
                curl_easy_setopt(hRef, CURLOPT_CONNECTTIMEOUT, 10L);
                curl_easy_setopt(hRef, CURLOPT_TIMEOUT, 20L);
                curl_easy_setopt(hRef, CURLOPT_SSL_VERIFYPEER, 0L);
                curl_easy_setopt(hRef, CURLOPT_SSL_VERIFYHOST, 0L);
                curl_easy_setopt(hRef, CURLOPT_TCP_KEEPALIVE, 1L);
        curl_easy_setopt(hRef, CURLOPT_FRESH_CONNECT, (attempt > 0) ? 1L : 0L);
                if (!userAgent.empty()) {
                    curl_easy_setopt(hRef, CURLOPT_USERAGENT, userAgent.c_str());
                }
                if (hlRef) {
                    curl_easy_setopt(hRef, CURLOPT_HTTPHEADER, hlRef);
                }
                curl_easy_setopt(hRef, CURLOPT_WRITEFUNCTION, &YouTubeHlsHttpReader::curl_write_vec);
                curl_easy_setopt(hRef, CURLOPT_WRITEDATA, &temp);
                curl_easy_setopt(hRef, CURLOPT_NOPROGRESS, 0L);
                curl_easy_setopt(hRef, CURLOPT_XFERINFOFUNCTION, &YouTubeHlsHttpReader::curl_progress_cb);
                curl_easy_setopt(hRef, CURLOPT_XFERINFODATA, this);

                CURLcode res = curl_easy_perform(hRef);
                long httpCode = 0;
                curl_easy_getinfo(hRef, CURLINFO_RESPONSE_CODE, &httpCode);
                if (res == CURLE_OK && httpCode >= 200 && httpCode < 300 && !temp.empty()) {
                    outBuf = std::move(temp);
                    return true;
                }
            }
        }
#endif

        AVIOInterruptCB intCb{ffmpeg_interrupt_callback, owner};

        for (int attempt = 0; attempt < maxAttempts; ++attempt) {
            if (owner && owner->is_stop_requested()) return false;
            if (attempt > 0) {
                int delayMs = std::min(1500, 150 * attempt);
                for (int waited = 0; waited < delayMs; waited += 50) {
                    if (owner && owner->is_stop_requested()) return false;
                    std::this_thread::sleep_for(std::chrono::milliseconds(50));
                }
            }

            AVDictionary* opts = nullptr;
            if (!userAgent.empty()) {
                av_dict_set(&opts, "user_agent", userAgent.c_str(), 0);
            }
            if (!baseHeaders.empty()) {
                av_dict_set(&opts, "headers", baseHeaders.c_str(), 0);
            }
            av_dict_set(&opts, "seekable", "0", 0);
            av_dict_set(&opts, "http_persistent", "0", 0);
            av_dict_set(&opts, "timeout", "10000000", 0);
            av_dict_set(&opts, "rw_timeout", "10000000", 0);
            av_dict_set(&opts, "tls_verify", "0", 0);

            AVIOContext* io = nullptr;
            int ret = avio_open2(&io, targetUrl.c_str(), AVIO_FLAG_READ, &intCb, &opts);
            if (opts) av_dict_free(&opts);

            if (ret < 0 || !io) {
                if (io) avio_closep(&io);
                continue;
            }

            std::vector<uint8_t> temp;
            temp.reserve(262144);
            uint8_t readChunk[32768];
            bool readError = false;
            while (true) {
                if (owner && owner->is_stop_requested()) {
                    readError = true;
                    break;
                }
                int r = avio_read(io, readChunk, sizeof(readChunk));
                if (r > 0) {
                    temp.insert(temp.end(), readChunk, readChunk + r);
                } else if (r == AVERROR_EOF || r == 0) {
                    break;
                } else {
                    readError = true;
                    break;
                }
            }
            avio_closep(&io);

            if (!readError && !temp.empty()) {
                outBuf = std::move(temp);
                return true;
            }
        }
        return false;
    }

    bool load_playlist() {
        if (playlistLoaded) return !segments.empty();
        playlistLoaded = true;

        std::vector<uint8_t> raw;
        if (!fetch_url_bytes(playlistUrl, raw, 8) || raw.empty()) {
            return false;
        }

        std::string content(reinterpret_cast<const char*>(raw.data()), raw.size());
        segments.clear();
        totalDurationSec = 0.0;

        double pendingDur = 0.0;
        size_t pos = 0;
        while (pos < content.size()) {
            size_t lineEnd = content.find('\n', pos);
            std::string line = (lineEnd == std::string::npos)
                ? content.substr(pos)
                : content.substr(pos, lineEnd - pos);
            pos = (lineEnd == std::string::npos) ? content.size() : lineEnd + 1;

            if (!line.empty() && line.back() == '\r') {
                line.pop_back();
            }
            if (line.empty()) continue;

            if (line.rfind("#EXT-X-MAP:", 0) == 0) {
                size_t uriPos = line.find("URI=\"");
                if (uriPos != std::string::npos) {
                    uriPos += 5;
                    size_t uriEnd = line.find('"', uriPos);
                    if (uriEnd != std::string::npos) {
                        initMapUrl = line.substr(uriPos, uriEnd - uriPos);
                        isFmp4 = true;
                    }
                }
            } else if (line.rfind("#EXTINF:", 0) == 0) {
                std::string durPart = line.substr(8);
                size_t comma = durPart.find(',');
                if (comma != std::string::npos) {
                    durPart = durPart.substr(0, comma);
                }
                try {
                    pendingDur = std::stod(durPart);
                } catch (...) {
                    pendingDur = 5.0;
                }
            } else if (line[0] != '#') {
                Segment seg;
                seg.url = line;
                seg.durationSec = pendingDur > 0.0 ? pendingDur : 5.0;
                seg.startSec = totalDurationSec;
                totalDurationSec += seg.durationSec;
                segments.push_back(std::move(seg));
                pendingDur = 0.0;
            }
        }

        if (segments.empty()) return false;
        if (isFmp4 && !initMapUrl.empty()) {
            if (!fetch_url_bytes(initMapUrl, initMapBytes, 8) || initMapBytes.empty()) {
                return false;
            }
            segBuf = initMapBytes;
            segOffset = 0;
            start_prefetch(0);
        }
        return true;
    }

    bool seek_to_ms(int64_t timestampMs) override {
        if (!load_playlist() || segments.empty()) return false;
        double targetSec = std::max(0.0, (double)timestampMs / 1000.0);
        size_t chosen = 0;
        for (size_t i = 0; i < segments.size(); ++i) {
            if (segments[i].startSec <= targetSec) {
                chosen = i;
            } else {
                break;
            }
        }
        wait_prefetch();
        prefetchIdx = static_cast<size_t>(-1);
        prefetchBuf.clear();
        currentSegIdx = chosen;
        segBuf.clear();
        segOffset = 0;
        return true;
    }

    static int read_packet(void* opaque, uint8_t* buf, int buf_size) {
        auto* self = static_cast<YouTubeHlsHttpReader*>(opaque);
        if (!self || buf_size <= 0) return AVERROR_EOF;
        if (self->owner && self->owner->is_stop_requested()) return AVERROR_EXIT;

        if (!self->playlistLoaded) {
            if (!self->load_playlist()) {
                return AVERROR_EOF;
            }
        }

        while (self->segOffset >= self->segBuf.size()) {
            if (self->owner && self->owner->is_stop_requested()) return AVERROR_EXIT;
            if (self->currentSegIdx >= self->segments.size()) {
                return AVERROR_EOF;
            }
            const std::string& segUrl = self->segments[self->currentSegIdx].url;
            self->segBuf.clear();
            self->segOffset = 0;
            bool got = false;
            if (self->prefetchIdx == self->currentSegIdx && self->prefetchFuture.valid()) {
                bool ok = false;
                try { ok = self->prefetchFuture.get(); } catch (...) { ok = false; }
                if (ok && !self->prefetchBuf.empty()) {
                    self->segBuf = std::move(self->prefetchBuf);
                    got = true;
                }
                self->prefetchBuf.clear();
                self->prefetchIdx = static_cast<size_t>(-1);
            } else {
                self->wait_prefetch();
                self->prefetchIdx = static_cast<size_t>(-1);
            }
            if (!got && !self->fetch_url_bytes(segUrl, self->segBuf, 12)) {
                if (self->owner && self->owner->is_stop_requested()) return AVERROR_EXIT;
                return AVERROR_EOF;
            }
            self->currentSegIdx++;
            self->start_prefetch(self->currentSegIdx);
        }

        size_t avail = self->segBuf.size() - self->segOffset;
        int toCopy = static_cast<int>(std::min<size_t>(static_cast<size_t>(buf_size), avail));
        std::memcpy(buf, self->segBuf.data() + self->segOffset, static_cast<size_t>(toCopy));
        self->segOffset += static_cast<size_t>(toCopy);
        return toCopy;
    }
};

StreamTelemetry get_active_stream_telemetry() {
    FFmpegStreamSource* src = g_activeStreamSource.load(std::memory_order_acquire);
    if (src != nullptr) {
        return src->get_telemetry();
    }
    return StreamTelemetry();
}

bool FFmpegStreamSource::is_network_url(const char* path) {
    if (path == nullptr) return false;
    std::string s(path);
    auto to_lower = [](std::string in) {
        for (auto &c : in) c = (char)::tolower(c);
        return in;
    };
    std::string lower = to_lower(s);
    return (lower.rfind("http://", 0) == 0 ||
            lower.rfind("https://", 0) == 0 ||
            lower.rfind("rtmp://", 0) == 0 ||
            lower.rfind("rtsp://", 0) == 0 ||
            lower.rfind("mms://", 0) == 0 ||
            lower.find(".m3u8") != std::string::npos ||
            lower.find(".mpd") != std::string::npos);
}

static std::string av_err2str_cpp(int errnum) {
    char errbuf[AV_ERROR_MAX_STRING_SIZE] = {0};
    av_strerror(errnum, errbuf, sizeof(errbuf));
    return std::string(errbuf);
}

FFmpegStreamSource::FFmpegStreamSource() {
    static std::once_flag initFlag;
    std::call_once(initFlag, []() {
        avformat_network_init();
    });
}

FFmpegStreamSource::~FFmpegStreamSource() {
    close();
}

void FFmpegStreamSource::set_telemetry_callback(StreamTelemetryCallback cb) {
    std::lock_guard<std::mutex> lock(m_stateMutex);
    m_telemetryCb = std::move(cb);
}

void FFmpegStreamSource::notify_telemetry() {
    StreamTelemetry copy;
    StreamTelemetryCallback cb;
    {
        std::lock_guard<std::mutex> lock(m_stateMutex);
        copy = m_telemetry;
        cb = m_telemetryCb;
    }
    if (cb) {
        cb(copy);
    }
}

void FFmpegStreamSource::set_error(StreamErrorCode code, const std::string& msg) {
    {
        std::lock_guard<std::mutex> lock(m_stateMutex);
        m_telemetry.state = StreamState::Error;
        m_telemetry.errorCode = code;
        std::strncpy(m_telemetry.errorMessage, msg.c_str(), sizeof(m_telemetry.errorMessage) - 1);
    }
    notify_telemetry();
}

StreamTelemetry FFmpegStreamSource::get_telemetry() const {
    std::lock_guard<std::mutex> lock(m_stateMutex);
    return m_telemetry;
}

bool FFmpegStreamSource::open(const std::string& url, int targetSampleRate, int targetChannels, int prebufferMs) {
    close();

    m_url = url;
    m_targetSampleRate = (targetSampleRate > 0) ? targetSampleRate : 48000;
    m_targetChannels = (targetChannels > 0) ? targetChannels : 2;
    
    bool isNetwork = is_network_url(m_url.c_str());

    // Allocate 10-second circular PCM ring buffer
    const size_t ringBufferDurationSec = 10;
    m_rbCapacityFrames = m_targetSampleRate * ringBufferDurationSec;
    m_pcmRingBuffer.assign(m_rbCapacityFrames * m_targetChannels, 0.0f);
    m_rbReadPos.store(0, std::memory_order_relaxed);
    m_rbWritePos.store(0, std::memory_order_relaxed);
    m_rbAvailableFrames.store(0, std::memory_order_relaxed);

    if (isNetwork) {
        // Initial prebuffer threshold (e.g. 1.5 seconds)
        size_t prebufferFrames = (m_targetSampleRate * (prebufferMs > 0 ? prebufferMs : 500)) / 1000;
        if (prebufferFrames == 0) prebufferFrames = m_targetSampleRate / 2; // minimum 500ms
        m_prebufferBytes = prebufferFrames;

        // Rebuffer threshold (e.g. 3.0 seconds for jitter recovery)
        size_t rebufferFrames = (m_targetSampleRate * 1500) / 1000; // 1.5s jitter recovery after an underrun
        if (rebufferFrames > m_rbCapacityFrames / 2) rebufferFrames = m_rbCapacityFrames / 2;
        m_rebufferBytes = rebufferFrames;

        m_isBuffering.store(true, std::memory_order_release);
    } else {
        // Local file - instant playback from disk with zero prebuffering delay
        m_prebufferBytes = 0;
        m_rebufferBytes = 0;
        m_isBuffering.store(false, std::memory_order_release);
    }

    m_hasStartedPlayback.store(false, std::memory_order_relaxed);
    m_stopRequested.store(false, std::memory_order_release);
    m_isPaused.store(false, std::memory_order_relaxed);
    m_isEnded.store(false, std::memory_order_relaxed);
    m_seekRequested.store(false, std::memory_order_relaxed);

    {
        std::lock_guard<std::mutex> lock(m_stateMutex);
        m_telemetry = StreamTelemetry();
        m_telemetry.state = isNetwork ? StreamState::Connecting : StreamState::Playing;
        m_telemetry.sampleRate = m_targetSampleRate;
        m_telemetry.channels = m_targetChannels;
    }
    notify_telemetry();

    m_isOpen.store(true, std::memory_order_release);
    {
        FFmpegStreamSource* expected = nullptr;
        g_activeStreamSource.compare_exchange_strong(expected, this, std::memory_order_acq_rel);
    }
    m_workerThread = std::thread(&FFmpegStreamSource::demux_and_decode_thread_func, this);
    return true;
}

void FFmpegStreamSource::close() {
    m_stopRequested.store(true, std::memory_order_release);
    m_cv.notify_all();

    if (m_workerThread.joinable()) {
        m_workerThread.join();
    }

    {
        std::lock_guard<std::mutex> lock(m_stateMutex);
        if (m_swrCtx) {
            swr_free(&m_swrCtx);
            m_swrCtx = nullptr;
        }
        if (m_swrInLayoutValid && m_swrInChLayout) {
            av_channel_layout_uninit(m_swrInChLayout);
            m_swrInLayoutValid = false;
        }
        if (m_swrInChLayout) {
            delete m_swrInChLayout;
            m_swrInChLayout = nullptr;
        }
        m_swrInSampleRate = 0;
        m_swrInSampleFmt = -1;

        if (m_codecCtx) {
            avcodec_free_context(&m_codecCtx);
            m_codecCtx = nullptr;
        }
        if (m_fmtCtx) {
            if (m_customAvioCtx) {
                m_fmtCtx->pb = nullptr;
            }
            avformat_close_input(&m_fmtCtx);
            m_fmtCtx = nullptr;
        }
        if (m_customAvioCtx) {
            if (m_customAvioCtx->buffer) {
                av_freep(&m_customAvioCtx->buffer);
            }
            avio_context_free(&m_customAvioCtx);
            m_customAvioCtx = nullptr;
        }
        if (m_customHttpReader) {
            delete static_cast<CustomHttpReaderBase*>(m_customHttpReader);
            m_customHttpReader = nullptr;
        }
        m_audioStreamIndex = -1;
        m_telemetry.state = StreamState::Idle;
    }

    if (g_activeStreamSource.load(std::memory_order_acquire) == this) {
        g_activeStreamSource.store(nullptr, std::memory_order_release);
    }

    m_isOpen.store(false, std::memory_order_release);
    m_isBuffering.store(false, std::memory_order_release);
    m_isEnded.store(false, std::memory_order_release);
}

void FFmpegStreamSource::pause() {
    m_isPaused.store(true, std::memory_order_release);
}

void FFmpegStreamSource::resume() {
    m_isPaused.store(false, std::memory_order_release);
    m_cv.notify_all();
}

bool FFmpegStreamSource::seek(int64_t timestampMs) {
    if (!m_isOpen.load(std::memory_order_acquire)) {
        return false;
    }
    bool isLive = false;
    {
        std::lock_guard<std::mutex> lock(m_stateMutex);
        isLive = m_telemetry.isLiveStream;
    }
    if (isLive) {
        return false;
    }
    m_seekTargetMs.store(timestampMs, std::memory_order_release);
    m_seekRequested.store(true, std::memory_order_release);
    m_cv.notify_all();
    return true;
}

size_t FFmpegStreamSource::read_pcm(float* pOut, size_t frameCount) {
    if (!m_isOpen.load(std::memory_order_acquire) || pOut == nullptr || frameCount == 0) {
        return 0;
    }

    size_t available = m_rbAvailableFrames.load(std::memory_order_acquire);
    if (m_isBuffering.load(std::memory_order_relaxed)) {
        // Exit buffering once we have enough frames or reached stream end
        const size_t requiredFrames = m_hasStartedPlayback.load(std::memory_order_relaxed) ? m_rebufferBytes : m_prebufferBytes;
        if (available >= requiredFrames || m_isEnded.load(std::memory_order_relaxed)) {
            m_isBuffering.store(false, std::memory_order_release);
            m_hasStartedPlayback.store(true, std::memory_order_relaxed);
            g_activeStreamSource.store(this, std::memory_order_release);
            {
                std::lock_guard<std::mutex> lock(m_stateMutex);
                if (m_telemetry.state != StreamState::Error && m_telemetry.errorCode == StreamErrorCode::None) {
                    m_telemetry.state = StreamState::Playing;
                }
            }
            notify_telemetry();
        } else {
            // Fill with silence while buffering and return 0 frames to prevent timeline drift
            std::fill(pOut, pOut + frameCount * m_targetChannels, 0.0f);
            return 0;
        }
    }

    if (available == 0) {
        if (m_isEnded.load(std::memory_order_relaxed)) {
            {
                std::lock_guard<std::mutex> lock(m_stateMutex);
                if (m_telemetry.state != StreamState::Error && m_telemetry.errorCode == StreamErrorCode::None) {
                    m_telemetry.state = StreamState::Ended;
                }
            }
            notify_telemetry();
            return 0;
        }
        // Jitter underrun: enter buffering mode
        m_isBuffering.store(true, std::memory_order_release);
        {
            std::lock_guard<std::mutex> lock(m_stateMutex);
            m_telemetry.state = StreamState::Buffering;
        }
        notify_telemetry();
        std::fill(pOut, pOut + frameCount * m_targetChannels, 0.0f);
        return 0;
    }

    size_t toRead;
    {
        // Serialize with worker-side writes and seek resets: without this, a
        // seek reset landing between our `available` snapshot and the
        // fetch_sub would underflow the counter (size_t wrap -> ring
        // permanently "full" of garbage) and tear old/new audio.
        std::lock_guard<std::mutex> rbLock(m_rbAccessMutex);
        const size_t availNow = m_rbAvailableFrames.load(std::memory_order_acquire);
        if (availNow == 0) {
            toRead = 0;
        } else {
            toRead = std::min(frameCount, availNow);
            const size_t readPos = m_rbReadPos.load(std::memory_order_relaxed);

            const size_t firstPart = std::min(toRead, m_rbCapacityFrames - readPos);
            std::memcpy(pOut, &m_pcmRingBuffer[readPos * m_targetChannels], firstPart * m_targetChannels * sizeof(float));

            if (toRead > firstPart) {
                const size_t secondPart = toRead - firstPart;
                std::memcpy(pOut + firstPart * m_targetChannels, &m_pcmRingBuffer[0], secondPart * m_targetChannels * sizeof(float));
            }

            m_rbReadPos.store((readPos + toRead) % m_rbCapacityFrames, std::memory_order_relaxed);
            m_rbAvailableFrames.fetch_sub(toRead, std::memory_order_release);
        }
    }

    if (toRead < frameCount) {
        std::fill(pOut + toRead * m_targetChannels, pOut + frameCount * m_targetChannels, 0.0f);
    }

    // Wake decoder thread if buffer has room
    m_cv.notify_one();
    return toRead;
}

void FFmpegStreamSource::update_icy_metadata() {
    if (!m_fmtCtx) return;

    AVDictionaryEntry* tag = nullptr;
    tag = av_dict_get(m_fmtCtx->metadata, "StreamTitle", nullptr, 0);
    if (!tag) {
        tag = av_dict_get(m_fmtCtx->metadata, "title", nullptr, 0);
    }

    if (tag && tag->value) {
        std::string rawTitle = tag->value;
        std::string artist, title;
        size_t dashPos = rawTitle.find(" - ");
        if (dashPos != std::string::npos) {
            artist = rawTitle.substr(0, dashPos);
            title = rawTitle.substr(dashPos + 3);
        } else {
            title = rawTitle;
        }

        bool changed = false;
        {
            std::lock_guard<std::mutex> lock(m_stateMutex);
            if (std::strcmp(m_telemetry.icyTitle, title.c_str()) != 0 ||
                std::strcmp(m_telemetry.icyArtist, artist.c_str()) != 0) {
                std::strncpy(m_telemetry.icyTitle, title.c_str(), sizeof(m_telemetry.icyTitle) - 1);
                m_telemetry.icyTitle[sizeof(m_telemetry.icyTitle) - 1] = '\0';
                std::strncpy(m_telemetry.icyArtist, artist.c_str(), sizeof(m_telemetry.icyArtist) - 1);
                m_telemetry.icyArtist[sizeof(m_telemetry.icyArtist) - 1] = '\0';
                changed = true;
            }
        }
        // notify_telemetry() takes m_stateMutex itself: calling it while
        // holding the lock deadlocks (recursive acquisition of a
        // non-recursive std::mutex). Notify after releasing.
        if (changed) {
            notify_telemetry();
        }
    }
}

void FFmpegStreamSource::demux_and_decode_thread_func() {
    sauti::dsp::ScopedDenormalsDisable denormalsScope;
    bool isNetwork = is_network_url(m_url.c_str());
    bool isHlsOrDash = isNetwork &&
                       (m_url.find(".m3u8") != std::string::npos ||
                        m_url.find(".mpd") != std::string::npos ||
                        m_url.find("/hls_variant/") != std::string::npos ||
                        m_url.find("/hls_playlist/") != std::string::npos);
    bool isYouTube = isNetwork &&
                     (m_url.find("googlevideo.com") != std::string::npos ||
                      m_url.find("youtube.com") != std::string::npos);
    AVDictionary* opts = nullptr;
    std::string ytUserAgent;
    std::string ytHeaders;

    if (isNetwork) {
        if (isYouTube) {
            if (m_url.find("c=VISIONOS") != std::string::npos || m_url.find("/c/VISIONOS/") != std::string::npos) {
                ytUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 15_7_3) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.0 Safari/605.1.15";
            } else if (m_url.find("c=ANDROID_VR") != std::string::npos || m_url.find("c=ANDROID") != std::string::npos || m_url.find("/c/ANDROID") != std::string::npos) {
                ytUserAgent = "com.google.android.youtube/1.56.21 (Linux; U; Android 12; Quest 3) gzip";
            } else if (m_url.find("c=IOS") != std::string::npos || m_url.find("/c/IOS/") != std::string::npos) {
                ytUserAgent = "com.google.ios.youtube/20.10.4 (iPhone16,2; U; CPU iOS 18_3_1 like Mac OS X; en_US)";
            } else if (m_url.find("c=TVHTML5") != std::string::npos) {
                ytUserAgent = "Mozilla/5.0 (ChromiumStylePlatform) Cobalt/Version,gzip(gfe)";
                ytHeaders = "Origin: https://www.youtube.com\r\n";
            } else if (isHlsOrDash) {
                ytUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/15.5 Safari/605.1.15,gzip(gfe)";
                ytHeaders = "Referer: https://www.youtube.com/\r\nOrigin: https://www.youtube.com\r\n";
            } else {
                ytUserAgent = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:130.0) Gecko/20100101 Firefox/130.0";
                ytHeaders = "Referer: https://music.youtube.com/\r\nOrigin: https://music.youtube.com\r\n";
            }
            av_dict_set(&opts, "user_agent", ytUserAgent.c_str(), 0);
            if (!ytHeaders.empty()) {
                av_dict_set(&opts, "headers", ytHeaders.c_str(), 0);
            }
        } else {
            av_dict_set(&opts, "user_agent", "Mozilla/5.0 (Windows NT 10.0; Win64; x64) MiniAudioDart/1.0 SautiFlow/1.0", 0);
            av_dict_set(&opts, "icy", "1", 0); // Enable Shoutcast/Icecast in-band metadata for non-YouTube radio streams
        }
        av_dict_set(&opts, "reconnect", "1", 0);
        av_dict_set(&opts, "reconnect_streamed", "1", 0);
        av_dict_set(&opts, "reconnect_delay_max", "5", 0);
        av_dict_set(&opts, "timeout", "10000000", 0);      // 10s socket timeout
        av_dict_set(&opts, "rw_timeout", "10000000", 0);   // 10s read/write timeout
        av_dict_set(&opts, "probesize", isHlsOrDash ? "262144" : "32768", 0);
        av_dict_set(&opts, "max_analyze_duration", isHlsOrDash ? "2000000" : "500000", 0);
        av_dict_set(&opts, "tls_verify", "0", 0);          // Disable TLS verify for Android where CA bundles are not in /etc/ssl
        if (isHlsOrDash) {
            av_dict_set(&opts, "allowed_extensions", "ALL", 0);
        }
    }

    m_fmtCtx = avformat_alloc_context();
    if (!m_fmtCtx) {
        if (opts) av_dict_free(&opts);
        set_error(StreamErrorCode::OpenFailed, "Failed to allocate AVFormatContext");
        m_isBuffering.store(false, std::memory_order_release);
        m_isEnded.store(true, std::memory_order_release);
        m_cv.notify_all();
        return;
    }

    if (isNetwork) {
        // Register interrupt callback to abort hanging socket/network calls immediately on close
        m_fmtCtx->interrupt_callback.callback = ffmpeg_interrupt_callback;
        m_fmtCtx->interrupt_callback.opaque = this;
    }

    const AVInputFormat* customInputFmt = nullptr;
    bool isYouTubeHls = isYouTube && isHlsOrDash && m_url.find(".mpd") == std::string::npos;

    if (isYouTubeHls) {
        auto* hlsReader = new YouTubeHlsHttpReader();
        hlsReader->playlistUrl = m_url;
        hlsReader->userAgent = ytUserAgent;
        hlsReader->baseHeaders = ytHeaders;
        hlsReader->owner = this;

        if (hlsReader->load_playlist()) {
            const int avioBufSize = 32768;
            auto* avioBuf = static_cast<uint8_t*>(av_malloc(avioBufSize));
            if (avioBuf) {
                m_customAvioCtx = avio_alloc_context(
                    avioBuf,
                    avioBufSize,
                    0,
                    hlsReader,
                    &YouTubeHlsHttpReader::read_packet,
                    nullptr,
                    nullptr
                );
                if (m_customAvioCtx) {
                    m_customAvioCtx->seekable = 0;
                    m_fmtCtx->pb = m_customAvioCtx;
                    m_fmtCtx->flags |= AVFMT_FLAG_CUSTOM_IO;
                    m_customHttpReader = hlsReader;
                    customInputFmt = av_find_input_format(
                        hlsReader->isFmp4 ? "mov,mp4,m4a,3gp,3g2,mj2" : "mpegts"
                    );
                } else {
                    av_free(avioBuf);
                    delete hlsReader;
                }
            } else {
                delete hlsReader;
            }
        } else {
            delete hlsReader;
        }
    } else if (isYouTube && !isHlsOrDash) {
        auto* reader = new YouTubeChunkedHttpReader();
        reader->url = m_url;
        reader->userAgent = ytUserAgent;
        reader->baseHeaders = ytHeaders;
        reader->owner = this;
        reader->totalSize = YouTubeChunkedHttpReader::parse_clen(m_url);

        const int avioBufSize = 32768;
        auto* avioBuf = static_cast<uint8_t*>(av_malloc(avioBufSize));
        if (avioBuf) {
            m_customAvioCtx = avio_alloc_context(
                avioBuf,
                avioBufSize,
                0,
                reader,
                &YouTubeChunkedHttpReader::read_packet,
                nullptr,
                reader->totalSize > 0 ? &YouTubeChunkedHttpReader::seek : nullptr
            );
            if (m_customAvioCtx) {
                m_customAvioCtx->seekable = (reader->totalSize > 0) ? AVIO_SEEKABLE_NORMAL : 0;
                m_fmtCtx->pb = m_customAvioCtx;
                m_fmtCtx->flags |= AVFMT_FLAG_CUSTOM_IO;
                m_customHttpReader = reader;
            } else {
                av_free(avioBuf);
                delete reader;
            }
        } else {
            delete reader;
        }
    }

    if (isNetwork) {
        SF_LOG("[ffmpeg] Step 1/5: Opening format context for online stream%s\n",
               m_customAvioCtx
                   ? (isYouTubeHls ? " (YouTube HLS resilient segment reader)" : " (YouTube 512KB chunked range reader)")
                   : "");
    } else {
        SF_LOG("[ffmpeg] Step 1/5: Opening format context for local file: %s\n", m_url.c_str());
    }

    int ret = avformat_open_input(&m_fmtCtx, m_customAvioCtx ? nullptr : m_url.c_str(), customInputFmt, opts ? &opts : nullptr);
    if (opts) av_dict_free(&opts);

    if (ret < 0) {
        if (isNetwork) {
            SF_LOGE("[ffmpeg] Step 1/5 FAILED: avformat_open_input returned error %s for online stream\n",
                    av_err2str_cpp(ret).c_str());
        } else {
            SF_LOGE("[ffmpeg] Step 1/5 FAILED: avformat_open_input returned error %s for %s\n",
                    av_err2str_cpp(ret).c_str(), m_url.c_str());
        }
        if (!m_stopRequested.load(std::memory_order_acquire)) {
            set_error(StreamErrorCode::OpenFailed, "Failed to open " + std::string(isNetwork ? "online stream: " : "audio file: ") + av_err2str_cpp(ret));
        }
        m_isBuffering.store(false, std::memory_order_release);
        m_isEnded.store(true, std::memory_order_release);
        m_cv.notify_all();
        return;
    }

    SF_LOG("[ffmpeg] Step 2/5: Probing stream information...\n");
    if (m_customAvioCtx) {
        // Custom readers feed a single known audio stream: keep probing minimal for instant start.
        m_fmtCtx->probesize = 32768;
        m_fmtCtx->max_analyze_duration = 500000;
    }

    if (avformat_find_stream_info(m_fmtCtx, nullptr) < 0) {
        if (isNetwork) {
            SF_LOGE("[ffmpeg] Step 2/5 FAILED: avformat_find_stream_info failed for online stream\n");
        } else {
            SF_LOGE("[ffmpeg] Step 2/5 FAILED: avformat_find_stream_info failed for %s\n", m_url.c_str());
        }
        if (!m_stopRequested.load(std::memory_order_acquire)) {
            set_error(StreamErrorCode::StreamInfoNotFound, "Could not find stream info");
        }
        m_isBuffering.store(false, std::memory_order_release);
        m_isEnded.store(true, std::memory_order_release);
        m_cv.notify_all();
        return;
    }

    const AVCodec* decoder = nullptr;
    m_audioStreamIndex = av_find_best_stream(m_fmtCtx, AVMEDIA_TYPE_AUDIO, -1, -1, &decoder, 0);
    if (m_audioStreamIndex < 0 || !decoder) {
        if (isNetwork) {
            SF_LOGE("[ffmpeg] Step 2/5 FAILED: No audio stream or decoder found in online stream\n");
        } else {
            SF_LOGE("[ffmpeg] Step 2/5 FAILED: No audio stream or decoder found in %s\n", m_url.c_str());
        }
        if (!m_stopRequested.load(std::memory_order_acquire)) {
            set_error(StreamErrorCode::CodecNotFound, "No audio stream or decoder found");
        }
        m_isBuffering.store(false, std::memory_order_release);
        m_isEnded.store(true, std::memory_order_release);
        m_cv.notify_all();
        return;
    }

    // Discard non-audio streams (e.g. video in HLS muxed streams) so the demuxer skips them
    for (unsigned int i = 0; i < m_fmtCtx->nb_streams; ++i) {
        if (static_cast<int>(i) != m_audioStreamIndex && m_fmtCtx->streams[i]) {
            m_fmtCtx->streams[i]->discard = AVDISCARD_ALL;
        }
    }

    AVStream* audioStream = m_fmtCtx->streams[m_audioStreamIndex];
    SF_LOG("[ffmpeg] Step 2/5 SUCCESS: Found audio stream (index=%d, codec=%s, rate=%d Hz, channels=%d)\n",
           m_audioStreamIndex, decoder->name, audioStream->codecpar->sample_rate, audioStream->codecpar->ch_layout.nb_channels);

    m_codecCtx = avcodec_alloc_context3(decoder);
    if (!m_codecCtx) {
        set_error(StreamErrorCode::CodecOpenFailed, "Failed to allocate codec context");
        m_isBuffering.store(false, std::memory_order_release);
        m_isEnded.store(true, std::memory_order_release);
        m_cv.notify_all();
        return;
    }

    if (avcodec_parameters_to_context(m_codecCtx, audioStream->codecpar) < 0) {
        set_error(StreamErrorCode::CodecOpenFailed, "Failed to copy codec parameters");
        m_isBuffering.store(false, std::memory_order_release);
        m_isEnded.store(true, std::memory_order_release);
        m_cv.notify_all();
        return;
    }

    m_codecCtx->pkt_timebase = audioStream->time_base;

    if (avcodec_open2(m_codecCtx, decoder, nullptr) < 0) {
        SF_LOGE("[ffmpeg] Step 3/5 FAILED: avcodec_open2 failed for codec %s\n", decoder->name);
        set_error(StreamErrorCode::CodecOpenFailed, "Failed to open audio codec");
        m_isBuffering.store(false, std::memory_order_release);
        m_isEnded.store(true, std::memory_order_release);
        m_cv.notify_all();
        return;
    }

    SF_LOG("[ffmpeg] Step 3/5 SUCCESS: Codec %s initialized\n", decoder->name);

    // Initial Resampler setup if sample format is already known
    if (m_codecCtx->sample_rate > 0 && m_codecCtx->sample_fmt != AV_SAMPLE_FMT_NONE) {
        AVChannelLayout outLayout;
        av_channel_layout_default(&outLayout, m_targetChannels == 1 ? 1 : 2);

        ret = swr_alloc_set_opts2(
            &m_swrCtx,
            &outLayout,
            AV_SAMPLE_FMT_FLT, // 32-bit float interleaved
            m_targetSampleRate,
            &m_codecCtx->ch_layout,
            m_codecCtx->sample_fmt,
            m_codecCtx->sample_rate,
            0,
            nullptr
        );

        av_channel_layout_uninit(&outLayout);

        if (ret >= 0 && m_swrCtx) {
            if (init_swr_context(m_swrCtx)) {
                m_swrInSampleRate = m_codecCtx->sample_rate;
                m_swrInSampleFmt = (int)m_codecCtx->sample_fmt;
                if (!m_swrInChLayout) m_swrInChLayout = new AVChannelLayout();
                av_channel_layout_copy(m_swrInChLayout, &m_codecCtx->ch_layout);
                m_swrInLayoutValid = true;

                SF_LOG("[ffmpeg] Step 4/5 SUCCESS: Initial SwrContext configured (%d Hz -> %d Hz, %d ch)\n",
                       m_codecCtx->sample_rate, m_targetSampleRate, m_targetChannels);
            } else {
                SF_LOGE("[ffmpeg] Step 4/5 FAILED: Failed to initialize SwrContext\n");
                swr_free(&m_swrCtx);
                m_swrCtx = nullptr;
            }
        }
    }

    // Populate initial telemetry
    {
        std::lock_guard<std::mutex> lock(m_stateMutex);
        m_telemetry.state = isNetwork ? StreamState::Buffering : StreamState::Playing;
        m_telemetry.bitrate = m_fmtCtx->bit_rate > 0 ? m_fmtCtx->bit_rate : audioStream->codecpar->bit_rate;
        m_telemetry.sampleRate = m_codecCtx->sample_rate > 0
            ? m_codecCtx->sample_rate
            : audioStream->codecpar->sample_rate;
        m_telemetry.channels = m_codecCtx->ch_layout.nb_channels > 0
            ? m_codecCtx->ch_layout.nb_channels
            : audioStream->codecpar->ch_layout.nb_channels;
        int bits = audioStream->codecpar->bits_per_raw_sample;
        if (bits <= 0) bits = m_codecCtx->bits_per_raw_sample;
        if (bits <= 0) {
            const int bps = av_get_bytes_per_sample(m_codecCtx->sample_fmt);
            if (bps > 0) bits = bps * 8;
        }
        if (bits <= 0) bits = audioStream->codecpar->bits_per_coded_sample;
        m_telemetry.bitDepth = bits;
        double customDurSec = 0.0;
        if (m_customHttpReader) {
            customDurSec = static_cast<CustomHttpReaderBase*>(m_customHttpReader)->get_duration_sec();
        }
        double fmtDurSec = (m_fmtCtx->duration > 0 && m_fmtCtx->duration != AV_NOPTS_VALUE)
            ? (double)m_fmtCtx->duration / AV_TIME_BASE
            : 0.0;
        double resolvedDurSec = fmtDurSec > 0.0 ? fmtDurSec : customDurSec;
        m_telemetry.isLiveStream = (resolvedDurSec <= 0.0);
        m_telemetry.totalDurationSec = m_telemetry.isLiveStream ? 0.0 : resolvedDurSec;
        m_telemetry.isSeekable = !m_telemetry.isLiveStream;
        std::strncpy(m_telemetry.codecName, decoder->name, sizeof(m_telemetry.codecName) - 1);
    }
    if (isNetwork) {
        update_icy_metadata();
    }
    notify_telemetry();

    SF_LOG("[ffmpeg] Step 5/5 SUCCESS: Playback pipeline active (duration=%.2fs, isLive=%d, isSeekable=%d)\n",
           m_telemetry.totalDurationSec, m_telemetry.isLiveStream ? 1 : 0, m_telemetry.isSeekable ? 1 : 0);

    AVPacket* packet = av_packet_alloc();
    AVFrame* frame = av_frame_alloc();
    std::vector<float> resampleOutBuf;

    auto write_to_ring = [&](const float* pData, size_t frameCount) -> bool {
        if (frameCount == 0 || pData == nullptr) return true;

        // Wait for ring space (worker side of the backpressure protocol).
        {
            std::unique_lock<std::mutex> cvLock(m_stateMutex);
            m_cv.wait(cvLock, [this, frameCount]() {
                return m_stopRequested.load(std::memory_order_acquire) ||
                       m_seekRequested.load(std::memory_order_acquire) ||
                       (m_rbCapacityFrames - m_rbAvailableFrames.load(std::memory_order_acquire)) >= frameCount;
            });

            if (m_stopRequested.load(std::memory_order_acquire) || m_seekRequested.load(std::memory_order_acquire)) {
                return false;
            }
        }

        // Write to the ring under the access lock (consistent with
        // read_pcm and seek resets).
        {
            std::lock_guard<std::mutex> rbLock(m_rbAccessMutex);
            const size_t writePos = m_rbWritePos.load(std::memory_order_relaxed);
            const size_t firstPart = std::min(frameCount, m_rbCapacityFrames - writePos);
            std::memcpy(&m_pcmRingBuffer[writePos * m_targetChannels], pData, firstPart * m_targetChannels * sizeof(float));

            if (frameCount > firstPart) {
                const size_t secondPart = frameCount - firstPart;
                std::memcpy(&m_pcmRingBuffer[0], pData + firstPart * m_targetChannels, secondPart * m_targetChannels * sizeof(float));
            }

            m_rbWritePos.store((writePos + frameCount) % m_rbCapacityFrames, std::memory_order_relaxed);
            m_rbAvailableFrames.fetch_add(frameCount, std::memory_order_release);
        }
        m_cv.notify_one();
        return true;
    };

    // Resample a decoded frame (or, with f == nullptr, flush the SwrContext
    // tail) and write it into the PCM ring. Returns false when aborted
    // (stop requested / new seek pending).
    auto push_frame = [&](AVFrame* f) -> bool {
        if (f != nullptr) {
            // Check if context needs initial creation or rebuild due to mid-stream format changes
            // (e.g. adaptive bitrate switches, dynamic reconnection, multi-format stream segments).
            bool needRebuild = (!m_swrCtx) ||
                               (f->sample_rate != m_swrInSampleRate) ||
                               (f->format != m_swrInSampleFmt) ||
                               (!m_swrInLayoutValid) ||
                               (m_swrInChLayout != nullptr && av_channel_layout_compare(&f->ch_layout, m_swrInChLayout) != 0);

            if (needRebuild) {
                if (m_swrCtx) {
                    SF_LOG("[ffmpeg] Mid-stream format change detected: %d Hz (fmt %d) -> %d Hz (fmt %d). Rebuilding resampler\n",
                           m_swrInSampleRate, m_swrInSampleFmt, f->sample_rate, f->format);
                    // Drain and flush residual audio from previous stream format before rebuilding resampler
                    int delaySamples = swr_get_out_samples(m_swrCtx, 0);
                    if (delaySamples > 0) {
                        resampleOutBuf.resize((size_t)delaySamples * (size_t)m_targetChannels);
                        uint8_t* outData[1] = { reinterpret_cast<uint8_t*>(resampleOutBuf.data()) };
                        int flushed = swr_convert(m_swrCtx, outData, delaySamples, nullptr, 0);
                        if (flushed > 0) {
                            if (!write_to_ring(resampleOutBuf.data(), static_cast<size_t>(flushed))) {
                                return false;
                            }
                        }
                    }
                    swr_free(&m_swrCtx);
                    m_swrCtx = nullptr;
                }

                if (m_swrInLayoutValid && m_swrInChLayout) {
                    av_channel_layout_uninit(m_swrInChLayout);
                    m_swrInLayoutValid = false;
                }

                AVChannelLayout outLayout;
                av_channel_layout_default(&outLayout, m_targetChannels == 1 ? 1 : 2);
                swr_alloc_set_opts2(
                    &m_swrCtx,
                    &outLayout,
                    AV_SAMPLE_FMT_FLT,
                    m_targetSampleRate,
                    &f->ch_layout,
                    (AVSampleFormat)f->format,
                    f->sample_rate,
                    0,
                    nullptr
                );
                av_channel_layout_uninit(&outLayout);

                if (m_swrCtx && init_swr_context(m_swrCtx)) {
                    m_swrInSampleRate = f->sample_rate;
                    m_swrInSampleFmt = f->format;
                    if (!m_swrInChLayout) m_swrInChLayout = new AVChannelLayout();
                    av_channel_layout_copy(m_swrInChLayout, &f->ch_layout);
                    m_swrInLayoutValid = true;
                } else {
                    SF_LOGE("[ffmpeg] Failed to allocate/initialize resampler for incoming frame format\n");
                    if (m_swrCtx) {
                        swr_free(&m_swrCtx);
                        m_swrCtx = nullptr;
                    }
                }
            }
            if (!m_swrCtx) return true; // skip this frame, keep decoding
        }

        if (!m_swrCtx) return true;

        const int outSamples = swr_get_out_samples(m_swrCtx, f ? f->nb_samples : 0);
        if (outSamples <= 0) return true;

        resampleOutBuf.resize((size_t)outSamples * (size_t)m_targetChannels);
        uint8_t* outData[32] = { nullptr };
        outData[0] = reinterpret_cast<uint8_t*>(resampleOutBuf.data());

        const int converted = swr_convert(
            m_swrCtx,
            outData,
            outSamples,
            f ? const_cast<const uint8_t**>(f->data) : nullptr,
            f ? f->nb_samples : 0
        );
        if (converted <= 0) return true;

        return write_to_ring(resampleOutBuf.data(), static_cast<size_t>(converted));
    };

    auto lastTelemetryUpdate = std::chrono::steady_clock::now();

    while (!m_stopRequested.load(std::memory_order_acquire)) {
        // Handle Seek Request
        if (m_seekRequested.load(std::memory_order_acquire)) {
            int64_t targetMs = m_seekTargetMs.load(std::memory_order_acquire);
            m_seekRequested.store(false, std::memory_order_release);

            if (m_fmtCtx != nullptr && m_audioStreamIndex >= 0) {
                AVStream* audioStream = m_fmtCtx->streams[m_audioStreamIndex];
                int seekRes = -1;
                if (m_customHttpReader && static_cast<CustomHttpReaderBase*>(m_customHttpReader)->seek_to_ms(targetMs)) {
                    if (m_customAvioCtx) {
                        avio_flush(m_customAvioCtx);
                        m_customAvioCtx->eof_reached = 0;
                        m_customAvioCtx->error = 0;
                    }
                    avformat_flush(m_fmtCtx);
                    seekRes = 0;
                } else {
                    int64_t targetTs = av_rescale_q(targetMs, AVRational{1, 1000}, audioStream->time_base);
                    seekRes = avformat_seek_file(m_fmtCtx, m_audioStreamIndex, INT64_MIN, targetTs, targetTs, 0);
                    if (seekRes < 0) {
                        // Fallback to av_seek_frame with AVSEEK_FLAG_BACKWARD
                        seekRes = av_seek_frame(m_fmtCtx, m_audioStreamIndex, targetTs, AVSEEK_FLAG_BACKWARD);
                    }
                }

                if (seekRes >= 0) {
                    avcodec_flush_buffers(m_codecCtx);
                    if (m_swrCtx) {
                        swr_init(m_swrCtx);
                    }
                    {
                        // Reset ring under the access lock so a concurrent
                        // read_pcm can never fetch_sub into the reset values
                        // (underflow) or serve half-old/half-new audio.
                        std::lock_guard<std::mutex> rbLock(m_rbAccessMutex);
                        m_rbReadPos.store(0, std::memory_order_release);
                        m_rbWritePos.store(0, std::memory_order_release);
                        m_rbAvailableFrames.store(0, std::memory_order_release);
                    }
                    m_isBuffering.store(true, std::memory_order_release);
                    m_isEnded.store(false, std::memory_order_release);

                    {
                        std::lock_guard<std::mutex> lock(m_stateMutex);
                        m_telemetry.state = StreamState::Buffering;
                    }
                    notify_telemetry();
                }
            }
        }

        // Wait if paused
        if (m_isPaused.load(std::memory_order_acquire)) {
            std::unique_lock<std::mutex> lock(m_stateMutex);
            m_cv.wait_for(lock, std::chrono::milliseconds(50), [this]() {
                return !m_isPaused.load(std::memory_order_acquire) || m_stopRequested.load(std::memory_order_acquire);
            });
            continue;
        }

        // Check if ring buffer is near full (prevent overflow)
        size_t available = m_rbAvailableFrames.load(std::memory_order_relaxed);
        if (available >= m_rbCapacityFrames - (size_t)(m_targetSampleRate * 2)) {
            // Buffer has plenty of headroom (> 8 seconds)
            std::unique_lock<std::mutex> lock(m_stateMutex);
            m_cv.wait_for(lock, std::chrono::milliseconds(20), [this]() {
                return m_stopRequested.load(std::memory_order_acquire) || 
                       m_seekRequested.load(std::memory_order_acquire) ||
                       m_rbAvailableFrames.load(std::memory_order_relaxed) < m_rbCapacityFrames / 2;
            });
            continue;
        }

        // Periodic telemetry & ICY metadata check
        auto now = std::chrono::steady_clock::now();
        if (std::chrono::duration_cast<std::chrono::milliseconds>(now - lastTelemetryUpdate).count() >= 250) {
            lastTelemetryUpdate = now;
            update_icy_metadata();

            double bufferedSec = (double)available / m_targetSampleRate;
            double pct = std::min(100.0, (bufferedSec / ((double)m_prebufferBytes / m_targetSampleRate)) * 100.0);
            {
                std::lock_guard<std::mutex> lock(m_stateMutex);
                m_telemetry.bufferedDurationSec = bufferedSec;
                m_telemetry.bufferPercent = pct;
            }
            notify_telemetry();
        }

        ret = av_read_frame(m_fmtCtx, packet);
        if (ret < 0) {
            if (ret == AVERROR_EOF || (m_fmtCtx->pb && avio_feof(m_fmtCtx->pb))) {
                // End of stream: drain the decoder (NULL packet) and flush the
                // resampler tail (NULL input to swr_convert). Previously both
                // were skipped, truncating ~one codec frame + filter delay of
                // audio at the end of every track.
                if (m_codecCtx) {
                    avcodec_send_packet(m_codecCtx, nullptr);
                    while (avcodec_receive_frame(m_codecCtx, frame) >= 0) {
                        if (!push_frame(frame)) {
                            break;
                        }
                    }
                }
                if (!m_stopRequested.load(std::memory_order_acquire) &&
                    !m_seekRequested.load(std::memory_order_acquire)) {
                    push_frame(nullptr); // swr tail flush
                }
                m_isEnded.store(true, std::memory_order_release);
                m_isBuffering.store(false, std::memory_order_release);
                break;
            }
            if (m_stopRequested.load(std::memory_order_acquire)) {
                break;
            }
            // Transient error: wait and retry
            std::this_thread::sleep_for(std::chrono::milliseconds(10));
            continue;
        }

        if (packet->stream_index == m_audioStreamIndex) {
            int sendRes = avcodec_send_packet(m_codecCtx, packet);
            if (sendRes == AVERROR(EAGAIN)) {
                // Decoder output not drained: receive pending frames first,
                // then retry the packet once instead of dropping it.
                while (avcodec_receive_frame(m_codecCtx, frame) >= 0) {
                    if (!push_frame(frame)) {
                        break;
                    }
                }
                sendRes = avcodec_send_packet(m_codecCtx, packet);
            }
            if (sendRes >= 0) {
                bool aborted = false;
                while (avcodec_receive_frame(m_codecCtx, frame) >= 0) {
                    if (!push_frame(frame)) {
                        aborted = true;
                        break;
                    }
                }
                (void)aborted;
            }
        }
        av_packet_unref(packet);
    }

    av_frame_free(&frame);
    av_packet_free(&packet);
}

// ============================================================================
// FFmpegLocalFileSource IMPLEMENTATION (Synchronous Audiophile Local Decoder)
// ============================================================================

FFmpegLocalFileSource::FFmpegLocalFileSource() {}

FFmpegLocalFileSource::~FFmpegLocalFileSource() {
    close();
}

void FFmpegLocalFileSource::close() {
    if (m_swrCtx) {
        swr_free(&m_swrCtx);
        m_swrCtx = nullptr;
    }
    if (m_swrInLayoutValid && m_swrInChLayout) {
        av_channel_layout_uninit(m_swrInChLayout);
        m_swrInLayoutValid = false;
    }
    if (m_swrInChLayout) {
        delete m_swrInChLayout;
        m_swrInChLayout = nullptr;
    }
    m_swrInSampleRate = 0;
    m_swrInSampleFmt = -1;

    if (m_frame) {
        av_frame_free(&m_frame);
        m_frame = nullptr;
    }
    if (m_packet) {
        av_packet_free(&m_packet);
        m_packet = nullptr;
    }
    if (m_codecCtx) {
        avcodec_free_context(&m_codecCtx);
        m_codecCtx = nullptr;
    }
    if (m_fmtCtx) {
        avformat_close_input(&m_fmtCtx);
        m_fmtCtx = nullptr;
    }
    m_residualBuffer.clear();
    m_residualOffset = 0;
    m_audioStreamIndex = -1;
    m_sampleRate = 0;
    m_channels = 0;
    m_totalFrames = 0;
    m_cursor = 0;
    m_isEnded = false;
}

bool FFmpegLocalFileSource::open(const std::string& filePath) {
    close();
    m_filePath = filePath;

    if (filePath.empty()) return false;

    AVDictionary* opts = nullptr;
    av_dict_set(&opts, "scan_all_pmts", "0", 0);

    if (avformat_open_input(&m_fmtCtx, filePath.c_str(), nullptr, &opts) < 0) {
        if (opts) av_dict_free(&opts);
        return false;
    }
    if (opts) av_dict_free(&opts);

    if (avformat_find_stream_info(m_fmtCtx, nullptr) < 0) {
        close();
        return false;
    }

    const AVCodec* decoder = nullptr;
    m_audioStreamIndex = av_find_best_stream(m_fmtCtx, AVMEDIA_TYPE_AUDIO, -1, -1, &decoder, 0);
    if (m_audioStreamIndex < 0 || !decoder) {
        close();
        return false;
    }

    AVStream* audioStream = m_fmtCtx->streams[m_audioStreamIndex];
    m_codecCtx = avcodec_alloc_context3(decoder);
    if (!m_codecCtx) {
        close();
        return false;
    }

    if (avcodec_parameters_to_context(m_codecCtx, audioStream->codecpar) < 0) {
        close();
        return false;
    }

    m_codecCtx->pkt_timebase = audioStream->time_base;

    if (avcodec_open2(m_codecCtx, decoder, nullptr) < 0) {
        close();
        return false;
    }

    m_sampleRate = m_codecCtx->sample_rate > 0 ? m_codecCtx->sample_rate : 44100;
    m_channels = m_codecCtx->ch_layout.nb_channels > 0 ? m_codecCtx->ch_layout.nb_channels : 2;

    if (audioStream->duration > 0 && audioStream->duration != AV_NOPTS_VALUE) {
        m_totalFrames = av_rescale_q(audioStream->duration, audioStream->time_base, AVRational{1, m_sampleRate});
    } else if (m_fmtCtx->duration > 0 && m_fmtCtx->duration != AV_NOPTS_VALUE) {
        m_totalFrames = static_cast<ma_uint64>(((double)m_fmtCtx->duration / AV_TIME_BASE) * m_sampleRate);
    } else {
        m_totalFrames = 0;
    }

    m_packet = av_packet_alloc();
    m_frame = av_frame_alloc();
    if (!m_packet || !m_frame) {
        close();
        return false;
    }

    if (m_codecCtx->ch_layout.nb_channels > 0 && m_codecCtx->ch_layout.order == AV_CHANNEL_ORDER_UNSPEC) {
        av_channel_layout_default(&m_codecCtx->ch_layout, m_codecCtx->ch_layout.nb_channels);
    }

    AVChannelLayout outLayout;
    av_channel_layout_default(&outLayout, m_channels);

    int ret = swr_alloc_set_opts2(
        &m_swrCtx,
        &outLayout,
        AV_SAMPLE_FMT_FLT, // Interleaved 32-bit float
        m_sampleRate,       // Native sample rate preserved
        &m_codecCtx->ch_layout,
        m_codecCtx->sample_fmt,
        m_codecCtx->sample_rate,
        0,
        nullptr
    );
    av_channel_layout_uninit(&outLayout);

    if (ret < 0 || !m_swrCtx || !init_swr_context(m_swrCtx)) {
        close();
        return false;
    }

    m_swrInSampleRate = m_codecCtx->sample_rate;
    m_swrInSampleFmt = (int)m_codecCtx->sample_fmt;
    if (!m_swrInChLayout) m_swrInChLayout = new AVChannelLayout();
    av_channel_layout_copy(m_swrInChLayout, &m_codecCtx->ch_layout);
    m_swrInLayoutValid = true;

    m_cursor = 0;
    m_isEnded = false;
    return true;
}

bool FFmpegLocalFileSource::read_and_decode_next_packet() {
    if (!m_fmtCtx || !m_codecCtx || !m_packet) return false;

    while (true) {
        av_packet_unref(m_packet);
        int ret = av_read_frame(m_fmtCtx, m_packet);
        if (ret < 0) {
            return false;
        }

        if (m_packet->stream_index == m_audioStreamIndex) {
            int sendRes = avcodec_send_packet(m_codecCtx, m_packet);
            av_packet_unref(m_packet);
            if (sendRes < 0 && sendRes != AVERROR(EAGAIN)) {
                return false;
            }
            return true;
        }
    }
}

size_t FFmpegLocalFileSource::read_pcm(float* pOut, size_t frameCount) {
    if (!m_fmtCtx || !m_codecCtx || !pOut || frameCount == 0 || m_channels <= 0) {
        return 0;
    }

    size_t framesRead = 0;

    // 1. Drain residual buffer if any
    size_t residualFrames = (m_residualBuffer.size() / m_channels) - m_residualOffset;
    if (residualFrames > 0) {
        size_t toCopy = std::min(frameCount, residualFrames);
        std::memcpy(pOut, m_residualBuffer.data() + (m_residualOffset * m_channels), toCopy * m_channels * sizeof(float));
        m_residualOffset += toCopy;
        framesRead += toCopy;
        if (m_residualOffset >= m_residualBuffer.size() / m_channels) {
            m_residualBuffer.clear();
            m_residualOffset = 0;
        }
    }

    // 2. Decode frames as needed until frameCount is satisfied
    while (framesRead < frameCount && !m_isEnded) {
        int recvRes = avcodec_receive_frame(m_codecCtx, m_frame);
        if (recvRes == 0) {
            int inSamples = m_frame->nb_samples;
            if (inSamples <= 0) continue;

            bool needRebuild = (!m_swrCtx) ||
                               (m_frame->sample_rate != m_swrInSampleRate) ||
                               (m_frame->format != m_swrInSampleFmt) ||
                               (!m_swrInLayoutValid) ||
                               (m_swrInChLayout != nullptr && av_channel_layout_compare(&m_frame->ch_layout, m_swrInChLayout) != 0);

            if (needRebuild) {
                if (m_swrCtx) {
                    // Flush residual audio from previous format
                    int delaySamples = swr_get_out_samples(m_swrCtx, 0);
                    if (delaySamples > 0) {
                        std::vector<float> tailBuf(delaySamples * m_channels);
                        uint8_t* outPtr = reinterpret_cast<uint8_t*>(tailBuf.data());
                        int flushed = swr_convert(m_swrCtx, &outPtr, delaySamples, nullptr, 0);
                        if (flushed > 0) {
                            m_residualBuffer.insert(m_residualBuffer.end(), tailBuf.data(), tailBuf.data() + flushed * m_channels);
                        }
                    }
                    swr_free(&m_swrCtx);
                    m_swrCtx = nullptr;
                }

                if (m_swrInLayoutValid && m_swrInChLayout) {
                    av_channel_layout_uninit(m_swrInChLayout);
                    m_swrInLayoutValid = false;
                }

                AVChannelLayout outLayout;
                av_channel_layout_default(&outLayout, m_channels);
                swr_alloc_set_opts2(
                    &m_swrCtx,
                    &outLayout,
                    AV_SAMPLE_FMT_FLT,
                    m_sampleRate,
                    &m_frame->ch_layout,
                    (AVSampleFormat)m_frame->format,
                    m_frame->sample_rate,
                    0,
                    nullptr
                );
                av_channel_layout_uninit(&outLayout);

                if (m_swrCtx && init_swr_context(m_swrCtx)) {
                    m_swrInSampleRate = m_frame->sample_rate;
                    m_swrInSampleFmt = m_frame->format;
                    if (!m_swrInChLayout) m_swrInChLayout = new AVChannelLayout();
                    av_channel_layout_copy(m_swrInChLayout, &m_frame->ch_layout);
                    m_swrInLayoutValid = true;
                }
            }

            if (!m_swrCtx) continue;

            int outMaxSamples = swr_get_out_samples(m_swrCtx, inSamples);
            if (outMaxSamples <= 0) outMaxSamples = inSamples;

            std::vector<float> converted(outMaxSamples * m_channels);
            uint8_t* outPtr = reinterpret_cast<uint8_t*>(converted.data());

            int outSamples = swr_convert(
                m_swrCtx,
                &outPtr,
                outMaxSamples,
                const_cast<const uint8_t**>(m_frame->extended_data),
                inSamples
            );

            if (outSamples > 0) {
                size_t needed = frameCount - framesRead;
                size_t directCopy = std::min(needed, static_cast<size_t>(outSamples));

                std::memcpy(pOut + (framesRead * m_channels), converted.data(), directCopy * m_channels * sizeof(float));
                framesRead += directCopy;

                size_t leftover = outSamples - directCopy;
                if (leftover > 0) {
                    m_residualBuffer.assign(
                        converted.data() + (directCopy * m_channels),
                        converted.data() + (outSamples * m_channels)
                    );
                    m_residualOffset = 0;
                }
            }
        } else if (recvRes == AVERROR(EAGAIN)) {
            if (!read_and_decode_next_packet()) {
                // End of input stream: flush decoder
                avcodec_send_packet(m_codecCtx, nullptr);
            }
        } else if (recvRes == AVERROR_EOF) {
            m_isEnded = true;
            break;
        } else {
            break;
        }
    }

    m_cursor += framesRead;
    return framesRead;
}

bool FFmpegLocalFileSource::seek(ma_uint64 frameIndex) {
    if (!m_fmtCtx || !m_codecCtx || m_audioStreamIndex < 0 || m_sampleRate <= 0) {
        return false;
    }

    if (m_totalFrames > 0 && frameIndex >= m_totalFrames) {
        m_residualBuffer.clear();
        m_residualOffset = 0;
        m_isEnded = true;
        m_cursor = m_totalFrames;
        return true;
    }

    AVStream* st = m_fmtCtx->streams[m_audioStreamIndex];
    int64_t basePts = (st->start_time != AV_NOPTS_VALUE) ? st->start_time : 0;

    int64_t prerollSamples = 0;
    if (st->codecpar->seek_preroll > 0) {
        prerollSamples = st->codecpar->seek_preroll;
    } else if (m_codecCtx->seek_preroll > 0) {
        prerollSamples = m_codecCtx->seek_preroll;
    } else if (m_codecCtx->frame_size > 0) {
        // Transform codecs (AAC, MP3, etc.) require at least 1-2 frames of filterbank warmup
        prerollSamples = static_cast<int64_t>(m_codecCtx->frame_size) * 2;
    }

    int64_t seekFrame = (static_cast<int64_t>(frameIndex) > prerollSamples) ? (static_cast<int64_t>(frameIndex) - prerollSamples) : 0;
    int64_t seekPts = basePts + av_rescale_q(seekFrame, AVRational{1, m_sampleRate}, st->time_base);

    // Seek backward to preceding keyframe packet
    int seekRes = av_seek_frame(m_fmtCtx, m_audioStreamIndex, seekPts, AVSEEK_FLAG_BACKWARD);
    if (seekRes < 0) {
        seekRes = avformat_seek_file(m_fmtCtx, m_audioStreamIndex, INT64_MIN, seekPts, seekPts, 0);
        if (seekRes < 0) {
            return false;
        }
    }

    avcodec_flush_buffers(m_codecCtx);
    if (m_swrCtx) {
        swr_init(m_swrCtx);
    }
    m_residualBuffer.clear();
    m_residualOffset = 0;
    m_isEnded = false;

    // Decode and discard priming / preroll frames up to frameIndex
    int64_t currentTrackSample = -1;
    bool reachedTarget = false;

    while (!reachedTarget && !m_isEnded) {
        int recvRes = avcodec_receive_frame(m_codecCtx, m_frame);
        if (recvRes == 0) {
            int inSamples = m_frame->nb_samples;
            if (inSamples <= 0) continue;

            // Determine presentation timestamp of decoded frame
            int64_t framePts = m_frame->best_effort_timestamp;
            if (framePts == AV_NOPTS_VALUE) {
                framePts = m_frame->pts;
            }

            int64_t frameStartSample = 0;
            if (framePts != AV_NOPTS_VALUE) {
                frameStartSample = av_rescale_q(framePts - basePts, st->time_base, AVRational{1, m_sampleRate});
                currentTrackSample = frameStartSample;
            } else if (currentTrackSample >= 0) {
                frameStartSample = currentTrackSample;
            } else {
                frameStartSample = seekFrame;
            }

            int64_t frameEndSample = frameStartSample + inSamples;
            currentTrackSample = frameEndSample;

            if (frameEndSample <= static_cast<int64_t>(frameIndex)) {
                // Entire frame lies before target: discard preroll frame
                continue;
            }

            bool needRebuild = (!m_swrCtx) ||
                               (m_frame->sample_rate != m_swrInSampleRate) ||
                               (m_frame->format != m_swrInSampleFmt) ||
                               (!m_swrInLayoutValid) ||
                               (m_swrInChLayout != nullptr && av_channel_layout_compare(&m_frame->ch_layout, m_swrInChLayout) != 0);

            if (needRebuild) {
                if (m_swrCtx) {
                    swr_free(&m_swrCtx);
                    m_swrCtx = nullptr;
                }
                if (m_swrInLayoutValid && m_swrInChLayout) {
                    av_channel_layout_uninit(m_swrInChLayout);
                    m_swrInLayoutValid = false;
                }
                AVChannelLayout outLayout;
                av_channel_layout_default(&outLayout, m_channels);
                swr_alloc_set_opts2(
                    &m_swrCtx,
                    &outLayout,
                    AV_SAMPLE_FMT_FLT,
                    m_sampleRate,
                    &m_frame->ch_layout,
                    (AVSampleFormat)m_frame->format,
                    m_frame->sample_rate,
                    0,
                    nullptr
                );
                av_channel_layout_uninit(&outLayout);

                if (m_swrCtx && init_swr_context(m_swrCtx)) {
                    m_swrInSampleRate = m_frame->sample_rate;
                    m_swrInSampleFmt = m_frame->format;
                    if (!m_swrInChLayout) m_swrInChLayout = new AVChannelLayout();
                    av_channel_layout_copy(m_swrInChLayout, &m_frame->ch_layout);
                    m_swrInLayoutValid = true;
                }
            }

            if (!m_swrCtx) continue;

            // Frame reaches or overlaps target: convert to float PCM
            int outMaxSamples = swr_get_out_samples(m_swrCtx, inSamples);
            if (outMaxSamples <= 0) outMaxSamples = inSamples;

            std::vector<float> converted(outMaxSamples * m_channels);
            uint8_t* outPtr = reinterpret_cast<uint8_t*>(converted.data());

            int outSamples = swr_convert(
                m_swrCtx,
                &outPtr,
                outMaxSamples,
                const_cast<const uint8_t**>(m_frame->extended_data),
                inSamples
            );

            if (outSamples > 0) {
                if (frameStartSample < static_cast<int64_t>(frameIndex)) {
                    int64_t discardFrames = static_cast<int64_t>(frameIndex) - frameStartSample;
                    if (discardFrames > outSamples) {
                        discardFrames = outSamples;
                    }
                    size_t keepFrames = static_cast<size_t>(outSamples - discardFrames);
                    if (keepFrames > 0) {
                        m_residualBuffer.assign(
                            converted.data() + (discardFrames * m_channels),
                            converted.data() + (outSamples * m_channels)
                        );
                        m_residualOffset = 0;
                    }
                } else {
                    size_t padFrames = 0;
                    if (frameStartSample > static_cast<int64_t>(frameIndex)) {
                        int64_t diff = frameStartSample - static_cast<int64_t>(frameIndex);
                        if (diff < static_cast<int64_t>(m_sampleRate * 2)) {
                            padFrames = static_cast<size_t>(diff);
                        }
                    }
                    m_residualBuffer.assign(padFrames * m_channels, 0.0f);
                    m_residualBuffer.insert(
                        m_residualBuffer.end(),
                        converted.data(),
                        converted.data() + (outSamples * m_channels)
                    );
                    m_residualOffset = 0;
                }
            }

            reachedTarget = true;
            break;
        } else if (recvRes == AVERROR(EAGAIN)) {
            if (!read_and_decode_next_packet()) {
                // End of input stream: flush decoder
                avcodec_send_packet(m_codecCtx, nullptr);
            }
        } else if (recvRes == AVERROR_EOF) {
            m_isEnded = true;
            break;
        } else {
            // Unrecoverable decoding error
            break;
        }
    }

    m_cursor = frameIndex;
    return true;
}

} // namespace sautiflow

// ============================================================================
// MINIAUDIO DATA SOURCE & DECODING BACKEND ADAPTER
// ============================================================================

struct ma_ffmpeg_data_source {
    ma_data_source_base base;
    bool isNetwork;
    sautiflow::FFmpegStreamSource* stream;
    sautiflow::FFmpegLocalFileSource* local;
    ma_format format;
    ma_uint32 channels;
    ma_uint32 sampleRate;
    ma_uint64 cursor;
};

static ma_result ma_ffmpeg_ds_read(ma_data_source* pDataSource, void* pFramesOut, ma_uint64 frameCount, ma_uint64* pFramesRead) {
    auto* ds = reinterpret_cast<ma_ffmpeg_data_source*>(pDataSource);
    if (!ds) return MA_INVALID_ARGS;

    if (ds->isNetwork) {
        if (!ds->stream) return MA_INVALID_ARGS;
        size_t read = ds->stream->read_pcm(reinterpret_cast<float*>(pFramesOut), static_cast<size_t>(frameCount));
        if (pFramesRead) *pFramesRead = read;
        ds->cursor += read;
        if (read == 0) {
            if (ds->stream->is_buffering()) {
                std::memset(pFramesOut, 0, frameCount * ds->channels * sizeof(float));
                return MA_BUSY;
            }
            if (ds->stream->is_ended()) {
                return MA_AT_END;
            }
        }
        return MA_SUCCESS;
    } else {
        if (!ds->local) return MA_INVALID_ARGS;
        size_t read = ds->local->read_pcm(reinterpret_cast<float*>(pFramesOut), static_cast<size_t>(frameCount));
        if (pFramesRead) *pFramesRead = read;
        ds->cursor = ds->local->get_cursor();
        if (read == 0) {
            if (ds->local->is_ended()) {
                return MA_AT_END;
            }
        }
        return MA_SUCCESS;
    }
}

static ma_result ma_ffmpeg_ds_seek(ma_data_source* pDataSource, ma_uint64 frameIndex) {
    auto* ds = reinterpret_cast<ma_ffmpeg_data_source*>(pDataSource);
    if (!ds) return MA_INVALID_ARGS;

    if (ds->isNetwork) {
        if (!ds->stream) return MA_INVALID_ARGS;
        if (ds->sampleRate > 0) {
            int64_t ms = (frameIndex * 1000) / ds->sampleRate;
            ds->stream->seek(ms);
            ds->cursor = frameIndex;
        }
        return MA_SUCCESS;
    } else {
        if (!ds->local) return MA_INVALID_ARGS;
        if (ds->local->seek(frameIndex)) {
            ds->cursor = frameIndex;
            return MA_SUCCESS;
        }
        return MA_ERROR;
    }
}

static ma_result ma_ffmpeg_ds_get_data_format(ma_data_source* pDataSource, ma_format* pFormat, ma_uint32* pChannels, ma_uint32* pSampleRate, ma_channel* pChannelMap, size_t channelMapCap) {
    auto* ds = reinterpret_cast<ma_ffmpeg_data_source*>(pDataSource);
    if (!ds) return MA_INVALID_ARGS;

    if (pFormat) *pFormat = ds->format;
    if (pChannels) *pChannels = ds->channels;
    if (pSampleRate) *pSampleRate = ds->sampleRate;
    if (pChannelMap) ma_channel_map_init_standard(ma_standard_channel_map_default, pChannelMap, channelMapCap, ds->channels);
    return MA_SUCCESS;
}

static ma_result ma_ffmpeg_ds_get_cursor(ma_data_source* pDataSource, ma_uint64* pCursor) {
    auto* ds = reinterpret_cast<ma_ffmpeg_data_source*>(pDataSource);
    if (!ds) return MA_INVALID_ARGS;
    if (pCursor) *pCursor = ds->cursor;
    return MA_SUCCESS;
}

static ma_result ma_ffmpeg_ds_get_length(ma_data_source* pDataSource, ma_uint64* pLength) {
    auto* ds = reinterpret_cast<ma_ffmpeg_data_source*>(pDataSource);
    if (!ds) return MA_INVALID_ARGS;

    if (ds->isNetwork) {
        if (!ds->stream) return MA_INVALID_ARGS;
        auto tel = ds->stream->get_telemetry();
        if (pLength) {
            if (tel.isLiveStream || tel.totalDurationSec <= 0) {
                *pLength = 0;
            } else {
                *pLength = static_cast<ma_uint64>(tel.totalDurationSec * ds->sampleRate);
            }
        }
        return MA_SUCCESS;
    } else {
        if (!ds->local) return MA_INVALID_ARGS;
        if (pLength) {
            *pLength = ds->local->get_total_frames();
        }
        return MA_SUCCESS;
    }
}

static ma_data_source_vtable g_ma_ffmpeg_ds_vtable = {
    ma_ffmpeg_ds_read,
    ma_ffmpeg_ds_seek,
    ma_ffmpeg_ds_get_data_format,
    ma_ffmpeg_ds_get_cursor,
    ma_ffmpeg_ds_get_length,
    nullptr, // set_looping
    0
};

namespace sautiflow {

StreamTelemetry get_stream_telemetry_from_decoder(ma_decoder* pDecoder) {
    if (pDecoder == nullptr || pDecoder->pBackend == nullptr) {
        return get_active_stream_telemetry();
    }
    auto* ds = reinterpret_cast<ma_ffmpeg_data_source*>(pDecoder->pBackend);
    if (ds && ds->base.vtable == &g_ma_ffmpeg_ds_vtable) {
        if (ds->isNetwork && ds->stream) {
            return ds->stream->get_telemetry();
        } else if (!ds->isNetwork && ds->local) {
            StreamTelemetry tel;
            tel.state = ds->local->is_ended() ? StreamState::Ended : StreamState::Playing;
            tel.sampleRate = ds->local->get_sample_rate();
            tel.channels = ds->local->get_channels();
            tel.totalDurationSec = ds->local->get_sample_rate() > 0 ? (double)ds->local->get_total_frames() / ds->local->get_sample_rate() : 0.0;
            tel.isLiveStream = false;
            tel.isSeekable = true;
            return tel;
        }
    }
    return get_active_stream_telemetry();
}

bool read_file_metadata_ffmpeg(
    const char *filePath,
    bool getPicture,
    std::string &outArtist,
    std::string &outTitle,
    std::string &outAlbum,
    std::string &outGenre,
    std::string &outYear,
    int &outTrackNumber,
    double &outDurationSecs,
    int &outSampleRate,
    int &outChannels,
    int &outBitrateKbps,
    std::string &outCodec,
    float &outTrackGain,
    float &outAlbumGain,
    float &outTrackPeak,
    float &outAlbumPeak,
    std::vector<uint8_t> *outPicture
) {
    outArtist.clear();
    outTitle.clear();
    outAlbum.clear();
    outGenre.clear();
    outYear.clear();
    outCodec.clear();
    outTrackNumber = 0;
    outDurationSecs = 0.0;
    outSampleRate = 44100;
    outChannels = 2;
    outBitrateKbps = 0;
    outTrackGain = 0.0f;
    outAlbumGain = 0.0f;
    outTrackPeak = 1.0f;
    outAlbumPeak = 1.0f;
    if (outPicture) outPicture->clear();

    if (!filePath || filePath[0] == '\0') {
        return false;
    }

    // STRICT ISOLATION: Never attempt to open or probe network URLs with this file inspector!
    if (FFmpegStreamSource::is_network_url(filePath)) {
        return false;
    }

    AVFormatContext *fmt_ctx = nullptr;
    AVDictionary *opts = nullptr;
    av_dict_set(&opts, "scan_all_pmts", "0", 0);

    if (avformat_open_input(&fmt_ctx, filePath, nullptr, &opts) < 0) {
        if (opts) av_dict_free(&opts);
        return false;
    }
    if (opts) av_dict_free(&opts);

    (void)avformat_find_stream_info(fmt_ctx, nullptr);

    if (fmt_ctx->duration > 0 && fmt_ctx->duration != AV_NOPTS_VALUE) {
        outDurationSecs = (double)fmt_ctx->duration / (double)AV_TIME_BASE;
    }

    auto get_tag = [&](const char *key) -> const char* {
        AVDictionaryEntry *e = av_dict_get(fmt_ctx->metadata, key, nullptr, AV_DICT_IGNORE_SUFFIX);
        if (e && e->value) return e->value;
        for (unsigned int i = 0; i < fmt_ctx->nb_streams; ++i) {
            e = av_dict_get(fmt_ctx->streams[i]->metadata, key, nullptr, AV_DICT_IGNORE_SUFFIX);
            if (e && e->value) return e->value;
        }
        return nullptr;
    };

    const char *artist = get_tag("artist");
    if (!artist) artist = get_tag("album_artist");
    if (!artist) artist = get_tag("author");
    if (!artist) artist = get_tag("performer");
    if (artist) outArtist = artist;

    const char *title = get_tag("title");
    if (!title) title = get_tag("song");
    if (title) outTitle = title;

    const char *album = get_tag("album");
    if (album) outAlbum = album;

    const char *genre = get_tag("genre");
    if (genre) outGenre = genre;

    const char *date = get_tag("date");
    if (!date) date = get_tag("year");
    if (!date) date = get_tag("TYER");
    if (!date) date = get_tag("TDRC");
    if (date) outYear = date;

    const char *track = get_tag("track");
    if (!track) track = get_tag("TRCK");
    if (track) {
        int t = std::atoi(track);
        if (t > 0) outTrackNumber = t;
    }

    auto parse_gain_db = [](const char *str) -> float {
        if (!str) return 0.0f;
        char *end = nullptr;
        float val = std::strtof(str, &end);
        return val;
    };

    const char *rgTrack = get_tag("REPLAYGAIN_TRACK_GAIN");
    if (!rgTrack) rgTrack = get_tag("replaygain_track_gain");
    if (!rgTrack) rgTrack = get_tag("R128_TRACK_GAIN");
    if (!rgTrack) rgTrack = get_tag("r128_track_gain");
    if (rgTrack) outTrackGain = parse_gain_db(rgTrack);

    const char *rgAlbum = get_tag("REPLAYGAIN_ALBUM_GAIN");
    if (!rgAlbum) rgAlbum = get_tag("replaygain_album_gain");
    if (!rgAlbum) rgAlbum = get_tag("R128_ALBUM_GAIN");
    if (!rgAlbum) rgAlbum = get_tag("r128_album_gain");
    if (rgAlbum) outAlbumGain = parse_gain_db(rgAlbum);

    const char *rgPeak = get_tag("REPLAYGAIN_TRACK_PEAK");
    if (!rgPeak) rgPeak = get_tag("replaygain_track_peak");
    if (!rgPeak) rgPeak = get_tag("R128_TRACK_PEAK");
    if (!rgPeak) rgPeak = get_tag("r128_track_peak");
    if (rgPeak) outTrackPeak = parse_gain_db(rgPeak);

    const char *rgAlbumPeak = get_tag("REPLAYGAIN_ALBUM_PEAK");
    if (!rgAlbumPeak) rgAlbumPeak = get_tag("replaygain_album_peak");
    if (!rgAlbumPeak) rgAlbumPeak = get_tag("R128_ALBUM_PEAK");
    if (!rgAlbumPeak) rgAlbumPeak = get_tag("r128_album_peak");
    if (rgAlbumPeak) outAlbumPeak = parse_gain_db(rgAlbumPeak);

    for (unsigned int i = 0; i < fmt_ctx->nb_streams; ++i) {
        AVStream *st = fmt_ctx->streams[i];
        if (!st || !st->codecpar) continue;

        if (st->codecpar->codec_type == AVMEDIA_TYPE_AUDIO) {
            if (st->codecpar->sample_rate > 0) {
                outSampleRate = st->codecpar->sample_rate;
            }
            int ch = st->codecpar->ch_layout.nb_channels;
            if (ch > 0) {
                outChannels = ch;
            }
            if (st->codecpar->bit_rate > 0) {
                outBitrateKbps = (int)(st->codecpar->bit_rate / 1000);
            }
            const char *cname = avcodec_get_name(st->codecpar->codec_id);
            if (cname && outCodec.empty()) {
                outCodec = cname;
            }
            if (outDurationSecs <= 0.0 && st->duration > 0 && st->duration != AV_NOPTS_VALUE) {
                outDurationSecs = st->duration * av_q2d(st->time_base);
            }

            const AVPacketSideData *sd = av_packet_side_data_get(
                st->codecpar->coded_side_data,
                st->codecpar->nb_coded_side_data,
                AV_PKT_DATA_REPLAYGAIN
            );
            if (sd && sd->data && sd->size >= sizeof(AVReplayGain)) {
                const AVReplayGain *rg = reinterpret_cast<const AVReplayGain*>(sd->data);
                if (rg->track_gain != INT32_MIN && outTrackGain == 0.0f) {
                    outTrackGain = (float)rg->track_gain / 100000.0f;
                }
                if (rg->album_gain != INT32_MIN && outAlbumGain == 0.0f) {
                    outAlbumGain = (float)rg->album_gain / 100000.0f;
                }
                if (rg->track_peak > 0 && outTrackPeak == 1.0f) {
                    outTrackPeak = (float)rg->track_peak / 100000.0f;
                }
                if (rg->album_peak > 0 && outAlbumPeak == 1.0f) {
                    outAlbumPeak = (float)rg->album_peak / 100000.0f;
                }
            }
        }

        if (getPicture && outPicture && outPicture->empty()) {
            if ((st->disposition & AV_DISPOSITION_ATTACHED_PIC) &&
                st->attached_pic.size > 0 && st->attached_pic.data) {
                outPicture->assign(st->attached_pic.data, st->attached_pic.data + st->attached_pic.size);
            }
        }
    }

    if (outBitrateKbps <= 0 && fmt_ctx->bit_rate > 0) {
        outBitrateKbps = (int)(fmt_ctx->bit_rate / 1000);
    }

    avformat_close_input(&fmt_ctx);
    return true;
}

bool read_file_tags_ffmpeg(
    const char *filePath,
    std::string &outArtist,
    std::string &outTitle,
    std::string &outAlbum,
    float &outTrackGain,
    float &outAlbumGain,
    float &outTrackPeak,
    float &outAlbumPeak
) {
    std::string dummyGenre, dummyYear, dummyCodec;
    int dummyTrack = 0, dummySr = 0, dummyCh = 0, dummyBr = 0;
    double dummyDur = 0.0;
    return read_file_metadata_ffmpeg(
        filePath,
        false,
        outArtist,
        outTitle,
        outAlbum,
        dummyGenre,
        dummyYear,
        dummyTrack,
        dummyDur,
        dummySr,
        dummyCh,
        dummyBr,
        dummyCodec,
        outTrackGain,
        outAlbumGain,
        outTrackPeak,
        outAlbumPeak,
        nullptr
    );
}

} // namespace sautiflow

#if defined(_WIN32) || defined(_WIN64)
#ifndef WIN32_LEAN_AND_MEAN
#define WIN32_LEAN_AND_MEAN
#endif
#include <windows.h>

static std::string wstring_to_utf8_path(const wchar_t* wstr) {
    if (!wstr || wstr[0] == L'\0') return {};
    int len = WideCharToMultiByte(CP_UTF8, 0, wstr, -1, nullptr, 0, nullptr, nullptr);
    if (len <= 0) return {};
    std::string utf8(len, '\0');
    WideCharToMultiByte(CP_UTF8, 0, wstr, -1, &utf8[0], len, nullptr, nullptr);
    if (!utf8.empty() && utf8.back() == '\0') {
        utf8.pop_back();
    }
    return utf8;
}
#endif

static bool is_miniaudio_native_local_file(const char* path) {
    if (path == nullptr) return false;
    std::string s(path);
    auto dot = s.find_last_of('.');
    if (dot == std::string::npos) return false;
    std::string ext = s.substr(dot);
    for (auto &c : ext) c = (char)::tolower(c);
    return (ext == ".flac" || ext == ".mp3" || ext == ".wav" ||
            ext == ".ogg"  || ext == ".oga");
}

static ma_result ma_decoding_backend_init_file__ffmpeg(void* pUserData, const char* pFilePath, const ma_decoding_backend_config* pConfig, const ma_allocation_callbacks* pAllocationCallbacks, ma_data_source** ppBackend) {
    (void)pUserData;
    (void)pConfig;
    (void)pAllocationCallbacks;

    if (pFilePath == nullptr || ppBackend == nullptr) {
        return MA_INVALID_ARGS;
    }

    bool isNetwork = sautiflow::FFmpegStreamSource::is_network_url(pFilePath);
    const auto* initCfg = static_cast<const sautiflow::FFmpegDecoderInitConfig*>(pUserData);
    bool forceFallback = (initCfg != nullptr) && initCfg->forceFallback;

    if (!isNetwork && !forceFallback && is_miniaudio_native_local_file(pFilePath)) {
        // Return MA_NO_BACKEND so miniaudio uses its built-in dr_flac, dr_mp3, dr_wav, stb_vorbis decoders directly.
        return MA_NO_BACKEND;
    }

    if (isNetwork) {
        ma_uint32 outChannels = 2;
        ma_uint32 outSampleRate = 48000;
        if (pUserData != nullptr) {
            const auto* initCfg = static_cast<const sautiflow::FFmpegDecoderInitConfig*>(pUserData);
            if (initCfg->targetChannels > 0) outChannels = (ma_uint32)initCfg->targetChannels;
            if (initCfg->targetSampleRate > 0) outSampleRate = (ma_uint32)initCfg->targetSampleRate;
        }
        int prebufferMs = 500;

        std::printf("[ffmpeg_backend] Requesting online stream decoder\n");
        std::fflush(stdout);

        auto* stream = new sautiflow::FFmpegStreamSource();
        if (!stream->open(pFilePath, outSampleRate, outChannels, prebufferMs)) {
            std::printf("[ffmpeg_backend] Online stream decoder failed to open\n");
            std::fflush(stdout);
            delete stream;
            return MA_ERROR;
        }

        auto* ds = static_cast<ma_ffmpeg_data_source*>(std::malloc(sizeof(ma_ffmpeg_data_source)));
        if (!ds) {
            stream->close();
            delete stream;
            return MA_OUT_OF_MEMORY;
        }

        ds->isNetwork = true;
        ds->stream = stream;
        ds->local = nullptr;
        ds->format = ma_format_f32;
        ds->channels = outChannels;
        ds->sampleRate = outSampleRate;
        ds->cursor = 0;

        ma_data_source_config baseConfig = ma_data_source_config_init();
        baseConfig.vtable = &g_ma_ffmpeg_ds_vtable;
        ma_result res = ma_data_source_init(&baseConfig, &ds->base);
        if (res != MA_SUCCESS) {
            stream->close();
            delete stream;
            std::free(ds);
            return res;
        }

        *ppBackend = reinterpret_cast<ma_data_source*>(ds);
        return MA_SUCCESS;
    } else {
        std::printf("[ffmpeg_backend] Requesting native local file decoder for: %s\n", pFilePath);
        std::fflush(stdout);

        auto* local = new sautiflow::FFmpegLocalFileSource();
        if (!local->open(pFilePath)) {
            std::printf("[ffmpeg_backend] Local file decoder failed to open: %s\n", pFilePath);
            std::fflush(stdout);
            delete local;
            return MA_ERROR;
        }

        auto* ds = static_cast<ma_ffmpeg_data_source*>(std::malloc(sizeof(ma_ffmpeg_data_source)));
        if (!ds) {
            local->close();
            delete local;
            return MA_OUT_OF_MEMORY;
        }

        ds->isNetwork = false;
        ds->stream = nullptr;
        ds->local = local;
        ds->format = ma_format_f32;
        ds->channels = static_cast<ma_uint32>(local->get_channels());
        ds->sampleRate = static_cast<ma_uint32>(local->get_sample_rate());
        ds->cursor = 0;

        ma_data_source_config baseConfig = ma_data_source_config_init();
        baseConfig.vtable = &g_ma_ffmpeg_ds_vtable;
        ma_result res = ma_data_source_init(&baseConfig, &ds->base);
        if (res != MA_SUCCESS) {
            local->close();
            delete local;
            std::free(ds);
            return res;
        }

        *ppBackend = reinterpret_cast<ma_data_source*>(ds);
        return MA_SUCCESS;
    }
}

static ma_result ma_decoding_backend_init_file_w__ffmpeg(void* pUserData, const wchar_t* pFilePathW, const ma_decoding_backend_config* pConfig, const ma_allocation_callbacks* pAllocationCallbacks, ma_data_source** ppBackend) {
#if defined(_WIN32) || defined(_WIN64)
    if (pFilePathW == nullptr || ppBackend == nullptr) {
        return MA_INVALID_ARGS;
    }
    std::string pathUtf8 = wstring_to_utf8_path(pFilePathW);
    if (pathUtf8.empty()) {
        return MA_INVALID_ARGS;
    }
    return ma_decoding_backend_init_file__ffmpeg(pUserData, pathUtf8.c_str(), pConfig, pAllocationCallbacks, ppBackend);
#else
    (void)pUserData;
    (void)pFilePathW;
    (void)pConfig;
    (void)pAllocationCallbacks;
    (void)ppBackend;
    return MA_NOT_IMPLEMENTED;
#endif
}

static void ma_decoding_backend_uninit__ffmpeg(void* pUserData, ma_data_source* pBackend, const ma_allocation_callbacks* pAllocationCallbacks) {
    (void)pUserData;
    (void)pAllocationCallbacks;

    auto* ds = reinterpret_cast<ma_ffmpeg_data_source*>(pBackend);
    if (!ds) return;

    ma_data_source_uninit(&ds->base);
    if (ds->stream) {
        ds->stream->close();
        delete ds->stream;
        ds->stream = nullptr;
    }
    if (ds->local) {
        ds->local->close();
        delete ds->local;
        ds->local = nullptr;
    }
    std::free(ds);
}

extern "C" {
ma_decoding_backend_vtable g_ma_decoding_backend_vtable_ffmpeg = {
    nullptr, // onInit (stream callbacks)
    ma_decoding_backend_init_file__ffmpeg,
    ma_decoding_backend_init_file_w__ffmpeg, // onInitFileW
    nullptr, // onInitMemory
    ma_decoding_backend_uninit__ffmpeg
};
}
#else

namespace sautiflow {

static std::atomic<FFmpegStreamSource*> g_activeStreamSource{nullptr};

StreamTelemetry get_active_stream_telemetry() {
    return StreamTelemetry();
}

StreamTelemetry get_stream_telemetry_from_decoder(ma_decoder* pDecoder) {
    (void)pDecoder;
    return StreamTelemetry();
}

bool FFmpegStreamSource::is_network_url(const char* path) {
    if (path == nullptr) return false;
    std::string s(path);
    auto to_lower = [](std::string in) {
        for (auto &c : in) c = (char)::tolower(c);
        return in;
    };
    std::string lower = to_lower(s);
    return (lower.rfind("http://", 0) == 0 ||
            lower.rfind("https://", 0) == 0 ||
            lower.rfind("rtmp://", 0) == 0 ||
            lower.rfind("rtsp://", 0) == 0 ||
            lower.rfind("mms://", 0) == 0 ||
            lower.find(".m3u8") != std::string::npos ||
            lower.find(".mpd") != std::string::npos);
}

FFmpegStreamSource::FFmpegStreamSource() {}
FFmpegStreamSource::~FFmpegStreamSource() {}

bool FFmpegStreamSource::open(const std::string& url, int targetSampleRate, int targetChannels, int prebufferMs) {
    (void)url; (void)targetSampleRate; (void)targetChannels; (void)prebufferMs;
    set_error(StreamErrorCode::OpenFailed, "FFmpeg streaming not compiled in for this build target");
    return false;
}

void FFmpegStreamSource::close() {}
size_t FFmpegStreamSource::read_pcm(float* pOut, size_t frameCount) { (void)pOut; (void)frameCount; return 0; }
bool FFmpegStreamSource::seek(int64_t timestampMs) { (void)timestampMs; return false; }
void FFmpegStreamSource::pause() {}
void FFmpegStreamSource::resume() {}
StreamTelemetry FFmpegStreamSource::get_telemetry() const { return m_telemetry; }
void FFmpegStreamSource::set_telemetry_callback(StreamTelemetryCallback cb) { (void)cb; }
void FFmpegStreamSource::demux_and_decode_thread_func() {}
void FFmpegStreamSource::update_icy_metadata() {}
void FFmpegStreamSource::notify_telemetry() {}
void FFmpegStreamSource::set_error(StreamErrorCode code, const std::string& msg) {
    m_telemetry.state = StreamState::Error;
    m_telemetry.errorCode = code;
    std::strncpy(m_telemetry.errorMessage, msg.c_str(), sizeof(m_telemetry.errorMessage) - 1);
}

bool read_file_tags_ffmpeg(
    const char *filePath,
    std::string &outArtist,
    std::string &outTitle,
    std::string &outAlbum,
    float &outTrackGain,
    float &outAlbumGain,
    float &outTrackPeak,
    float &outAlbumPeak
) {
    (void)filePath;
    outArtist.clear();
    outTitle.clear();
    outAlbum.clear();
    outTrackGain = 0.0f;
    outAlbumGain = 0.0f;
    outTrackPeak = 0.0f;
    outAlbumPeak = 0.0f;
    return false;
}

bool read_file_metadata_ffmpeg(
    const char *filePath,
    bool getPicture,
    std::string &outArtist,
    std::string &outTitle,
    std::string &outAlbum,
    std::string &outGenre,
    std::string &outYear,
    int &outTrackNumber,
    double &outDurationSecs,
    int &outSampleRate,
    int &outChannels,
    int &outBitrateKbps,
    std::string &outCodec,
    float &outTrackGain,
    float &outAlbumGain,
    float &outTrackPeak,
    float &outAlbumPeak,
    std::vector<uint8_t> *outPicture
) {
    (void)filePath;
    (void)getPicture;
    outArtist.clear();
    outTitle.clear();
    outAlbum.clear();
    outGenre.clear();
    outYear.clear();
    outTrackNumber = 0;
    outDurationSecs = 0.0;
    outSampleRate = 44100;
    outChannels = 2;
    outBitrateKbps = 0;
    outCodec.clear();
    outTrackGain = 0.0f;
    outAlbumGain = 0.0f;
    outTrackPeak = 1.0f;
    outAlbumPeak = 1.0f;
    if (outPicture) outPicture->clear();
    return false;
}

} // namespace sautiflow

static ma_result ma_decoding_backend_init_file__ffmpeg_stub(void* pUserData, const char* pFilePath, const ma_decoding_backend_config* pConfig, const ma_allocation_callbacks* pAllocationCallbacks, ma_data_source** ppBackend) {
    (void)pUserData; (void)pFilePath; (void)pConfig; (void)pAllocationCallbacks; (void)ppBackend;
    return MA_NOT_IMPLEMENTED;
}

static ma_result ma_decoding_backend_init_file_w__ffmpeg_stub(void* pUserData, const wchar_t* pFilePathW, const ma_decoding_backend_config* pConfig, const ma_allocation_callbacks* pAllocationCallbacks, ma_data_source** ppBackend) {
    (void)pUserData; (void)pFilePathW; (void)pConfig; (void)pAllocationCallbacks; (void)ppBackend;
    return MA_NOT_IMPLEMENTED;
}

static void ma_decoding_backend_uninit__ffmpeg_stub(void* pUserData, ma_data_source* pBackend, const ma_allocation_callbacks* pAllocationCallbacks) {
    (void)pUserData; (void)pBackend; (void)pAllocationCallbacks;
}

extern "C" {
ma_decoding_backend_vtable g_ma_decoding_backend_vtable_ffmpeg = {
    nullptr,
    ma_decoding_backend_init_file__ffmpeg_stub,
    ma_decoding_backend_init_file_w__ffmpeg_stub,
    nullptr,
    ma_decoding_backend_uninit__ffmpeg_stub
};
}
#endif
