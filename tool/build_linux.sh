#!/usr/bin/env bash
set -euo pipefail

echo "Building Linux shared library..."
mkdir -p build/linux

g++ -std=c++17 -O2 -fPIC -shared audio_engine.cpp -o build/linux/libaudio_engine.so -lpthread -ldl -lm

echo "Done: build/linux/libaudio_engine.so"
