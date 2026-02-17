#!/usr/bin/env bash
set -euo pipefail

: "${ANDROID_NDK_HOME:?Set ANDROID_NDK_HOME to your Android NDK path}"

API=24
ABIS=(arm64-v8a armeabi-v7a x86_64)

# Optional: pass extra compiler/linker flags (for example to enable libcurl).
# Example:
#   export AE_EXTRA_CXXFLAGS="-DAE_ENABLE_CURL=1 -I/path/to/curl/include"
#   export AE_EXTRA_LDFLAGS="-L/path/to/curl/libs/arm64-v8a -lcurl -lz"
AE_EXTRA_CXXFLAGS="${AE_EXTRA_CXXFLAGS:-}"
AE_EXTRA_LDFLAGS="${AE_EXTRA_LDFLAGS:-}"

mkdir -p build/android

for ABI in "${ABIS[@]}"; do
  case "$ABI" in
    arm64-v8a)
      TARGET=aarch64-linux-android
      ;;
    armeabi-v7a)
      TARGET=armv7a-linux-androideabi
      ;;
    x86_64)
      TARGET=x86_64-linux-android
      ;;
    *)
      echo "Unsupported ABI: $ABI"; exit 1
      ;;
  esac

  OUT_DIR="build/android/$ABI"
  mkdir -p "$OUT_DIR"

  CLANG="$ANDROID_NDK_HOME/toolchains/llvm/prebuilt/linux-x86_64/bin/${TARGET}${API}-clang++"

  "$CLANG" \
    -std=c++17 -O2 -fPIC -shared \
    audio_engine.cpp \
    -o "$OUT_DIR/libaudio_engine.so" \
    -D__ANDROID_API__=$API \
    $AE_EXTRA_CXXFLAGS \
    $AE_EXTRA_LDFLAGS

  echo "Built $OUT_DIR/libaudio_engine.so"
done
