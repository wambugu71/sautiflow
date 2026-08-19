# Test & Guide: Extracting Direct YouTube Streaming Links

This repository module demonstrates and documents how to extract **direct audio streaming links** directly on-device using Dart, replacing the need for an external hosted scraping API (e.g. `wambugu-music.vercel.app/download?url=...`).

---

## 🚀 Architecture Overview

```
 ┌────────────────────────────────────────────────────────────────────────────────────────┐
 │                                   FLUTTER UI LAYER                                     │
 │  (HomeScreen, SearchScreen, ArtistScreen, AlbumDetailScreen, StreamExtractionTestScreen)│
 └───────────────────────────┬────────────────────────────────┬───────────────────────────┘
                             │ (1. User Searches / Browses)   │ (3. Requests Audio Stream)
                             ▼                                ▼
 ┌─────────────────────────────────────────┐      ┌───────────────────────────────────────┐
 │            dart_ytmusic_api             │      │          youtube_explode_dart         │
 │     (Metadata & Discovery Engine)       │      │     (Stream Resolution & CDN Engine)  │
 ├─────────────────────────────────────────┤      ├───────────────────────────────────────┤
 │ • Autocomplete search suggestions       │      │ • Decodes YouTube stream manifest     │
 │ • Categorized search (songs, artists)   │      │ • Extracts audio-only streams:        │
 │ • Home feeds & charts (8 sections)      │      │   - Tag 139 / 249 (~50 kbps Low)      │
 │ • Artist profiles & full discographies  │      │   - Tag 250 (~70 kbps Medium)         │
 │ • High-res artwork & synchronized lyrics│      │   - Tag 140 (~128 kbps High AAC)      │
 │ • Returns: videoId, name, artist, album │      │   - Tag 251 (~160 kbps Opus Max)      │
 └────────────────────┬────────────────────┘      └───────────────────┬───────────────────┘
                      │                                               │
                      │ 2. Passes 11-char Video ID (e.g. "vbvyNnw8Qjg")│ 4. Direct CDN URL
                      └──────────────────────►────────────────────────┘ (googlevideo.com)
                                                                      │
                                                                      ▼
                                                  ┌───────────────────────────────────────┐
                                                  │       SAUTIFLOW / MINIAUDIO ENGINE    │
                                                  │ (FFmpegStreamDecoder, RingBuffer, DSP)│
                                                  └───────────────────────────────────────┘
```

---

## 📦 Tested Libraries

1. **`youtube_explode_dart`** (Local path: `../youtube_explode_dart`):
   - Reverse-engineers YouTube video/stream manifests without official API keys or quota limits.
   - Extracts direct `googlevideo.com` CDN stream URLs with specific audio containers (`mp4`, `webm`), bitrates, and codecs.
   - Supports live HTTP chunk piping or passing the URL straight to audio decoders.

2. **`dart_ytmusic_api`** (Local path: `../dart_ytmusic_api`):
   - Interacts with YouTube Music Innertube API.
   - Searches songs, albums, artists, playlists.
   - Fetches track duration, high-resolution album artwork, lyrics, and time-synchronized lyrics (`getTimedLyrics`).

---

## 🧪 Test Scripts & UI in this Repository

### 1. Interactive Flutter Test UI: `StreamExtractionTestScreen`
- **Location**: `sautiplay/lib/stream_extraction_test_screen.dart`
- **Launch via**: Header stream icon (`Icons.stream_rounded`) on the Home Screen.
- **Features**:
  - Live query autocomplete & search.
  - Quality preset chips: **Data Saver (~50k)**, **Balanced (~70k)**, **High AAC (~128k)**, and **Audiophile (~160k)**.
  - Full stream manifest table (Itags, Codecs, Bitrates, Sizes in MB).
  - Live HTTP `HEAD` and `Range: bytes=0-65535` buffer connectivity tester.
  - Direct one-tap playback in Sautiflow audio engine.

### 2. `test_bitrate_selection.dart`
Tests adaptive stream selection and preset filters:
```bash
dart run test_extract_streams/test_bitrate_selection.dart
```

### 3. `test_artist_and_album_flow.dart`
Tests full discovery from search $\rightarrow$ artist profile $\rightarrow$ discography $\rightarrow$ album tracks:
```bash
dart run test_extract_streams/test_artist_and_album_flow.dart
```

### 4. `test_home_playlists.dart` & `test_home_playlist_ids.dart`
Tests all 8 home sections (including Quick Picks) and verifies playlist track extraction:
```bash
dart run test_extract_streams/test_home_playlists.dart
```

### 5. `test_extract_streams.dart`
Tests direct stream extraction and HTTP byte-range verification on a single Video ID.
```bash
dart run test_extract_streams/test_extract_streams.dart vbvyNnw8Qjg
```

---

## 🎧 Audio Codecs & Best Format for Sautiflow / Miniaudio

| Quality Tier | Stream Tag / Itag | Container | Codec | Typical Bitrate | Miniaudio Compatibility | Recommendation |
| :--- | :--- | :--- | :--- | :--- | :--- | :--- |
| **Data Saver / Low** | `Tag 139` / `Tag 249` | `MP4` / `WebM` | `mp4a.40.5` / `Opus` | **~48 – 51 kbps** | ✅ | Bandwidth conservation mode |
| **Medium** | `Tag 250` | `WebM` | `Opus` | **~68 – 70 kbps** | ✅ | Standard mobile data |
| **High** | `Tag 140` | `MP4` / `M4A` | `mp4a.40.2` (AAC-LC) | **~128 kbps** | ✅ **Native AAC Decoders** | Recommended for standard AAC hardware decoding |
| **Audiophile** | `Tag 251` | `WebM` | `Opus` | **~135 – 160 kbps**| ✅ **Opus / FFmpeg Decoder**| Highest fidelity audio stream on YouTube |

---

## 🔍 Investigation: Resolving the 400 `INVALID_ARGUMENT` Error

### 1. Root Cause of 400 Error on `getPlaylistVideos` / `browse`
When making requests to YouTube Music's Innertube `browse` endpoint (`https://music.youtube.com/youtubei/v1/browse`), YouTube requires playlist browse IDs to be prefixed with **`VL`** (Video List), e.g.:
- `RDCLAK5uy_...` $\rightarrow$ **`VLRDCLAK5uy_...`**
- `PL4fGSI1pDJn...` $\rightarrow$ **`VLPL4fGSI1pDJn...`**
- `OLAK5uy_...` $\rightarrow$ **`VLOLAK5uy_...`**

If a raw playlist ID without the `VL` prefix was sent to `browseId`:
```json
{ "browseId": "RDCLAK5uy_lnm4v4arFrmL63NUzIdoXJe-E7G4_sriU" }
```
YouTube Innertube responded with:
```json
{
  "error": {
    "code": 400,
    "message": "Request contains an invalid argument.",
    "status": "INVALID_ARGUMENT"
  }
}
```

### 2. The Fix Applied in `dart_ytmusic_api`:
1. **Automated `VL` prefixing**: In `getPlaylist(playlistId)` and `getPlaylistVideos(playlistId)`:
   ```dart
   if (!playlistId.startsWith("VL")) {
     playlistId = "VL$playlistId";
   }
   ```
2. **Proper continuation loop exit**: Fixed the continuation loop so `continuation is! List` doesn't evaluate to `true` on `null`.
3. **Per-Item Parser for Home Sections**: `Parser.parseHomeSection` now parses each item individually rather than relying on a top-level section `pageType`. This correctly parses:
   - `musicResponsiveListItemRenderer` tracks (e.g. "Quick picks" $\rightarrow$ `SongDetailed`)
   - `musicTwoRowItemRenderer` albums (`AlbumDetailed`) and playlists (`PlaylistDetailed`)

---

## 🔐 Account Authentication & Bot Mitigation

1. **OAuth 2.0 Device Code Flow (RFC 8628)**:
   - App requests a user code (`ABCD-EFGH`) and displays `google.com/device` or a QR code.
   - User approves in browser/phone; app securely receives `access_token` and `refresh_token`.
2. **Personalized Features Unlocked**:
   - Liked Songs (`LM` playlist)
   - User Library (`FElibrary` for saved albums, artists, custom playlists)
   - History (`FEhistory`) & tailored recommendations
3. **Bot Detection Mitigation**:
   - Authenticated sessions pass legitimate user credentials (`Authorization: Bearer ...` or `SAPISIDHASH` cookie header), preventing anonymous IP rate-limiting (429) and cipher challenges.

---

## 💡 Important Considerations for YouTube Streaming URLs

1. **Expiration (`expire=...`)**:
   - Direct `googlevideo.com` URLs generated by YouTube typically expire after **6 hours**.
   - For offline caching or long background playback pauses, fetch a fresh manifest if playback resumes after long delays.

2. **Range Requests (`206 Partial Content`)**:
   - The streaming URLs support HTTP `Range` headers (`bytes=start-end`), enabling smooth seeking without redownloading entire tracks.

3. **No External Backend Needed**:
   - Using `youtube_explode_dart` directly on-device eliminates external proxy downloaders, server hosting costs, and points of failure.
