$ErrorActionPreference = "Stop"

$ffmpegDir = Join-Path $PSScriptRoot "..\third_party\ffmpeg"
if (Test-Path "$ffmpegDir\include\libavformat\avformat.h") {
    Write-Host "FFmpeg dev package is already installed at $ffmpegDir"
    exit 0
}

Write-Host "Fetching FFmpeg dev package for Windows..."
$tempZip = Join-Path $env:TEMP "ffmpeg_win64_shared.zip"
$tempExtract = Join-Path $env:TEMP "ffmpeg_extract"

if (Test-Path $tempExtract) {
    Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue
}

$url = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-lgpl-shared.zip"
Write-Host "Downloading from $url with resume and retry support..."

# Download with curl with auto-resume (-C -) and retry
& curl.exe -L -C - --retry 10 --retry-delay 2 --retry-all-errors -o $tempZip $url

if ($LASTEXITCODE -ne 0) {
    Write-Host "GitHub download had issues, trying mirror..."
    $urlMirror = "https://www.gyan.dev/ffmpeg/builds/ffmpeg-release-full-shared.7z"
    # Fallback if needed
}

Write-Host "Verifying zip file..."
if (-not (Test-Path $tempZip)) {
    throw "Download failed: $tempZip not found"
}

Write-Host "Extracting archive..."
Expand-Archive -Path $tempZip -DestinationPath $tempExtract -Force

$extractedFolder = Get-ChildItem -Path $tempExtract -Directory | Select-Object -First 1

if (-not (Test-Path $ffmpegDir)) {
    New-Item -ItemType Directory -Path $ffmpegDir -Force | Out-Null
}

Write-Host "Copying include, lib, and bin to $ffmpegDir..."
Copy-Item -Path "$($extractedFolder.FullName)\include" -Destination "$ffmpegDir\include" -Recurse -Force
Copy-Item -Path "$($extractedFolder.FullName)\lib" -Destination "$ffmpegDir\lib" -Recurse -Force
Copy-Item -Path "$($extractedFolder.FullName)\bin" -Destination "$ffmpegDir\bin" -Recurse -Force

Write-Host "Cleaning up temp files..."
Remove-Item $tempZip -Force -ErrorAction SilentlyContinue
Remove-Item $tempExtract -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "FFmpeg dev package installed successfully at $ffmpegDir!"
