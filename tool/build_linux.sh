#!/usr/bin/env bash
set -euo pipefail

echo "Building Linux shared library..."
mkdir -p build/linux

EXTRA_CXXFLAGS=""
EXTRA_LDFLAGS=""
if command -v pkg-config >/dev/null 2>&1 && pkg-config --exists libcurl; then
	EXTRA_CXXFLAGS="-DAE_ENABLE_CURL=1 $(pkg-config --cflags libcurl)"
	EXTRA_LDFLAGS="$(pkg-config --libs libcurl)"
	echo "libcurl detected: enabling native URL byte-streaming"
else
	echo "libcurl not found: building without native URL byte-streaming"
fi

g++ -std=c++17 -O2 -fPIC -shared audio_engine.cpp -o build/linux/libaudio_engine.so \
	$EXTRA_CXXFLAGS -lpthread -ldl -lm $EXTRA_LDFLAGS

echo "Done: build/linux/libaudio_engine.so"
