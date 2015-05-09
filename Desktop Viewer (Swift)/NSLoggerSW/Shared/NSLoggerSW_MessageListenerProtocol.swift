//
//  NSLoggerSW_MessageListenerProtocol.swift
//  NSLoggerSW
//
//  Created by Guillaume Laurent on 03/05/15.
//  Copyright (c) 2015 Guillaume Laurent. All rights reserved.
//

import Foundation

@objc(NSLoggerSW_MessageListenerProtocol) protocol NSLoggerSW_MessageListenerProtocol {

    // from app to MessageListener
    func startListener()
    func stopListener()


    // from MessageListener to app
    func newConnection(connection:LoggerConnectionInfo) // tell app about new connection
    func receivedMessages(connection:LoggerConnectionInfo, messages:[LoggerMessage]) // tell app about new messages received

}

/*
To use the service from an application or other process, use NSXPCConnection to establish a connection to the service by doing something like this:

_connectionToService = [[NSXPCConnection alloc] initWithServiceName:@"org.telegraph-road.NSLoggerSW-MessageListener"];
_connectionToService.remoteObjectInterface = [NSXPCInterface interfaceWithProtocol:@protocol(StringModifing)];
[_connectionToService resume];

Once you have a connection to the service, you can use it like this:

[[_connectionToService remoteObjectProxy] upperCaseString:@"hello" withReply:^(NSString *aString) {
// We have received a response. Update our text field, but do it on the main thread.
NSLog(@"Result string was: %@", aString);
}];

And, when you are finished with the service, clean up the connection like this:

[_connectionToService invalidate];
*/
