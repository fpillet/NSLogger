/*
 * NSLogger.swift
 *
 * version 1.8.3 8-MAY-2017
 *
 * Part of NSLogger (client side)
 * https://github.com/fpillet/NSLogger
 *
 * BSD license follows (http://www.opensource.org/licenses/bsd-license.php)
 *
 * Copyright (c) 2010-2017 Florent Pillet All Rights Reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * Redistributions of  source code  must retain  the above  copyright notice,
 * this list of  conditions and the following  disclaimer. Redistributions in
 * binary  form must  reproduce  the  above copyright  notice,  this list  of
 * conditions and the following disclaimer  in the documentation and/or other
 * materials  provided with  the distribution.  Neither the  name of  Florent
 * Pillet nor the names of its contributors may be used to endorse or promote
 * products  derived  from  this  software  without  specific  prior  written
 * permission.  THIS  SOFTWARE  IS  PROVIDED BY  THE  COPYRIGHT  HOLDERS  AND
 * CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT
 * NOT LIMITED TO, THE IMPLIED  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A  PARTICULAR PURPOSE  ARE DISCLAIMED.  IN  NO EVENT  SHALL THE  COPYRIGHT
 * HOLDER OR  CONTRIBUTORS BE  LIABLE FOR  ANY DIRECT,  INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY,  OR CONSEQUENTIAL DAMAGES (INCLUDING,  BUT NOT LIMITED
 * TO, PROCUREMENT  OF SUBSTITUTE GOODS  OR SERVICES;  LOSS OF USE,  DATA, OR
 * PROFITS; OR  BUSINESS INTERRUPTION)  HOWEVER CAUSED AND  ON ANY  THEORY OF
 * LIABILITY,  WHETHER  IN CONTRACT,  STRICT  LIABILITY,  OR TORT  (INCLUDING
 * NEGLIGENCE  OR OTHERWISE)  ARISING  IN ANY  WAY  OUT OF  THE  USE OF  THIS
 * SOFTWARE,   EVEN  IF   ADVISED  OF   THE  POSSIBILITY   OF  SUCH   DAMAGE.
 *
 */

import Foundation

#if os(iOS) || os(tvOS)

import UIKit

#endif
#if os(OSX)

import Cocoa

#endif

public enum LoggerDomain {
	case App
	case View
	case Layout
	case Controller
	case Routing
	case Service
	case Network
	case Model
	case Cache
	case DB
	case IO
	case Custom(String)

	var rawValue: String {
		switch self {
			case .App: return "App"
			case .View: return "View"
			case .Layout: return "Layout"
			case .Controller: return "Controller"
			case .Routing: return "Routing"
			case .Service: return "Service"
			case .Network: return "Network"
			case .Model: return "Model"
			case .Cache: return "Cache"
			case .DB: return "DB"
			case .IO: return "IO"
			case let .Custom(customDomain): return customDomain
		}
	}
}

public enum LoggerLevel: Int32 {
	case Error = 0
	case Warning = 1
	case Important = 2
	case Info = 3
	case Debug = 4
	case Verbose = 5
	case Noise = 6
}

/*
* Log a string to display in the viewer
*
*/
public func Log(_ domain: LoggerDomain, _ level: LoggerLevel, _ format: @autoclosure () -> String,
				_ filename: String = #file, lineNumber: Int32 = #line, fnName: String = #function) {
#if !NSLOGGER_DISABLED || NSLOGGER_ENABLED
	let vaArgs = getVaList([format()])

	let fileNameCstr = stringToCStr(filename)
	let fnNameCstr = stringToCStr(fnName)

	LogMessageF_va(fileNameCstr, lineNumber, fnNameCstr,
				   domain.rawValue, level.rawValue,
				   "%@", vaArgs)

#endif
}

/*
* Log an iOS / tvOS UIImage to display in the viewer
*
*/
#if os(iOS) || os(tvOS)

public func LogImage(_ domain: LoggerDomain, _ level: LoggerLevel, _ image: @autoclosure () -> UIImage,
					 _ filename: String = #file, lineNumber: Int32 = #line, fnName: String = #function) {
#if !NSLOGGER_DISABLED || NSLOGGER_ENABLED
	let image = image()
	let imageData = UIImagePNGRepresentation(image)
	let fileNameCstr = stringToCStr(filename)
	let fnNameCstr = stringToCStr(fnName)
	LogImageDataF(fileNameCstr, lineNumber, fnNameCstr,
				  domain.rawValue, level.rawValue,
				  Int32(image.size.width), Int32(image.size.height), imageData)
#endif
}

#endif

/*
* Log a macOS NSImage to display in the viewer
*
*/
#if os(OSX)

public func LogImage(_ domain: LoggerDomain, _ level: LoggerLevel, _ image: @autoclosure () -> NSImage,
					 _ filename: String = #file, lineNumber: Int32 = #line, fnName: String = #function) {
#if !NSLOGGER_DISABLED || NSLOGGER_ENABLED
	let image = image()
	let width = image.size.width
	let height = image.size.height
	guard
		let tiff = image.tiffRepresentation,
		let bitmapRep = NSBitmapImageRep(data: tiff),
		let imageData = bitmapRep.representation(using: NSPNGFileType, properties: [:]) else {
		return
	}
	let fileNameCstr = stringToCStr(filename)
	let fnNameCstr = stringToCStr(fnName)
	LogImageDataF(fileNameCstr, lineNumber, fnNameCstr,
				  domain.rawValue, level.rawValue,
				  Int32(width), Int32(height), imageData)
#endif
}

#endif

/*
* Log a binary block of data to a binary representation in the viewer
*
*/
public func LogData(filename: String, lineNumber: Int32, functionName: String,
					domain: LoggerDomain, level: LoggerLevel, data: @autoclosure () -> Data) {
#if !NSLOGGER_DISABLED || NSLOGGER_ENABLED
	let fileNameCstr = stringToCStr(filename)
	let functionNameCstr = stringToCStr(functionName)
	LogDataF(fileNameCstr, lineNumber, functionNameCstr,
			 domain.rawValue, level.rawValue, data())
#endif
}


fileprivate func stringToCStr(_ string: String) -> UnsafePointer<Int8> {
	let cfStr = string as NSString
	return cfStr.cString(using: String.Encoding.ascii.rawValue)!
}


