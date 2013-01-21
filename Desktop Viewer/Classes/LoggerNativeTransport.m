/*
 * LoggerNativeTransport.m
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

@synthesize listenerPort, listenerSocket_ipv4, listenerSocket_ipv6;
@synthesize publishBonjourService;

- (void)dealloc
{
	[listenerThread cancel];
}

- (NSString *)transportInfoString
{
	if (publishBonjourService)
	{
		NSString *name = bonjourServiceName;
		if (![name length])
			name = [bonjourService name];
		if ([name length])
			return [NSString stringWithFormat:NSLocalizedString(@"Bonjour (%@, port %d%s)", @"Named Bonjour transport info string"),
					name,
					listenerPort,
					secure ? ", SSL" : ""];
		return [NSString stringWithFormat:NSLocalizedString(@"Bonjour (port %d%s)", @"Bonjour transport (default name) info string"),
				listenerPort,
				secure ? ", SSL" : ""];
	}
	return [NSString stringWithFormat:NSLocalizedString(@"TCP/IP (port %d%s)", @"TCP/IP transport info string"),
			listenerPort,
			secure ? ", SSL" : ""];
}

- (NSString *)transportStatusString
{
	if (failed)
	{
		if (failureReason != nil)
			return failureReason;
		return NSLocalizedString(@"Failed opening service", @"Transport failed opening - unknown reason");
	}
	if (active && ready)
	{
		__block NSInteger numConnected = 0;
		[connections enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
			if (((LoggerConnection *)obj).connected)
				numConnected++;
		}];

		if (numConnected == 0)
			return NSLocalizedString(@"Ready to accept connections", @"Transport ready status");
		if (numConnected == 1)
			return NSLocalizedString(@"1 active connection", @"1 active connection for transport");
		return [NSString stringWithFormat:NSLocalizedString(@"%d active connections", @"Number of active connections for transport"), numConnected];
	}
	if (active)
		return NSLocalizedString(@"Opening service", @"Transport status: opening");
	return NSLocalizedString(@"Unavailable", @"Transport status: service unavailable");
}

- (void)restart
{
	if (active)
	{
		// Check whether we need to actually restart the service if the settings have changed
		BOOL shouldRestart = NO;
		if (publishBonjourService)
		{
			// Check whether the bonjour service name changed
			NSString *newBonjourServiceName = [[NSUserDefaults standardUserDefaults] objectForKey:kPrefBonjourServiceName];
			shouldRestart = (([newBonjourServiceName length] != [bonjourServiceName length]) ||
							 (bonjourServiceName != nil && [newBonjourServiceName compare:bonjourServiceName options:NSCaseInsensitiveSearch] != NSOrderedSame));
		}
		else
		{
			int port = [[[NSUserDefaults standardUserDefaults] objectForKey:kPrefDirectTCPIPResponderPort] integerValue];
			shouldRestart = (listenerPort != port);
		}
		if (shouldRestart)
		{
			[self shutdown];
			[self performSelector:@selector(completeRestart) withObject:nil afterDelay:0.1];
		}
	}
	else
	{
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(completeRestart) object:nil];
		[self startup];
	}
}

- (void)completeRestart
{
	if (active)
	{
		// wait for the service to be completely shut down, then restart it
		[self performSelector:_cmd withObject:nil afterDelay:0.1];
		return;
	}
	if (!publishBonjourService)
		listenerPort = [[[NSUserDefaults standardUserDefaults] objectForKey:kPrefDirectTCPIPResponderPort] integerValue];
	[self startup];
}

- (void)startup
{
	if (!active)
	{
		active = YES;
		ready = NO;
		failed = NO;
		self.failureReason = nil;
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(completeRestart) object:nil];
		[[NSNotificationCenter defaultCenter] postNotificationName:kShowStatusInStatusWindowNotification object:self];	
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

	// stop Bonjour service
	[bonjourService setDelegate:nil];
	[bonjourService stop];
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
		[self removeConnection:connections[0]];
	
	[listenerThread cancel];
	
	// when exiting this selector, we'll get out of the runloop. Thread being cancelled, it will be
	// deactivated immediately. We can safely reset active and listener thread just now so that
	// another startup with a different port can take place.
	listenerThread = nil;
	active = NO;
	
	[[NSNotificationCenter defaultCenter] postNotificationName:kShowStatusInStatusWindowNotification object:self];	
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
		CFSocketContext context = {0, (__bridge void *)(self), NULL, NULL, NULL};
		
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
		
	    if (CFSocketSetAddress(listenerSocket_ipv4, CFBridgingRetain(address4)) != kCFSocketSuccess)
		{
			@throw [NSException exceptionWithName:@"CFSocketSetAddress"
										   reason:NSLocalizedString(@"Failed setting IPv4 socket address", @"")
										 userInfo:nil];
		}
		
		if (listenerPort == 0)
		{
			// now that the binding was successful, we get the port number 
			// -- we will need it for the v6 endpoint and for NSNetService
			NSData *addr = (NSData *)CFBridgingRelease(CFSocketCopyAddress(listenerSocket_ipv4));
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
		
		if (CFSocketSetAddress(listenerSocket_ipv6, CFBridgingRetain(address6)) != kCFSocketSuccess) {
			@throw [NSException exceptionWithName:@"CFSocketSetAddress"
										   reason:NSLocalizedString(@"Failed setting IPv6 socket address", @"")
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

		// register Bonjour service
		if (publishBonjourService)
		{
			// The service type is nslogger-ssl (now the default), or nslogger for backwards
			// compatibility with pre-1.0.
			NSString *serviceType = (NSString *)(secure ? LOGGER_SERVICE_TYPE_SSL : LOGGER_SERVICE_TYPE);

			// The service name is either the one defined in the prefs, of by default
			// the local computer name (as defined in the sharing prefs panel
			// (see Technical Q&A QA1228 http://developer.apple.com/library/mac/#qa/qa2001/qa1228.html )
			NSString *serviceName = [[NSUserDefaults standardUserDefaults] objectForKey:kPrefBonjourServiceName];
			if (serviceName == nil || ![serviceName isKindOfClass:[NSString class]])
				serviceName = @"";

			bonjourServiceName = serviceName;

			bonjourService = [[NSNetService alloc] initWithDomain:@""
															 type:(NSString *)serviceType
															 name:(NSString *)serviceName
															 port:listenerPort];
			[bonjourService setDelegate:self];
			[bonjourService publish];
		}
		else
		{
			ready = YES;
		}

	}
	@catch (NSException * e)
	{
		failed = YES;
		if (publishBonjourService)
			self.failureReason = NSLocalizedString(@"Failed creating sockets for Bonjour%s service.", @"");
		else
			self.failureReason = [NSString stringWithFormat:NSLocalizedString(@"Failed listening on port %d (port busy?)",@""), listenerPort];

		[[NSNotificationCenter defaultCenter] postNotificationName:kShowStatusInStatusWindowNotification
															object:self];
		
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
	@finally
	{
		[[NSNotificationCenter defaultCenter] postNotificationName:kShowStatusInStatusWindowNotification
															object:self];
	}
	return YES;
}

- (void)listenerThread
{
	listenerThread = [NSThread currentThread];
	[listenerThread threadDictionary][@"runLoop"] = [NSRunLoop currentRunLoop];
	@autoreleasepool {
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
			listenerThread = nil;
			active = NO;
		}
	}
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p listenerPort=%d publishBonjourService=%d secure=%d>", 
			[self class], self, listenerPort, (int)publishBonjourService, (int)secure];
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
		int i, b = sprintf(buffer," %04lx: ", offset);
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
		
		dataLen -= i;
		offset += i;
	}
	NSLog(@"Received bytes:\n%@", s);
}
#endif

- (NSString *)clientInfoStringForMessage:(LoggerMessage *)message
{
	NSDictionary *parts = message.parts;
	NSString *clientName = parts[@PART_KEY_CLIENT_NAME];
	NSString *clientVersion = parts[@PART_KEY_CLIENT_VERSION];
	NSString *clientAppInfo = @"";
	if ([clientName length])
		clientAppInfo = [NSString stringWithFormat:NSLocalizedString(@"Client connected: %@ %@", @""),
						 clientName,
						 clientVersion ? clientVersion : @""];

	NSString *osName = parts[@PART_KEY_OS_NAME];
	NSString *osVersion = parts[@PART_KEY_OS_VERSION];
	NSString *osInfo = @"";
	if ([osName length])
		osInfo = [NSString stringWithFormat:NSLocalizedString(@"%@ (%@ %@)", @""),
				  [clientAppInfo length] ? @"" : NSLocalizedString(@"Client connected", @""),
				  osName,
				  osVersion ? osVersion : @""];

	NSString *hardware = parts[@PART_KEY_CLIENT_MODEL];
	NSString *hardwareInfo = @"";
	if ([hardware length])
		hardwareInfo = [NSString stringWithFormat:NSLocalizedString(@"\nHardware: %@", @""), hardware];
	
	NSString *uniqueID = parts[@PART_KEY_UNIQUEID];
	NSString *uniqueIDString = @"";
	if ([uniqueID length])
		uniqueIDString = [NSString stringWithFormat:NSLocalizedString(@"\nUDID: %@", @""), uniqueID];
	NSString *header = @"";
	if (clientAppInfo == nil)
		header = NSLocalizedString(@"Client connected\n", @"");
	return [NSString stringWithFormat:@"%@%@%@%@%@", header, clientAppInfo, osInfo, hardwareInfo, uniqueIDString];
}

- (BOOL)canDoSSL
{
	// This method can BLOCK THE CURRENT THREAD and run security dialog UI from the main thread
	LoggerAppDelegate *appDelegate = (LoggerAppDelegate *)[[NSApplication sharedApplication] delegate];
	if (!appDelegate.serverCertsLoadAttempted)
	{
		dispatch_sync(dispatch_get_main_queue(), ^{
			NSError *error = nil;
			if (![appDelegate loadEncryptionCertificate:&error])
			{
				[NSApp performSelector:@selector(presentError:) withObject:error afterDelay:0];
			}
		});
	}
	return (appDelegate.serverCerts != NULL);
}

- (BOOL)setupSSLForStream:(NSInputStream *)readStream
{
	LoggerAppDelegate *appDelegate = (LoggerAppDelegate *)[[NSApplication sharedApplication] delegate];
#ifdef DEBUG
	NSLog(@"setupSSLForStream, stream=%@ self=%@ serverCerts=%@", readStream, self, appDelegate.serverCerts);
#endif
	CFArrayRef serverCerts = appDelegate.serverCerts;
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
		CFReadStreamSetProperty((CFReadStreamRef)readStream, kCFStreamPropertySSLSettings, SSLDict);
		CFRelease(SSLDict);
		return YES;
	}
	return NO;
}

// -----------------------------------------------------------------------------
// NSStream delegate
// -----------------------------------------------------------------------------
- (void)stream:(NSStream *)theStream handleEvent:(NSStreamEvent)streamEvent
{
	@autoreleasepool {
		@try
		{
			// Locate the connection to which this stream is attached
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
					while ([cnx.readStream hasBytesAvailable])
					{
						// read bytes
						numBytes = [cnx.readStream read:cnx.tmpBuf maxLength:cnx.tmpBufSize];
						if (numBytes <= 0)
							break;
						
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
								// we receive a ClientInfo message only when the client connects. Once we get this message,
								// the connection is considered being "live" (we need to wait a bit to let SSL negotiation to
								// take place, and not open a window if it fails).
								LoggerMessage *message = [[LoggerNativeMessage alloc] initWithData:(__bridge NSData *)subset connection:cnx];
								CFRelease(subset);
								if (message.type == LOGMSG_TYPE_CLIENTINFO)
								{
									message.message = [self clientInfoStringForMessage:message];
									message.threadID = @"";
									[cnx clientInfoReceived:message];
									[self attachConnectionToWindow:cnx];
								}
								else
								{
									[msgs addObject:message];
								}
							}
							[cnx.buffer replaceBytesInRange:NSMakeRange(0, length+4) withBytes:NULL length:0];
							bufferLength = [cnx.buffer length];
						}
						
						if ([msgs count])
							[cnx messagesReceived:msgs];
					}
					break;
					
				case NSStreamEventErrorOccurred: {
					NSLog(@"Stream error occurred: stream=%@ self=%@ error=%@", theStream, self, [theStream streamError]);
					NSError *error = [theStream streamError];
					NSInteger errCode = [error code];
					if (errCode == errSSLDecryptionFail || errCode == errSSLBadRecordMac)
					{
						// SSL failure due to the application not being codesigned
						// See https://devforums.apple.com/thread/77848?tstart=0
						dispatch_async(dispatch_get_main_queue(), ^{
							NSDictionary *dict = @{NSLocalizedDescriptionKey: NSLocalizedString(@"NSLogger SSL authentication failure", @""),
												  NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Your NSLogger build may not be codesigned. As a result, a conflict between Firewall and Keychain tagging of your viewer requires that you restart NSLogger to complete the SSL certificate authorization.\n\nRestart NSLogger now to fix the issue.", @""),
												  NSUnderlyingErrorKey: [NSString stringWithFormat:@"CFStream error %ld", errCode],
												  NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Click the Restart button to restart NSLogger now.", @""),
												  NSLocalizedRecoveryOptionsErrorKey: @[NSLocalizedString(@"Restart", @"")],
												  NSRecoveryAttempterErrorKey: [NSApp delegate]};
							[NSApp presentError:[NSError errorWithDomain:@"NSLogger"
																	code:errCode
																userInfo:dict]];
						});
					}
					break;
				}
					// fall through
				case NSStreamEventEndEncountered: {
					// Append a disconnect message for only one of the two streams
					struct timeval t;
					gettimeofday(&t, NULL);
					LoggerMessage *msg = [[LoggerMessage alloc] init];
					msg.timestamp = t;
					msg.type = LOGMSG_TYPE_DISCONNECT;
					msg.message = NSLocalizedString(@"Client disconnected", @"");
					[cnx messagesReceived:@[msg]];
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
		} @catch (NSException * e) {
		}
	}
}

// -----------------------------------------------------------------------------
// NSNetService delegate
// -----------------------------------------------------------------------------
- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict
{
	[self shutdown];
	
	int errorCode = [errorDict[NSNetServicesErrorCode] integerValue];
	if (errorCode == NSNetServicesCollisionError)
		self.failureReason = NSLocalizedString(@"Duplicate Bonjour service name on your network", @"");
	else if (errorCode == NSNetServicesBadArgumentError)
		self.failureReason = NSLocalizedString(@"Bonjour bad argument - please report bug.", @"");
	else if (errorCode == NSNetServicesInvalidError)
		self.failureReason = NSLocalizedString(@"Bonjour invalid configuration - please report bug.", @"");
	else
		self.failureReason = [NSString stringWithFormat:NSLocalizedString(@"Bonjour error %d", @""), errorCode];
	failed = YES;

	[[NSNotificationCenter defaultCenter] postNotificationName:kShowStatusInStatusWindowNotification object:self];
}

- (void)netServiceDidPublish:(NSNetService *)sender
{
	ready = YES;
	[[NSNotificationCenter defaultCenter] postNotificationName:kShowStatusInStatusWindowNotification
														object:self];
}

@end

static void AcceptSocketCallback(CFSocketRef sock, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
	@autoreleasepool {
		@try
		{
			if (type == kCFSocketAcceptCallBack)
			{
				// we have a new incoming connection with a child socket
				// reenable accept callback
				CFSocketEnableCallBacks(sock, kCFSocketAcceptCallBack);
				
				// Get the native socket handle for the new incoming connection
				CFSocketNativeHandle nativeSocketHandle = *(CFSocketNativeHandle *)data;
				
				LoggerNativeTransport *myself = (__bridge LoggerNativeTransport *)info;
				if (myself.secure && ![myself canDoSSL])
				{
					// should enable SSL but loading or authorization failed
					close(nativeSocketHandle);
				}
				else
				{
					int addrSize;
					BOOL ipv6 = (sock == myself.listenerSocket_ipv6);
					if (!ipv6)
						addrSize = sizeof(struct sockaddr_in);
					else
						addrSize = sizeof(struct sockaddr_in6);
					
					if (CFDataGetLength(address) == addrSize)
					{
						// create the input and output streams. We don't need an output stream,
						// except for SSL negotiation.
						CFReadStreamRef readStream = NULL;
						CFStreamCreatePairWithSocket(kCFAllocatorDefault, nativeSocketHandle, &readStream, NULL);
						if (readStream != NULL)
						{
							// although this is implied, just want to make sure
							CFReadStreamSetProperty(readStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
							if (myself.secure)
								[myself setupSSLForStream:(__bridge NSInputStream *)readStream];
							
							// Create the connection instance
							LoggerNativeConnection *cnx = [[LoggerNativeConnection alloc] initWithInputStream:(__bridge NSInputStream *)readStream
																								clientAddress:(__bridge NSData *)address];
							[myself addConnection:cnx];
							
							// Schedule & open stream
							[(__bridge NSInputStream *)readStream setDelegate:myself];
							[(__bridge NSInputStream *)readStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
							
							[(__bridge NSInputStream *)readStream open];
							
						}
						else
						{
							// immediately close the child socket, we can't use it anymore
							close(nativeSocketHandle);
						}
					}
					else
					{
						// no valid address?
						close(nativeSocketHandle);
					}
				}
			}
		} @catch (NSException * e) {
#ifdef DEBUG
			NSLog(@"LoggerNativeTransport %p: exception catched in AcceptSocketCallback: %@", info, e);
#endif
		}
	}
}
