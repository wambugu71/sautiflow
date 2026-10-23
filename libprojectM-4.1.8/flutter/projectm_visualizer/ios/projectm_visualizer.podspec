#
# To learn more about a Podspec see http://guides.cocoapods.org/syntax/podspec.html.
# Run `pod lib lint projectm_visualizer.podspec` to validate before publishing.
#
Pod::Spec.new do |s|
  s.name             = 'projectm_visualizer'
  s.version          = '0.0.1'
  s.summary          = 'Milkdrop audio visualizations for Flutter iOS, powered by libprojectM.'
  s.description      = <<-DESC
Milkdrop audio visualizations for Flutter iOS, powered by libprojectM.
                       DESC
  s.homepage         = 'https://github.com/projectM-visualizer/projectm'
  s.license          = { :file => '../LICENSE' }
  s.author           = { 'projectM Visualizer Team' => 'https://github.com/projectM-visualizer/projectm' }

  s.source           = { :path => '.' }
  s.source_files     = 'Classes/**/*'
  s.dependency 'Flutter'

  s.platform = :ios, '13.0'
  s.frameworks = 'OpenGLES', 'CoreAudio', 'AudioToolbox', 'AVFoundation'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES', 'EXCLUDED_ARCHS[sdk=iphonesimulator*]' => 'i386' }
  s.swift_version = '5.0'
end
