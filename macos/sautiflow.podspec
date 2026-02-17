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
  s.source_files = '../audio_engine.cpp'
  s.public_header_files = '../audio_engine.h'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.13'
  s.libraries = 'c++', 'z', 'curl'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17',
    'OTHER_CPLUSPLUSFLAGS' => '$(inherited) -DAE_ENABLE_CURL=1'
  }

  s.swift_version = '5.0'
end