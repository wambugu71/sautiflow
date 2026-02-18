# Third-Party Notices

This project may be built with additional third-party native dependencies for optional Android network streaming.

## cURL

- Project: cURL
- Homepage: [https://curl.se/](https://curl.se/)
- Source: [https://github.com/curl/curl](https://github.com/curl/curl)
- Typical license: curl license (see upstream)
- Usage here: optional Android native HTTP streaming support when `MINIAUDIODART_ENABLE_CURL=ON`.

## Transitive dependencies (when statically linking cURL)

Depending on how your prebuilt `libcurl.a` was produced, it may also require and/or include:

- TLS backend (for example OpenSSL, BoringSSL, mbedTLS, or wolfSSL)
- Compression libraries (for example zlib, brotli, zstd)
- Optional transport libraries (for example nghttp2)

You are responsible for:

1. Matching the linker dependency chain for your prebuilt artifacts.
2. Complying with licenses for all bundled transitive dependencies.
3. Shipping corresponding notices/license texts in release artifacts.

## Distribution guidance

When distributing Android builds that include static native dependencies, include a copy of this file (or equivalent notice document) in your release package and app legal/about section.
