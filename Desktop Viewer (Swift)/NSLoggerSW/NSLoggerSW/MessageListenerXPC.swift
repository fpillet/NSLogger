//
//  MessageListenerXPC.swift
//  NSLoggerSW
//
//  Created by Guillaume Laurent on 03/05/15.
//  Copyright (c) 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

class MessageListenerXPC: NSObject, NSLoggerSW_MessageListenerProtocol {

    // XPC service
    lazy var messageListenerConnection : NSXPCConnection = makeConnection(self)()

    deinit {
        self.messageListenerConnection.invalidate()
    }

    func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(serviceName: "org.telegraph-road.MessageListener")
        connection.remoteObjectInterface = NSXPCInterface(withProtocol: NSLoggerSW_MessageListenerProtocol.self)

        connection.exportedObject = self // so we expose the newConnection and receivedMessage parts

        connection.resume()
        return connection
    }




    func startListener() {
        // unused on this side
    }

    func stopListener() {
        // unused on this side
    }


    func newConnection(connection:LoggerConnectionInfo) {
        println("new connection")
    }

    func receivedMessages(connection: LoggerConnectionInfo, messages: [LoggerMessage]) {
        println("received messages")
    }


}
