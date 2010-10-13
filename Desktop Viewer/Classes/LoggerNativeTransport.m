/*
 * LoggerNativeTransport.m
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
#include <sys/socket.h>
#include <netinet/in.h>
#import "LoggerCommon.h"
#import "LoggerNativeTransport.h"
#import "LoggerNativeConnection.h"
#import "LoggerNativeMessage.h"
#import "LoggerStatusWindowController.h"

/* Local prototypes */
static void AcceptSocketCallback(CFSocketRef sock, CFSocketCallBackType type, CFDataRef address, const void *data, void *info);

@implementation LoggerNativeTransport

@synthesize listenerPort, listenerSocket_ipv4, listenerSocket_ipv6;

- (void)startup
{
	[NSThread detachNewThreadSelector:@selector(listenerThread) toTarget:self withObject:nil];
}

- (void)shutdown
{
	if (listenerThread != nil && [NSThread currentThread] != listenerThread)
	{
		[self performSelector:_cmd onThread:listenerThread withObject:nil waitUntilDone:YES];
		return;
	}
	
	// stop Bonjour service
	[bonjourService setDelegate:nil];
	[bonjourService stop];
	[bonjourService release];
	bonjourService = nil;

	// close listener sockets
	if (listenerSocket_ipv4)
	{
		CFSocketInvalidate(listenerSocket_ipv4);
		CFRelease(listenerSocket_ipv4);
		listenerSocket_ipv4 = NULL;
	}
	if (listenerSocket_ipv6)
	{
		CFSocketInvalidate(listenerSocket_ipv6);
		CFRelease(listenerSocket_ipv6);
		listenerSocket_ipv6 = NULL;
	}

	// shutdown all connections
	while ([connections count])
		[self removeConnection:[connections objectAtIndex:0]];
}

- (void)dealloc
{
	[listenerThread cancel];
	[bonjourService release];
	[super dealloc];
}

- (NSString *)status
{
	// status is being observed by LoggerStatusWindowController and changes once when setupPort either
	// succeeds or fails
	if (listenerThread == nil)
		return NSLocalizedString(@"Bonjour service starting up...", @"");
	if (listenerSocket_ipv4 == NULL && listenerSocket_ipv6 == NULL)
		return NSLocalizedString(@"Failed starting Bonjour service.", @"");
	return [NSString stringWithFormat:@"Bonjour service ready (local port %d)", listenerPort];
}

- (void)removeConnection:(LoggerConnection *)aConnection
{
	if (listenerThread != nil && [NSThread currentThread] != listenerThread)
	{
		[self performSelector:_cmd onThread:listenerThread withObject:aConnection waitUntilDone:YES];
		return;
	}
	[super removeConnection:aConnection];
}

- (BOOL)setupWithPort:(int)port
{
	@try
	{
		CFSocketContext context = {0, self, NULL, NULL, NULL};
		
		// create sockets
		listenerSocket_ipv4 = CFSocketCreate(kCFAllocatorDefault,
											 PF_INET,
											 SOCK_STREAM, 
											 IPPROTO_TCP,
											 kCFSocketAcceptCallBack,
											 &AcceptSocketCallback,
											 &context);
		
		listenerSocket_ipv6 = CFSocketCreate(kCFAllocatorDefault,
											 PF_INET6,
											 SOCK_STREAM, 
											 IPPROTO_TCP,
											 kCFSocketAcceptCallBack,
											 &AcceptSocketCallback,
											 &context);
		
		if (listenerSocket_ipv4 == NULL || listenerSocket_ipv6 == NULL)
		{
			@throw [NSException exceptionWithName:@"CFSocketCreate"
										   reason:NSLocalizedString(@"Failed creating listener socket (CFSocketCreate failed)", @"")
										 userInfo:nil];
		}
		
		// set socket options & addresses
		int yes = 1;
		setsockopt(CFSocketGetNative(listenerSocket_ipv4), SOL_SOCKET, SO_REUSEADDR, (void *)&yes, sizeof(yes));
		setsockopt(CFSocketGetNative(listenerSocket_ipv6), SOL_SOCKET, SO_REUSEADDR, (void *)&yes, sizeof(yes));
		
		// set up the IPv4 endpoint; if port is 0, this will cause the kernel to choose a port for us
		struct sockaddr_in addr4;
		memset(&addr4, 0, sizeof(addr4));
		addr4.sin_len = sizeof(addr4);
		addr4.sin_family = AF_INET;
		addr4.sin_port = htons(port);
		addr4.sin_addr.s_addr = htonl(INADDR_ANY);
		NSData *address4 = [NSData dataWithBytes:&addr4 length:sizeof(addr4)];
		
	    if (CFSocketSetAddress(listenerSocket_ipv4, (CFDataRef)address4) != kCFSocketSuccess)
		{
			@throw [NSException exceptionWithName:@"CFSocketSetAddress"
										   reason:NSLocalizedString(@"Failed setting socket address", @"")
										 userInfo:nil];
		}
		
		if (port == 0)
		{
			// now that the binding was successful, we get the port number 
			// -- we will need it for the v6 endpoint and for NSNetService
			NSData *addr = [(NSData *)CFSocketCopyAddress(listenerSocket_ipv4) autorelease];
			memcpy(&addr4, [addr bytes], [addr length]);
			port = ntohs(addr4.sin_port);
		}
		
	    // set up the IPv6 endpoint
		struct sockaddr_in6 addr6;
		memset(&addr6, 0, sizeof(addr6));
		addr6.sin6_len = sizeof(addr6);
		addr6.sin6_family = AF_INET6;
		addr6.sin6_port = htons(port);
		memcpy(&(addr6.sin6_addr), &in6addr_any, sizeof(addr6.sin6_addr));
		NSData *address6 = [NSData dataWithBytes:&addr6 length:sizeof(addr6)];
		
		if (CFSocketSetAddress(listenerSocket_ipv6, (CFDataRef)address6) != kCFSocketSuccess)
		{
			@throw [NSException exceptionWithName:@"CFSocketSetAddress"
										   reason:NSLocalizedString(@"Failed setting socket address", @"")
										 userInfo:nil];
		}
		
		listenerPort = port;

		// set up the run loop sources for the sockets
		CFRunLoopRef rl = CFRunLoopGetCurrent();
		CFRunLoopSourceRef source4 = CFSocketCreateRunLoopSource(kCFAllocatorDefault, listenerSocket_ipv4, 0);
		CFRunLoopAddSource(rl, source4, kCFRunLoopCommonModes);
		CFRelease(source4);
		
		CFRunLoopSourceRef source6 = CFSocketCreateRunLoopSource(kCFAllocatorDefault, listenerSocket_ipv6, 0);
		CFRunLoopAddSource(rl, source6, kCFRunLoopCommonModes);
		CFRelease(source6);

		// register Bonjour services
		bonjourService = [[NSNetService alloc] initWithDomain:@""
														 type:(NSString *)LOGGER_SERVICE_TYPE
														 name:(NSString *)LOGGER_SERVICE_NAME
														 port:port];
		[bonjourService setDelegate:self];
		[bonjourService publish];
	}
	@catch (NSException * e)
	{
		if (listenerSocket_ipv4 != NULL)
		{
			CFRelease(listenerSocket_ipv4);
			listenerSocket_ipv4 = NULL;
		}
		if (listenerSocket_ipv6 != NULL)
		{
			CFRelease(listenerSocket_ipv6);
			listenerSocket_ipv6 = NULL;
		}
		@throw e;
	}
	@finally
	{
		[[NSNotificationCenter defaultCenter] postNotificationName:kShowStatusInStatusWindowNotification object:self];
	}
	return YES;
}

- (void)listenerThread
{
	listenerThread = [NSThread currentThread];
	[[listenerThread threadDictionary] setObject:[NSRunLoop currentRunLoop] forKey:@"runLoop"];
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	@try
	{
		[self setupWithPort:listenerPort];			// if listenerPort is 0, let the OS choose the port we're listening on
		while (![listenerThread isCancelled])
		{
			NSDate *next = [[NSDate alloc] initWithTimeIntervalSinceNow:0.10];
			[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:next];
			[next release];
		}
	}
	@catch (NSException * e)
	{
#ifdef DEBUG
		NSLog(@"listenerThread catched exception %@", e);
#endif
		// @@@ TODO
//		[NSApp presentError:];
	}
	@finally
	{
		[pool release];
		listenerThread = nil;
	}
}

// -----------------------------------------------------------------------------
// NSStream delegate
// -----------------------------------------------------------------------------
- (void)stream:(NSStream *)theStream handleEvent:(NSStreamEvent)streamEvent
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	@try
	{
		LoggerNativeConnection *cnx = nil;
		for (cnx in connections)
		{
			if (cnx.readStream == theStream)
				break;
			cnx = nil;
		}
		if (cnx == nil)
			return;
		
		NSInteger numBytes;

		switch(streamEvent)
		{
			case NSStreamEventHasBytesAvailable:
				while ([cnx.readStream hasBytesAvailable] && (numBytes = [cnx.readStream read:cnx.tmpBuf maxLength:cnx.tmpBufSize]) > 0)
				{
					// append data to the data buffer
					NSMutableArray *msgs = nil;
					[cnx.buffer appendBytes:cnx.tmpBuf length:numBytes];
					NSUInteger bufferLength = [cnx.buffer length];
					while (bufferLength > 4)
					{
						// check whether we have a full message
						uint32_t length;
						[cnx.buffer getBytes:&length length:4];
						length = ntohl(length);
						if (bufferLength < (length + 4))
							break;
						
						// get one message
						CFDataRef subset = CFDataCreateWithBytesNoCopy(kCFAllocatorDefault,
																	   (unsigned char *)[cnx.buffer mutableBytes] + 4,
																	   length,
																	   kCFAllocatorNull);
						if (subset != NULL)
						{
							LoggerMessage *message = [[LoggerNativeMessage alloc] initWithData:(NSData *)subset];
							if (message.type == LOGMSG_TYPE_CLIENTINFO)
								[cnx clientInfoReceived:message];
							else
							{
								if (msgs == nil)
									msgs = [[NSMutableArray alloc] init];
								[msgs addObject:message];
							}
							[message release];
							CFRelease(subset);
						}
						[cnx.buffer replaceBytesInRange:NSMakeRange(0, length+4) withBytes:NULL length:0];
						bufferLength = [cnx.buffer length];
					}
					
					if ([msgs count])
						[cnx messagesReceived:msgs];
					[msgs release];
				}
				break;
				
			case NSStreamEventErrorOccurred:
				NSLog(@"Stream error occurred");
				// fall through
			case NSStreamEventEndEncountered:
				cnx.connected = NO;
				[cnx.buffer setLength:0];
				break;
				
			case NSStreamEventOpenCompleted:
				cnx.connected = YES;
				break;
				
			default:
				break;
		}
	}
	@catch (NSException * e)
	{
	}
	@finally
	{
		[pool release];
	}	
}

// -----------------------------------------------------------------------------
// NSNetService delegate
// -----------------------------------------------------------------------------
- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict
{
	NSLog(@"netServiceDidNotPublish %@", errorDict);
}

@end

static void AcceptSocketCallback(CFSocketRef sock, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	@try
	{
		if (type == kCFSocketAcceptCallBack)
		{
			// reenable accept callback
			CFSocketEnableCallBacks(sock, kCFSocketAcceptCallBack);

			// we have a new incoming connection with a child socket
			int addrSize;
			LoggerNativeTransport *myself = (LoggerNativeTransport *)info;
			BOOL ipv6 = (sock == myself.listenerSocket_ipv6);
			if (!ipv6)
				addrSize = sizeof(struct sockaddr_in);
			else
				addrSize = sizeof(struct sockaddr_in6);
			
			if (CFDataGetLength(address) == addrSize)
			{
				// create the input stream (that's all we need)
				CFSocketNativeHandle nativeSocketHandle = *(CFSocketNativeHandle *)data;
				CFReadStreamRef readStream = NULL;
				CFStreamCreatePairWithSocket(kCFAllocatorDefault, nativeSocketHandle, &readStream, NULL);
				if (readStream != NULL) 
				{
					CFReadStreamSetProperty(readStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);

					LoggerNativeConnection *cnx = [[LoggerNativeConnection alloc] initWithStream:(NSInputStream *)readStream
																				   clientAddress:(NSData *)address];
					[myself addConnection:cnx];
					[(NSInputStream *)readStream setDelegate:myself];
					[(NSInputStream *)readStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
					[(NSInputStream *)readStream open];
					[(NSInputStream *)readStream release];
					[cnx release];
				}
				else
				{
					// immediately close the child socket, we can't use it anymore
					close(nativeSocketHandle);
				}
			}
		}
	}
	@catch (NSException * e)
	{
		NSLog(@"LoggerNativeTransport %p: exception catched in AcceptSocketCallback: %@", info, e);
	}
	@finally
	{
		[pool release];
	}
}
