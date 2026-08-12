#include <iostream>
#include <vector>
#include <cmath>
#include <cstring>
#include <algorithm>
#include <cstdio>
#include <cstdlib>

#define MINIAUDIO_IMPLEMENTATION
#include "miniaudio.h"
#include <samplerate.h>
#include <soxr.h>

// Re-create the LibSampleRateBackend and SoxrResamplerBackend VTable wrappers matching audio_engine.cpp

struct LibSampleRateBackend
{
    SRC_STATE *state;
    float ratio;
    int channels;
    int converterType;
};

static ma_result src_onGetHeapSize(void *pUserData, const ma_resampler_config *pConfig, size_t *pHeapSizeInBytes)
{
    if (!pHeapSizeInBytes) return MA_INVALID_ARGS;
    *pHeapSizeInBytes = sizeof(LibSampleRateBackend);
    return MA_SUCCESS;
}

static ma_result src_onInit(void *pUserData, const ma_resampler_config *pConfig, void *pAllocation, ma_resampling_backend **ppBackend)
{
    if (!pConfig || !pAllocation || !ppBackend) return MA_INVALID_ARGS;
    LibSampleRateBackend *backend = (LibSampleRateBackend *)pAllocation;
    backend->channels = pConfig->channels;

    int algo = pUserData ? *(int *)pUserData : 1;
    int converter = SRC_SINC_FASTEST;
    if (algo == 1) converter = SRC_SINC_BEST_QUALITY;
    else if (algo == 2) converter = SRC_SINC_MEDIUM_QUALITY;
    else if (algo == 3) converter = SRC_SINC_FASTEST;
    else if (algo == 4) converter = SRC_ZERO_ORDER_HOLD;
    else if (algo == 5 || algo == 6) converter = SRC_LINEAR;

    backend->converterType = converter;
    backend->ratio = (pConfig->sampleRateIn > 0) ? ((float)pConfig->sampleRateOut / (float)pConfig->sampleRateIn) : 1.0f;

    int err = 0;
    backend->state = src_new(converter, backend->channels, &err);
    if (!backend->state)
    {
        std::printf("src_onInit failed (err=%d: %s)\n", err, src_strerror(err));
        return MA_ERROR;
    }

    *ppBackend = (ma_resampling_backend *)backend;
    return MA_SUCCESS;
}

static void src_onUninit(void *pUserData, ma_resampling_backend *pBackend, const ma_allocation_callbacks *pAllocationCallbacks)
{
    LibSampleRateBackend *backend = (LibSampleRateBackend *)pBackend;
    if (backend && backend->state)
    {
        src_delete(backend->state);
        backend->state = nullptr;
    }
}

static ma_result src_onProcess(void *pUserData, ma_resampling_backend *pBackend, const void *pFramesIn, ma_uint64 *pFrameCountIn, void *pFramesOut, ma_uint64 *pFrameCountOut)
{
    LibSampleRateBackend *backend = (LibSampleRateBackend *)pBackend;
    if (!backend || !backend->state || !pFrameCountIn || !pFrameCountOut) return MA_ERROR;

    SRC_DATA srcData;
    srcData.data_in = (const float *)pFramesIn;
    srcData.input_frames = (long)std::min<ma_uint64>(*pFrameCountIn, 0x7FFFFFFF);
    srcData.data_out = (float *)pFramesOut;
    srcData.output_frames = (long)std::min<ma_uint64>(*pFrameCountOut, 0x7FFFFFFF);
    srcData.src_ratio = backend->ratio;
    srcData.end_of_input = 0;

    int err = src_process(backend->state, &srcData);
    if (err) return MA_ERROR;

    *pFrameCountIn = (ma_uint64)srcData.input_frames_used;
    *pFrameCountOut = (ma_uint64)srcData.output_frames_gen;
    return MA_SUCCESS;
}

static ma_result src_onSetRate(void *pUserData, ma_resampling_backend *pBackend, ma_uint32 sampleRateIn, ma_uint32 sampleRateOut)
{
    LibSampleRateBackend *backend = (LibSampleRateBackend *)pBackend;
    if (!backend) return MA_ERROR;
    backend->ratio = (sampleRateIn > 0) ? ((float)sampleRateOut / (float)sampleRateIn) : 1.0f;
    if (backend->state)
    {
        src_set_ratio(backend->state, backend->ratio);
    }
    return MA_SUCCESS;
}

static ma_resampling_backend_vtable g_customResamplerVTable = {
    src_onGetHeapSize,
    src_onInit,
    src_onUninit,
    src_onProcess,
    src_onSetRate,
    NULL, NULL, NULL, NULL, NULL
};

// Soxr Backend
struct SoxrResamplerBackend
{
    soxr_t handle;
    double ratio;
    int channels;
    int algorithm;
};

static ma_result soxr_onGetHeapSize(void *pUserData, const ma_resampler_config *pConfig, size_t *pHeapSizeInBytes)
{
    if (!pHeapSizeInBytes) return MA_INVALID_ARGS;
    *pHeapSizeInBytes = sizeof(SoxrResamplerBackend);
    return MA_SUCCESS;
}

static ma_result soxr_onInit(void *pUserData, const ma_resampler_config *pConfig, void *pAllocation, ma_resampling_backend **ppBackend)
{
    if (!pConfig || !pAllocation || !ppBackend) return MA_INVALID_ARGS;
    SoxrResamplerBackend *backend = (SoxrResamplerBackend *)pAllocation;
    backend->channels = pConfig->channels;

    int algo = pUserData ? *(int *)pUserData : 7;
    backend->algorithm = algo;

    unsigned long q_recipe = SOXR_HQ;
    unsigned long q_flags = 0;

    if (algo == 7) { q_recipe = SOXR_VHQ; q_flags = SOXR_LINEAR_PHASE; }
    else if (algo == 8) { q_recipe = SOXR_VHQ; q_flags = SOXR_MINIMUM_PHASE; }
    else if (algo == 9) { q_recipe = SOXR_HQ; q_flags = SOXR_LINEAR_PHASE; }
    else if (algo == 10) { q_recipe = SOXR_LQ; q_flags = SOXR_LINEAR_PHASE; }

    soxr_quality_spec_t q_spec = soxr_quality_spec(q_recipe, q_flags);
    soxr_io_spec_t io_spec = soxr_io_spec(SOXR_FLOAT32_I, SOXR_FLOAT32_I);
    backend->ratio = (pConfig->sampleRateIn > 0) ? ((double)pConfig->sampleRateOut / (double)pConfig->sampleRateIn) : 1.0;

    soxr_error_t err = nullptr;
    backend->handle = soxr_create((double)pConfig->sampleRateIn, (double)pConfig->sampleRateOut, (unsigned)backend->channels, &err, &io_spec, &q_spec, NULL);
    if (!backend->handle || err)
    {
        std::printf("soxr_onInit failed (err=%s)\n", soxr_strerror(err));
        return MA_ERROR;
    }

    *ppBackend = (ma_resampling_backend *)backend;
    return MA_SUCCESS;
}

static void soxr_onUninit(void *pUserData, ma_resampling_backend *pBackend, const ma_allocation_callbacks *pAllocationCallbacks)
{
    SoxrResamplerBackend *backend = (SoxrResamplerBackend *)pBackend;
    if (backend && backend->handle)
    {
        soxr_delete(backend->handle);
        backend->handle = nullptr;
    }
}

static ma_result soxr_onProcess(void *pUserData, ma_resampling_backend *pBackend, const void *pFramesIn, ma_uint64 *pFrameCountIn, void *pFramesOut, ma_uint64 *pFrameCountOut)
{
    SoxrResamplerBackend *backend = (SoxrResamplerBackend *)pBackend;
    if (!backend || !backend->handle || !pFrameCountIn || !pFrameCountOut) return MA_ERROR;

    size_t idone = 0, odone = 0;
    soxr_error_t err = soxr_process(backend->handle, pFramesIn, (size_t)*pFrameCountIn, &idone, pFramesOut, (size_t)*pFrameCountOut, &odone);
    if (err) return MA_ERROR;

    *pFrameCountIn = (ma_uint64)idone;
    *pFrameCountOut = (ma_uint64)odone;
    return MA_SUCCESS;
}

static ma_result soxr_onSetRate(void *pUserData, ma_resampling_backend *pBackend, ma_uint32 sampleRateIn, ma_uint32 sampleRateOut)
{
    SoxrResamplerBackend *backend = (SoxrResamplerBackend *)pBackend;
    if (!backend) return MA_ERROR;
    backend->ratio = (sampleRateIn > 0) ? ((double)sampleRateOut / (double)sampleRateIn) : 1.0;
    if (backend->handle)
    {
        soxr_error_t err = soxr_set_io_ratio(backend->handle, 1.0 / backend->ratio, 0);
        if (err) return MA_ERROR;
    }
    return MA_SUCCESS;
}

static ma_resampling_backend_vtable g_soxrResamplerVTable = {
    soxr_onGetHeapSize,
    soxr_onInit,
    soxr_onUninit,
    soxr_onProcess,
    soxr_onSetRate,
    NULL, NULL, NULL, NULL, NULL
};

// Frequency estimation by counting zero crossings
double estimate_frequency(const std::vector<float>& buffer, int channels, int sampleRate)
{
    if (buffer.empty() || sampleRate <= 0) return 0.0;
    
    // Process left channel (channel 0)
    int zeroCrossings = 0;
    size_t startFrame = buffer.size() / (channels * 4); // skip initial transient
    size_t endFrame = buffer.size() / channels - startFrame;
    
    for (size_t i = startFrame + 1; i < endFrame; ++i)
    {
        float prev = buffer[(i - 1) * channels];
        float curr = buffer[i * channels];
        if (prev <= 0.0f && curr > 0.0f)
        {
            zeroCrossings++;
        }
    }
    
    double durationSec = (double)(endFrame - startFrame) / (double)sampleRate;
    if (durationSec <= 0) return 0.0;
    return (double)zeroCrossings / durationSec;
}

void run_test(const char* name, int algo, ma_resampling_backend_vtable* vtable, int inRate, int outRate, int channels = 2, double sineFreq = 1000.0)
{
    double durationSec = 2.0;
    size_t totalInFrames = (size_t)(inRate * durationSec);
    std::vector<float> inputSignal(totalInFrames * channels);

    // Generate 1 kHz sine wave
    for (size_t i = 0; i < totalInFrames; ++i)
    {
        float val = (float)std::sin(2.0 * 3.14159265358979323846 * sineFreq * (double)i / (double)inRate);
        for (int c = 0; c < channels; ++c)
        {
            inputSignal[i * channels + c] = val;
        }
    }

    // Initialize resampler via miniaudio ma_resampler API
    ma_resampler_config config = ma_resampler_config_init(
        ma_format_f32,
        (ma_uint32)channels,
        (ma_uint32)inRate,
        (ma_uint32)outRate,
        ma_resample_algorithm_custom
    );
    config.pBackendVTable = vtable;
    config.pBackendUserData = &algo;

    ma_resampler resampler;
    ma_result res = ma_resampler_init(&config, NULL, &resampler);
    if (res != MA_SUCCESS)
    {
        std::printf("[%s] INIT FAILED (res=%d)\n", name, res);
        return;
    }

    // Process audio in chunks of 512 frames
    size_t chunkSizeIn = 512;
    size_t inFramesRead = 0;
    std::vector<float> outputSignal;
    outputSignal.reserve((size_t)(totalInFrames * ((double)outRate / inRate) + 4096) * channels);

    size_t totalInConsumed = 0;
    size_t totalOutGenerated = 0;

    while (inFramesRead < totalInFrames)
    {
        ma_uint64 framesInAvailable = std::min<size_t>(chunkSizeIn, totalInFrames - inFramesRead);
        ma_uint64 framesOutCapacity = (ma_uint64)std::ceil((double)framesInAvailable * ((double)outRate / inRate) + 256);

        std::vector<float> outBuf(framesOutCapacity * channels);

        ma_uint64 framesInConsumed = framesInAvailable;
        ma_uint64 framesOutGenerated = framesOutCapacity;

        res = ma_resampler_process_pcm_frames(
            &resampler,
            &inputSignal[inFramesRead * channels],
            &framesInConsumed,
            outBuf.data(),
            &framesOutGenerated
        );

        if (res != MA_SUCCESS)
        {
            std::printf("[%s] PROCESS ERROR at frame %zu\n", name, inFramesRead);
            break;
        }

        outputSignal.insert(outputSignal.end(), outBuf.begin(), outBuf.begin() + framesOutGenerated * channels);

        inFramesRead += framesInConsumed;
        totalInConsumed += framesInConsumed;
        totalOutGenerated += framesOutGenerated;

        if (framesInConsumed == 0 && framesOutGenerated == 0)
        {
            break; // no progress
        }
    }

    ma_resampler_uninit(&resampler, NULL);

    double estFreq = estimate_frequency(outputSignal, channels, outRate);
    double expectedOutFrames = (double)totalInFrames * ((double)outRate / (double)inRate);
    double generatedDurationSec = (double)totalOutGenerated / (double)outRate;
    double freqError = std::abs(estFreq - sineFreq);

    std::printf("[%s] %d Hz -> %d Hz | InConsumed: %zu/%zu | OutGen: %zu (exp: %.0f) | Dur: %.3fs | Est Freq: %.2f Hz (err: %.2f Hz) [%s]\n",
        name, inRate, outRate, totalInConsumed, totalInFrames, totalOutGenerated, expectedOutFrames, generatedDurationSec, estFreq, freqError,
        (freqError < 5.0 ? "PASS" : "FAIL - PITCH SHIFT"));
}

int main()
{
    std::printf("============================================================\n");
    std::printf("STANDALONE CUSTOM RESAMPLER BACKEND INTEGRATION TEST\n");
    std::printf("============================================================\n\n");

    std::printf("--- TESTING MINIAUDIO LINEAR RESAMPLER (BASELINE) ---\n");
    // Test linear resampler via stock miniaudio
    {
        ma_resampler_config config = ma_resampler_config_init(ma_format_f32, 2, 48000, 96000, ma_resample_algorithm_linear);
        ma_resampler resampler;
        if (ma_resampler_init(&config, NULL, &resampler) == MA_SUCCESS)
        {
            std::vector<float> inBuf(48000 * 2 * 2);
            for (size_t i = 0; i < 48000 * 2; ++i) {
                float val = (float)std::sin(2.0 * 3.14159265358979323846 * 1000.0 * i / 48000.0);
                inBuf[i * 2] = val; inBuf[i * 2 + 1] = val;
            }
            std::vector<float> outBuf(96000 * 2 * 2);
            ma_uint64 inCount = 48000 * 2;
            ma_uint64 outCount = 96000 * 2;
            ma_resampler_process_pcm_frames(&resampler, inBuf.data(), &inCount, outBuf.data(), &outCount);
            double freq = estimate_frequency(outBuf, 2, 96000);
            std::printf("[Linear Stock] 48000 -> 96000 | Est Freq: %.2f Hz [PASS]\n", freq);
            ma_resampler_uninit(&resampler, NULL);
        }
    }

    std::printf("\n--- TESTING LIBSAMPLERATE BACKEND (g_customResamplerVTable) ---\n");
    run_test("libsamplerate BEST", 1, &g_customResamplerVTable, 48000, 96000);
    run_test("libsamplerate BEST", 1, &g_customResamplerVTable, 96000, 48000);
    run_test("libsamplerate BEST", 1, &g_customResamplerVTable, 44100, 48000);
    run_test("libsamplerate BEST", 1, &g_customResamplerVTable, 48000, 44100);
    run_test("libsamplerate BEST", 1, &g_customResamplerVTable, 192000, 48000);

    run_test("libsamplerate FASTEST", 3, &g_customResamplerVTable, 48000, 96000);
    run_test("libsamplerate FASTEST", 3, &g_customResamplerVTable, 96000, 48000);

    std::printf("\n--- TESTING LIBSOXR BACKEND (g_soxrResamplerVTable) ---\n");
    run_test("libsoxr VHQ", 7, &g_soxrResamplerVTable, 48000, 96000);
    run_test("libsoxr VHQ", 7, &g_soxrResamplerVTable, 96000, 48000);
    run_test("libsoxr VHQ", 7, &g_soxrResamplerVTable, 44100, 48000);
    run_test("libsoxr VHQ", 7, &g_soxrResamplerVTable, 48000, 44100);
    run_test("libsoxr HQ",  9, &g_soxrResamplerVTable, 48000, 96000);
    run_test("libsoxr LQ", 10, &g_soxrResamplerVTable, 48000, 96000);

    return 0;
}
