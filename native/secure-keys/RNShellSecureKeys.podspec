require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name          = 'RNShellSecureKeys'
  s.version       = package['version']
  s.summary       = package['description']
  s.homepage      = 'https://github.com/bhoos/ReactNativeShell'
  s.license       = 'MIT'
  s.author        = 'Bhoos'
  s.platform      = :ios, '15.1'
  s.source        = { :path => '.' }
  s.source_files  = 'ios/**/*.{h,m,mm}'
  s.frameworks    = 'Security', 'DeviceCheck'

  install_modules_dependencies(s)
end
