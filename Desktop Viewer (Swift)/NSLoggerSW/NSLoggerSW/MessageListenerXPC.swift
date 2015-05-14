//
//  MessageListenerXPC.swift
//  NSLoggerSW
//
//  Created by Guillaume Laurent on 03/05/15.
//  Copyright (c) 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

class MessageListenerXPC: NSObject, AppMessagePassingProtocol {

    // XPC service
    lazy var messageListenerConnection : NSXPCConnection = makeConnection(self)()

    deinit {
        self.messageListenerConnection.invalidate()
    }

    func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(serviceName: "org.telegraph-road.MessageListener")
        connection.remoteObjectInterface = NSXPCInterface(withProtocol: MessageListenerProtocol.self)

        // so we expose the newConnection and receivedMessage parts
        //
        connection.exportedInterface = NSXPCInterface(withProtocol: AppMessagePassingProtocol.self)
        connection.exportedObject = self

        connection.resume()
        return connection
    }

    func listenerStarted() {
        NSLog("listenerStarted")
    }

    func ping(message:String) {
        NSLog("ping received \(message)")
    }

    func newConnection(connectionInfo:NSDictionary) {
        NSLog("MessageListenerXPC : new connection")
    }

    func receivedMessages(connectionInfo: NSDictionary, messages: NSArray) {
        NSLog("MessageListenerXPC : received messages")
    }


}
