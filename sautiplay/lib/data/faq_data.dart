import '../models/faq_item.dart';

/// Frequently Asked Questions data derived directly from site/index.html (Section 06).
const List<FaqItem> sautiplayFaqItems = [
  FaqItem(
    id: 'declined-exclusive-mode',
    question: 'Why does my device say "Hardware Declined Exclusive Mode"?',
    category: 'Hardware & Bit-Perfect',
    tags: [
      'exclusive mode',
      'hardware',
      'bit-perfect',
      'aaudio',
      'mmap',
      'hal',
      'shared mode',
      'dac'
    ],
    answer:
        'Android devices have wildly different hardware abstraction layers (HALs). '
        'When you request Bit-Perfect Exclusive mode, Sautiplay asks the operating system '
        'for direct, unmixed hardware access (via AAudio MMAP).\n\n'
        'Some internal phone DACs and vendor ROMs decline this exclusive lock. '
        'When that happens, Sautiplay doesn\'t crash or fail — it notifies you and '
        'falls back to low-latency shared mode, using its own clean internal floating-point '
        'engine for any required processing.',
  ),
  FaqItem(
    id: 'is-bit-perfect-actually-bit-perfect',
    question: 'When Bit-Perfect is enabled, is it actually bit-perfect?',
    category: 'Hardware & Bit-Perfect',
    tags: [
      'bit-perfect',
      'dac',
      'sample rate',
      'bit depth',
      'android',
      'desktop',
      'exclusive mode',
      'fidelity',
      'wasapi',
      'aaudio'
    ],
    answer:
        'It depends on your music files, your DAC hardware capabilities, and your operating system platform.\n\n'
        'Music tracks come in arbitrary sample rates (44.1, 48, 88.2, 96, 192 kHz) and bit depths (16-bit, 24-bit, 32-bit float). However, physical DACs only support a discrete list of native hardware clocks and formats. If a song\'s sample rate or bit depth is not natively supported by your DAC hardware, mathematically exact 1:1 bit transmission without conversion is impossible — the audio stream must be resampled or format-adapted.\n\n'
        'On Android, fidelity is not 100% guaranteed across all devices due to restrictive OEM audio drivers and the system AudioFlinger mixer, which typically forces 48 kHz resampling. When you enable Bit-Perfect in Sautiplay on Android, it requests native AAudio MMAP Exclusive mode on supported devices, bypassing system mixers and taking direct hardware control. If your device\'s HAL declines exclusive access, Sautiplay falls back to clean low-latency shared mode with transparent 64-bit float internal processing.\n\n'
        'On Desktop (Windows WASAPI Exclusive, Linux ALSA direct, and macOS CoreAudio), bit-perfect mode works exceptionally well. Sautiplay acquires full exclusive lock on the audio endpoint, reconfigures the DAC clock dynamically to the song\'s exact native sample rate and bit depth, and delivers genuine 100% bit-perfect audio without any OS resampling or intermediate processing.',
  ),
  FaqItem(
    id: 'auto-rate-matching',
    question: 'How does Auto-Rate Matching differ from Bit-Perfect?',
    category: 'Hardware & Bit-Perfect',
    tags: [
      'auto-rate',
      'sample rate',
      'bit-perfect',
      'clock',
      'dac',
      'exclusive',
      'khz'
    ],
    answer:
        'Bit-Perfect mode attempts to lock exclusive ownership of the hardware output '
        'so no other app or system notification can mix in.\n\n'
        'Auto Sample-Rate Match detects the exact sample rate of whatever song you\'re '
        'playing (44.1, 48, 96, 192 kHz) and asks the DAC to switch its internal clock '
        'to match that track. If both are on, Sautiplay manages rate-switching and exclusive '
        'access together.',
  ),
  FaqItem(
    id: 'bypass-oem-eq-atmos',
    question:
        'How does Sautiplay bypass OEM equalizers & Dolby Atmos without root?',
    category: 'Audio Routing',
    tags: [
      'oem',
      'dolby atmos',
      'dts',
      'equalizer',
      'audioflinger',
      'root',
      'mmap',
      'alsa',
      'aaudio'
    ],
    answer:
        'On supported Android devices, Sautiplay requests low-latency MMAP (Memory-Mapped) '
        'streams through Android\'s native AAudio C API.\n\n'
        'When supported, MMAP audio writes directly to the ALSA driver and DSP hardware, '
        'completely bypassing Android\'s user-space AudioFlinger mixer where forced OEM '
        'sound "enhancements" (Dolby Atmos, DTS:X, and factory equalizers) are normally '
        'injected. No root required.',
  ),
  FaqItem(
    id: 'resampler-choice',
    question:
        'Which resampler should I choose (r8brain or libsamplerate)?',
    category: 'DSP & Resampling',
    tags: [
      'resampler',
      'libsamplerate',
      'r8brain',
      'sinc',
      'phase',
      'stopband',
      'dsp'
    ],
    answer:
        'Both are top-tier sinc resamplers: r8brain offers ultra-clean linear and '
        'minimum phase modes with over -160 dB stopband attenuation and zero pre-ringing, '
        'while libsamplerate provides classic mastering-grade sinc conversion.\n\n'
        'For local files, either delivers mathematically transparent rate '
        'conversion with zero audible distortion or high-frequency loss.',
  ),
  FaqItem(
    id: 'streaming-tracks-resampler',
    question: 'Why do streaming tracks use FFmpeg\'s resampler instead?',
    category: 'DSP & Resampling',
    tags: [
      'streaming',
      'ffmpeg',
      'swresample',
      'resampler',
      'youtube music',
      'buffer',
      'demuxing'
    ],
    answer:
        'Online streams (like YouTube Music or direct URL radio) require real-time '
        'chunk demuxing, variable network bitrates, and live buffering.\n\n'
        'FFmpeg\'s built-in swresample is tightly integrated into the streaming '
        'decoder pipeline to guarantee glitch-free, instantaneous live playback '
        'without buffer underruns.',
  ),
  FaqItem(
    id: '64-bit-float-processing',
    question: 'What does 64-bit float processing do?',
    category: 'DSP & Resampling',
    tags: [
      '64-bit',
      '32-bit',
      'float',
      'double precision',
      'dynamic range',
      'headroom',
      'clipping',
      'dsp'
    ],
    answer:
        'Standard digital audio processing uses 32-bit float (around 144–150 dB of '
        'dynamic range). When you enable 64-Bit Float Processing in Sautiplay, the '
        'entire DSP chain (equalizers, crossfeed, surround virtualizer, limiter, and '
        'volume) computes in double precision.\n\n'
        'This yields over 320 dB of internal calculation headroom, completely '
        'eliminating accumulated rounding noise or clipping during complex multi-effect chains.',
  ),
  FaqItem(
    id: 'autoeq-and-convolver',
    question:
        'Can I import AutoEQ profiles or headphone impulse responses?',
    category: 'DSP & Equalizer',
    tags: [
      'autoeq',
      'headphones',
      'impulse response',
      'convolver',
      'viper4android',
      'vdc',
      'ddc',
      'wav'
    ],
    answer:
        'Yes. Sautiplay has native support for AutoEQ (importing parametric or graphic '
        'EQ curves for thousands of headphones), Viper4Android VDC/DDC profiles, and a '
        'Convolver that can load custom stereo impulse response (.wav) files for acoustic '
        'room simulation or headphone correction.',
  ),
  FaqItem(
    id: 'dlna-casting-receiver',
    question:
        'Can I cast to DLNA or use Sautiplay as a wireless receiver?',
    category: 'Network & Casting',
    tags: [
      'dlna',
      'upnp',
      'cast',
      'wireless',
      'receiver',
      'mediarenderer',
      'wifi',
      'streaming'
    ],
    answer:
        'Both! Sautiplay can cast out to UPnP/DLNA network speakers and smart TVs. '
        'It also includes a built-in DLNA MediaRenderer service that turns Sautiplay into '
        'a wireless receiver, letting you stream music from other phones, tablets, or '
        'computers on your local Wi-Fi network directly into Sautiplay.',
  ),
  FaqItem(
    id: 'ads-privacy-tracking',
    question: 'Are there ads, tracking, or mandatory accounts?',
    category: 'Privacy & Open Source',
    tags: [
      'ads',
      'tracking',
      'telemetry',
      'privacy',
      'account',
      'open source',
      'offline'
    ],
    answer:
        'None. Sautiplay is 100% open source, privacy-focused, and offline-first. '
        'There are zero ads, zero telemetry, and no mandatory account sign-ins. '
        'All audio playback, DSP calculations, and library indexing happen entirely '
        'locally on your device.',
  ),
];
