//
//  LoggerIPConnection.swift
//  NSLoggerSW
//
//  Created by Guillaume Laurent on 24/04/15.
//  Copyright (c) 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

class LoggerIPConnection: LoggerConnection {

    override func clientAddressDescription() -> String {
        if clientAddress?.length == sizeof(sockaddr_in6) {
            var addr6 = sockaddr_in6()

            clientAddress?.getBytes(&addr6, length: sizeof(sockaddr_in6))

//            let a = addr6.sin6_addr.__u6_addr.__u6_addr16[0]

            // TODO - sin6_add struct is empty in Xcode 6.3.1
            return "IPv6 not yet implemented"
        }

        var addr4 = sockaddr_in()

        clientAddress?.getBytes(&addr4, length: sizeof(sockaddr_in))
        let inetname = inet_ntoa(addr4.sin_addr)
        if inetname != nil {
            var tmpString = NSString(CString: inetname, encoding: NSASCIIStringEncoding)
            return String(tmpString!)
        } else {
            return "<empty>"
        }
    }

}
