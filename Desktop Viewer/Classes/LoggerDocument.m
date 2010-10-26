/*
 * LoggerDocument.h
 *
 * BSD license follows (http://www.opensource.org/licenses/bsd-license.php)
 * 
 * Copyright (c) 2010 Florent Pillet <fpillet@gmail.com> All Rights Reserved.
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
#import "LoggerDocument.h"
#import "LoggerWindowController.h"
#import "LoggerTransport.h"
#import "LoggerCommon.h"
#import "LoggerNativeMessage.h"
#import "LoggerAppDelegate.h"

@implementation LoggerDocument

@synthesize attachedConnection;

+ (BOOL)canConcurrentlyReadDocumentsOfType:(NSString *)typeName
{
	if ([typeName isEqualToString:@"NSLogger Data"])
		return YES;
	return NO;
}

- (id)initWithConnection:(LoggerConnection *)aConnection
{
	if (self = [super init])
	{
		self.attachedConnection = aConnection;
		attachedConnection.delegate = self;
	}
	return self;
}

- (void)close
{
	// since delegate is retained, we need to set it to nil
	attachedConnection.delegate = nil;
	[super close];
}

- (void)dealloc
{
	if (attachedConnection != nil)
	{
		// close the connection (if not already done) and make sure it is removed from transport
		for (LoggerTransport *t in ((LoggerAppDelegate *)[NSApp	delegate]).transports)
			[t removeConnection:attachedConnection];
		[attachedConnection release];
	}
	[super dealloc];
}

- (BOOL)writeToURL:(NSURL *)absoluteURL ofType:(NSString *)typeName error:(NSError **)outError
{
	if ([typeName isEqualToString:@"NSLogger Data"])
	{
		NSData *data = [NSKeyedArchiver archivedDataWithRootObject:attachedConnection];
		if (data != nil)
			return [data writeToURL:absoluteURL atomically:NO];
	}
	return NO;
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{
	assert(attachedConnection == nil);
	if ([typeName isEqualToString:@"NSLogger Data"])
	{
		attachedConnection = [[NSKeyedUnarchiver unarchiveObjectWithData:data] retain];
		return (attachedConnection != nil);
	}
	else if ([typeName isEqualToString:@"NSLogger Raw Data"])
	{
		attachedConnection = [[LoggerConnection alloc] init];
		NSMutableArray *msgs = [[NSMutableArray alloc] init];
		long dataLength = [data length];
		const uint8_t *p = [data bytes];
		while (dataLength)
		{
			// check whether we have a full message
			uint32_t length;
			memcpy(&length, p, 4);
			length = ntohl(length);
			if (dataLength < (length + 4))
				break;		// incomplete last message
			
			// get one message
			CFDataRef subset = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault,
														   (unsigned char *)p + 4,
														   length,
														   kCFAllocatorNull);
			if (subset != NULL)
			{
				LoggerMessage *message = [[LoggerNativeMessage alloc] initWithData:(NSData *)subset];
				if (message.type == LOGMSG_TYPE_CLIENTINFO)
					[attachedConnection clientInfoReceived:message];
				else
					[msgs addObject:message];
				[message release];
				CFRelease(subset);
			}
			dataLength -= length + 4;
			p += length + 4;
		}
		
		if ([msgs count])
			[attachedConnection messagesReceived:msgs];
		[msgs release];
	}
	return NO;
}

- (void)makeWindowControllers
{
	LoggerWindowController *controller = [[LoggerWindowController alloc] initWithWindowNibName:@"LoggerWindow"];
	controller.attachedConnection = attachedConnection;
	[self addWindowController:controller];
	[controller release];
}

- (BOOL)prepareSavePanel:(NSSavePanel *)sp
{
    // assign defaults for the save panel
    [sp setTitle:@"Save Logs"];
    [sp setExtensionHidden:NO];
    return YES;
}

- (LoggerWindowController *)mainWindowController
{
	for (LoggerWindowController *controller in [self windowControllers])
	{
		if ([controller isKindOfClass:[LoggerWindowController class]])
			return controller;
	}
	assert(false);
	return nil;
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark LoggerConnectionDelegate
// -----------------------------------------------------------------------------
- (void)connection:(LoggerConnection *)theConnection
didReceiveMessages:(NSArray *)theMessages
			 range:(NSRange)rangeInMessagesList
{
	[[self mainWindowController] connection:theConnection didReceiveMessages:theMessages range:rangeInMessagesList];
	if (theConnection.connected)
	{
		// fixed a crash where calling updateChangeCount: which does not appear to be
		// safe when called from a secondary thread
		dispatch_async(dispatch_get_main_queue(), ^{
			[self updateChangeCount:NSChangeDone];
		});
	}
}

- (void)remoteConnected:(LoggerConnection *)theConnection
{
	[[self mainWindowController] remoteConnected:theConnection];
}

- (void)remoteDisconnected:(LoggerConnection *)theConnection
{
	[[self mainWindowController] remoteDisconnected:theConnection];
}

@end
