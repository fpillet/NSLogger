/*
 * LoggerTCPTransport.m
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

/*
 * This class implements a TCP TRANSPORT with support for publishing over Bonjour,
 * as well as regular and SSL connection types.
 *
 * Subclasses implement the actual packet format decoding.
 *
 * A transport instance implements a specific type of transport, and holds any number of current
 * connections that send it logs in its format. Decoded messages are then being held in each
 * LoggerConnection subclass instance.
 */

#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#import "LoggerCommon.h"
#import "LoggerTCPTransport.h"
#import "LoggerStatusWindowController.h"
#import "LoggerAppDelegate.h"
#import "LoggerTCPConnection.h"
#import "LoggerMessage.h"

/* Local prototypes */
static void AcceptSocketCallback(CFSocketRef sock, CFSocketCallBackType type, CFDataRef address, const void *data, void *info);

@implementation LoggerTCPTransport

@synthesize listenerPort, listenerSocket_ipv4, listenerSocket_ipv6;
@synthesize publishBonjourService;

- (void)dealloc
{
	[self.listenerThread cancel];
}

- (NSString *)transportStatusString
{
	if (self.failed)
	{
		if (self.failureReason != nil)
			return self.failureReason;
		return NSLocalizedString(@"Failed opening service", @"Transport failed opening - unknown reason");
	}
	if (self.active && self.ready)
	{
		__block NSInteger numConnected = 0;
		[self.connections enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
			if (((LoggerConnection *)obj).connected)
				numConnected++;
		}];

		if (numConnected == 0)
			return NSLocalizedString(@"Ready to accept connections", @"Transport ready status");
		if (numConnected == 1)
			return NSLocalizedString(@"1 active connection", @"1 active connection for transport");
		return [NSString stringWithFormat:NSLocalizedString(@"%d active connections", @"Number of active connections for transport"), numConnected];
	}
	if (self.active)
		return NSLocalizedString(@"Opening service", @"Transport status: opening");
	return NSLocalizedString(@"Unavailable", @"Transport status: service unavailable");
}

- (void)restart
{
	if (self.active)
	{
		// Check whether we need to actually restart the service if the settings have changed
		BOOL shouldRestart = NO;
		if (publishBonjourService)
		{
			// Check whether the bonjour service name changed
			NSString *newBonjourServiceName = [self bonjourServiceName];
			shouldRestart = (([newBonjourServiceName length] != [self.bonjourServiceName length]) ||
							 (self.bonjourServiceName != nil && [newBonjourServiceName caseInsensitiveCompare:self.bonjourServiceName] != NSOrderedSame));
		}
		else
		{
			shouldRestart = (listenerPort != [self tcpPort]);
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
	if (self.active)
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
	if (!self.active)
	{
		self.active = YES;
		self.ready = NO;
		self.failed = NO;
		self.failureReason = nil;
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(completeRestart) object:nil];
		[[NSNotificationCenter defaultCenter] postNotificationName:kShowStatusInStatusWindowNotification object:self];	
		[NSThread detachNewThreadSelector:@selector(listenerThreadWorker) toTarget:self withObject:nil];
	}
}

- (void)shutdown
{
	if (!self.active)
		return;

	if ([NSThread currentThread] != self.listenerThread)
	{
		[self performSelector:_cmd onThread:self.listenerThread withObject:nil waitUntilDone:YES];
		return;
	}

	// stop Bonjour service
	[self.bonjourService setDelegate:nil];
	[self.bonjourService stop];
	self.bonjourService = nil;

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
	while ([self.connections count])
		[self removeConnection:[self.connections objectAtIndex:0]];
	
	[self.listenerThread cancel];
	
	// when exiting this selector, we'll get out of the runloop. Thread being cancelled, it will be
	// deactivated immediately. We can safely reset active and listener thread just now so that
	// another startup with a different port can take place.
	self.listenerThread = nil;
	self.active = NO;
	
	[[NSNotificationCenter defaultCenter] postNotificationName:kShowStatusInStatusWindowNotification object:self];	
}

- (void)removeConnection:(LoggerConnection *)aConnection
{
	if (self.listenerThread != nil && [NSThread currentThread] != self.listenerThread)
	{
		[self performSelector:_cmd onThread:self.listenerThread withObject:aConnection waitUntilDone:NO];
		return;
	}
	[super removeConnection:aConnection];
}

- (BOOL)setup
{
	@try
	{
		// Only setup sockets when not using Bonjour because the `NSNetServiceListenForConnections`
		// option automatically takes care of setting up sockets for listening
		if (!publishBonjourService)
		{
			CFSocketContext context = {0, (__bridge void *)self, NULL, NULL, NULL};
			
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
			
			if (CFSocketSetAddress(listenerSocket_ipv4, (__bridge CFDataRef)address4) != kCFSocketSuccess)
			{
				@throw [NSException exceptionWithName:@"CFSocketSetAddress"
				                               reason:NSLocalizedString(@"Failed setting IPv4 socket address", @"")
				                             userInfo:nil];
			}
			
			if (listenerPort == 0)
			{
				// now that the binding was successful, we get the port number
				// -- we will need it for the v6 endpoint and for NSNetService
				NSData *addr = (__bridge NSData *)CFSocketCopyAddress(listenerSocket_ipv4);
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
			
			if (CFSocketSetAddress(listenerSocket_ipv6, (__bridge CFDataRef)address6) != kCFSocketSuccess)
			{
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
			
			self.ready = YES;
		}
		else
		{
			// The service type is nslogger-ssl (now the default), or nslogger for backwards
			// compatibility with pre-1.0.
			NSString *serviceType = [self bonjourServiceType];

			// The service name is either the one defined in the prefs, or by default
			// the local computer name (as defined in the sharing prefs panel
			// (see Technical Q&A QA1228 http://developer.apple.com/library/mac/#qa/qa2001/qa1228.html )
			NSString *serviceName = [[NSUserDefaults standardUserDefaults] objectForKey:kPrefBonjourServiceName];
			BOOL useDefaultServiceName = (serviceName == nil || ![serviceName isKindOfClass:[NSString class]] || ![serviceName length]);
			if (useDefaultServiceName)
				serviceName = @"";

			self.bonjourServiceName = serviceName;

			self.bonjourService = [[NSNetService alloc] initWithDomain:@""
															 type:(NSString *)serviceType
															 name:(NSString *)serviceName
															 port:(int)listenerPort];

			// added in 1.5: let clients know that we have customized our service name and that they should connect to us
			// only if their own settings match our name
			if (!useDefaultServiceName)
			{
				NSData *filterData = [@"1" dataUsingEncoding:NSASCIIStringEncoding];
				[self.bonjourService setTXTRecordData:[NSNetService dataFromTXTRecordDictionary:@{@"filterClients": filterData}]];
			}

			[self.bonjourService setIncludesPeerToPeer:YES];
			[self.bonjourService setDelegate:self];
			[self.bonjourService publishWithOptions:NSNetServiceListenForConnections];
		}
	}
	@catch (NSException * e)
	{
		self.failed = YES;
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

- (void)listenerThreadWorker
{
	self.listenerThread = [NSThread currentThread];
	[self.listenerThread threadDictionary][@"runLoop"] = NSRunLoop.currentRunLoop;
	@autoreleasepool
	{
#ifdef DEBUG
		NSString *description = [self description];
		NSLog(@"Entering listenerThread for transport %@", description);
#endif
		@try
		{
			if ([self setup])
			{
				while (![self.listenerThread isCancelled])
				{
					NSDate *next = [[NSDate alloc] initWithTimeIntervalSinceNow:0.10];
					[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:next];
				}
			}
		}
		@catch (NSException *e)
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
			self.listenerThread = nil;
			self.active = NO;
		}
	}
}

- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p listenerPort=%d publishBonjourService=%d secure=%d>", 
			[self class], self, (int)listenerPort, (int)publishBonjourService, (int)self.secure];
}

- (BOOL)canDoSSL
{
	LoggerAppDelegate *appDelegate = (LoggerAppDelegate *)[[NSApplication sharedApplication] delegate];
	if (!appDelegate.serverCertsLoadAttempted)
	{
		NSError *error = nil;
		if (![appDelegate loadEncryptionCertificate:&error])
		{
			[NSApp performSelectorOnMainThread:@selector(presentError:) withObject:error waitUntilDone:NO];
		}
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
		CFReadStreamSetProperty((__bridge CFReadStreamRef)readStream, kCFStreamPropertySSLSettings, SSLDict);

        // force usage if TLSv1.2 or higher
        SSLContextRef context = (__bridge SSLContextRef) [readStream propertyForKey:(__bridge NSString *) kCFStreamPropertySSLContext];
        SSLSetProtocolVersionMin(context, kTLSProtocol12);
        
		CFRelease(SSLDict);
		return YES;
	}
	return NO;
}

// -----------------------------------------------------------------------------
// Methods that MUST be overriden by subclasses
// -----------------------------------------------------------------------------
- (NSString *)bonjourServiceName
{
	// subclasses must override this
	assert(false);
	return nil;
}

- (NSString *)bonjourServiceType
{
	// subclasses must override this
	assert(false);
	return nil;
}

- (NSInteger)tcpPort
{
	// subclasses must override this
	assert(false);
	return 0;
}

- (LoggerConnection *)connectionWithInputStream:(NSInputStream *)is outputStream:(NSOutputStream *)os clientAddress:(NSData *)addr
{
	// subclasses must implement this
	assert(false);
	return nil;
}

- (void)processIncomingData:(LoggerTCPConnection *)cnx
{
	// subclasses must implement this
	assert(false);
}

// -----------------------------------------------------------------------------
// NSStream delegate
// -----------------------------------------------------------------------------
- (void)stream:(NSStream *)theStream handleEvent:(NSStreamEvent)streamEvent
{
	@autoreleasepool
	{
		@try
		{
			// Locate the connection to which this stream is attached
			LoggerTCPConnection *cnx = nil;
			for (cnx in self.connections)
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
                case NSStreamEventHasSpaceAvailable:
                    break;
                    
				case NSStreamEventHasBytesAvailable:
					while ([cnx.readStream hasBytesAvailable])
					{
						// read bytes
						numBytes = [cnx.readStream read:cnx.tmpBuf maxLength:cnx.tmpBufSize];
						if (numBytes <= 0)
							break;
						[cnx.buffer appendBytes:cnx.tmpBuf length:(NSUInteger) numBytes];

						// method implemented by subclasses, depending on the input format
						[self processIncomingData:cnx];
					}
					break;

				case NSStreamEventErrorOccurred: {
#if DEBUG
					NSLog(@"Stream error occurred: stream=%@ self=%@ error=%@", theStream, self, [theStream streamError]);
#endif
					NSError *error = [theStream streamError];
					NSInteger errCode = [error code];
					if (errCode == errSSLDecryptionFail || errCode == errSSLBadRecordMac)
					{
						// SSL failure due to the application not being codesigned
						// See https://devforums.apple.com/thread/77848?tstart=0
						dispatch_async(dispatch_get_main_queue(), ^{
							NSDictionary *dict = @{
								NSLocalizedDescriptionKey: NSLocalizedString(@"NSLogger SSL authentication failure", @""),
								NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Your NSLogger build may not be codesigned. As a result, a conflict between Firewall and Keychain tagging of your viewer requires that you restart NSLogger to complete the SSL certificate authorization.\n\nRestart NSLogger now to fix the issue.", @""),
								NSUnderlyingErrorKey: [NSString stringWithFormat:@"CFStream error %d", (int) errCode],
								NSLocalizedRecoverySuggestionErrorKey: NSLocalizedString(@"Click the Restart button to restart NSLogger now.", @""),
								NSLocalizedRecoveryOptionsErrorKey: @[NSLocalizedString(@"Restart", @"")],
								NSRecoveryAttempterErrorKey: [NSApp delegate]
							};
							[NSApp presentError:[NSError errorWithDomain:@"NSLogger"
																	code:errCode
																userInfo:dict]];
						});
					}
                    
                    // in all cases, we need to properly clean up the connection
                    [cnx shutdown];
					break;
				}

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
		}
		@catch (NSException * e)
		{
		}
	}
}

// -----------------------------------------------------------------------------
// NSNetService delegate
// -----------------------------------------------------------------------------
- (void)netService:(NSNetService *)sender didNotPublish:(NSDictionary *)errorDict
{
#ifdef DEBUG
    NSLog(@"netServiceDidNotPublish, error=%@", errorDict);
#endif
	[self shutdown];
	
	int errorCode = (int)[errorDict[NSNetServicesErrorCode] integerValue];
	if (errorCode == NSNetServicesCollisionError)
		self.failureReason = NSLocalizedString(@"Duplicate Bonjour service name on your network", @"");
	else if (errorCode == NSNetServicesBadArgumentError)
		self.failureReason = NSLocalizedString(@"Bonjour bad argument - please report bug.", @"");
	else if (errorCode == NSNetServicesInvalidError)
		self.failureReason = NSLocalizedString(@"Bonjour invalid configuration - please report bug.", @"");
	else
		self.failureReason = [NSString stringWithFormat:NSLocalizedString(@"Bonjour error %d", @""), errorCode];
	self.failed = YES;

	[[NSNotificationCenter defaultCenter] postNotificationName:kShowStatusInStatusWindowNotification object:self];
}

- (void)netServiceDidPublish:(NSNetService *)sender
{
	self.ready = YES;
	listenerPort = sender.port;
	[[NSNotificationCenter defaultCenter] postNotificationName:kShowStatusInStatusWindowNotification
														object:self];
}

- (void)netService:(NSNetService *)sender didAcceptConnectionWithInputStream:(NSInputStream *)inputStream outputStream:(NSOutputStream *)outputStream
{
#ifdef DEBUG
    NSLog(@"incoming connection");
#endif
	if (self.secure && ![self canDoSSL])
		return;
	
	if (self.secure)
		[self setupSSLForStream:inputStream];
	
	NSData *clientAddress = nil; // TODO: how to get it?
    [self addConnection:[self connectionWithInputStream:inputStream outputStream:outputStream clientAddress:clientAddress]];
	
	[inputStream setDelegate:self];
	[inputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	[inputStream open];

    [outputStream setDelegate:self];
	[outputStream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
	[outputStream open];
}

@end

static void AcceptSocketCallback(CFSocketRef sock, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
	@autoreleasepool
	{
		@try
		{
			if (type == kCFSocketAcceptCallBack)
			{
				// we have a new incoming connection with a child socket
				// reenable accept callback
				CFSocketEnableCallBacks(sock, kCFSocketAcceptCallBack);

				// Get the native socket handle for the new incoming connection
				CFSocketNativeHandle nativeSocketHandle = *(CFSocketNativeHandle *)data;

				LoggerTCPTransport *myself = (__bridge LoggerTCPTransport *)info;
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
                        CFWriteStreamRef writeStream = NULL;
						CFStreamCreatePairWithSocket(kCFAllocatorDefault, nativeSocketHandle, &readStream, &writeStream);
						if (readStream != NULL)
						{
							// although this is implied, just want to make sure
							CFReadStreamSetProperty(readStream, kCFStreamPropertyShouldCloseNativeSocket, kCFBooleanTrue);
							if (myself.secure)
								[myself setupSSLForStream:(__bridge NSInputStream *)readStream];

							// Create the connection instance
                            [myself addConnection:[myself connectionWithInputStream:(__bridge NSInputStream *)readStream outputStream:(__bridge NSOutputStream *)writeStream clientAddress:(__bridge NSData *)address]];

							// Schedule & open streams
                            for (NSStream *stream in @[(__bridge NSInputStream *)readStream, (__bridge NSOutputStream *)writeStream])
                            {
                                [stream setDelegate:myself];
                                [stream scheduleInRunLoop:[NSRunLoop currentRunLoop] forMode:NSDefaultRunLoopMode];
                                
                                [stream open];

							}
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
		}
		@catch (NSException * e)
		{
	#ifdef DEBUG
			NSLog(@"LoggerTCPTransport %p: exception catched in AcceptSocketCallback: %@", info, e);
	#endif
		}
	}
}
