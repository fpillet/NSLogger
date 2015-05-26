//
//  MessageListenerXPC.swift
//  NSLoggerSW
//
//  Created by Guillaume Laurent on 03/05/15.
//  Copyright (c) 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa
import ReactiveCocoa

class MessageListenerXPC: NSObject, AppMessagePassingProtocol {

    var messageSignal:Signal<LoggerMessage, NoError>?
    var sink:SinkOf<Event<LoggerMessage, NoError>>?

    // XPC service
    lazy var messageListenerConnection : NSXPCConnection = makeConnection(self)()

    deinit {
        self.messageListenerConnection.invalidate()
    }

    func makeConnection() -> NSXPCConnection {
        let connection = NSXPCConnection(serviceName: "org.telegraph-road.MessageListener")
        connection.remoteObjectInterface = NSXPCInterface(withProtocol: MessageListenerProtocol.self)

        let aClass = LoggerNativeMessage.self

        let interface = NSXPCInterface(withProtocol: AppMessagePassingProtocol.self)

        let currentExpectedClasses = interface.classesForSelector("receivedMessages:messages:", argumentIndex: 1, ofReply: false) as NSSet

        let allClasses = currentExpectedClasses.setByAddingObject(LoggerNativeMessage.self)

        interface.setClasses(allClasses as Set<NSObject>, forSelector: "receivedMessages:messages:", argumentIndex: 1, ofReply: false)
        connection.exportedInterface = interface
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

        if let sink = self.sink {
            for msg in messages {
                if let message = msg as? LoggerMessage {
                    sendNext(sink, message)
                }
            }
        }
    }


}
