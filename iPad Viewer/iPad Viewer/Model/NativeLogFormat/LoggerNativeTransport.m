/*
 *
 * Modified BSD license.
 *
 * Based on source code copyright (c) 2010-2012 Florent Pillet,
 * Copyright (c) 2012-2013 Sung-Taek, Kim <stkim1@colorfulglue.com> All Rights
 * Reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * 3. Any redistribution is done solely for personal benefit and not for any
 *    commercial purpose or for monetary gain
 *
 * 4. No binary form of source code is submitted to App Store℠ of Apple Inc.
 *
 * 5. Neither the name of the Sung-Taek, Kim nor the names of its contributors
 *    may be used to endorse or promote products derived from  this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR  IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL COPYRIGHT HOLDER AND AND CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *
 */

#include <dns_sd.h>
#include <dns_util.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <netinet/in.h>
#import "LoggerCommon.h"
#import "LoggerNativeTransport.h"
#import "LoggerNativeConnection.h"
#import "LoggerNativeMessage.h"

/* Local prototypes */
static void
AcceptSocketCallback(CFSocketRef, CFSocketCallBackType, CFDataRef, const void*, void*);


@interface LoggerNativeTransport()
static void
ServiceRegisterCallback(DNSServiceRef,DNSServiceFlags,DNSServiceErrorType,const char*,const char*,const char*,void*);
static void
ServiceRegisterSocketCallBack(CFSocketRef,CFSocketCallBackType,CFDataRef,const void*,void*);
-(void)startListening;
-(void)destorySockets;
- (void)didNotRegisterWithError:(DNSServiceErrorType)errorCode;
- (void)didRegisterWithDomain:(const char *)domain name:(const char *)name;
@end

@implementation LoggerNativeTransport
{
	BOOL				_useBluetooth;
	DNSServiceRef		_sdServiceRef;
	CFSocketRef			_sdServiceSocket;	// browser service socket to tie in the current runloop
	CFRunLoopSourceRef	_sdServiceRunLoop;	// browser service callback runloop
}
@synthesize listenerPort, listenerSocket_ipv4, listenerSocket_ipv6;
@synthesize publishBonjourService;
@synthesize useBluetooth = _useBluetooth;

- (void)dealloc
{
	[self destorySockets];
	[listenerThread cancel];
	[bonjourServiceName release];
	[super dealloc];
}

//------------------------------------------------------------------------------
#pragma mark - Info Strings
//------------------------------------------------------------------------------
- (NSString *)description
{
	return [NSString stringWithFormat:@"<%@ %p listenerPort=%d publishBonjourService=%d secure=%d>"
			,[self class] ,self ,listenerPort ,(int)publishBonjourService ,(int)secure];
}

- (NSString *)transportInfoString
{
	if (publishBonjourService)
	{
		NSString *name = bonjourServiceName;
		if ([name length])
		{
			return [NSString
					stringWithFormat:
					NSLocalizedString(@"Bonjour (%@, port %d%s)", @"Named Bonjour transport info string")
					,name
					,listenerPort
					,secure ? ", SSL" : ""];
		}

		return [NSString
				stringWithFormat:NSLocalizedString(@"Bonjour (port %d%s)", @"Bonjour transport (default name) info string")
				,listenerPort
				,secure ? ", SSL" : ""];
	}

	return [NSString
			stringWithFormat:NSLocalizedString(@"TCP/IP (port %d%s)", @"TCP/IP transport info string")
			,listenerPort
			,secure ? ", SSL" : ""];
}

- (NSString *)transportStatusString
{
	if (failed)
	{
		if (failureReason != nil)
		{
			return failureReason;
		}
		
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

- (NSDictionary *)status
{
	return
		@{kTransportTag:[NSNumber numberWithInt:[self tag]]
		,kTransportSecure:[NSNumber numberWithBool:[self secure]]
		,kTransportReady:[NSNumber numberWithBool:[self ready]]
		,kTransportActivated:[NSNumber numberWithBool:[self active]]
		,kTransportFailed:[NSNumber numberWithBool:[self failed]]
		,kTransportBluetooth:[NSNumber numberWithBool:[self useBluetooth]]
		,kTransportBonjour:[NSNumber numberWithBool:[self publishBonjourService]]
		,kTransportInfoString:[self transportInfoString]
		,kTransportStatusString:[self transportStatusString]};
}


//------------------------------------------------------------------------------
#pragma mark - Property Controls
//------------------------------------------------------------------------------
- (BOOL)canDoSSL
{
	/*
	 stkim1_dec.11,2012
	 by the time transport object reaches this point server cert must be loaded
	 and ready. If an error ever occured, it should have been reported.
	 All we want atm is to know whether it's ok to go with SSL
	 */
	return [self.certManager isEncryptionCertificateAvailable];
}

static void
ServiceRegisterCallback(DNSServiceRef			sdRef,
						DNSServiceFlags			flags,
						DNSServiceErrorType		errorCode,
						const char				*name,
						const char				*regtype,
						const char				*domain,
						void					*context)

{
	LoggerNativeTransport *callbackSelf = (LoggerNativeTransport *) context;
    assert([callbackSelf isKindOfClass:[LoggerNativeTransport class]]);
    assert(sdRef == callbackSelf->_sdServiceRef);
    assert(flags & kDNSServiceFlagsAdd);
	
    if (errorCode == kDNSServiceErr_NoError)
	{
		// We're assuming SRV records over unicast DNS here, so the first result packet we get
        // will contain all the information we're going to get.  In a more dynamic situation
        // (for example, multicast DNS or long-lived queries in Back to My Mac) we'd would want
        // to leave the query running.
        
		// we only need to find out whether the service is registered. unregsitering is not concerned.
		if (flags & kDNSServiceFlagsAdd)
		{
            [callbackSelf didRegisterWithDomain:domain name:name];
        }
		
    } else {
        [callbackSelf didNotRegisterWithError:errorCode];
    }
}


// A CFSocket callback for Browsing. This runs when we get messages from mDNSResponder
// regarding our DNSServiceRef.  We just turn around and call DNSServiceProcessResult,
// which does all of the heavy lifting (and would typically call BrowserServiceReply).
static void
ServiceRegisterSocketCallBack(CFSocketRef			socket,
							  CFSocketCallBackType	type,
							  CFDataRef				address,
							  const void			*data,
							  void					*info)
{
	DNSServiceErrorType errorCode = kDNSServiceErr_NoError;

	LoggerNativeTransport *callbackSelf = (LoggerNativeTransport *)info;
	assert(callbackSelf != NULL);

	errorCode = DNSServiceProcessResult(callbackSelf->_sdServiceRef);
    if (errorCode != kDNSServiceErr_NoError)
	{
        [callbackSelf didNotRegisterWithError:errorCode];
    }
}

- (BOOL)setup
{
	int yes = 1;
	DNSServiceErrorType errorType	= kDNSServiceErr_NoError;
	int fd = 0;
	CFSocketContext context = { 0, (void *)self, NULL, NULL, NULL };
	CFOptionFlags socketFlag = 0;

	@try
	{
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
			@throw [NSException
					exceptionWithName:@"CFSocketCreate"
					reason:NSLocalizedString(@"Failed creating listener socket (CFSocketCreate failed)", nil)
					userInfo:nil];
		}
		
		// set socket options & addresses
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
			@throw [NSException
					exceptionWithName:@"CFSocketSetAddress"
					reason:NSLocalizedString(@"Failed setting IPv4 socket address", nil)
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
			@throw [NSException
					exceptionWithName:@"CFSocketSetAddress"
					reason:NSLocalizedString(@"Failed setting IPv6 socket address", nil)
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
			BOOL publishingResult = NO;
			
			// The service type is nslogger-ssl (now the default), or nslogger for backwards
			// compatibility with pre-1.0.
			NSString *serviceType = (NSString *)(secure ? LOGGER_SERVICE_TYPE_SSL : LOGGER_SERVICE_TYPE);

			// when bonjour is on, and bluetooth to be used
			DNSServiceFlags serviceFlag = (_useBluetooth) ? kDNSServiceFlagsIncludeP2P : 0;
			
			// The service name is either the one defined in the prefs, of by default
			// the local computer name (as defined in the sharing prefs panel
			// (see Technical Q&A QA1228 http://developer.apple.com/library/mac/#qa/qa2001/qa1228.html )
			NSString *serviceName = [self.prefManager bonjourServiceName];
			if (serviceName == nil || ![serviceName isKindOfClass:[NSString class]])
				serviceName = @"";

			[serviceName retain];
			[bonjourServiceName release];
			bonjourServiceName = serviceName;

			errorType =
				DNSServiceRegister(&(self->_sdServiceRef),		// sdRef
								   serviceFlag,					// flags
								   kDNSServiceInterfaceIndexAny,// interfaceIndex. kDNSServiceInterfaceIndexP2P does not have meanning when serving
								   bonjourServiceName.UTF8String,// name
								   serviceType.UTF8String,		// regtype
								   NULL,						// domain
								   NULL,						// host
								   htons(listenerPort),			// port. just for bt init
								   0,							// txtLen
								   NULL,						// txtRecord
								   ServiceRegisterCallback,		// callBack
								   (void *)(self)				// context
								   );

			if (errorType == kDNSServiceErr_NoError)
			{
				fd = DNSServiceRefSockFD(self->_sdServiceRef);
				if(0 <= fd)
				{
					self->_sdServiceSocket =
						CFSocketCreateWithNative(NULL,
												 fd,
												 kCFSocketReadCallBack,
												 ServiceRegisterSocketCallBack,
												 &context);
					if(self->_sdServiceSocket != NULL)
					{
						socketFlag = CFSocketGetSocketFlags(self->_sdServiceSocket);
						socketFlag = socketFlag &~ (CFOptionFlags)kCFSocketCloseOnInvalidate;
						CFSocketSetSocketFlags(self->_sdServiceSocket,socketFlag);

						self->_sdServiceRunLoop = CFSocketCreateRunLoopSource(NULL,self->_sdServiceSocket, 0);
						CFRunLoopAddSource(CFRunLoopGetCurrent(), self->_sdServiceRunLoop, kCFRunLoopCommonModes);

						publishingResult = YES;
					}
				}
			}

			if(!publishingResult)
			{
				@throw
					[NSException
					 exceptionWithName:@"DNSServiceRegister"
					 reason:[NSString
							 stringWithFormat:@"%@\n\n%@"
							 ,NSLocalizedString(@"Failed announce Bonjour service (DNSServiceRegister failed)", nil)
							 ,@"Transport failed opening - unknown reason"]
					 userInfo:nil];
			}
		}
		else
		{
			ready = YES;
		}
	}
	@catch (NSException * e)
	{
		failed = YES;

		self.failureReason = [e reason];

		NSDictionary *errorStatus =
			@{NSLocalizedDescriptionKey:[e name]
			,NSLocalizedFailureReasonErrorKey:[e reason]};

		[self destorySockets];
		
		[self reportErrorToManager:errorStatus];

		return NO;
	}
	@finally
	{
		[self reportStatusToManager:[self status]];
	}
	return YES;
}

- (void)startListening
{
	listenerThread = [NSThread currentThread];
	[[listenerThread threadDictionary] setObject:[NSRunLoop currentRunLoop] forKey:@"runLoop"];
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
#ifdef DEBUG
	NSString *description = [self description];
	MTLog(@"Entering listenerThread for transport %@", description);
#endif
	@try
	{
		if ([self setup])
		{
			while (![listenerThread isCancelled])
			{
				/*
				 NSDate *next = [[NSDate alloc] initWithTimeIntervalSinceNow:0.10];
				 [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:next];
				 [next release];
				 */
				//stkim1 Feb.02,2013
				//Double autorelease pool is in place to reduce memory pool size
				// as well as performance hit
				@autoreleasepool {
					[[NSRunLoop currentRunLoop] run];
				}
			}
		}
	}
	@catch (NSException * e)
	{
#ifdef DEBUG
		MTLog(@"listenerThread catched exception %@", e);
#endif
	}
	@finally
	{
#ifdef DEBUG
		MTLog(@"Exiting listenerThread for transport %@", description);
#endif
		[pool release];
		listenerThread = nil;
		active = NO;
	}
}

- (void)removeConnection:(LoggerConnection *)aConnection
{
	if (listenerThread != nil && [NSThread currentThread] != listenerThread)
	{
		[self
		 performSelector:_cmd
		 onThread:listenerThread
		 withObject:aConnection
		 waitUntilDone:NO];
		return;
	}
	[super removeConnection:aConnection];
}

//------------------------------------------------------------------------------
#pragma mark - Activity Controls
//------------------------------------------------------------------------------
- (void)restart
{
	if (active)
	{
		// Check whether we need to actually restart the service if the settings have changed
		BOOL shouldRestart = NO;
		if (publishBonjourService)
		{
			// Check whether the bonjour service name changed
			NSString *newBonjourServiceName = \
				[self.prefManager bonjourServiceName];

			shouldRestart = (([newBonjourServiceName length] != [bonjourServiceName length]) ||
							 (bonjourServiceName != nil &&
							  [newBonjourServiceName
							   compare:bonjourServiceName
							   options:NSCaseInsensitiveSearch] != NSOrderedSame));
		}
		else
		{
			int port = [self.prefManager directTCPIPResponderPort];
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
		[NSObject
		 cancelPreviousPerformRequestsWithTarget:self
		 selector:@selector(completeRestart)
		 object:nil];

		[self startup];
	}
}

- (void)startup
{
	if (!active)
	{
		active = YES;
		ready = NO;
		failed = NO;
		self.failureReason = nil;
		
		[NSObject
		 cancelPreviousPerformRequestsWithTarget:self
		 selector:@selector(completeRestart)
		 object:nil];
		
		[self reportStatusToManager:[self status]];
		
		[NSThread
		 detachNewThreadSelector:@selector(startListening)
		 toTarget:self
		 withObject:nil];
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
	{
		listenerPort = [self.prefManager directTCPIPResponderPort];
	}

	[self startup];
}

-(void)destorySockets
{
	if(self->_sdServiceRunLoop != NULL)
	{
		CFRunLoopSourceInvalidate(self->_sdServiceRunLoop);
		CFRelease(self->_sdServiceRunLoop);
		self->_sdServiceRunLoop = NULL;
	}
	
	if (self->_sdServiceSocket != NULL)
	{
        CFSocketInvalidate(self->_sdServiceSocket);
        CFRelease(self->_sdServiceSocket);
        self->_sdServiceSocket = NULL;
    }
	
	// stop DNS-SD service, stop Bonjour service
	if (self->_sdServiceRef != NULL)
	{
        DNSServiceRefDeallocate(self->_sdServiceRef);
        self->_sdServiceRef = NULL;
    }
	
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
}

- (void)shutdown
{
	if (!active)
		return;

	if ([NSThread currentThread] != listenerThread)
	{
		[self
		 performSelector:_cmd
		 onThread:listenerThread
		 withObject:nil
		 waitUntilDone:YES];

		return;
	}

	[self destorySockets];

	// shutdown all connections
	while ([connections count])
		[self removeConnection:[connections objectAtIndex:0]];
	
	[listenerThread cancel];
	
	// when exiting this selector, we'll get out of the runloop. Thread being cancelled, it will be
	// deactivated immediately. We can safely reset active and listener thread just now so that
	// another startup with a different port can take place.
	listenerThread = nil;
	active = NO;

	[self reportStatusToManager:[self status]];
}

//------------------------------------------------------------------------------
#pragma mark - Network Delegate/Callback
//------------------------------------------------------------------------------
- (BOOL)setupSSLForStream:(NSInputStream *)readStream
{
	CFArrayRef serverCerts = [[self certManager] serverCerts];
#ifdef DEBUG
	MTLog(@"setupSSLForStream, stream=%@ self=%@ serverCerts=%@", readStream, self, serverCerts);
#endif
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
	MTLog(@"Received bytes:\n%@", s);
	[s release];
}
#endif

// -----------------------------------------------------------------------------
// NSStream delegate
// -----------------------------------------------------------------------------
- (void)stream:(NSStream *)theStream handleEvent:(NSStreamEvent)streamEvent
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
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
			case NSStreamEventHasBytesAvailable:{
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
							LoggerMessage *message = [[LoggerNativeMessage alloc] initWithData:(NSData *)subset connection:cnx];
							CFRelease(subset);

							if (message.type == LOGMSG_TYPE_CLIENTINFO)
							{
								// stkim1_Apr.07,2013
								// as soon as client info is recieved and client hash is generated,
								// then new connection gets reporeted to transport manager
								[cnx clientInfoReceived:message];
							}
							else
							{
								[msgs addObject:message];
							}
							[message release];
						}
						[cnx.buffer replaceBytesInRange:NSMakeRange(0, length+4) withBytes:NULL length:0];
						bufferLength = [cnx.buffer length];
					}

					if ([msgs count])
						[cnx messagesReceived:msgs];
					[msgs release];
				}
				break;
			}

			case NSStreamEventErrorOccurred: {
				MTLog(@"Stream error occurred: stream=%@ self=%@ error=%@", theStream, self, [theStream streamError]);
				NSError *error = [theStream streamError];
				NSInteger errCode = [error code];
				
				MTLog(@"errCode [errSSLDecryptionFail:%d],[errSSLBadRecordMac:%d] actual error :%d",errSSLDecryptionFail,errSSLBadRecordMac,errCode);

				if (errCode == errSSLDecryptionFail || errCode == errSSLBadRecordMac)
				{
					// SSL failure due to the application not being codesigned
					// See https://devforums.apple.com/thread/77848?tstart=0

					NSDictionary *dict = \
						@{NSLocalizedDescriptionKey:NSLocalizedString(@"NSLogger SSL authentication failure", @"")
						,NSLocalizedRecoverySuggestionErrorKey:NSLocalizedString(@"Your NSLogger build may not be codesigned. As a result, a conflict between Firewall and Keychain tagging of your viewer requires that you restart NSLogger to complete the SSL certificate authorization.\n\nRestart NSLogger now to fix the issue.", @"")
						,NSUnderlyingErrorKey:[NSString stringWithFormat:@"CFStream error %d", errCode]
						,NSLocalizedRecoverySuggestionErrorKey:NSLocalizedString(@"Click the Restart button to restart NSLogger now.", @"")
						,NSLocalizedRecoveryOptionsErrorKey:[NSArray arrayWithObject:NSLocalizedString(@"Restart", @"")]};

					// stkim1_jan.27,2013 modified for iOS
					NSDictionary *status = [self status];
					
					NSMutableDictionary *errorStatus = \
						[NSMutableDictionary dictionaryWithDictionary:status];

					[errorStatus
					 setObject:
						[NSError
						 errorWithDomain:@"NSLogger"
						 code:errCode
						 userInfo:dict]
					 forKey:kTransportError];
					
					[self reportErrorToManager:errorStatus];
				}
				break;
			}

				// fall through
			case NSStreamEventEndEncountered: {
				// Append a disconnect message for only one of the two streams
				LoggerMessage *msg = [[LoggerMessage alloc] init];
				[msg makeTerminalMessage];
				[cnx clientDisconnectWithMessage:msg];
				cnx.connected = NO;
				[msg release];
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
		MTLog(@"error happens : %@",[e reason]);
	}
	@finally
	{
		[pool release];
	}	
}

//------------------------------------------------------------------------------
#pragma mark - DNS-SD callback response
//------------------------------------------------------------------------------
- (void)didNotRegisterWithError:(DNSServiceErrorType)errorCode
{
	[self shutdown];
	
	switch (errorCode)
	{
		case kDNSServiceErr_NameConflict:{
			self.failureReason = NSLocalizedString(@"Duplicate Bonjour service name on your network", @"");
			break;
		}
		case kDNSServiceErr_BadParam:{
			self.failureReason = NSLocalizedString(@"Bonjour bad argument - please report bug.", @"");
			break;
		}
		case kDNSServiceErr_Invalid:{
			self.failureReason = NSLocalizedString(@"Bonjour invalid configuration - please report bug.", @"");
			break;
		}
		default:{
			self.failureReason = [NSString stringWithFormat:NSLocalizedString(@"Bonjour error %d", @""), errorCode];
			break;
		}
	}

	MTLog(@"service failed %@",self.failureReason);
	failed = YES;
	[self reportErrorToManager:[self status]];	
}

- (void)didRegisterWithDomain:(const char *)domain name:(const char *)name
{
	MTLog(@"service registration success domain[%s]  name[%s]",domain,name);
	
	ready = YES;
	[self reportStatusToManager:[self status]];
}
@end

static void
AcceptSocketCallback(CFSocketRef sock, CFSocketCallBackType type, CFDataRef address, const void *data, void *info)
{
	NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
	@try
	{
		if (type == kCFSocketAcceptCallBack)
		{
			// we have a new incoming connection with a child socket
			// reenable accept callback
			CFSocketEnableCallBacks(sock, kCFSocketAcceptCallBack);

			// Get the native socket handle for the new incoming connection
			CFSocketNativeHandle nativeSocketHandle = *(CFSocketNativeHandle *)data;

			LoggerNativeTransport *myself = (LoggerNativeTransport *)info;
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
							[myself setupSSLForStream:(NSInputStream *)readStream];
						
						// Create the connection instance
						LoggerNativeConnection *cnx = \
							[[LoggerNativeConnection alloc]
							 initWithInputStream:(NSInputStream *)readStream
							 clientAddress:(NSData *)address];

						[myself addConnection:cnx];

						// stkim1_jan,15.2013
						// all connections will report to its corresponding
						// transport so that we can set its delegate as soon as
						// one gets instantiated
						[cnx setDelegate:myself];

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
		MTLog(@"LoggerNativeTransport %p: exception catched in AcceptSocketCallback: %@", info, e);
#endif
	}
	@finally
	{
		[pool release];
	}
}
