//
//  LoggerMessage.swift
//  NSLoggerSW
//
//  Created by Guillaume Laurent on 22/04/15.
//  Copyright (c) 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

enum LogMsgType {
    case Log
    case BlockStart
    case BlockEnd
    case ClientInfo
    case Disconnect
    case Mark
}


enum LogMsgContentsType {
    case TypeString
    case TypeData
    case TypeImage
}

enum LogMsgClientInfo : Int {
    case ClientName     = 20
    case ClientVersion // 21
    case OSName        // 22
    case OSVersion     // 23
    case ClientModel   // 24
    case UniqueId      // 25
}

class LoggerMessage: NSObject, NSCoding {

    var tag:String?
    var filename:String?
    var functionName:String?
    var parts = [LogMsgClientInfo:AnyObject]()
    var message:AnyObject?
    var image:NSImage?

    var sequence:UInt = 0
    var threadId:String?

    var lineNumber:Int = 0

    var level:Int8 = 0
    var type:LogMsgType = .Log
    var contentsType:LogMsgContentsType = .TypeString

    var imageSize:NSSize?
    var cachedCellSize:NSSize?


    // TODO

    required init(coder aDecoder: NSCoder) {

    }

    func encodeWithCoder(aCoder: NSCoder) {
        // TODO
    }

}
