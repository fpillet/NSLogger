//
//  SwiftLoggerClient.swift
//  NSLoggerTestApp
//
//  Created by Guillaume Laurent on 09/04/15.
//
//

import Foundation

class SwiftLoggerClient {

    class func logMessage(message:String) {
        #if DEBUG
        LogMessageRaw(message)
        #endif
    }

//    class func logMessage(#domain:String, level:Int32, format:String, args:CVarArgType ...) {
//        #if DEBUG
//            let vaArgs = getVaList(args)
//            LogMessage_va(domain, level, format, vaArgs)
//        #endif
//    }

    class func logMessage(#domain:String, level:Int32, @autoclosure format: () -> String) {
        #if DEBUG
            let vaArgs = getVaList([format()])
            LogMessage_va(domain, level, "%@", vaArgs)
        #endif
    }


    class func logMessage(#filename:String, lineNumber:Int32, functionName:String, domain:String, level:Int32, @autoclosure format: () -> String) {
        #if DEBUG
        let vaArgs = getVaList([format()])

        let fileNameCstr = stringToCStr(filename)
        let functionNameCstr = stringToCStr(functionName)

        LogMessageF_va(fileNameCstr, lineNumber, functionNameCstr, domain, level, "%@", vaArgs)
        #endif
    }


    class func logData(#domain:String, level:Int32, @autoclosure data: () -> NSData) {
        #if DEBUG
        LogData(domain, level, data())
        #endif
    }

    class func logData(#filename:String, lineNumber:Int32, functionName:String, domain:String, level:Int32, @autoclosure data: () -> NSData) {
        #if DEBUG
            let fileNameCstr = stringToCStr(filename)
            let functionNameCstr = stringToCStr(functionName)
            LogDataF(fileNameCstr, lineNumber, functionNameCstr, domain, level, data())
        #endif
    }

    class func logImageData(#domain:String, level:Int32, width:Int32, height:Int32, @autoclosure data: () -> NSData) {
        #if DEBUG
            LogImageData(domain, level, width, height, data())
        #endif
    }

    class func logImageData(#filename:String, lineNumber:Int32, functionName:String, domain:String, level:Int32, width:Int32, height:Int32, @autoclosure data: () -> NSData) {
        #if DEBUG
            let fileNameCstr = stringToCStr(filename)
            let functionNameCstr = stringToCStr(functionName)
            LogImageDataF(fileNameCstr, lineNumber, functionNameCstr, domain, level, width, height, data())
        #endif
    }
    

    private class func stringToCStr(string:String) -> UnsafePointer<Int8> {
        let cfStr = string as NSString
        return cfStr.cStringUsingEncoding(NSASCIIStringEncoding)
    }
}
