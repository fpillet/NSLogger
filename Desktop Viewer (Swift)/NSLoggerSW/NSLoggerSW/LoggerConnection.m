/*
 * LoggerConnection.m
 *
 * BSD license follows (http://www.opensource.org/licenses/bsd-license.php)
 * 
 * Copyright (c) 2010-2011 Florent Pillet <fpillet@gmail.com> All Rights Reserved.
 *
 * Redistribution and use in source and binary forms, with or without modification,
 * are permitted provided that the following conditions are met:
 *
 * Redistributions of  source code  must retain  the above  copyright notice,
 * this list of  conditions and the following  disclaimer. Redistributions in
 * binary  form must  reproduce  the  above copyright  notice,  this list  of
 * conditions and the following disclaimer  in the documentation and/or other
 * materials  provided with  the distribution.  Neither the  name of  Florent
 * Pillet nor the names of its contributors may be used to endorse or promote
 * products  derived  from  this  software  without  specific  prior  written
 * permission.  THIS  SOFTWARE  IS  PROVIDED BY  THE  COPYRIGHT  HOLDERS  AND
 * CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT
 * NOT LIMITED TO, THE IMPLIED  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR
 * A  PARTICULAR PURPOSE  ARE DISCLAIMED.  IN  NO EVENT  SHALL THE  COPYRIGHT
 * HOLDER OR  CONTRIBUTORS BE  LIABLE FOR  ANY DIRECT,  INDIRECT, INCIDENTAL,
 * SPECIAL, EXEMPLARY,  OR CONSEQUENTIAL DAMAGES (INCLUDING,  BUT NOT LIMITED
 * TO, PROCUREMENT  OF SUBSTITUTE GOODS  OR SERVICES;  LOSS OF USE,  DATA, OR
 * PROFITS; OR  BUSINESS INTERRUPTION)  HOWEVER CAUSED AND  ON ANY  THEORY OF
 * LIABILITY,  WHETHER  IN CONTRACT,  STRICT  LIABILITY,  OR TORT  (INCLUDING
 * NEGLIGENCE  OR OTHERWISE)  ARISING  IN ANY  WAY  OUT OF  THE  USE OF  THIS
 * SOFTWARE,   EVEN  IF   ADVISED  OF   THE  POSSIBILITY   OF  SUCH   DAMAGE.
 * 
 */
#include <netinet/in.h>
#import <objc/runtime.h>
#import "LoggerConnection.h"
#import "LoggerMessage.h"
#import "LoggerCommon.h"
#import "MessageListener-Swift.h"

char sConnectionAssociatedObjectKey = 1;

@implementation LoggerConnection

@synthesize connectionInfo = _connectionInfo;
@synthesize delegate = _delegate;

- (id)init
{
	if ((self = [super init]) != nil)
	{
		_messages = [[NSMutableArray alloc] initWithCapacity:1024];
		self.parentIndexesStack = [[NSMutableArray alloc] init];
		_filenames = [[NSMutableSet alloc] init];
		_functionNames = [[NSMutableSet alloc] init];
	}
	return self;
}

- (id)initWithAddress:(NSData *)anAddress
{
	if ((self = [super init]) != nil)
	{
		_messages = [[NSMutableArray alloc] initWithCapacity:1024];
		self.parentIndexesStack = [[NSMutableArray alloc] init];
		_clientAddress = [anAddress copy];
		_filenames = [[NSMutableSet alloc] init];
		_functionNames = [[NSMutableSet alloc] init];
	}
	return self;
}

- (void)dealloc
{
}

- (BOOL)isNewRunOfClient:(LoggerConnection *)aConnection
{
	// Try to detect if a connection is a new run of an older, disconnected session
	// (goal is to detect restarts, so as to replace logs in the same window)
	assert(self.restoredFromSave == NO);

	// exclude files loaded from disk
	if (aConnection.restoredFromSave)
		return NO;
	
	// as well as still-up connections
	if (aConnection.connected)
		return NO;

	// check whether client info is the same
	BOOL (^isSame)(NSString *, NSString *) = ^(NSString *s1, NSString *s2)
	{
		if ((s1 == nil) != (s2 == nil))
			return NO;
		if (s1 != nil && ![s2 isEqualToString:s1])
			return NO;
		return YES;	// s1 and d2 either nil or same
	};

	if (!isSame(self.clientName, aConnection.clientName) ||
		!isSame(self.clientVersion, aConnection.clientVersion) ||
		!isSame(self.clientOSName, aConnection.clientOSName) ||
		!isSame(self.clientOSVersion, aConnection.clientOSVersion) ||
		!isSame(self.clientDevice, aConnection.clientDevice))
	{
		return NO;
	}
	
	// check whether address is the same, OR hardware ID (if present) is the same.
	// hardware ID wins (on desktop, iOS simulator can connect have different
	// addresses from run to run if the computer has multiple network interfaces / VMs installed
	if (self.clientUDID != nil && isSame(self.clientUDID, aConnection.clientUDID))
		return YES;
	
	if ((self.clientAddress != nil) != (aConnection.clientAddress != nil))
		return NO;

	if (self.clientAddress != nil)
	{
		// compare address blocks sizes (ipv4 vs. ipv6)
		NSUInteger addrSize = [self.clientAddress length];
		if (addrSize != [aConnection.clientAddress length])
			return NO;
		
		// compare ipv4 or ipv6 address. We don't want to compare the source port,
		// because it will change with each connection
		if (addrSize == sizeof(struct sockaddr_in))
		{
			struct sockaddr_in addra, addrb;
			[self.clientAddress getBytes:&addra length:sizeof(struct sockaddr_in)];
			[aConnection.clientAddress getBytes:&addrb length:sizeof(struct sockaddr_in)];
			if (memcmp(&addra.sin_addr, &addrb.sin_addr, sizeof(addra.sin_addr)))
				return NO;
		}
		else if (addrSize == sizeof(struct sockaddr_in6))
		{
			struct sockaddr_in6 addr6a, addr6b;
			[self.clientAddress getBytes:&addr6a length:sizeof(struct sockaddr_in6)];
			[aConnection.clientAddress getBytes:&addr6b length:sizeof(struct sockaddr_in6)];
			if (memcmp(&addr6a.sin6_addr, &addr6b.sin6_addr, sizeof(addr6a.sin6_addr)))
				return NO;
		}
		else if (![self.clientAddress isEqualToData:aConnection.clientAddress])
			return NO;		// we only support ipv4 and ipv6, so this should not happen
	}
	
	return YES;
}

- (void)messagesReceived:(NSArray *)msgs
{
    if (self.delegate) {
        [self.delegate connection:self didReceiveMessages:msgs];
    } else {
        NSLog(@"connection %@ has no delegate", self);
    }

}

- (void)clearMessages
{
    // Clear the backlog of messages, only keeping the top (client info) message
    // This MUST be called on the messageProcessingQueue
    if (![self.messages count])
        return;

    // Locate the clientInfo message
    if (((LoggerMessage *)[self.messages objectAtIndex:0]).type == LOGMSG_TYPE_CLIENTINFO)
        [self.messages removeObjectsInRange:NSMakeRange(1, [self.messages count]-1)];
    else
        [self.messages removeAllObjects];
}

- (void)clientInfoReceived:(LoggerMessage *)message
{
	// Insert message at first position in the message list. In the unlikely event there is
	// an existing ClientInfo message at this position, just replace it. Also, don't fire
	// a "didReceiveMessages". The rationale behind this is that if the connection just came in,
	// we are not yet attached to a window and when attaching, the window will refresh all messages.
    if ([self.messages count] == 0 || ((LoggerMessage *)[self.messages objectAtIndex:0]).type != LOGMSG_TYPE_CLIENTINFO)
        [self.messages insertObject:message atIndex:0];

	// all this stuff occurs on the main thread to avoid touching values
	// while the UI reads them
    NSDictionary *parts = message.parts;
    id value = [parts objectForKey:[NSNumber numberWithInteger:PART_KEY_CLIENT_NAME]];
    if (value != nil)
        self.clientName = value;
    value = [parts objectForKey:[NSNumber numberWithInteger:PART_KEY_CLIENT_VERSION]];
    if (value != nil)
        self.clientVersion = value;
    value = [parts objectForKey:[NSNumber numberWithInteger:PART_KEY_OS_NAME]];
    if (value != nil)
        self.clientOSName = value;
    value = [parts objectForKey:[NSNumber numberWithInteger:PART_KEY_OS_VERSION]];
    if (value != nil)
        self.clientOSVersion = value;
    value = [parts objectForKey:[NSNumber numberWithInteger:PART_KEY_CLIENT_MODEL]];
    if (value != nil)
        self.clientDevice = value;
    value = [parts objectForKey:[NSNumber numberWithInteger:PART_KEY_UNIQUEID]];
    if (value != nil)
        self.clientUDID = value;

}

- (NSString *)clientAppDescription
{
	// enforce thread safety (only on main thread)
	assert([NSThread isMainThread]);
	NSMutableString *s = [[NSMutableString alloc] init];
	if (self.clientName != nil)
		[s appendString:self.clientName];
	if (self.clientVersion != nil)
		[s appendFormat:@" %@", self.clientVersion];
	if (self.clientName == nil && self.clientVersion == nil)
		[s appendString:NSLocalizedString(@"<unknown>", @"")];
	if (self.clientOSName != nil && self.clientOSVersion != nil)
		[s appendFormat:@"%@(%@ %@)", [s length] ? @" " : @"", self.clientOSName, self.clientOSVersion];
	else if (self.clientOSName != nil)
		[s appendFormat:@"%@(%@)", [s length] ? @" " : @"", self.clientOSName];

	return s;
}

- (NSString *)clientAddressDescription
{
	// subclasses should implement this
	return @"";
}

- (NSString *)clientDescription
{
	// enforce thread safety (only on main thread)
	assert([NSThread isMainThread]);
	return [NSString stringWithFormat:@"%@ @ %@", [self clientAppDescription], [self clientAddressDescription]];
}

- (NSString *)status
{
	// status is being observed by LoggerStatusWindowController and changes once
	// when the connection gets disconnected
	NSString *format;
	if (self.connected)
		format = NSLocalizedString(@"%@ connected", @"");
	else
		format = NSLocalizedString(@"%@ disconnected", @"");
	if ([NSThread isMainThread])
		return [NSString stringWithFormat:format, [self clientDescription]];
	__block NSString *status;
	dispatch_sync(dispatch_get_main_queue(), ^{
		status = [NSString stringWithFormat:format, [self clientDescription]];
	});
	return status;
}

- (void)setConnected:(BOOL)newConnected
{
	if (_connected != newConnected)
	{
		_connected = newConnected;
		
		if (!self.connected && [(id)self.delegate respondsToSelector:@selector(remoteDisconnected:)])
			[(id)self.delegate performSelectorOnMainThread:@selector(remoteDisconnected:) withObject:self waitUntilDone:NO];

//		[[NSNotificationCenter defaultCenter] postNotificationName:kShowStatusInStatusWindowNotification
//															object:self];
	}
}

- (void)shutdown
{
	self.connected = NO;
}

- (NSDictionary*)connectionInfo
{
    if (! _connectionInfo) {

        NSMutableDictionary* tmpConnectionInfo = [NSMutableDictionary dictionary];
        _connectionInfo = tmpConnectionInfo;

        tmpConnectionInfo[@"clientName"]      = self.clientName;
        tmpConnectionInfo[@"clientVersion"]   = self.clientVersion;
        tmpConnectionInfo[@"clientOSName"]    = self.clientOSName;
        tmpConnectionInfo[@"clientOSVersion"] = self.clientOSVersion;
        tmpConnectionInfo[@"clientDevice"]    = self.clientDevice;
        tmpConnectionInfo[@"clientUDID"]      = self.clientUDID;
    }

    return _connectionInfo;
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark NSCoding
// -----------------------------------------------------------------------------
- (id)initWithCoder:(NSCoder *)aDecoder
{
	if ((self = [super init]) != nil)
	{
		self.clientName = [aDecoder decodeObjectForKey:@"clientName"];
		self.clientVersion = [aDecoder decodeObjectForKey:@"clientVersion"];
		self.clientOSName = [aDecoder decodeObjectForKey:@"clientOSName"];
		self.clientOSVersion = [aDecoder decodeObjectForKey:@"clientOSVersion"];
		self.clientDevice = [aDecoder decodeObjectForKey:@"clientDevice"];
		self.clientUDID = [aDecoder decodeObjectForKey:@"clientUDID"];
		self.parentIndexesStack = [aDecoder decodeObjectForKey:@"parentIndexes"];
		_filenames = [aDecoder decodeObjectForKey:@"filenames"];
		if (_filenames == nil)
			_filenames = [[NSMutableSet alloc] init];
		_functionNames = [aDecoder decodeObjectForKey:@"functionNames"];
		if (_functionNames == nil)
			_functionNames = [[NSMutableSet alloc] init];
		objc_setAssociatedObject(aDecoder, &sConnectionAssociatedObjectKey, self, OBJC_ASSOCIATION_ASSIGN);
		_messages = [aDecoder decodeObjectForKey:@"messages"];
		_reconnectionCount = [aDecoder decodeIntForKey:@"reconnectionCount"];
		_restoredFromSave = YES;
		
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	if (self.clientName != nil)
		[aCoder encodeObject:self.clientName forKey:@"clientName"];
	if (self.clientVersion != nil)
		[aCoder encodeObject:self.clientVersion forKey:@"clientVersion"];
	if (self.clientOSName != nil)
		[aCoder encodeObject:self.clientOSName forKey:@"clientOSName"];
	if (self.clientOSVersion != nil)
		[aCoder encodeObject:self.clientOSVersion forKey:@"clientOSVersion"];
	if (self.clientDevice != nil)
		[aCoder encodeObject:self.clientDevice forKey:@"clientDevice"];
	if (self.clientUDID != nil)
		[aCoder encodeObject:self.clientUDID forKey:@"clientUDID"];
	[aCoder encodeObject:self.filenames forKey:@"filenames"];
	[aCoder encodeObject:self.functionNames forKey:@"functionNames"];
	[aCoder encodeInt:self.reconnectionCount forKey:@"reconnectionCount"];
	@synchronized (self.messages)
	{
		[aCoder encodeObject:self.messages forKey:@"messages"];
		[aCoder encodeObject:self.parentIndexesStack forKey:@"parentIndexes"];
	}
}

- (void)setDelegate:(id<LoggerConnectionDelegate>)delegate
{
    _delegate = delegate;
}

- (id<LoggerConnectionDelegate>)delegate {
    return _delegate;
}

@end
