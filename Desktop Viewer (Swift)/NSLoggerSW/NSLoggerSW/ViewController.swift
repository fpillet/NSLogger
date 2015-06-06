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

        messageListener!.messageSignal!.observe(next: { message in

            self.messageCounter++

            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                self.messages.append(message)
//                self.messagesTableView.reloadData()
                let lastIndexSet = NSIndexSet(index: (self.messages.count - 1))
                self.messagesTableView.insertRowsAtIndexes(lastIndexSet, withAnimation: NSTableViewAnimationOptions.SlideUp)
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

    func timeOffsetStringFromMessage(message:LoggerMessage, previousMessage:LoggerMessage) -> String {
        var td = timeval()

        message.computeTimeDelta(&td, since: previousMessage)

        var res = ""

        if td.tv_sec != 0 {

            let hrs = td.tv_sec / 3600
            let mn = (td.tv_sec % 3600) / 60
            let s = (td.tv_sec % 60)
            let ms = td.tv_usec / 1000

            if hrs != 0 {
                res = String(format:"+%dh %dmn %d.%03ds", hrs, mn, s, ms)
            } else if mn != 0 {
                res = String(format:"+%dmn %d.%03ds", mn, s, ms)
            } else if s != 0 {
                if ms != 0 {
                    res = String(format:"+%d.%03ds", s, ms)
                } else {
                    res = String(format:"+%ds", s)
                }
            }

        }

        return res
    }

    func setupMessageContentCellView(cellView : LoggerMessageCellViewMessageContent, forMessage message:LoggerMessage) {

        let t = Int(message.contentsType)

        if let msgType = LoggerMessageType(rawValue: t) {

            switch msgType {
            case .String:
                if let messageString = message.message as? String {
                    cellView.messageText.stringValue = messageString
                    cellView.messageText.hidden = false
                    cellView.messageImage.hidden = true
                } else {
                    NSLog("setupMessageContentCellView : problem, message type is String (%d) but message content is not", message.contentsType)
                }

            case .Image:
                cellView.messageImage.image = message.image
                cellView.messageText.hidden = true
                cellView.messageImage.hidden = false

            case .Data:
                if let messageData = message.message as? NSData {
                    let dataStrings = stringsWithData(messageData)
                    let dataString = dataStrings.reduce("") { (res, str) -> String in
                        res + str
                    }
                    cellView.messageText.stringValue = dataString
                    cellView.messageText.hidden = false
                    cellView.messageImage.hidden = true
                } else {
                    NSLog("setupMessageContentCellView : problem, message type is Data (%d) but message content is not", message.contentsType)
                }
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
            if row > 0 {
                timeStampCellView?.timeOffset.stringValue = timeOffsetStringFromMessage(message, previousMessage: messages[row - 1])
            } else {
                timeStampCellView?.timeOffset.stringValue = ""
            }
            tableCellView = timeStampCellView

        case "SENDER_ID":
            var senderIdCellView = tableView.makeViewWithIdentifier(identifier!, owner: self) as? LoggerMessageCellViewThreadId
            senderIdCellView?.threadName.stringValue = message.threadID
            senderIdCellView?.messageTag.stringValue = "\(message.tag) \(message.level)"
            // senderIdCellView?.messageTag.backgroundColor = NSColor.grayColor()
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


    // MARK: Utilities

    let MAX_DATA_LINES = 16

    func stringsWithData(data:NSData) -> [String] {
        var strings = [String]()

        var offset = 0
        var dataLen = data.length

        let ptr = UnsafePointer<UInt8>(data.bytes)
        let bytes = UnsafeBufferPointer<UInt8>(start:ptr, count:data.length)

        if dataLen == 1 {
            let t = NSLocalizedString("Raw data, 1 byte :", comment:"")
            strings.append(t)
        } else {
            let t = String(format:NSLocalizedString("Raw data, %u bytes :", comment:""), dataLen)
            strings.append(t)
        }

        while dataLen > 0 {
            if strings.count == MAX_DATA_LINES {
                let t = String(format:NSLocalizedString("Double-click to see all data...", comment:""), dataLen)
                strings.append(t)
            }

            // print offset
            //
            let offsetString = String(format:"%04x: ", offset)
            var string = offsetString

            // print bytes
            //
            var nbBytesPrinted = 0
            for i in 0..<min(16, dataLen) {
                let aByte = Int(bytes[i + offset])
                string += String(format: "%02x ", aByte)
                ++nbBytesPrinted
            }

            // pad string with spaces if needed
            //
            if nbBytesPrinted < 16 {
                for j in nbBytesPrinted..<16 {
                    string += "   "
                }
            }

            string += "\'"
            nbBytesPrinted = 0

            // now print data as ASCII chars
            for i in 0..<min(16, dataLen) {
                let aByte = Int(bytes[i + offset])
                if aByte >= 32 && aByte < 128 {
                    string += String(format: "%c", aByte)
                } else {
                    string += " "
                }
                ++nbBytesPrinted
            }

            // pad string with spaces if needed
            //
            if nbBytesPrinted < 16 {
                for j in nbBytesPrinted..<16 {
                    string += " "
                }
            }

            string += "\'"

            strings.append(string)

            offset += nbBytesPrinted
            dataLen -= nbBytesPrinted
        }


        return strings
    }
}

