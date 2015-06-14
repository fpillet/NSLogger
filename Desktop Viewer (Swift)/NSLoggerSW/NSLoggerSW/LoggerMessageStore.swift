//
//  LoggerMessageStore.swift
//  NSLoggerSW
//
//  Created by Guillaume Laurent on 12/06/15.
//  Copyright (c) 2015 Guillaume Laurent. All rights reserved.
//

import Cocoa
import ReactiveCocoa


class LoggerMessageStore: NSObject {

    var messages = [LoggerMessage]()

    var displayedMessages = [LoggerMessage]()

    let messageFilterQueue = dispatch_queue_create("com.florentpillet.nslogger.messageFiltering", nil)

    let (refreshSignal, refreshSignalSink) = Signal<Int, NoError>.pipe() // if the filter predicate is changed, this signal is emitted once the filtering is done

    var newMessageSignal:Signal<NSIndexSet, NoError>?

    var filterPredicate:NSPredicate? {
        didSet {
            if let fp = filterPredicate {

                dispatch_async(messageFilterQueue, { () -> Void in

                    // long version
                    //
                    // displayedMessages = messages.filter({ (message) -> Bool in
                    //     fp.evaluateWithObject(message)
                    // })

                    // short version
                    self.displayedMessages = self.messages.filter() { fp.evaluateWithObject($0) }

                    sendNext(self.refreshSignalSink, 0) // signal completion of filtering of previous messages with the new filter
                })

            } else {
                displayedMessages = messages
                sendNext(self.refreshSignalSink, 0) // signal completion of filtering
            }
        }
    }

    lazy var signalFilter: (LoggerMessage) -> Bool = { [unowned self] (message:LoggerMessage) in
        if let fp = self.filterPredicate {
            let r = fp.evaluateWithObject(message)
            NSLog("signalFilter : r = %d", r)
            return r
        } else {
            NSLog("signalFilter : no filter")
            return true
        }
    }

    func observeMessagesSignal(signal:Signal<LoggerMessage, NoError>) {

        signal |> observe(next:{ self.messages.append($0)}) // gather all messages

        let filteredSignal = signal |> filter(signalFilter)

//        filteredSignal |> observe(next: { self.displayedMessages.append($0) }) // done in the mapper below

        let messageToIndexSetMapper:(LoggerMessage) -> NSIndexSet = { (message:LoggerMessage) in
            self.displayedMessages.append(message)
            let lastIndexSet = NSIndexSet(index: (self.displayedMessages.count - 1))
            return lastIndexSet
        }

        newMessageSignal = filteredSignal |> map { messageToIndexSetMapper($0) }

    }

//    func foo() {
//
//        let aSimpleMessagePred = { (message:LoggerMessage) in
//            return true
//        }
//
//        let aSimplePred = { (i:Int) in
//            return true
//        }
//
//
//        let f = refreshSignal |> filter(aSimplePred)
//
//    }

}
