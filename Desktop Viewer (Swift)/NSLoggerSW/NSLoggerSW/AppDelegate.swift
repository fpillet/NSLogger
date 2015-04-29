//
//  AppDelegate.swift
//  NSLoggerSW
//
//  Created by Guillaume Laurent on 20/04/15.
//  Copyright (c) 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

@NSApplicationMain

class AppDelegate: NSObject, NSApplicationDelegate, LoggerConnectionDelegate {

    var transports = [LoggerTransport]()

    var connection:LoggerConnection?

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

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        // Insert code here to initialize your application

        var nativeTransport = LoggerNativeTransport()
        nativeTransport.publishBonjourService = true
        nativeTransport.secure = false
        transports.append(nativeTransport)

        var secureNativeTransport = LoggerNativeTransport()
        secureNativeTransport.publishBonjourService = true
        secureNativeTransport.secure = true
        transports.append(secureNativeTransport)

        startStopTransports()
    }

    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
    }


    func startStopTransports() {
        for transport in transports {
            if let t = transport as? LoggerNativeTransport {

                t.restart() // be more subtle with Bonjour publishing later
            }
        }
    }

    func newConnection(aConnection:LoggerConnection, fromTransport aTransport:LoggerTransport) {

        let foo = encryptionCertificateLoader.serverCerts


        println("new connection received")
        connection = aConnection
        connection?.delegate = self
        connection?.attachedToWindow = true
    }

    func loadEncryptionCertificate(outError : NSErrorPointer) -> Bool {
        return encryptionCertificateLoader.loadEncryptionCertificate(outError)
    }

    //MARK: LoggerConnectionDelegate

    func connection(theConnection: LoggerConnection!, didReceiveMessages theMessages: [AnyObject]!, range rangeInMessagesList: NSRange) {
        println("new message received")
    }
}

