Pod::Spec.new do |s|
  s.name     = 'NSLogger'
  s.version  = '1.8.3'
  s.license  = 'BSD'
  s.summary  = 'A modern, flexible logging tool.'
  s.homepage = 'https://github.com/fpillet/NSLogger'
  s.author   = { 'Florent Pillet' => 'fpillet@gmail.com' }
  s.source   = { :git => 'https://github.com/fpillet/NSLogger.git', :tag => 'v1.8.3' }
  s.screenshot  = "https://github.com/fpillet/NSLogger/raw/master/Screenshots/mainwindow.png"

  s.description = 'NSLogger is a high perfomance logging utility which displays traces emitted by ' \
                  'client applications running on Mac OS X or iOS (iPhone OS). It replaces your '   \
                  'usual NSLog()-based traces and provides powerful additions like display '        \
                  'filtering, image and binary logging, traces buffering, timing information, etc. ' \
                  'Download a prebuilt desktop viewer from https://github.com/fpillet/NSLogger/releases'

  s.ios.deployment_target  = '8.0'
  s.osx.deployment_target  = '10.10'
  s.tvos.deployment_target = '9.0'
  
  s.requires_arc = false
  
  s.default_subspec = 'Default'

  # The 'Default' subspec is the default: has C / Obj-C support
  # unused NSLogger functions will be stripped from the final build
  s.subspec 'Default' do |ss|
    ss.source_files = 'Client/iOS/*.{h,m}'
	ss.public_header_files = 'Client/iOS/*.h'
	ss.ios.frameworks = 'CFNetwork', 'SystemConfiguration', 'UIKit'
	ss.osx.frameworks = 'CFNetwork', 'SystemConfiguration', 'CoreServices', 'AppKit'
    ss.xcconfig = {
      'GCC_PREPROCESSOR_DEFINITIONS' => '${inherited} NSLOGGER_WAS_HERE=1 NSLOGGER_BUILD_USERNAME="${USER}"'
    }
    ss.pod_target_xcconfig = {
        'OTHER_SWIFT_FLAGS[config=Release]' => '$(inherited) -DNSLOGGER_DISABLED'
    }
  end
  

  # The 'Swift' subspec is the legacy ObjC only version: no Swift code will be added to your project.
  # Since there's a direct dependency on 'NSLogger/Default', Swift developers can simply include
  # 'NSLogger/Swift' in their Podfile
  s.subspec 'Swift' do |ss|
    ss.ios.deployment_target  = '8.0'
    ss.osx.deployment_target  = '10.10'
    ss.tvos.deployment_target = '9.0'
	ss.dependency 'NSLogger/Default'
    ss.source_files = 'Client/iOS/*.swift'
  end
  
  # The 'NoStrip' subspec prevents unused functions from being stripped by the linker.
  # this is useful when other frameworks linked into the application dynamically look for
  # NSLogger functions and use them if present. Use 'NSLogger/NoStrip' instead of regular
  # 'NSLogger' pod, add 'NSLogger/Swift' as needed.
  s.subspec 'NoStrip' do |ss|
  	ss.dependency 'NSLogger/Default'
    ss.xcconfig = {
      'GCC_PREPROCESSOR_DEFINITIONS' => '${inherited} NSLOGGER_ALLOW_NOSTRIP=1'
    }
  end

end
