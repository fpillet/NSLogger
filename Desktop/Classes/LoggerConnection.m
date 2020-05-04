/*
 * LoggerConnection.m
 *
 * BSD license follows (http://www.opensource.org/licenses/bsd-license.php)
 * 
 * Copyright (c) 2010-2018 Florent Pillet <fpillet@gmail.com> All Rights Reserved.
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
#import "LoggerAppDelegate.h"
#import "LoggerStatusWindowController.h"

char sConnectionAssociatedObjectKey = 1;

@implementation LoggerConnection

- (id)init
{
	if ((self = [super init]) != nil)
	{
		_messageProcessingQueue = dispatch_queue_create("com.florentpillet.nslogger._messageProcessingQueue", NULL);
		_messages = [[NSMutableArray alloc] initWithCapacity:1024];
		_parentIndexesStack = [[NSMutableArray alloc] init];
		_filenames = [[NSMutableSet alloc] init];
		_functionNames = [[NSMutableSet alloc] init];
	}
	return self;
}

- (id)initWithAddress:(NSData *)anAddress
{
	if ((self = [super init]) != nil)
	{
		_messageProcessingQueue = dispatch_queue_create("com.florentpillet.nslogger._messageProcessingQueue", NULL);
		_messages = [[NSMutableArray alloc] initWithCapacity:1024];
		_parentIndexesStack = [[NSMutableArray alloc] init];
		_clientAddress = [anAddress copy];
		_filenames = [[NSMutableSet alloc] init];
		_functionNames = [[NSMutableSet alloc] init];
	}
	return self;
}

- (BOOL)isNewRunOfClient:(LoggerConnection *)aConnection
{
	// Try to detect if a connection is a new run of an older, disconnected session
	// (goal is to detect restarts, so as to replace logs in the same window)
	assert(_restoredFromSave == NO);

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

	if (!isSame(_clientName, aConnection.clientName) ||
		!isSame(_clientVersion, aConnection.clientVersion) ||
		!isSame(_clientOSName, aConnection.clientOSName) ||
		!isSame(_clientOSVersion, aConnection.clientOSVersion) ||
		!isSame(_clientDevice, aConnection.clientDevice) ||
		!isSame(_clientUDID, aConnection.clientUDID))
	{
		return NO;
	}
	
	// check whether address is the same, OR hardware ID (if present) is the same.
	// hardware ID wins (on desktop, iOS simulator can connect have different
	// addresses from run to run if the computer has multiple network interfaces / VMs installed
	if (_clientUDID != nil && isSame(_clientUDID, aConnection.clientUDID))
		return YES;
	
	if ((_clientAddress != nil) != (aConnection.clientAddress != nil))
		return NO;

	if (_clientAddress != nil)
	{
		// compare address blocks sizes (ipv4 vs. ipv6)
		NSUInteger addrSize = [_clientAddress length];
		if (addrSize != [aConnection.clientAddress length])
			return NO;
		
		// compare ipv4 or ipv6 address. We don't want to compare the source port,
		// because it will change with each connection
		if (addrSize == sizeof(struct sockaddr_in))
		{
			struct sockaddr_in addra, addrb;
			[_clientAddress getBytes:&addra length:addrSize];
			[aConnection.clientAddress getBytes:&addrb length:MIN([aConnection.clientAddress length], sizeof(addrb))];
			if (memcmp(&addra.sin_addr, &addrb.sin_addr, sizeof(addra.sin_addr)))
				return NO;
		}
		else if (addrSize == sizeof(struct sockaddr_in6))
		{
			struct sockaddr_in6 addr6a, addr6b;
			[_clientAddress getBytes:&addr6a length:addrSize];
			[aConnection.clientAddress getBytes:&addr6b length:MIN([aConnection.clientAddress length], sizeof(addr6b))];
			if (memcmp(&addr6a.sin6_addr, &addr6b.sin6_addr, sizeof(addr6a.sin6_addr)))
				return NO;
		}
		else if (![_clientAddress isEqualToData:aConnection.clientAddress])
			return NO;		// we only support ipv4 and ipv6, so this should not happen
	}
	
	return YES;
}

- (void)messagesReceived:(NSArray *)msgs
{
	dispatch_async(_messageProcessingQueue, ^{
		/* Code not functional yet
		 *
		NSRange range = NSMakeRange([_messages count], [msgs count]);
		NSUInteger lastParent = NSNotFound;
		if ([_parentIndexesStack count])
			lastParent = [[_parentIndexesStack lastObject] intValue];
		
		for (NSUInteger i = 0, count = [msgs count]; i < count; i++)
		{
			// update cache for indentation
			LoggerMessage *message = [msgs objectAtIndex:i];
			switch (message.type)
			{
				case LOGMSG_TYPE_BLOCKSTART:
					[_parentIndexesStack addObject:[NSNumber numberWithInt:range.location+i]];
					lastParent = range.location + i;
					break;
					
				case LOGMSG_TYPE_BLOCKEND:
					if ([_parentIndexesStack count])
					{
						[_parentIndexesStack removeLastObject];
						if ([_parentIndexesStack count])
							lastParent = [[_parentIndexesStack lastObject] intValue];
						else
							lastParent = NSNotFound;
					}
					break;
					
				default:
					if (lastParent != NSNotFound)
					{
						message.distanceFromParent = range.location + i - lastParent;
						message.indent = [_parentIndexesStack count];
					}
					break;
			}
		}
		 *
		 */
		NSRange range;
		@synchronized (self.messages)
		{
			range = NSMakeRange([self.messages count], [msgs count]);
			[self.messages addObjectsFromArray:msgs];
		}
		
		if (self.attachedToWindow)
			[self.delegate connection:self didReceiveMessages:msgs range:range];
	});
}

- (void)clearMessages
{
	// Clear the backlog of _messages, only keeping the top (client info) message
	// This MUST be called on the _messageProcessingQueue
	if (![_messages count])
		return;

	// Locate the clientInfo message
	if (((LoggerMessage *) _messages[0]).type == LOGMSG_TYPE_CLIENTINFO)
		[_messages removeObjectsInRange:NSMakeRange(1, [_messages count]-1)];
	else
		[_messages removeAllObjects];
}

- (void)clientInfoReceived:(LoggerMessage *)message
{
	// Insert message at first position in the message list. In the unlikely event there is
	// an existing ClientInfo message at this position, just replace it. Also, don't fire
	// a "didReceiveMessages". The rationale behind this is that if the connection just came in,
	// we are not yet attached to a window and when attaching, the window will refresh all _messages.
	dispatch_async(_messageProcessingQueue, ^{
		@synchronized (self.messages)
		{
			if ([self.messages count] == 0 || ((LoggerMessage *) self.messages[0]).type != LOGMSG_TYPE_CLIENTINFO)
				[self.messages insertObject:message atIndex:0];
		}
	});

	// all this stuff occurs on the main thread to avoid touching values
	// while the UI reads them
	dispatch_async(dispatch_get_main_queue(), ^{
		NSDictionary *parts = message.parts;
		id value = parts[@PART_KEY_CLIENT_NAME];
		if (value != nil)
			self.clientName = value;
		value = parts[@PART_KEY_CLIENT_VERSION];
		if (value != nil)
			self.clientVersion = value;
		value = parts[@PART_KEY_OS_NAME];
		if (value != nil)
			self.clientOSName = value;
		value = parts[@PART_KEY_OS_VERSION];
		if (value != nil)
			self.clientOSVersion = value;
		value = parts[@PART_KEY_CLIENT_MODEL];
		if (value != nil)
			self.clientDevice = value;
		value = parts[@PART_KEY_UNIQUEID];
		if (value != nil)
			self.clientUDID = value;

		[[NSNotificationCenter defaultCenter] postNotificationName:kShowStatusInStatusWindowNotification
															object:self];
	});
}

- (NSString *)clientAppDescription
{
	// enforce thread safety (only on main thread)
	assert([NSThread isMainThread]);
	NSMutableString *s = [[NSMutableString alloc] init];
	if (_clientName != nil)
		[s appendString:_clientName];
	if (_clientVersion != nil)
		[s appendFormat:@" %@", _clientVersion];
	if (_clientName == nil && _clientVersion == nil)
		[s appendString:NSLocalizedString(@"<unknown>", @"")];

	if (_clientOSName != nil && _clientOSVersion != nil)
		[s appendFormat:@"%@(%@ %@)", [s length] ? @" " : @"", _clientOSName, _clientOSVersion];
	else if (_clientOSName != nil)
		[s appendFormat:@"%@(%@)", [s length] ? @" " : @"", _clientOSName];
	if (_clientUDID != nil)
		[s appendFormat:@" — %@", _clientUDID];

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
	NSString *clientAppDescription = [self clientAppDescription];
	NSString *clientAddressDescription = [self clientAddressDescription];
	return clientAddressDescription ? [NSString stringWithFormat:@"%@ @ %@", clientAppDescription, clientAddressDescription] : clientAppDescription;
}

- (NSString *)status
{
	// status is being observed by LoggerStatusWindowController and changes once
	// when the connection gets disconnected
	NSString *format;
	if (_connected)
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
		
		if (!_connected && [(id)_delegate respondsToSelector:@selector(remoteDisconnected:)])
			[(id)_delegate performSelectorOnMainThread:@selector(remoteDisconnected:) withObject:self waitUntilDone:NO];

		[[NSNotificationCenter defaultCenter] postNotificationName:kShowStatusInStatusWindowNotification
															object:self];
	}
}

- (void)shutdown
{
	self.connected = NO;
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark NSCoding
// -----------------------------------------------------------------------------
- (id)initWithCoder:(NSCoder *)aDecoder
{
	if ((self = [super init]) != nil)
	{
		_clientName = [aDecoder decodeObjectForKey:@"_clientName"];
		// When the code was converted to ARC, some of the keys have changed.
		// In order to be backward compatible, we also need to check if the coder
		// is using the old keys.
		if (_clientName == nil)
			_clientName = [aDecoder decodeObjectForKey:@"clientName"];

		_clientVersion = [aDecoder decodeObjectForKey:@"_clientVersion"];
		if (_clientVersion == nil)
			_clientVersion = [aDecoder decodeObjectForKey:@"clientVersion"];

		_clientOSName = [aDecoder decodeObjectForKey:@"clientOSName"];
		_clientOSVersion = [aDecoder decodeObjectForKey:@"clientOSVersion"];
		_clientDevice = [aDecoder decodeObjectForKey:@"clientDevice"];
		_clientUDID = [aDecoder decodeObjectForKey:@"clientUDID"];
		_parentIndexesStack = [aDecoder decodeObjectForKey:@"parentIndexes"];
		_filenames = [aDecoder decodeObjectForKey:@"_filenames"];
		if (_filenames == nil)
			_filenames = [aDecoder decodeObjectForKey:@"filenames"];
		if (_filenames == nil)
			_filenames = [[NSMutableSet alloc] init];
		_functionNames = [aDecoder decodeObjectForKey:@"_functionNames"];
		if (_functionNames == nil)
			_functionNames = [aDecoder decodeObjectForKey:@"functionNames"];
		if (_functionNames == nil)
			_functionNames = [[NSMutableSet alloc] init];
		objc_setAssociatedObject(aDecoder, &sConnectionAssociatedObjectKey, self, OBJC_ASSOCIATION_ASSIGN);
		_messages = [aDecoder decodeObjectForKey:@"_messages"];
		if (_messages == nil)
			_messages = [aDecoder decodeObjectForKey:@"messages"];
		_reconnectionCount = [aDecoder decodeIntForKey:@"reconnectionCount"];
		_restoredFromSave = YES;
		
		// we need a _messageProcessingQueue just for the ability to add/insert marks
		// when user does post-mortem investigation
		_messageProcessingQueue = dispatch_queue_create("com.florentpillet.nslogger._messageProcessingQueue", NULL);
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)aCoder
{
	if (_clientName != nil)
		[aCoder encodeObject:_clientName forKey:@"_clientName"];
	if (_clientVersion != nil)
		[aCoder encodeObject:_clientVersion forKey:@"_clientVersion"];
	if (_clientOSName != nil)
		[aCoder encodeObject:_clientOSName forKey:@"clientOSName"];
	if (_clientOSVersion != nil)
		[aCoder encodeObject:_clientOSVersion forKey:@"clientOSVersion"];
	if (_clientDevice != nil)
		[aCoder encodeObject:_clientDevice forKey:@"clientDevice"];
	if (_clientUDID != nil)
		[aCoder encodeObject:_clientUDID forKey:@"clientUDID"];
	[aCoder encodeObject:_filenames forKey:@"_filenames"];
	[aCoder encodeObject:_functionNames forKey:@"_functionNames"];
	[aCoder encodeInt:_reconnectionCount forKey:@"reconnectionCount"];
	@synchronized (_messages)
	{
		[aCoder encodeObject:_messages forKey:@"_messages"];
		[aCoder encodeObject:_parentIndexesStack forKey:@"parentIndexes"];
	}
}

@end
