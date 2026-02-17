param(
    [string]$Configuration = "Release"
)

$ErrorActionPreference = "Stop"

Write-Host "Building Windows DLL..."

$curlCflags = ""
$curlLibs = ""
try {
    $null = (Get-Command pkg-config -ErrorAction Stop)
    pkg-config --exists libcurl
    if ($LASTEXITCODE -eq 0) {
        $curlCflags = "-DAE_ENABLE_CURL=1 " + (pkg-config --cflags libcurl)
        $curlLibs = (pkg-config --libs libcurl)
        Write-Host "libcurl detected: enabling native URL byte-streaming"
    }
}
catch {
}

if ([string]::IsNullOrWhiteSpace($curlCflags)) {
    Write-Host "libcurl not found: building without native URL byte-streaming"
}

g++ -std=c++17 -O2 -shared -o audio_engine.dll audio_engine.cpp $curlCflags -static-libgcc -static-libstdc++ -lwinmm -lpthread $curlLibs

New-Item -ItemType Directory -Force -Path "build\windows" | Out-Null
Copy-Item "audio_engine.dll" "build\windows\audio_engine.dll" -Force

Write-Host "Done: build/windows/audio_engine.dll"
