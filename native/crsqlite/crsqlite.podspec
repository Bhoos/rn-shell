require 'json'

package = JSON.parse(File.read(File.join(__dir__, 'package.json')))

Pod::Spec.new do |s|
  s.name          = 'crsqlite'
  s.version       = package['version']
  s.summary       = 'Custom local build of cr-sqlite for iOS'
  s.homepage      = 'https://github.com/bhoos/cr-sqlite'
  s.license       = 'MIT'
  s.author        = 'Bhoos'
  s.platform      = :ios, '13.0'
  
  s.source        = { :path => './ios' }
  s.vendored_frameworks = 'ios/crsqlite.xcframework'
end
