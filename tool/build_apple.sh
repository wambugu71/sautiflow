#!/usr/bin/env bash
set -euo pipefail

mkdir -p build/apple/ios build/apple/ios-sim build/apple/macos

EXTRA_CXXFLAGS=""
EXTRA_LDFLAGS=""
if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libcurl; then
  EXTRA_CXXFLAGS="-DAE_ENABLE_CURL=1 $(pkg-config --cflags libcurl)"
  EXTRA_LDFLAGS="$(pkg-config --libs libcurl)"
  echo "libcurl detected: enabling native URL byte-streaming"
else
  echo "libcurl not found: building without native URL byte-streaming"
fi

echo "Building iOS device static library..."
xcrun --sdk iphoneos clang++ -std=c++17 -O2 -fembed-bitcode -arch arm64 $EXTRA_CXXFLAGS -c audio_engine.cpp -o build/apple/ios/audio_engine.o
libtool -static -o build/apple/ios/libaudio_engine.a build/apple/ios/audio_engine.o

echo "Building iOS simulator static library..."
xcrun --sdk iphonesimulator clang++ -std=c++17 -O2 -arch arm64 -arch x86_64 $EXTRA_CXXFLAGS -c audio_engine.cpp -o build/apple/ios-sim/audio_engine.o
libtool -static -o build/apple/ios-sim/libaudio_engine.a build/apple/ios-sim/audio_engine.o

echo "Building macOS dynamic library..."
xcrun --sdk macosx clang++ -std=c++17 -O2 -dynamiclib audio_engine.cpp -o build/apple/macos/libaudio_engine.dylib $EXTRA_CXXFLAGS $EXTRA_LDFLAGS

echo "Creating XCFramework for iOS..."
xcodebuild -create-xcframework \
  -library build/apple/ios/libaudio_engine.a \
  -library build/apple/ios-sim/libaudio_engine.a \
  -output build/apple/audio_engine.xcframework

echo "Done. Outputs:"
echo "  build/apple/audio_engine.xcframework"
echo "  build/apple/macos/libaudio_engine.dylib"
