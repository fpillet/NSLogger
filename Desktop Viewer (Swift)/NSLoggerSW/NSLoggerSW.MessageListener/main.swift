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
        newConnection.exportedInterface = NSXPCInterface(withProtocol: MessageListenerProtocol.self)
        var exportedObject = MessageListener()
        newConnection.exportedObject = exportedObject

        newConnection.remoteObjectInterface = NSXPCInterface(withProtocol: AppMessagePassingProtocol.self)

        newConnection.resume()

        // setup app counterpart side
        exportedObject.appConnection = newConnection

//        let remoteObjectProxy:AnyObject = newConnection.remoteObjectProxyWithErrorHandler({ error in
//            NSLog("remote proxy error : %@", error)
//        })
//
//        if let appRemoteObjectProxy =  remoteObjectProxy as? NSLoggerSW_MessageListenerProtocol {
//            exportedObject.appCounterPart = appRemoteObjectProxy
//        } else {
//            NSLog("appRemoteObjectProxy error - couldn't cast to NSLoggerSW_MessageListenerProtocol")
//        }

        return true
    }
}


// Create the listener and resume it:
//
let delegate = ServiceDelegate()
let listener = NSXPCListener.serviceListener()
listener.delegate = delegate;
listener.resume()
