$ErrorActionPreference = "Stop"

$objDir = "build/obj_standalone"
New-Item -ItemType Directory -Force -Path $objDir | Out-Null
Remove-Item "$objDir/*" -Force -Recurse -ErrorAction SilentlyContinue

$includes = @(
    "-I.",
    "-Ithird_party",
    "-Ithird_party/libsamplerate/include",
    "-Ithird_party/r8brain"
)

$defines = @(
    "-D_USE_MATH_DEFINES",
    "-DNOMINMAX",
    "-DWIN32_LEAN_AND_MEAN",
    '-DPACKAGE_VERSION=\"2.11.1\"',
    '-DPACKAGE=\"libsamplerate\"',
    '-DVERSION=\"0.2.2\"',
    '-DHAVE_INTTYPES_H=1',
    '-DHAVE_MEMCPY=1',
    '-DHAVE_STRING_H=1',
    '-DHAVE_STDBOOL_H=1',
    '-DHAVE_STRINGS_H=1',
    '-DHAVE_SYS_TYPES_H=1',
    '-DENABLE_SINC_BEST_CONVERTER=1',
    '-DENABLE_SINC_MEDIUM_CONVERTER=1',
    '-DENABLE_SINC_FAST_CONVERTER=1'
)

$cFiles = (Get-ChildItem -Path "third_party/libsamplerate/src/*.c" | Select-Object -ExpandProperty FullName)

foreach ($f in $cFiles) {
    $objName = [System.IO.Path]::GetFileNameWithoutExtension($f) + "_" + [System.IO.Path]::GetRandomFileName() + ".o"
    $objPath = Join-Path $objDir $objName
    gcc -O2 -c $f -o $objPath @includes @defines
    if ($LASTEXITCODE -ne 0) { throw "gcc failed on $f" }
}

g++ -std=c++17 -O2 -c test_resampler_standalone.cpp -o "$objDir/test_resampler_standalone.o" @includes @defines
if ($LASTEXITCODE -ne 0) { throw "g++ failed on test_resampler_standalone.cpp" }

$allObjs = Get-ChildItem -Path "$objDir/*.o" | Select-Object -ExpandProperty FullName
g++ -std=c++17 -O2 -o test_resampler_standalone.exe @allObjs -static-libgcc -static-libstdc++ -lm
if ($LASTEXITCODE -ne 0) { throw "Linking test_resampler_standalone.exe failed" }

Write-Host "Running standalone resampler test..."
./test_resampler_standalone.exe
