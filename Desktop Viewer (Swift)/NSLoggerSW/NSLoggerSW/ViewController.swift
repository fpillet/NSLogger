//
//  ViewController.swift
//  NSLoggerSW
//
//  Created by Guillaume Laurent on 20/04/15.
//  Copyright (c) 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa
import ReactiveCocoa

class ViewController: NSViewController {

    dynamic var messageCounter = 0

    var messageListener:MessageListenerXPC?
    var messageListenerConnection:NSXPCConnection?

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.

        if let appDelegate = NSApplication.sharedApplication().delegate as? AppDelegate {

            let (aSignal, aSink) = Signal<LoggerMessage, NoError>.pipe()

            appDelegate.messageSignal = aSignal
            appDelegate.sink = aSink

            appDelegate.messageSignal!.observe(next: {
                message in
                self.messageCounter++
            })
        }

        messageListener = MessageListenerXPC()
        messageListenerConnection = messageListener?.messageListenerConnection

        if let connection = messageListenerConnection {
            let remoteObjectProxy = connection.remoteObjectProxyWithErrorHandler({ error in
                NSLog("remote proxy error : %@", error)
            }) as! NSLoggerSW_MessageListenerProtocol

            remoteObjectProxy.startListener()

        }

    }

    override var representedObject: AnyObject? {
        didSet {
        // Update the view, if already loaded.
        }
    }


    @IBAction func testCounterIncrement(sender: AnyObject) {
        messageCounter++
    }
}

