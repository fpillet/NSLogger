//
//  LoggerConnection.swift
//  NSLoggerSW
//
//  Created by Guillaume Laurent on 21/04/15.
//  Copyright (c) 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa
import Dispatch

var sConnectionAssociatedObjectKey:UInt8 = 1

let kShowStatusInStatusWindowNotification = "ShowStatusInStatusWindowNotification"

protocol LoggerConnectionDelegate {

    func connection(connection:LoggerConnection, messages didReceiveMessages:[LoggerMessage], range rangeInMessagesList:Range<Int>)
    func remoteDisconnected(connection:LoggerConnection)

}

func ==(a:sockaddr_in, b:sockaddr_in) -> Bool {

    var a1 = a
    var b1 = b

    return memcmp(&a1, &b1, sizeof(sockaddr_in)) == 0
}

func ==(a:sockaddr_in6, b:sockaddr_in6) -> Bool {

    var a1 = a
    var b1 = b

    return memcmp(&a1, &b1, sizeof(sockaddr_in6)) == 0
}


class LoggerConnection: NSObject, NSCoding {

    var clientName:String?
    var clientVersion:String?
    var clientOSName:String?
    var clientOSVersion:String?
    var clientDevice:String?
    var clientUDID:String?

    var filenames = Set<String>()
    var functionNames = Set<String>()

    var clientAddress:NSData?

    var messages = [LoggerMessage]()
    var parentIndexesStack = [Int]()

    var messageProcessingQueue = dispatch_queue_create("com.florentpillet.nslogger.messageProcessingQueue", nil)

    var reconnectionCount = 0

    var connected:Bool {
        didSet {
            if !connected {
                dispatch_async(dispatch_get_main_queue(), { () -> Void in
                    self.delegate?.remoteDisconnected(self)
                })
            }
        }
    }

    var restoredFromSave = false
    var attachedToWindow = false

    var delegate:LoggerConnectionDelegate?

    required override init() {
        connected = false
        super.init()
    }

    required init(coder aDecoder: NSCoder) {

        connected = false

        super.init()

        clientName         = aDecoder.decodeObjectForKey("clientName") as? String
        clientVersion      = aDecoder.decodeObjectForKey("clientVersion") as? String
        clientOSName       = aDecoder.decodeObjectForKey("clientOSName") as? String
        clientOSVersion    = aDecoder.decodeObjectForKey("clientOSVersion") as? String
        clientDevice       = aDecoder.decodeObjectForKey("clientDevice") as? String
        clientUDID         = aDecoder.decodeObjectForKey("clientUDID") as? String
        parentIndexesStack = (aDecoder.decodeObjectForKey("parentIndexes") as? [Int])!

        if let decodedFileNames = aDecoder.decodeObjectForKey("filenames") as? Set<String> {
            filenames = decodedFileNames
        }

        if let decodedFunctionNames = aDecoder.decodeObjectForKey("functionNames") as? Set<String> {
            functionNames = decodedFunctionNames
        }

        objc_setAssociatedObject(aDecoder, &sConnectionAssociatedObjectKey, self, objc_AssociationPolicy(OBJC_ASSOCIATION_ASSIGN))

        if let decodedMessages = aDecoder.decodeObjectForKey("messages") as? [LoggerMessage] {
            messages = decodedMessages
        }

        reconnectionCount = aDecoder.decodeIntegerForKey("reconnectionCount")

        restoredFromSave = true

        messageProcessingQueue = dispatch_queue_create("com.florentpillet.nslogger.messageProcessingQueue", nil)

    }

    func encodeWithCoder(aCoder: NSCoder) {
        if let clientName = self.clientName {
            aCoder.encodeObject(clientName, forKey: "clientName")
        }
        if let clientVersion = self.clientVersion {
            aCoder.encodeObject(clientVersion, forKey: "clientVersion")
        }
        if let clientOSName = self.clientOSName {
            aCoder.encodeObject(clientName, forKey: "clientOSName")
        }
        if let clientOSVersion = self.clientOSVersion {
            aCoder.encodeObject(clientOSVersion, forKey: "clientOSVersion")
        }
        if let clientDevice = self.clientDevice {
            aCoder.encodeObject(clientDevice, forKey: "clientDevice")
        }
        if let clientUDID = self.clientUDID {
            aCoder.encodeObject(clientUDID, forKey: "clientUDID")
        }

        aCoder.encodeObject(filenames, forKey: "filenames")
        aCoder.encodeObject(functionNames, forKey: "functionNames")
        aCoder.encodeInteger(reconnectionCount, forKey: "reconnectionCount")

        synced(messages) { () -> () in
            aCoder.encodeObject(self.messages, forKey: "messages")
            aCoder.encodeObject(self.parentIndexesStack, forKey: "parentIndexes")
        }
    }


    func isNewRunOfClient(connection:LoggerConnection) -> Bool {

        assert(restoredFromSave == false, "isNewRunOfClient called with restoredFromSave == true")

        if connection.restoredFromSave {
            return false
        }

        if connection.connected {
            return false
        }

        if clientName != connection.clientName ||
            clientVersion != connection.clientVersion ||
            clientOSName != connection.clientOSName ||
            clientOSVersion != connection.clientOSVersion ||
            clientDevice != connection.clientDevice {
                return false
        }

        if clientUDID == connection.clientUDID {
            return true
        }

        if (clientAddress != nil) != (connection.clientAddress != nil) {
            return false
        }

        if let clientAddress = self.clientAddress, connectionClientAddress = connection.clientAddress {

            let addrSize = clientAddress.length

            if addrSize != connection.clientAddress?.length {
                return false
            }

            if addrSize == sizeof(sockaddr_in) {
                var addrA = sockaddr_in()
                var addrB = sockaddr_in()

                clientAddress.getBytes(&addrA, length:addrSize)
                connectionClientAddress.getBytes(&addrB, length:addrSize)

                if !(addrA == addrB) {
                    return false
                }

            } else if addrSize == sizeof(sockaddr_in6) {
                var addrA = sockaddr_in6()
                var addrB = sockaddr_in6()

                clientAddress.getBytes(&addrA, length:addrSize)
                connectionClientAddress.getBytes(&addrB, length:addrSize)

                if !(addrA == addrB) {
                    return false
                }

            } else {
                if !clientAddress.isEqualToData(connectionClientAddress) {
                    return false
                }
            }

        }

        return true
    }


    func messagesReceived(theMessages:[LoggerMessage]) {
        dispatch_async(messageProcessingQueue) { () -> Void in

            var range:Range<Int> = Range(start: self.messages.count, end: theMessages.count)

            synced(theMessages) { () -> () in
                self.messages += theMessages
            }

            if self.attachedToWindow {
                self.delegate?.connection(self, messages: theMessages, range: range)
            }

        }
    }

    func clearMessages() {
        dispatch_sync(messageProcessingQueue, { () -> Void in
            if self.messages.count > 0 {
                if self.messages[0].type == .ClientInfo {
                    let range = Range<Int>(start: 1, end: self.messages.count - 1)
                    self.messages.removeRange(range)
                } else {
                    self.messages.removeAll(keepCapacity: false)
                }
            }
        })
    }

    func clientInfoReceived(message:LoggerMessage) {
        dispatch_async(messageProcessingQueue) { () -> Void in
            synced(self.messages) { () -> () in
                if self.messages.count == 0 || self.messages[0].type != .ClientInfo {
                    self.messages.insert(message, atIndex: 0)
                }
            }
        }

        dispatch_async(dispatch_get_main_queue()) { () -> Void in
            let parts = message.parts

            if let value = parts[.ClientName] as? String {
                self.clientName = value
            }

            if let value = parts[.ClientVersion] as? String {
                self.clientVersion = value
            }

            if let value = parts[.OSName] as? String {
                self.clientOSName = value
            }

            if let value = parts[.OSVersion] as? String {
                self.clientOSVersion = value
            }

            if let value = parts[.ClientModel] as? String {
                self.clientDevice = value
            }

            if let value = parts[.UniqueId] as? String {
                self.clientUDID = value
            }

            NSNotificationCenter.defaultCenter().postNotificationName(kShowStatusInStatusWindowNotification, object: self)

        }

    }


    func clientAppDescription() -> String {
        assert(NSThread.isMainThread())

        var res = ""

        if let clientName = self.clientName {
            res += clientName
        }

        if let clientVersion = self.clientVersion {
            res += " \(clientVersion)"
        }

        if clientName == nil && clientVersion == nil {
            res = NSLocalizedString("<unknown>", comment:"")
        }

        if let clientOSName = self.clientOSName {

            if let clientOSVersion = self.clientOSVersion {
                if !res.isEmpty {
                    res += " "
                }
                res += "\(clientOSName) \(clientOSVersion)"
            } else {
                if !res.isEmpty {
                    res += " "
                }
                res += "\(clientOSName)"
            }
        }

        return res
    }

    func clientAddressDescription() -> String {
        return ""
    }

    func clientDescription() -> String {
        assert(NSThread.isMainThread())

        return "\(clientAppDescription()) @ \(clientAddressDescription())"
    }

    func status() -> String {
        let connectedString = connected ? NSLocalizedString("connected", comment: "") : NSLocalizedString("disconnected", comment: "")

        var res = ""

        dispatch_sync(dispatch_get_main_queue()) { () -> Void in
            res = "\(self.clientDescription()) \(connectedString)"
        }

        return res
    }


    func shutdown() {
        connected = false
    }

}
