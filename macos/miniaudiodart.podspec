Pod::Spec.new do |s|
  s.name             = 'miniaudiodart'
  s.version          = '0.1.0'
  s.summary          = 'miniaudio C++ FFI engine for Flutter'
  s.description      = <<-DESC
A cross-platform miniaudio-backed native engine exposed to Flutter through Dart FFI.
                       DESC
  s.homepage         = 'https://example.com'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'miniaudiodart' => 'dev@example.com' }
  s.source           = { :path => '.' }
  s.source_files = '../audio_engine.cpp'
  s.public_header_files = '../audio_engine.h'
  s.dependency 'FlutterMacOS'
  s.platform = :osx, '10.13'

  s.pod_target_xcconfig = {
    'DEFINES_MODULE' => 'YES',
    'CLANG_CXX_LANGUAGE_STANDARD' => 'c++17'
  }

  s.swift_version = '5.0'
end
