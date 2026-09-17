# Third-Party Notices

This project incorporates, links against, or builds with several open-source libraries and algorithms. Below are the attributions and license notices for these components:

---

## C / C++ Engine Dependencies

### FFmpeg
- **Project:** FFmpeg
- **Website:** https://ffmpeg.org/
- **License:** GNU Lesser General Public License v2.1 or later (LGPLv2.1+ / LGPLv3)
- **Usage:** Stream and local file demuxing, audio decoding (AAC, MP4, M4A, etc.), and network stream resampling via dynamic linking (`libavformat`, `libavcodec`, `libavutil`, `libswresample`).

### miniaudio
- **Project:** miniaudio
- **Author:** David Reid
- **Website:** https://miniaud.io/
- **License:** Choice of Public Domain (Unlicense) or MIT-0 (MIT No Attribution).
- **Usage:** Cross-platform hardware audio backends and device stream routing.

### r8brain-free-src
- **Project:** r8brain-free-src
- **Author:** Aleksey Vaneev (Voxengo)
- **Website:** https://github.com/avaneev/r8brain-free-src
- **License:** MIT License
- **Usage:** High-performance, audiophile-grade sinc sample rate conversion.

### libsamplerate
- **Project:** libsamplerate (Secret Rabbit Code)
- **Author:** Erik de Castro Lopo
- **License:** BSD 2-Clause License
- **Usage:** Audiophile sinc sample rate conversion (Sinc Best / Medium / Fastest).

### libsoxr
- **Project:** SoX Resampler Library
- **Author:** Rob Sykes
- **License:** GNU Lesser General Public License v2.1 or later (LGPLv2.1+)
- **Usage:** High-quality resampling algorithms.

### cURL (Optional / Android Network Streaming)
- **Project:** cURL
- **Homepage:** https://curl.se/
- **License:** curl License (MIT/X derivate)
- **Usage:** Optional native HTTP/HTTPS streaming on Android (`MINIAUDIODART_ENABLE_CURL=ON`).
- *Note on transitive dependencies:* If statically linking prebuilt `libcurl.a`, dependencies may include mbedTLS (Apache-2.0 / GPL-2.0+), OpenSSL, or zlib.

---

## Dart / Flutter Dependencies

### dart_ytmusic_api
- **Project:** dart_ytmusic_api
- **Source:** https://github.com/MusilyApp/dart_ytmusic_api
- **License:** GNU General Public License v3.0 (GPL-3.0)
- **Usage:** YouTube Music metadata search, albums, and artist exploration in Sautiplay.

### youtube_explode_dart
- **Project:** youtube_explode_dart
- **Author:** Mattia
- **License:** BSD 3-Clause License
- **Usage:** YouTube audio stream extraction.

### dlna_dart
- **Project:** dlna_dart
- **License:** BSD 3-Clause License
- **Usage:** UPnP/DLNA media renderer and discovery.

### audio_metadata_reader
- **Project:** audio_metadata_reader
- **Author:** Clément Béal
- **License:** MIT License
- **Usage:** Parsing ID3, Vorbis, and FLAC track tags.

### material_3_expressive
- **Project:** material_3_expressive
- **Author:** Paa Developments
- **License:** MIT License
- **Usage:** Modern Material Design 3 Expressive UI components.

---

## Distribution Guidance

When distributing compiled application packages (such as APKs, Linux tarballs, or Windows installers), this notice file should be included in release distributions alongside the primary [LICENSE](LICENSE) file.
