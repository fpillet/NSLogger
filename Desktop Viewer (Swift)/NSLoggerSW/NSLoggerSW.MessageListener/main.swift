//
//  main.swift
//  NSLoggerSW
//
//  Created by Guillaume Laurent on 03/05/15.
//  Copyright (c) 2015 Guillaume Laurent. All rights reserved.
//

import Foundation

class ServiceDelegate : NSObject, NSXPCListenerDelegate {

    var connection:NSXPCConnection?

    func listener(listener: NSXPCListener, shouldAcceptNewConnection newConnection: NSXPCConnection) -> Bool {
        connection = newConnection
        newConnection.exportedInterface = NSXPCInterface(withProtocol: NSLoggerSW_MessageListenerProtocol.self)
        var exportedObject = MessageListener()
        newConnection.exportedObject = exportedObject
        newConnection.resume()

        // setup app counterpart side
        exportedObject.appCounterPart = newConnection.remoteObjectProxy as? NSLoggerSW_MessageListenerProtocol

        return true
    }
}


// Create the listener and resume it:
//
let delegate = ServiceDelegate()
let listener = NSXPCListener.serviceListener()
listener.delegate = delegate;
listener.resume()
