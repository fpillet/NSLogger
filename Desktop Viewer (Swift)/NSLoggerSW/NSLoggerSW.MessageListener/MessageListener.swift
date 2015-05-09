//
//  NSLoggerSW_MessageListener.swift
//  NSLoggerSW
//
//  Created by Guillaume Laurent on 03/05/15.
//  Copyright (c) 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa


class MessageListener: NSObject, NSLoggerSW_MessageListenerProtocol, LoggerTransportDelegate, LoggerConnectionDelegate {

    static let sharedInstance = MessageListener()

    var appCounterPart:NSLoggerSW_MessageListenerProtocol? // same object on the app side to talk back to the app when new connection and messages are received

    var transports = [LoggerTransport]()

    var serverCertsLoadAttempted:Bool {
        get {
            return encryptionCertificateLoader.serverCertsLoadAttempted
        }
    }

    var serverCerts:CFArray {
        get {
            return encryptionCertificateLoader.serverCerts
        }
    }

    var encryptionCertificateLoader = EncryptionCertificateLoader()


    override init() {

        super.init()

        var nativeTransport = LoggerNativeTransport()
        nativeTransport.publishBonjourService = true
        nativeTransport.secure = false
        nativeTransport.delegate = self
        transports.append(nativeTransport)

        var secureNativeTransport = LoggerNativeTransport()
        secureNativeTransport.publishBonjourService = true
        secureNativeTransport.secure = true
        secureNativeTransport.delegate = self
        transports.append(secureNativeTransport)

    }

    func startStopTransports() {
        for transport in transports {
            if let t = transport as? LoggerNativeTransport {

                t.restart() // be more subtle with Bonjour publishing later
            }
        }
    }


    func startListener() {
        for transport in transports {
            if let t = transport as? LoggerNativeTransport {

                t.restart() // be more subtle with Bonjour publishing later
            }
        }
    }

    func stopListener() {
        for transport in transports {
            if let t = transport as? LoggerNativeTransport {

                t.shutdown()
            }
        }
    }


    func newConnection(connection:LoggerConnectionInfo) {
        // unused on this side
        assert(false, "newConnection shouldn't be called here (XPC service side)")
    }

    func receivedMessages(connection: LoggerConnectionInfo, messages: [LoggerMessage]) {
        // unused on this side
        assert(false, "recievedMessages shouldn't be called here (XPC service side)")
    }

    func loadEncryptionCertificate(outError : NSErrorPointer) -> Bool {
        return encryptionCertificateLoader.loadEncryptionCertificate(outError)
    }

    // MARK: LoggerTransportDelegate
    func attachConnection(connection: LoggerConnection!, fromTransport: LoggerTransport!) {
        println("NSLoggerSW_MessageListener attachConnection")

        let connectionInfo = connection.connectionInfo

        appCounterPart?.newConnection(connectionInfo)

    }

    // MARK: LoggerConnectionDelegate
    func connection(theConnection: LoggerConnection!, didReceiveMessages theMessages: [AnyObject]!, range rangeInMessagesList: NSRange) {
        let connectionInfo = theConnection.connectionInfo

        if let messages = theMessages as? [LoggerMessage] {
            appCounterPart?.receivedMessages(connectionInfo, messages:messages)
        }
        
    }

}
