require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name          = 'RNShellUpdates'
  s.version       = package['version']
  s.summary       = package['description']
  s.homepage      = 'https://github.com/bhoos/ReactNativeShell'
  s.license       = 'MIT'
  s.author        = 'Bhoos'
  s.platform      = :ios, '15.1'
  s.source        = { :path => '.' }
  s.source_files  = 'ios/**/*.{h,m,mm}', 'cpp/**/*.{h,cpp}'
  # The AppDelegate (Swift) imports the launcher only: its header is plain Objective-C
  s.public_header_files = 'ios/RNShellUpdatesLauncher.h'
  s.frameworks    = 'Security'
  s.pod_target_xcconfig = { 'DEFINES_MODULE' => 'YES' }

  install_modules_dependencies(s)
end
