param(
    [string]$NdkHome = $env:ANDROID_NDK_HOME,
    [int]$Api = 24
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($NdkHome)) {
    throw "ANDROID_NDK_HOME is not set. Pass -NdkHome or set env var."
}

$toolchain = Join-Path $NdkHome "toolchains\llvm\prebuilt\windows-x86_64\bin"
if (-not (Test-Path $toolchain)) {
    throw "NDK toolchain not found at $toolchain"
}

$targets = @(
    @{ Abi = "arm64-v8a"; Target = "aarch64-linux-android" },
    @{ Abi = "armeabi-v7a"; Target = "armv7a-linux-androideabi" },
    @{ Abi = "x86_64"; Target = "x86_64-linux-android" }
)

New-Item -ItemType Directory -Force -Path "build\android" | Out-Null

foreach ($t in $targets) {
    $abi = $t.Abi
    $target = $t.Target
    $clang = Join-Path $toolchain ("{0}{1}-clang++.cmd" -f $target, $Api)
    if (-not (Test-Path $clang)) {
        throw "Compiler not found: $clang"
    }

    $outDir = Join-Path "build\android" $abi
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null
    $outLib = Join-Path $outDir "libaudio_engine.so"

    & $clang -std=c++17 -O2 -fPIC -shared audio_engine.cpp -o $outLib -D__ANDROID_API__=$Api
    if ($LASTEXITCODE -ne 0) {
        throw "Build failed for ABI $abi"
    }

    Write-Host "Built $outLib"
}

Write-Host "Done. Android ABI outputs under build/android/."
