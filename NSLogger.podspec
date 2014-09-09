Pod::Spec.new do |s|
  s.name     = 'NSLogger'
  s.version  = '1.5'
  s.license  = 'BSD'
  s.summary  = 'A modern, flexible logging tool.'
  s.homepage = 'https://github.com/fpillet/NSLogger'
  s.author   = { 'Florent Pillet' => 'fpillet@gmail.com' }
  s.source   = { :git => 'https://github.com/fpillet/NSLogger.git', :tag => 'v1.5' }
  s.screenshot  = "https://github.com/fpillet/NSLogger/raw/master/Screenshots/mainwindow.png"

  s.description = 'NSLogger is a high perfomance logging utility which displays traces emitted by ' \
                  'client applications running on Mac OS X or iOS (iPhone OS). It replaces your '   \
                  'usual NSLog()-based traces and provides powerful additions like display '        \
                  'filtering, image and binary logging, traces buffering, timing information, etc. ' \
                  'Download a prebuilt desktop viewer from https://github.com/fpillet/NSLogger/releases'

  s.source_files = 'Client Logger/iOS/*.{h,m}'
  s.ios.frameworks   = 'CFNetwork', 'SystemConfiguration'
  s.osx.frameworks = 'CFNetwork', 'SystemConfiguration', 'CoreServices'
  
  s.xcconfig = {
    'GCC_PREPROCESSOR_DEFINITIONS' => '$(inherited) NSLOGGER_WAS_HERE=1',
    'GCC_PREPROCESSOR_DEFINITIONS' => '${inherited} NSLOGGER_BUILD_USERNAME="${USER}"'
  }
  
end
