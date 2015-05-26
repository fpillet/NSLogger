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


        // Setup XPC service
        //
        messageListener = MessageListenerXPC()
        messageListenerConnection = messageListener?.messageListenerConnection

        if let connection = messageListenerConnection {
            let remoteObjectProxy:AnyObject = connection.remoteObjectProxyWithErrorHandler({ error in
                NSLog("remote proxy error : %@", error)
            })

            if let messageListenerRemoteProxy = remoteObjectProxy as? MessageListenerProtocol {

                messageListenerRemoteProxy.startListener()
            }

        }


        // connect ReactiveCocoa stuff
        //
        let (aSignal, aSink) = Signal<LoggerMessage, NoError>.pipe()

        messageListener!.messageSignal = aSignal
        messageListener!.sink = aSink

        messageListener!.messageSignal!.observe(next: {
            message in
            self.messageCounter++
        })


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

