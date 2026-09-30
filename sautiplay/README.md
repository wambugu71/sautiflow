# Sautiplay

Sautiplay is a clean, fast music player built for people who care about how their music sounds. It runs on Sautiflow, a custom low-latency C++ audio engine designed to bypass noisy system mixers, handle mixed sample rates cleanly, and send bit-perfect audio directly to your DAC or headphones.

No ads, no tracking, and no bloated menus; just clean sound and direct control over your playback.

![Sautiplay](../docs/assets/sautiflow.png)

## Download

Pre-compiled binaries are available on GitHub Releases:

**[Download Latest Sautiplay Release](https://github.com/wambugu71/sautiflow/releases/latest)** | **[Join Telegram Community](https://t.me/+MilnrgkNkbFiYmY0)**

Available platforms:

- **Android**: sautiflow_android_arm64.apk and sautiflow_android_armv7.apk
- **Windows**: sautiflow_windows.zip
- **Linux**: sautiflow_linux.tar.gz
- **macOS**: sautiflow_macos.zip
- **iOS**: sautiflow_ios.ipa

*Note: Production builds are compiled with release optimizations.*

## Sideloading on iOS

To install the Sautiplay `.ipa` on iOS, you must sign it yourself because it is distributed unsigned. Tools like [Sideloadly](https://sideloadly.io/) or [AltStore](https://altstore.io/) let you sign and install the `.ipa` onto your iPhone or iPad using your Apple ID.

## Why I built Sautiplay

I started building Sautiplay in 2023. At first, I just wanted a simple music player for Android that could deliver clean, bit-perfect sound.

Existing music apps were frustrating. Most were bloated, full of ads, or cluttered with complex menus. The bigger problem was how Android handles audio:

- **Variable sample rates**: real music libraries are mixed. You have 44.1 kHz CD rips, 48 kHz video audio, and 96 kHz hi-res files. Android normally forces everything through a cheap system resampler to match a fixed rate. I wanted high-precision resampling built directly into the player.
- **Forced OEM processing**: most phone manufacturers inject equalizers, Dolby Atmos, or DTS:X into the audio pipeline. These alter frequency response, and bypassing them usually required rooting the phone.

I wrote Sautiflow, a low-latency C++ audio engine, to talk directly to the hardware.

### How the engine works

- **Bypassing OEM processing without root**: the engine requests low-latency MMAP mode through Android's AAudio API. On supported devices, this writes audio straight to the hardware driver, bypassing Android's shared mixer and OEM effects (Dolby Atmos, DTS:X, and vendor EQs). If a device HAL rejects MMAP or bit-perfect streams, the engine falls back to the lowest-latency mode available.
- **Built-in sinc resampling**: for local tracks that require rate conversion, the engine embeds `r8brain` and `libsamplerate`. Both use high-precision sinc interpolation to prevent phase distortion and treble roll-off. Network streams decode through FFmpeg's resampler for low-overhead streaming playback.
- **Sample rate matching**: when the output DAC supports it, the engine switches hardware sample rates to match the source file.
- **Accurate DSP algorithms**: the processing chain uses Robert Bristow-Johnson's Audio EQ Cookbook biquad equations, BS2B (Bauer stereophonic-to-binaural) crossfeed, partitioned FFT convolution for headphone correction, tube warmth modeling, and WSOLA time-stretching. Each algorithm was modeled and verified in MATLAB before being implemented in C++.
- **Android hardware fallback**: some phones accept bit-perfect or direct MMAP streams, while others reject them. When a device rejects exclusive mode, the engine keeps low-latency AAudio buffers and uses its internal resampler, avoiding the system's stock resampler.

## Features

- **Playback**: miniaudio engine backend with r8brain and libsamplerate sinc resampling for local files, and FFmpeg for network streams.
- **Gapless playback**: zero silence between queued tracks.
- **DSP effects**:
  - 3-band and multiband equalizers
  - Reverb, delay, and stereo widening
  - Parametric filters (low-pass, high-pass, band-pass, notch, peak EQ, low-shelf, high-shelf)
- **Playlist management**: queue reordering, shuffling, and dynamic track insertion.
- **Network streaming**: native HTTP/HTTPS audio stream playback.
- **Platforms**: Android, Windows, Linux, macOS, and iOS.

## Developer guide: cross-platform setup and building

The UI is built with Flutter, and audio processing runs in a shared C++ engine (Sautiflow) via Dart FFI. The same DSP algorithms, resamplers, and mixer logic run across Android, Windows, Linux, macOS, and iOS.

### Prerequisites

- **Android**:
  - Flutter SDK
  - Android Studio & Android SDK
  - Android NDK (install via *Android Studio > SDK Manager > SDK Tools > NDK*)
  - CMake (install via SDK Manager)
- **Windows**:
  - Flutter SDK
  - Visual Studio 2022 (with the *Desktop development with C++* workload)
  - CMake
- **Linux**:
  - Flutter SDK
  - C++ compiler (`clang` or `gcc`), `cmake`, `ninja-build`, `pkg-config`
  - Audio headers: `sudo apt install cmake ninja-build libasound2-dev libpulse-dev pkg-config`
- **macOS & iOS**:
  - Flutter SDK
  - Xcode & Command Line Tools
  - CocoaPods: `sudo gem install cocoapods`

### Platform configuration

#### Android (`AndroidManifest.xml`)
For background playback, lockscreen transport controls, and notification controls, configure `android/app/src/main/AndroidManifest.xml`. `AudioServiceActivity` replaces the default `FlutterActivity`:

```xml
<manifest xmlns:android="http://schemas.android.com/apk/res/android">
    <!-- Required permissions for background audio & Android 13+ notifications -->
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>

    <application ...>
        <!-- Main Activity must use or extend AudioServiceActivity -->
        <activity
            android:name="com.ryanheise.audioservice.AudioServiceActivity"
            android:exported="true"
            android:launchMode="singleTask">
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>

        <!-- Background Media Playback Service -->
        <service
            android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService" />
            </intent-filter>
        </service>

        <!-- Headphone & Bluetooth hardware button receiver -->
        <receiver
            android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON" />
            </intent-filter>
        </receiver>
    </application>
</manifest>
```

#### Android native streaming (`android/gradle.properties`)
To enable native cURL streaming for online radio and web streams on Android, set these native flags:

```properties
MINIAUDIODART_ENABLE_CURL=ON
MINIAUDIODART_CURL_INCLUDE_DIR=/path/to/curl/include
MINIAUDIODART_CURL_LIBRARY=/path/to/libcurl.so
```

#### Audio session initialization (`main.dart`)
Initialize the audio session for background playback and start the Sautiflow engine:

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Configure audio session for background music playback
  final session = await AudioSession.instance;
  await session.configure(const AudioSessionConfiguration.music());

  // 2. Initialize Sautiflow engine with system audio integration
  final player = MiniAudioPlayer();
  await player.init(enableSystemAudio: true);

  runApp(const MyApp());
}

// Update lockscreen / notification metadata on track changes:
await player.updateNowPlaying(
  title: "Track Title",
  artist: "Artist Name",
  album: "Album Name",
  duration: Duration(minutes: 3, seconds: 45),
);
```

### Build and run

1. **Clone and fetch dependencies**:
   ```bash
   git clone https://github.com/wambugu71/sautiflow.git
   cd sautiflow/sautiplay
   flutter pub get
   ```

2. **Run with compile-time stream URLs**:
   Endpoints are passed via `--dart-define` so they are never hardcoded:
   ```bash
   flutter run --dart-define=STREAM_URL_1="your_stream_url_1" --dart-define=STREAM_URL_2="your_stream_url_2"
   ```

3. **Building release binaries**:
   - **Android APK**:
     ```bash
     flutter build apk --release --dart-define=STREAM_URL_1="..." --dart-define=STREAM_URL_2="..."
     ```
   - **Windows Portable**:
     ```bash
     flutter build windows --release --dart-define=STREAM_URL_1="..." --dart-define=STREAM_URL_2="..."
     ```
   - **Linux App**:
     ```bash
     flutter build linux --release --dart-define=STREAM_URL_1="..." --dart-define=STREAM_URL_2="..."
     ```
   - **macOS App**:
     ```bash
     flutter build macos --release --dart-define=STREAM_URL_1="..." --dart-define=STREAM_URL_2="..."
     ```
   - **iOS IPA**:
     ```bash
     flutter build ipa --release --no-codesign --dart-define=STREAM_URL_1="..." --dart-define=STREAM_URL_2="..."
     ```

## FAQ

### Why does Android show "Hardware declined Exclusive Mode"?
Android devices vary in their hardware abstraction layers (HALs) and firmware rules. When you enable Bit-Perfect Exclusive mode, Sautiplay requests direct hardware ownership via AAudio MMAP. Some internal DACs and vendor ROMs decline that lock. When that happens, Sautiplay notifies you and falls back to low-latency shared mode, keeping all internal processing in floating point.

### How does auto sample-rate matching differ from bit-perfect mode?
Bit-perfect mode requests exclusive hardware ownership so system sounds cannot mix in. Auto sample-rate matching detects the track's sample rate (44.1 kHz, 48 kHz, 96 kHz, 192 kHz) and requests that the DAC switch its internal clock to match. When both are enabled, Sautiplay requests the hardware clock change and exclusive lock together.

### How does Sautiplay bypass Dolby Atmos, DTS:X, and OEM equalizers without root?
On supported Android devices, Sautiplay requests low-latency MMAP streams through Android's AAudio C API. MMAP audio writes directly to the ALSA driver and DSP hardware, bypassing Android's user-space `AudioFlinger` mixer where OEM sound processing is injected. No root access or bootloader unlock is required.

### Which resampler should I choose between r8brain and libsamplerate?
Both are high-grade sinc resamplers:
- **`r8brain`**: linear-phase and minimum-phase resampler with over -160 dB stopband attenuation and high throughput.
- **`libsamplerate`** (Secret Rabbit Code): classic sinc converter with flat frequency response.

For local playback, both provide transparent conversion without audible distortion.

### Why do live streams use FFmpeg's resampler instead?
Live network streams require chunk demuxing, variable bitrates, and dynamic buffering. FFmpeg's `swresample` runs directly inside the decoder pipeline to keep playback steady without extra buffer copies.

### What does 64-bit float processing mode do?
Standard processing uses 32-bit floats (~144 dB dynamic range). 64-bit float mode calculates equalizers, filters, crossfeed, and volume scaling in double precision (>320 dB internal headroom), preventing rounding error accumulation during long effect chains.

### Can I import AutoEQ profiles or custom headphone impulse responses?
Yes. Sautiplay imports AutoEQ profiles (both parametric and graphic curves), Viper4Android VDC/DDC files, and stereo impulse response WAV files via a partitioned convolver for headphone or room correction.

### Can I cast music or use Sautiplay as a wireless receiver?
Yes. Sautiplay can stream to UPnP/DLNA speakers and smart TVs. It also includes a DLNA MediaRenderer service, allowing other devices on your local network to cast audio into Sautiplay.

### Are there ads, tracking, or accounts required?
No. Sautiplay is open source, offline-first, and has no ads, telemetry, or account requirements.

## Community

Join the Telegram group for updates, questions, and discussion:
[Join Sautiplay Telegram Group](https://t.me/+MilnrgkNkbFiYmY0)

## Credits

Sautiplay and Sautiflow build on several open-source projects and algorithms:

- **MATLAB**: used for DSP modeling, filter simulation, and verifying resamplers before C++ implementation.
- **DSP algorithms**:
  - **RBJ Audio EQ Cookbook**: biquad equations for parametric, peaking, shelving, notch, and pass filters.
  - **BS2B (Boris Mikhaylov)**: Bauer stereophonic-to-binaural crossfeed for headphone listening.
  - **Partitioned Overlap-Add FFT Convolution**: frequency-domain convolution for impulse response (.wav) processing.
  - **WSOLA**: time-scale modification for pitch-preserving speed changes.
- **miniaudio** (David Reid): audio device backend (AAudio, WASAPI, CoreAudio, ALSA, PulseAudio).
- **libsamplerate** (Erik de Castro Lopo): sample rate converter for local playback.
- **r8brain-free-src** (Aleksey Vaneev / Voxengo): high-performance sinc sample rate converter.
- **FFmpeg**: network stream demuxing, decoding, and streaming resampling.
- **Flutter & Dart**: UI framework and FFI bindings.

## Support

If you enjoy using Sautiplay or the Sautiflow engine, consider supporting development:

<a href="https://buymeacoffee.com/wambugu" target="_blank"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" alt="Buy Me A Coffee" style="height: 60px !important;width: 217px !important;" ></a>

## License

Sautiplay is open-source software licensed under the GNU General Public License v3.0 (GPL-3.0). See [LICENSE](LICENSE) for details.
