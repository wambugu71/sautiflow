#pragma once

#include <cstdint>

#if defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86)
#include <xmmintrin.h>
#include <pmmintrin.h>
#elif defined(_MSC_VER) && (defined(_M_ARM) || defined(_M_ARM64))
#include <float.h>
#endif

namespace sauti::dsp {

// =============================================================================
// ScopedDenormalsDisable: Zero-Overhead RAII Denormal / Subnormal Flushing
//
// Flushes IEEE-754 denormal (subnormal) floating point numbers to zero (FTZ)
// and treats denormals as zero (DAZ) on the current thread during audio DSP
// execution. This prevents CPU penalty spikes (10x-100x slowdowns) and
// micro-stutters during quiet passages or reverb/IIR tail decays.
//
// Platform support:
// - x86 / x86-64 (SSE / AVX): MXCSR DAZ (bit 6) + FTZ (bit 15)
// - ARM64 (AArch64): FPCR FZ (bit 24)
// - ARM32 (ARMv7-A VFP/NEON): FPSCR FZ (bit 24)
// =============================================================================
struct ScopedDenormalsDisable {
#if defined(__x86_64__) || defined(_M_X64) || defined(__i386__) || defined(_M_IX86)
    unsigned int old_mxcsr_ = 0;

    ScopedDenormalsDisable() noexcept {
        old_mxcsr_ = _mm_getcsr();
        // 0x8000 = FTZ (Flush-To-Zero), 0x0040 = DAZ (Denormals-Are-Zero)
        _mm_setcsr(old_mxcsr_ | 0x8040);
    }

    ~ScopedDenormalsDisable() noexcept {
        _mm_setcsr(old_mxcsr_);
    }

#elif defined(__aarch64__) || defined(_M_ARM64)
#if defined(__GNUC__) || defined(__clang__)
    uint64_t old_fpcr_ = 0;

    ScopedDenormalsDisable() noexcept {
        __asm__ __volatile__("mrs %0, fpcr" : "=r"(old_fpcr_));
        const uint64_t new_fpcr = old_fpcr_ | (1ULL << 24); // Bit 24: FZ (Flush-to-Zero)
        __asm__ __volatile__("msr fpcr, %0" : : "r"(new_fpcr));
    }

    ~ScopedDenormalsDisable() noexcept {
        __asm__ __volatile__("msr fpcr, %0" : : "r"(old_fpcr_));
    }
#elif defined(_MSC_VER)
    unsigned int old_fp_ = 0;

    ScopedDenormalsDisable() noexcept {
        _controlfp_s(&old_fp_, _DN_FLUSH, _MCW_DN);
    }

    ~ScopedDenormalsDisable() noexcept {
        unsigned int cur = 0;
        _controlfp_s(&cur, old_fp_, _MCW_DN);
    }
#else
    ScopedDenormalsDisable() noexcept = default;
    ~ScopedDenormalsDisable() noexcept = default;
#endif

#elif defined(__arm__) || defined(_M_ARM)
#if (defined(__GNUC__) || defined(__clang__)) && !defined(__SOFTFP__)
    uint32_t old_fpscr_ = 0;

    ScopedDenormalsDisable() noexcept {
        __asm__ __volatile__("vmrs %0, fpscr" : "=r"(old_fpscr_));
        const uint32_t new_fpscr = old_fpscr_ | (1u << 24); // Bit 24: FZ (Flush-to-Zero)
        __asm__ __volatile__("vmsr fpscr, %0" : : "r"(new_fpscr));
    }

    ~ScopedDenormalsDisable() noexcept {
        __asm__ __volatile__("vmsr fpscr, %0" : : "r"(old_fpscr_));
    }
#elif defined(_MSC_VER)
    unsigned int old_fp_ = 0;

    ScopedDenormalsDisable() noexcept {
        _controlfp_s(&old_fp_, _DN_FLUSH, _MCW_DN);
    }

    ~ScopedDenormalsDisable() noexcept {
        unsigned int cur = 0;
        _controlfp_s(&cur, old_fp_, _MCW_DN);
    }
#else
    ScopedDenormalsDisable() noexcept = default;
    ~ScopedDenormalsDisable() noexcept = default;
#endif

#else
    ScopedDenormalsDisable() noexcept = default;
    ~ScopedDenormalsDisable() noexcept = default;
#endif

    // Non-copyable, non-movable
    ScopedDenormalsDisable(const ScopedDenormalsDisable&) = delete;
    ScopedDenormalsDisable& operator=(const ScopedDenormalsDisable&) = delete;
};

} // namespace sauti::dsp
