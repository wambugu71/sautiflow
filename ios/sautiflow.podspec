Pod::Spec.new do |s|
  s.name             = 'sautiflow'
  s.version          = '0.1.0'
  s.summary          = 'miniaudio C++ FFI engine for Flutter'
  s.description      = <<-DESC
A cross-platform miniaudio-backed native engine exposed to Flutter through Dart FFI.
                       DESC
  s.homepage         = 'https://github.com/wambugukinyua/miniaudiodart'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'sautiflow' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files = '../audio_engine.cpp', '../mp4_aac_decoder.cpp', '../third_party/faad2/libfaad/*.c', '../third_party/libsamplerate/src/*.c', '../third_party/libsoxr/src/soxr.c', '../third_party/libsoxr/src/data-io.c', '../third_party/libsoxr/src/filter.c', '../third_party/libsoxr/src/cr.c', '../third_party/libsoxr/src/cr32.c', '../third_party/libsoxr/src/cr32s.c', '../third_party/libsoxr/src/cr64.c', '../third_party/libsoxr/src/vr32.c', '../third_party/libsoxr/src/pffft32s.c', '../third_party/libsoxr/src/pffft-wrap.c', '../third_party/libsoxr/src/fft4g32.c', '../third_party/libsoxr/src/fft4g64.c', '../third_party/libsoxr/src/dbesi0.c', '../third_party/libsoxr/src/vr-coefs.c', '../third_party/libsoxr/src/util32s.c', '../ViPERDSP/viper/ViPER.cpp', '../ViPERDSP/viper/effects/*.cpp', '../ViPERDSP/viper/utils/*.cpp', '../ViPERDSP/viper/utils/*.c'
  s.public_header_files = '../audio_engine.h'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.libraries = 'c++', 'z'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -O3 -ffast-math -ftree-vectorize',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) HAVE_INTTYPES_H=1 HAVE_MEMCPY=1 HAVE_STRING_H=1 HAVE_STRINGS_H=1 HAVE_SYS_TYPES_H=1 PACKAGE="libsamplerate" VERSION="0.2.2" ENABLE_SINC_BEST_CONVERTER=1 ENABLE_SINC_MEDIUM_CONVERTER=1 ENABLE_SINC_FAST_CONVERTER=1 SOXR_LIB=1',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../third_party" "${PODS_TARGET_SRCROOT}/../third_party/faad2/include" "${PODS_TARGET_SRCROOT}/../third_party/libsamplerate/include" "${PODS_TARGET_SRCROOT}/../third_party/libsoxr/include" "${PODS_TARGET_SRCROOT}/../third_party/libsoxr/src" "${PODS_TARGET_SRCROOT}/../ViPERDSP/include" "${PODS_TARGET_SRCROOT}/../ViPERDSP/viper" "${PODS_TARGET_SRCROOT}/../ViPERDSP/viper/effects" "${PODS_TARGET_SRCROOT}/../ViPERDSP/viper/utils"'
  }

  s.swift_version = '5.0'
end