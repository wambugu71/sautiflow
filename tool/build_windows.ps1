param(
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"

Write-Host "Building Windows DLL..."

g++ -std=c++17 -O2 -shared -o audio_engine.dll audio_engine.cpp -static-libgcc -static-libstdc++ -lwinmm -lpthread

New-Item -ItemType Directory -Force -Path "build\windows" | Out-Null
Copy-Item "audio_engine.dll" "build\windows\audio_engine.dll" -Force

Write-Host "Done: build/windows/audio_engine.dll"
