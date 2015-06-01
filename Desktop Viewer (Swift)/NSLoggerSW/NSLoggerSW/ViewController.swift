//
//  ViewController.swift
//  NSLoggerSW
//
//  Created by Guillaume Laurent on 20/04/15.
//  Copyright (c) 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa
import ReactiveCocoa

class ViewController: NSViewController, NSTableViewDataSource, NSTableViewDelegate {

    dynamic var messageCounter = 0

    var messageListener:MessageListenerXPC?
    var messageListenerConnection:NSXPCConnection?

    var messages = [LoggerMessage]()

    @IBOutlet weak var messagesTableView: NSTableView!

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

            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                self.messages.append(message)
                self.messagesTableView.reloadData()
            })

        })


    }

    override var representedObject: AnyObject? {
        didSet {
        // Update the view, if already loaded.
        }
    }

    func timestampString(timestamp:timeval) -> String {
        var sec = time_t(timestamp.tv_sec)

        let localTimePtr = localtime(&sec)

        let localTime = localTimePtr.memory

        let res:String

        if timestamp.tv_usec == 0 {
            res = String(format:"%02d:%02d:%02d", localTime.tm_hour, localTime.tm_min, localTime.tm_sec)
        } else {
            res = String(format:"%02d:%02d:%02d.%03d", localTime.tm_hour, localTime.tm_min, localTime.tm_sec, timestamp.tv_usec / 1000)
        }

        return res
    }

    func setupMessageContentCellView(cellView : LoggerMessageCellViewMessageContent, forMessage message:LoggerMessage) {

        let t = Int(message.type)

        if let msgType = LoggerMessageType(rawValue: t) {

            switch msgType {
            case .String:
                let messageString = message.message as! String
                cellView.messageText.stringValue = messageString
                cellView.messageText.hidden = false
                cellView.messageImage.hidden = true

            case .Image:
                cellView.messageImage.image = message.image
                cellView.messageText.hidden = true
                cellView.messageImage.hidden = false

            case .Data:
                cellView.messageText.stringValue = "TODO - data"
                cellView.messageText.hidden = false
                cellView.messageImage.hidden = true
            }
        }

    }

    // MARK: NSTableView dataSource & delegate

    func numberOfRowsInTableView(aTableView: NSTableView) -> Int {
        return messages.count
    }

    func tableView(tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        return 30.0
    }

    func tableView(tableView: NSTableView, viewForTableColumn tableColumn: NSTableColumn?, row: Int) -> NSView? {

        let message = messages[row]

        var tableCellView:NSTableCellView?

        let identifier = tableColumn?.identifier

        switch identifier! {
        case "TIMESTAMP":
            var timeStampCellView = tableView.makeViewWithIdentifier(identifier!, owner: self) as? LoggerMessageCellViewTimeStamp
            timeStampCellView?.timestamp.stringValue = timestampString(message.timestamp)
            tableCellView = timeStampCellView

        case "SENDER_ID":
            var senderIdCellView = tableView.makeViewWithIdentifier(identifier!, owner: self) as? LoggerMessageCellViewThreadId
            senderIdCellView?.threadName.stringValue = message.threadID
            senderIdCellView?.messageTag.stringValue = "\(message.type) \(message.level)"
            tableCellView = senderIdCellView

        case "MESSAGE_CONTENT":
            var messageContentCellView = tableView.makeViewWithIdentifier(identifier!, owner: self) as? LoggerMessageCellViewMessageContent
            setupMessageContentCellView(messageContentCellView!, forMessage: message)
            tableCellView = messageContentCellView

        default:
            NSLog("unknown table column ID : \(identifier)")
        }


        return tableCellView
    }

}

