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
  s.source_files = '../audio_engine.cpp', '../mp4_aac_decoder.cpp', '../third_party/faad2/libfaad/*.c', '../third_party/libsamplerate/src/*.c', '../ViPERDSP/viper/ViPER.cpp', '../ViPERDSP/viper/effects/*.cpp', '../ViPERDSP/viper/utils/*.cpp', '../ViPERDSP/viper/utils/*.c'
  s.public_header_files = '../audio_engine.h'
  s.dependency 'Flutter'
  s.platform = :ios, '12.0'
  s.libraries = 'c++', 'z'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) ',
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) HAVE_INTTYPES_H=1 HAVE_MEMCPY=1 HAVE_STRING_H=1 HAVE_STRINGS_H=1 HAVE_SYS_TYPES_H=1',
    'HEADER_SEARCH_PATHS' => '$(inherited) "${PODS_TARGET_SRCROOT}/../third_party" "${PODS_TARGET_SRCROOT}/../third_party/faad2/include" "${PODS_TARGET_SRCROOT}/../third_party/libsamplerate/include" "${PODS_TARGET_SRCROOT}/../ViPERDSP/include" "${PODS_TARGET_SRCROOT}/../ViPERDSP/viper" "${PODS_TARGET_SRCROOT}/../ViPERDSP/viper/effects" "${PODS_TARGET_SRCROOT}/../ViPERDSP/viper/utils"'
  }

  s.swift_version = '5.0'
end