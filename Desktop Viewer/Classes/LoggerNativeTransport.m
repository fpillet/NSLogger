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
#include <sys/time.h>
#include <netinet/in.h>
#import "LoggerCommon.h"
#import "LoggerNativeTransport.h"
#import "LoggerNativeConnection.h"
#import "LoggerNativeMessage.h"
#import "LoggerStatusWindowController.h"
#import "LoggerAppDelegate.h"

/* Local prototypes */
static void AcceptSocketCallback(CFSocketRef sock, CFSocketCallBackType type, CFDataRef address, const void *data, void *info);

@implementation LoggerNativeTransport

@synthesize listenerPort, listenerSocket_ipv4, listenerSocket_ipv6, publishBonjourService;

- (void)startup
{
	if (!active)
	{
		active = YES;
		[NSThread detachNewThreadSelector:@selector(listenerThread) toTarget:self withObject:nil];		
	}
}

- (void)shutdown
{
	if (!active)
		return;

	if ([NSThread currentThread] != listenerThread)
	{
		[self performSelector:_cmd onThread:listenerThread withObject:nil waitUntilDone:YES];
		return;
	}
	
	// post status update
	NSString *status;
	if (publishBonjourService)
		status = NSLocalizedString(@"Bonjour service closing.", @"");
	else
		status = [NSString stringWithFormat:NSLocalizedString(@"TCP/IP responder for port %d closing.", @""), listenerPort];
	[[NSNotificationCenter defaultCenter] postNotificationName:kShowStatusInStatusWindowNotification
														object:status];

	// stop Bonjour service
	[bonjourService setDelegate:nil];
	[bonjourService stop];
	[bonjourService release];
	bonjourService = nil;

	// close listener sockets (removing input sources)
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
	
	[listenerThread cancel];
	
	// when exiting this selector, we'll get out of the runloop. Thread being cancelled, it will be
	// deactivated immediately. We can safely reset active and listener thread just now so that
	// another startup with a different port can take place.
	listenerThread = nil;
	active = NO;
}

- (void)dealloc
{
	[listenerThread cancel];
	[bonjourService release];
	[super dealloc];
}

- (void)removeConnection:(LoggerConnection *)aConnection
{
	if (listenerThread != nil && [NSThread currentThread] != listenerThread)
	{
		[self performSelector:_cmd onThread:listenerThread withObject:aConnection waitUntilDone:NO];
		return;
	}
	[super removeConnection:aConnection];
}

- (BOOL)setup
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
		addr4.sin_port = htons(listenerPort);
		addr4.sin_addr.s_addr = htonl(INADDR_ANY);
		NSData *address4 = [NSData dataWithBytes:&addr4 length:sizeof(addr4)];
		
	    if (CFSocketSetAddress(listenerSocket_ipv4, (CFDataRef)address4) != kCFSocketSuccess)
		{
			@throw [NSException exceptionWithName:@"CFSocketSetAddress"
										   reason:NSLocalizedString(@"Failed setting socket address", @"")
										 userInfo:nil];
		}
		
		if (listenerPort == 0)
		{
			// now that the binding was successful, we get the port number 
			// -- we will need it for the v6 endpoint and for NSNetService
			NSData *addr = [(NSData *)CFSocketCopyAddress(listenerSocket_ipv4) autorelease];
			memcpy(&addr4, [addr bytes], [addr length]);
			listenerPort = ntohs(addr4.sin_port);
		}
		
	    // set up the IPv6 endpoint
		struct sockaddr_in6 addr6;
		memset(&addr6, 0, sizeof(addr6));
		addr6.sin6_len = sizeof(addr6);
		addr6.sin6_family = AF_INET6;
		addr6.sin6_port = htons(listenerPort);
		memcpy(&(addr6.sin6_addr), &in6addr_any, sizeof(addr6.sin6_addr));
		NSData *address6 = [NSData dataWithBytes:&addr6 length:sizeof(addr6)];
		
		if (CFSocketSetAddress(listenerSocket_ipv6, (CFDataRef)address6) != kCFSocketSuccess)
		{
			@throw [NSException exceptionWithName:@"CFSocketSetAddress"
										   reason:NSLocalizedString(@"Failed setting socket address", @"")
										 userInfo:nil];
		}
		
		// set up the run loop sources for the sockets
		CFRunLoopRef rl = CFRunLoopGetCurrent();
		CFRunLoopSourceRef source4 = CFSocketCreateRunLoopSource(kCFAllocatorDefault, listenerSocket_ipv4, 0);
		CFRunLoopAddSource(rl, source4, kCFRunLoopCommonModes);
		CFRelease(source4);
		
		CFRunLoopSourceRef source6 = CFSocketCreateRunLoopSource(kCFAllocatorDefault, listenerSocket_ipv6, 0);
		CFRunLoopAddSource(rl, source6, kCFRunLoopCommonModes);
		CFRelease(source6);

		// register Bonjour services
		NSString *status;
		if (publishBonjourService)
		{
			bonjourService = [[NSNetService alloc] initWithDomain:@""
															 type:(NSString *)LOGGER_SERVICE_TYPE
															 name:(NSString *)LOGGER_SERVICE_NAME
															 port:listenerPort];
			[bonjourService setDelegate:self];
			[bonjourService publish];

			status = NSLocalizedString(@"Bonjour service starting up...", @"");
		}
		else
		{
			status = [NSString stringWithFormat:@"TCP/IP responder ready (local port %d)", listenerPort];
		}

		[[NSNotificationCenter defaultCenter] postNotificationName:kShowStatusInStatusWindowNotification
															object:status];
	}
	@catch (NSException * e)
	{
		NSString *status;
		if (publishBonjourService)
			status = NSLocalizedString(@"Failed creating sockets for Bonjour service.", @"");
		else
			status = [NSString stringWithFormat:NSLocalizedString(@"Failed starting TCP/IP responder on port %d",@""), listenerPort];
		[[NSNotificationCenter defaultCenter] postNotificationName:kShowStatusInStatusWindowNotification
															object:status];
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
		return NO;
	}
	return YES;
}

- (void)listenerThread
{
	listenerThread = [NSThread currentThread];
	[[listenerThread threadDictionary] setObject:[NSRunLoop currentRunLoop] forKey:@"runLoop"];
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
#ifdef DEBUG
	NSString *description = [self description];
	NSLog(@"Entering listenerThread for transport %@", description);
#endif
	@try
	{
		if ([self setup])
		{
			while (![listenerThread isCancelled])
			{
				NSDate *next = [[NSDate alloc] initWithTimeIntervalSinceNow:0.10];
				[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:next];
				[next release];
			}
		}
	}
	@catch (NSException * e)
	{
#ifdef DEBUG
		NSLog(@"listenerThread catched exception %@", e);
#endif
	}
	@finally
	{
#ifdef DEBUG
		NSLog(@"Exiting listenerThread for transport %@", description);
#endif
		[pool release];
		listenerThread = nil;
		active = NO;
	}
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p listenerPort=%d publishBonjourService=%d>", 
			[self class], self, listenerPort, (int)publishBonjourService];
}

#ifdef DEBUG
- (void)dumpBytes:(uint8_t *)bytes length:(int)dataLen
{
	NSMutableString *s = [[NSMutableString alloc] init];
	NSUInteger offset = 0;
	NSString *str;
	char buffer[1+6+16*3+1+16+1+1+1];
	buffer[0] = '\0';
	const unsigned char *q = bytes;
	if (dataLen == 1)
		[s appendString:NSLocalizedString(@"Raw data, 1 byte:\n", @"")];
	else
		[s appendFormat:NSLocalizedString(@"Raw data, %u bytes:\n", @""), dataLen];
	while (dataLen)
	{
		int i, b = sprintf(buffer," %04x: ", offset);
		for (i=0; i < 16 && i < dataLen; i++)
			sprintf(&buffer[b+3*i], "%02x ", (int)q[i]);
		for (int j=i; j < 16; j++)
			strcat(buffer, "   ");
		
		b = strlen(buffer);
		buffer[b++] = '\'';
		for (i=0; i < 16 && i < dataLen; i++, q++)
		{
			if (*q >= 32 && *q < 128)
				buffer[b++] = *q;
			else
				buffer[b++] = ' ';
		}
		for (int j=i; j < 16; j++)
			buffer[b++] = ' ';
		buffer[b++] = '\'';
		buffer[b++] = '\n';
		buffer[b] = 0;
		
		str = [[NSString alloc] initWithBytes:buffer length:strlen(buffer) encoding:NSISOLatin1StringEncoding];
		[s appendString:str];
		[str release];
		
		dataLen -= i;
		offset += i;
	}
	NSLog(@"Received bytes:\n%@", s);
	[s release];
}
#endif

- (NSString *)clientInfoStringForMessage:(LoggerMessage *)message
{
	NSDictionary *parts = message.parts;
	NSString *clientName = [parts objectForKey:[NSNumber numberWithInteger:PART_KEY_CLIENT_NAME]];
	NSString *clientVersion = [parts objectForKey:[NSNumber numberWithInteger:PART_KEY_CLIENT_VERSION]];
	NSString *clientAppInfo = @"";
	if ([clientName length])
		clientAppInfo = [NSString stringWithFormat:NSLocalizedString(@"\nClient: %@ %@", @""),
						 clientName,
						 clientVersion ? clientVersion : @""];

	NSString *osName = [parts objectForKey:[NSNumber numberWithInteger:PART_KEY_OS_NAME]];
	NSString *osVersion = [parts objectForKey:[NSNumber numberWithInteger:PART_KEY_OS_VERSION]];
	NSString *osInfo = @"";
	if ([osName length])
		osInfo = [NSString stringWithFormat:NSLocalizedString(@"\nOS: %@ %@", @""),
				  osName,
				  osVersion ? osVersion : @""];

	NSString *hardware = [parts objectForKey:[NSNumber numberWithInteger:PART_KEY_CLIENT_MODEL]];
	NSString *hardwareInfo = @"";
	if ([hardware length])
		hardwareInfo = [NSString stringWithFormat:NSLocalizedString(@"\nHardware: %@", @""), hardware];
	
	NSString *uniqueID = [parts objectForKey:[NSNumber numberWithInteger:PART_KEY_UNIQUEID]];
	NSString *uniqueIDString = @"";
	if ([uniqueID length])
		uniqueIDString = [NSString stringWithFormat:NSLocalizedString(@"\nUDID: %@", @""), uniqueID];
	return [NSString stringWithFormat:NSLocalizedString(@"Client connected%@%@%@%@", @""),
			clientAppInfo, osInfo, hardwareInfo, uniqueIDString];
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
					NSMutableArray *msgs = [[NSMutableArray alloc] init];
					//[self dumpBytes:cnx.tmpBuf length:numBytes];
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
																	   (unsigned char *)[cnx.buffer bytes] + 4,
																	   length,
																	   kCFAllocatorNull);
						if (subset != NULL)
						{
							LoggerMessage *message = [[LoggerNativeMessage alloc] initWithData:(NSData *)subset];
							if (message.type == LOGMSG_TYPE_CLIENTINFO)
							{
								message.message = [self clientInfoStringForMessage:message];
								message.threadID = @"";
								[cnx clientInfoReceived:message];
							}
							[msgs addObject:message];
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
				// @@@ TODO: add message with error description
#ifdef DEBUG
				NSLog(@"Stream error occurred: %@", [theStream streamError]);
#endif
				// fall through
			case NSStreamEventEndEncountered: {
				// Append a disconnect message for only one of the two streams
				struct timeval t;
				gettimeofday(&t, NULL);
				LoggerMessage *msg = [[LoggerMessage alloc] init];
				msg.timestamp = t;
				msg.type = LOGMSG_TYPE_DISCONNECT;
				msg.message = NSLocalizedString(@"Client disconnected", @"");
				[cnx messagesReceived:[NSArray arrayWithObject:msg]];
				[msg release];
				cnx.connected = NO;
				[cnx.buffer setLength:0];
				break;
			}
				
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
	[self shutdown];
	
	NSString *errorString = [errorDict description];
	int errorCode = [[errorDict objectForKey:NSNetServicesErrorCode] integerValue];
	if (errorCode == NSNetServicesCollisionError)
		errorString = NSLocalizedString(@"Another logger may be publishing itself on your network with the same name", @"");
	else if (errorCode == NSNetServicesBadArgumentError)
		errorString = NSLocalizedString(@"Bonjour is improperly configured (bad argument) - please contact NSLogger developers", @"");
	else if (errorCode == NSNetServicesInvalidError)
		errorString = NSLocalizedString(@"Bonjour is improperly configured (invalid) - please contact NSLogger developers", @"");

	NSString *status = [NSString stringWithFormat:NSLocalizedString(@"Failed starting Bonjour service (%@).", @""), errorString];
	[[NSNotificationCenter defaultCenter] postNotificationName:kShowStatusInStatusWindowNotification object:status];
}

- (void)netServiceDidPublish:(NSNetService *)sender
{
	NSString *status = [NSString stringWithFormat:@"Bonjour service ready (%@ local port %d)", [sender domain], listenerPort];
	[[NSNotificationCenter defaultCenter] postNotificationName:kShowStatusInStatusWindowNotification
														object:status];
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
				// create the input and output streams. We don't need an output stream,
				// except for SSL negotiation.
				CFSocketNativeHandle nativeSocketHandle = *(CFSocketNativeHandle *)data;
				CFReadStreamRef readStream = NULL;
				CFStreamCreatePairWithSocket(kCFAllocatorDefault, nativeSocketHandle, &readStream, NULL);
				if (readStream != NULL)
				{
					// although this is implied, just want to make sure
					CFReadStreamSetProperty(readStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
					CFReadStreamSetProperty(readStream, kCFStreamPropertySocketSecurityLevel, kCFStreamSocketSecurityLevelSSLv3);
					
					CFArrayRef serverCerts = ((LoggerAppDelegate *)[[NSApplication sharedApplication] delegate]).serverCerts;
					if (serverCerts != NULL)
					{
						// setup stream for SSL
						const void *SSLKeys[] = {
							kCFStreamSSLLevel,
							kCFStreamSSLValidatesCertificateChain,
							kCFStreamSSLIsServer,
							kCFStreamSSLCertificates
						};
						const void *SSLValues[] = {
							kCFStreamSocketSecurityLevelNegotiatedSSL,
							kCFBooleanFalse,			// no certificate chain validation (we use a self-signed certificate)
							kCFBooleanTrue,				// we are server
							serverCerts,
						};
						CFDictionaryRef SSLDict = CFDictionaryCreate(NULL, SSLKeys, SSLValues, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
						CFReadStreamSetProperty(readStream, kCFStreamPropertySSLSettings, SSLDict);
						CFRelease(SSLDict);
					}

					// Create the connection instance
					LoggerNativeConnection *cnx = [[LoggerNativeConnection alloc] initWithInputStream:(NSInputStream *)readStream
																						clientAddress:(NSData *)address];
					[myself addConnection:cnx];

					// Schedule & open stream
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
#ifdef DEBUG
		NSLog(@"LoggerNativeTransport %p: exception catched in AcceptSocketCallback: %@", info, e);
#endif
	}
	@finally
	{
		[pool release];
	}
}
