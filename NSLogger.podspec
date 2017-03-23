Pod::Spec.new do |s|
  s.name     = 'NSLogger'
  s.version  = '1.8.0'
  s.license  = 'BSD'
  s.summary  = 'A modern, flexible logging tool.'
  s.homepage = 'https://github.com/fpillet/NSLogger'
  s.author   = { 'Florent Pillet' => 'fpillet@gmail.com' }
  s.source   = { :git => 'https://github.com/fpillet/NSLogger.git', :tag => 'v1.8.0' }
  s.screenshot  = "https://github.com/fpillet/NSLogger/raw/master/Screenshots/mainwindow.png"

  s.description = 'NSLogger is a high perfomance logging utility which displays traces emitted by ' \
                  'client applications running on Mac OS X or iOS (iPhone OS). It replaces your '   \
                  'usual NSLog()-based traces and provides powerful additions like display '        \
                  'filtering, image and binary logging, traces buffering, timing information, etc. ' \
                  'Download a prebuilt desktop viewer from https://github.com/fpillet/NSLogger/releases'

  s.ios.deployment_target  = '8.0'
  s.osx.deployment_target  = '10.10'
  s.tvos.deployment_target = '9.0'
  
  s.ios.frameworks   = 'CFNetwork', 'SystemConfiguration'
  s.osx.frameworks = 'CFNetwork', 'SystemConfiguration', 'CoreServices'
  s.requires_arc = false
  
  s.default_subspec = 'Standard'

  # The 'Standard' subspec is the default: unused NSLogger functions will be stripped
  # from the final build
  s.subspec 'Standard' do |standard|
    standard.source_files = 'Client Logger/iOS/*.{h,m,swift}'
    standard.xcconfig = {
      'GCC_PREPROCESSOR_DEFINITIONS' => '${inherited} NSLOGGER_WAS_HERE=1 NSLOGGER_BUILD_USERNAME="${USER}"'
    }
    standard.pod_target_xcconfig = {
        'OTHER_SWIFT_FLAGS[config=Release]' => '$(inherited) -DNSLOGGER_DISABLED'
    }
  end
  
  # The 'NoStrip' subspec prevents unused functions from being stripped by the linker.
  # this is useful when other frameworks linked into the application dynamically look for
  # NSLogger functions and use them if present.
  s.subspec 'NoStrip' do |nostrip|
    nostrip.source_files = 'Client/iOS/*.{h,m,swift}'
    nostrip.xcconfig = {
      'GCC_PREPROCESSOR_DEFINITIONS' => '${inherited} NSLOGGER_WAS_HERE=1 NSLOGGER_BUILD_USERNAME="${USER}" NSLOGGER_ALLOW_NOSTRIP=1'
    }
    nostrip.pod_target_xcconfig = {
        'OTHER_SWIFT_FLAGS[config=Release]' => '$(inherited) -DNSLOGGER_DISABLED'
    }
  end

  # The 'NoSwift' subspec is the legacy ObjC only version: no Swift code will be added to your project.
  s.subspec 'NoSwift' do |noswift|
    noswift.source_files = 'Client Logger/iOS/*.{h,m}'
    noswift.xcconfig = {
      'GCC_PREPROCESSOR_DEFINITIONS' => '${inherited} NSLOGGER_WAS_HERE=1 NSLOGGER_BUILD_USERNAME="${USER}"'
    }
  end

end
