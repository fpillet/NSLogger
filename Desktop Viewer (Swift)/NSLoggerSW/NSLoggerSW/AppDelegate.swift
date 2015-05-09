//
//  AppDelegate.swift
//  NSLoggerSW
//
//  Created by Guillaume Laurent on 20/04/15.
//  Copyright (c) 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa

import LlamaKit
import ReactiveCocoa

@NSApplicationMain

class AppDelegate: NSObject, NSApplicationDelegate {

    var messageSignal:Signal<LoggerMessage, NoError>?
    var sink:SinkOf<Event<LoggerMessage, NoError>>?

//    var serverCertsLoadAttempted:Bool {
//        get {
//            return encryptionCertificateLoader.serverCertsLoadAttempted
//        }
//    }
//
//    var serverCerts:CFArray {
//        get {
//            return encryptionCertificateLoader.serverCerts
//        }
//    }
//
//    var encryptionCertificateLoader = EncryptionCertificateLoader()

    func applicationDidFinishLaunching(aNotification: NSNotification) {
        // Insert code here to initialize your application

    }

    func applicationWillTerminate(aNotification: NSNotification) {
        // Insert code here to tear down your application
    }


    func connection(theConnection: LoggerConnectionInfo!, didReceiveMessages theMessages: [AnyObject]!, range rangeInMessagesList: NSRange) {
        println("new message received")

        if let sink = self.sink {
            for msg in theMessages {
                if let message = msg as? LoggerMessage {
                    sendNext(sink, message)
                }
            }
        } else {
            println("got message before app was fully launched, appDelegate.sink not setup yet - this shouldn't be possible")
        }

    }
}

