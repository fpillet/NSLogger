/*
 * LoggerClient.m
 *
 * version 1.0b4 2010-11-01
 *
 * Main implementation of the NSLogger client side code
 * Part of NSLogger (client side)
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
#import <libkern/OSAtomic.h>
#import <sys/time.h>
#import <fcntl.h>

#import "LoggerClient.h"
#import "LoggerCommon.h"

/* --------------------------------------------------------------------------------
 * IMPLEMENTATION NOTES:
 *
 * The logger runs in a separate thread. It is written
 * in straight C for maximum compatibility with all runtime environments
 * (does not use the Objective-C runtime, only uses unix and CoreFoundation
 * calls, except for get the thread name and device information, but these
 * can be disabled by setting ALLOW_COCOA_USE to 0).
 * 
 * It is suitable for use in both Cocoa and low-level code. It does not activate
 * Cocoa multi-threading (no call to [NSThread detachNewThread...]). You can start
 * logging very early (as soon as your code starts running), logs will be
 * buffered and sent to the log viewer as soon as a connection is acquired.
 * This makes the logger suitable for use in conditions where you usually
 * don't have a connection to a remote machine yet (early wakeup, network
 * down, etc).
 *
 * When you call one of the public logging functions, the logger is designed
 * to return to your application as fast as possible. It enqueues logs to
 * send for processing by its own thread, while your application keeps running.
 *
 * The logger does buffer logs while not connected to a desktop
 * logger. It uses Bonjour to find a logger on the local network, and can
 * optionally connect to a remote logger identified by an IP address / port
 * or a Host Name / port.
 *
 * The logger can optionally output its log to the console, like NSLog().
 *
 * The logger can optionally buffer its logs to a file for which you specify the
 * full path. Upon connection to the desktop viewer, the file contents are
 * transmitted to the viewer prior to sending new logs. When the whole file
 * content has been transmitted, it is emptied.
 *
 * Multiple loggers can coexist at the same time. You can perfectly use a
 * logger for your debug traces, and another that connects remotely to help
 * diagnostic issues while the application runs on your user's device.
 *
 * Using the logger's flexible packet format, you can customize logging by
 * creating your own log types, and customize the desktop viewer to display
 * runtime information panels for your application.
 * --------------------------------------------------------------------------------
 */

// Set this to 1 to activate console logs when running the logger itself
#define LOGGER_DEBUG 0
#ifdef NSLog
	#undef NSLog
#endif

// Internal debugging stuff for the logger itself
#if LOGGER_DEBUG
#define LOGGERDBG LoggerDbg
static void LoggerDbg(CFStringRef format, ...);
#else
#define LOGGERDBG(format, ...) while(0){}
#endif

/* Local prototypes */
static void* LoggerWorkerThread(Logger *logger);

// Bonjour management
static void LoggerStartBonjourBrowsing(Logger *logger);
static void LoggerStopBonjourBrowsing(Logger *logger);
static BOOL LoggerBrowseBonjourForServices(Logger *logger, CFStringRef domainName);
static void LoggerServiceBrowserCallBack(CFNetServiceBrowserRef browser, CFOptionFlags flags, CFTypeRef domainOrService, CFStreamError* error, void *info);

// Reachability
static void LoggerStartReachabilityChecking(Logger *logger);
static void LoggerStopReachabilityChecking(Logger *logger);
static void LoggerReachabilityCallBack(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info);

// Connection & stream management
static void LoggerTryConnect(Logger *logger);
static void LoggerWriteStreamCallback(CFWriteStreamRef ws, CFStreamEventType event, void* info);

// File buffering
static void LoggerCreateBufferWriteStream(Logger *logger);
static void LoggerCreateBufferReadStream(Logger *logger);
static void LoggerEmptyBufferFile(Logger *logger);

// IPC
static CFDataRef LoggerMessagePortCallout(CFMessagePortRef local, SInt32 msgid, CFDataRef data, void* info);
static void PushMessageToLoggerQueue(Logger *logger, CFDataRef message);

// Encoding functions
static void	LoggerPushClientInfoToFrontOfQueue(Logger *logger);
static void EncodeTimestampAndThreadID(CFMutableDataRef encoder);
static void LogDataInternal(Logger *logger, NSString *domain, int level, NSData *data, int binaryOrImageType);

static CFMutableDataRef CreateLoggerData();
static void UpdateLoggerDataHeader(CFMutableDataRef data);
static void EncodeLoggerInt16(CFMutableDataRef data, int16_t anInt, int key);
static void EncodeLoggerInt32(CFMutableDataRef data, int32_t anInt, int key);
static void EncodeLoggerInt64(CFMutableDataRef data, int64_t anInt, int key);
static void EncodeLoggerString(CFMutableDataRef data, CFStringRef aString, int key);
static void EncodeLoggerData(CFMutableDataRef data, CFDataRef theData, int key, int partType);

/* Static objects */
static Logger* volatile sDefaultLogger = NULL;
static pthread_mutex_t sDefaultLoggerMutex = PTHREAD_MUTEX_INITIALIZER;

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Default logger
// -----------------------------------------------------------------------------
void LoggerSetDefautLogger(Logger *defaultLogger)
{
	pthread_mutex_lock(&sDefaultLoggerMutex);
	sDefaultLogger = defaultLogger;
	pthread_mutex_unlock(&sDefaultLoggerMutex);
}

Logger *LoggerGetDefaultLogger()
{
	if (sDefaultLogger == NULL)
	{
		pthread_mutex_lock(&sDefaultLoggerMutex);
		Logger *logger = LoggerInit();
		if (sDefaultLogger == NULL)
		{
			sDefaultLogger = logger;
			logger = NULL;
		}
		pthread_mutex_unlock(&sDefaultLoggerMutex);
		if (logger != NULL)
			LoggerStop(logger);
	}
	return sDefaultLogger;
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Initialization and setup
// -----------------------------------------------------------------------------
Logger *LoggerInit()
{
	LOGGERDBG(CFSTR("LoggerInit defaultLogger=%p"), sDefaultLogger);
	
	Logger *logger = (Logger *)malloc(sizeof(Logger));
	bzero(logger, sizeof(Logger));

	logger->logQueue = CFArrayCreateMutable(NULL, 16, &kCFTypeArrayCallBacks);
	logger->bonjourServiceBrowsers = CFArrayCreateMutable(NULL, 4, &kCFTypeArrayCallBacks);
	logger->bonjourServices = CFArrayCreateMutable(NULL, 4, &kCFTypeArrayCallBacks);
	
	// for now we don't grow the send buffer, just use one page of memory which should be enouh
	// (bigger messages will be sent separately)
	logger->sendBuffer = (uint8_t *)malloc(4096);
	logger->sendBufferSize = 4096;
	
	logger->logToConsole = NO;
	logger->bufferLogsUntilConnection = YES;
	logger->browseBonjour = YES;
	logger->browseOnlyLocalDomain = YES;
	logger->quit = NO;
	
	// Set this logger as the default logger is none exist already
	if (!pthread_mutex_trylock(&sDefaultLoggerMutex))
	{
		if (sDefaultLogger == NULL)
			sDefaultLogger = logger;
		pthread_mutex_unlock(&sDefaultLoggerMutex);
	}
	
	return logger;
}

void LoggerSetOptions(Logger *logger, BOOL logToConsole, BOOL bufferLocallyUntilConnection, BOOL browseBonjour, BOOL browseOnlyLocalDomains)
{
	LOGGERDBG(CFSTR("LoggerSetOptions logToConsole=%d bufferLocally=%d browseBonjour=%d browseOnlyLocalDomains=%d"),
			  (int)logToConsole, (int)bufferLocallyUntilConnection, (int)browseBonjour, (int)browseOnlyLocalDomains);
	
	if (logger == NULL)
		logger = LoggerGetDefaultLogger();
	if (logger == NULL)
		return;

	logger->logToConsole = logToConsole;
	logger->bufferLogsUntilConnection = bufferLocallyUntilConnection;
	logger->browseBonjour = browseBonjour;
	logger->browseOnlyLocalDomain = browseOnlyLocalDomains;
}

void LoggerSetViewerHost(Logger *logger, CFStringRef hostName, UInt32 port)
{
	if (logger == NULL)
		logger = LoggerGetDefaultLogger();
	if (logger == NULL)
		return;
	
	if (logger->host != NULL)
	{
		CFRelease(logger->host);
		logger->host = NULL;
	}
	if (hostName != NULL)
	{
		logger->host = CFStringCreateCopy(NULL, hostName);
		logger->port = port;
	}
}

void LoggerSetBufferFile(Logger *logger, CFStringRef absolutePath)
{
	if (logger == NULL)
		logger = LoggerGetDefaultLogger();
	if (logger == NULL)
		return;

	if (logger->bufferFile != NULL)
	{
		CFRelease(logger->bufferFile);
		logger->bufferFile = NULL;
	}
	if (absolutePath != NULL)
		logger->bufferFile = CFStringCreateCopy(NULL, absolutePath);
}

void LoggerStart(Logger *logger)
{
	// will do nothing if logger is already started
	if (logger == NULL)
		logger = LoggerGetDefaultLogger();

	if (logger->workerThread == NULL)
	{
		// Start the work thread which performs the Bonjour search,
		// connects to the logging service and forwards the logs
		LOGGERDBG(CFSTR("LoggerStart logger=%p"), logger);
		pthread_create(&logger->workerThread, NULL, (void *(*)(void *))&LoggerWorkerThread, logger);
	}
}

void LoggerStop(Logger *logger)
{
	// Stop logging remotely, stop Bonjour discovery, redirect all traces to console
	LOGGERDBG(CFSTR("LoggerStop"));

	pthread_mutex_lock(&sDefaultLoggerMutex);
	if (logger == NULL || logger == sDefaultLogger)
	{
		logger = sDefaultLogger;
		sDefaultLogger = NULL;
	}
	pthread_mutex_unlock(&sDefaultLoggerMutex);

	if (logger != NULL)
	{
		if (logger->workerThread != NULL)
		{
			logger->quit = YES;
			pthread_join(logger->workerThread, NULL);
		}

		CFRelease(logger->bonjourServiceBrowsers);
		CFRelease(logger->bonjourServices);
		free(logger->sendBuffer);
		if (logger->host != NULL)
			CFRelease(logger->host);
		if (logger->bufferFile != NULL)
			CFRelease(logger->bufferFile);

		// to make sure potential errors are catched, set the whole structure
		// to a value that will make code crash if it tries using pointers to it.
		memset(logger, 0x55, sizeof(logger));

		free(logger);
	}
}

static void LoggerDbg(CFStringRef format, ...)
{
	// Internal debugging function
	// (what do you think, that we use the Logger to debug itself ??)
	if (format != NULL)
	{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		va_list	args;	
		va_start(args, format);
		CFStringRef s = CFStringCreateWithFormatAndArguments(NULL, NULL, (CFStringRef)format, args);
		va_end(args);
		if (s != NULL)
		{
			CFShow(s);
			CFRelease(s);
		}
		[pool release];
	}
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Main processing
// -----------------------------------------------------------------------------
static void *LoggerWorkerThread(Logger *logger)
{
	LOGGERDBG(CFSTR("Start LoggerWorkerThread"));
	
	CFRunLoopRef runLoop = CFRunLoopGetCurrent();
	
	// Create the message port we use to transfer data from the application
	// to the logger thread's queue. Use a unique message port name.
	CFMessagePortContext context = {0, (void*)logger, NULL, NULL, NULL};
	CFUUIDRef uuid = CFUUIDCreate(NULL);
	CFStringRef uuidString = CFUUIDCreateString(NULL, uuid);
	CFRelease(uuid);
	logger->messagePort = CFMessagePortCreateLocal(NULL,
												   uuidString,
												   (CFMessagePortCallBack)&LoggerMessagePortCallout,
												   &context,
												   NULL);
	CFRelease(uuidString);
	
	CFRunLoopSourceRef messagePortSource = CFMessagePortCreateRunLoopSource(NULL, logger->messagePort, 0);
	CFRunLoopAddSource(runLoop, messagePortSource, kCFRunLoopCommonModes);
	CFRelease(messagePortSource);
	
	// Start Bonjour browsing, wait for remote logging service to be found
	if (logger->browseBonjour && logger->host == NULL)
	{
		LOGGERDBG(CFSTR("-> logger configured for Bonjour, no direct host set -- trying Bonjour first"));
		LoggerStartBonjourBrowsing(logger);
	}
	else if (logger->host != NULL)
	{
		LOGGERDBG(CFSTR("-> logger configured with direct host, trying it first"));
		LoggerTryConnect(logger);
	}

	// Run logging thread until LoggerStop() is called
	while (!logger->quit)
	{
		int result = CFRunLoopRunInMode(kCFRunLoopDefaultMode, 0.10, true);
		if (result == kCFRunLoopRunFinished || result == kCFRunLoopRunStopped)
			break;
		
		// Make sure we restart connection attempts if we get disconnected
		if (!logger->connected &&
			!CFArrayGetCount(logger->bonjourServices) &&
			!CFArrayGetCount(logger->bonjourServiceBrowsers) &&
			!CFArrayGetCount(logger->bonjourServices))
		{
			if (logger->browseBonjour)
				LoggerStartBonjourBrowsing(logger);
			else if (logger->host != NULL && logger->reachability == NULL)
				LoggerTryConnect(logger);
		}
	}

	// Cleanup
	if (logger->browseBonjour)
		LoggerStopBonjourBrowsing(logger);

	if (logger->logStream != NULL)
	{
		CFWriteStreamClose(logger->logStream);
		CFRelease(logger->logStream);
		logger->logStream = NULL;
	}
	LoggerStopReachabilityChecking(logger);

	if (logger->bufferWriteStream == NULL && logger->bufferFile != NULL && CFArrayGetCount(logger->logQueue))
	{
		// If there are messages in the queue and LoggerStop() was called and
		// a buffer file was set just before LoggerStop() was called, flush
		// the log queue to the buffer file
		LoggerCreateBufferWriteStream(logger);
	}

	if (logger->bufferWriteStream != NULL)
	{
		CFWriteStreamClose(logger->bufferWriteStream);
		CFRelease(logger->bufferWriteStream);
		logger->bufferWriteStream = NULL;
	}

	CFMessagePortInvalidate(logger->messagePort);
	CFRelease(logger->messagePort);
	logger->messagePort = NULL;
	
	return NULL;
}

static void LoggerWriteMoreData(Logger *logger)
{
	if (!logger->connected)
		return;
	
	if (CFWriteStreamCanAcceptBytes(logger->logStream))
	{
		// prepare archived data with log queue contents, unblock the queue as soon as possible
		CFMutableDataRef sendFirstItem = NULL;
		if (logger->sendBufferUsed == 0)
		{
			// pull more data from the log queue
			if (logger->bufferReadStream != NULL)
			{
				if (!CFReadStreamHasBytesAvailable(logger->bufferReadStream))
				{
					CFReadStreamClose(logger->bufferReadStream);
					CFRelease(logger->bufferReadStream);
					logger->bufferReadStream = NULL;
					LoggerEmptyBufferFile(logger);
				}
				else
				{
					logger->sendBufferUsed = CFReadStreamRead(logger->bufferReadStream, logger->sendBuffer, logger->sendBufferSize);
				}
			}
			else while (CFArrayGetCount(logger->logQueue))
			{
				CFDataRef d = (CFDataRef)CFArrayGetValueAtIndex(logger->logQueue, 0);
				CFIndex dsize = CFDataGetLength(d);
				if ((logger->sendBufferUsed + dsize) > logger->sendBufferSize)
					break;
				memcpy(logger->sendBuffer + logger->sendBufferUsed, CFDataGetBytePtr(d), dsize);
				logger->sendBufferUsed += dsize;
				CFArrayRemoveValueAtIndex(logger->logQueue, 0);
			}
			if (logger->sendBufferUsed == 0) 
			{
				// are we done yet?
				if (CFArrayGetCount(logger->logQueue) == 0)
					return;
				
				// first item is too big to fit in a single packet, send it separately
				sendFirstItem = (CFMutableDataRef)CFArrayGetValueAtIndex(logger->logQueue, 0);
				logger->sendBufferOffset = 0;
			}
		}

		// send data over the socket. We try hard to be failsafe and if we have to send
		// data in fragments, we make sure that in case a disconnect occurs we restart
		// sending the whole message(s)
		if (logger->sendBufferUsed != 0)
		{
			CFIndex written = CFWriteStreamWrite(logger->logStream,
												 logger->sendBuffer + logger->sendBufferOffset,
												 logger->sendBufferUsed - logger->sendBufferOffset);
			if (written < 0)
			{
				// We'll get an event if the stream closes on error. Don't discard the data,
				// it will be sent as soon as a connection is re-acquired.
				return;
			}
			if ((logger->sendBufferOffset + written) < logger->sendBufferUsed)
			{
				// everything couldn't be sent at once
				logger->sendBufferOffset += written;
			}
			else
			{
				logger->sendBufferUsed = 0;
				logger->sendBufferOffset = 0;
			}
		}
		else if (sendFirstItem)
		{
			CFIndex length = CFDataGetLength(sendFirstItem) - logger->sendBufferOffset;
			CFIndex written = CFWriteStreamWrite(logger->logStream,
												 CFDataGetBytePtr(sendFirstItem) + logger->sendBufferOffset,
												 length);
			if (written < 0)
			{
				// We'll get an event if the stream closes on error
				return;
			}
			if (written < length)
			{
				// The output pipe is full, and the first item has not been sent completely
				// We need to reduce the remaining data on the first item so it can be taken
				// care of at the next iteration. We take advantage of the fact that each item
				// in the queue is actually a mutable data block
				CFDataReplaceBytes((CFMutableDataRef)sendFirstItem, CFRangeMake(0, written), NULL, 0);
				return;
			}
			
			// we are done sending the first item in the queue, remove it now
			CFArrayRemoveValueAtIndex(logger->logQueue, 0);
			logger->sendBufferOffset = 0;
		}
	}
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark File buffering functions
// -----------------------------------------------------------------------------
static void LoggerCreateBufferWriteStream(Logger *logger)
{
	LOGGERDBG(CFSTR("LoggerCreateBufferWriteStream to file %@"), logger->bufferFile);
	CFURLRef fileURL = CFURLCreateWithFileSystemPath(NULL, logger->bufferFile, kCFURLPOSIXPathStyle, false);
	if (fileURL != NULL)
	{
		// Create write stream to file
		logger->bufferWriteStream = CFWriteStreamCreateWithFile(NULL, fileURL);
		CFRelease(fileURL);
		if (logger->bufferWriteStream != NULL)
		{
			if (!CFWriteStreamOpen(logger->bufferWriteStream))
			{
				CFRelease(logger->bufferWriteStream);
				logger->bufferWriteStream = NULL;
			}
			else
			{
				// Set flag to append new data to buffer file
				CFWriteStreamSetProperty(logger->bufferWriteStream, kCFStreamPropertyAppendToFile, kCFBooleanTrue);
				
				// Write client info and flush the queue contents to buffer file
				CFIndex totalWritten = 0;
				LoggerPushClientInfoToFrontOfQueue(logger);
				while (CFArrayGetCount(logger->logQueue))
				{
					CFDataRef data = CFArrayGetValueAtIndex(logger->logQueue, 0);
					CFIndex dataLength = CFDataGetLength(data);
					CFIndex written = CFWriteStreamWrite(logger->bufferWriteStream, CFDataGetBytePtr(data), dataLength);
					totalWritten += written;
					if (written != dataLength)
					{
						// couldn't write all data to file, maybe storage run out of space?
						CFShow(CFSTR("NSLogger Error: failed flushing the whole queue to buffer file:"));
						CFShow(logger->bufferFile);
						break;
					}
					CFArrayRemoveValueAtIndex(logger->logQueue, 0);
				}
				LOGGERDBG(CFSTR("-> bytes written to file: %ld"), (long)totalWritten);
			}
		}
	}
	if (logger->bufferWriteStream == NULL)
	{
		CFShow(CFSTR("NSLogger Warning: failed opening buffer file for writing:"));
		CFShow(logger->bufferFile);
	}
}

static void LoggerCreateBufferReadStream(Logger *logger)
{
	LOGGERDBG(CFSTR("LoggerCreateBufferReadStream from file %@"), logger->bufferFile);
	CFURLRef fileURL = CFURLCreateWithFileSystemPath(NULL, logger->bufferFile, kCFURLPOSIXPathStyle, false);
	if (fileURL != NULL)
	{
		// Create read stream from file
		logger->bufferReadStream = CFReadStreamCreateWithFile(NULL, fileURL);
		CFRelease(fileURL);
		if (logger->bufferReadStream != NULL)
		{
			if (!CFReadStreamOpen(logger->bufferReadStream))
			{
				CFRelease(logger->bufferReadStream);
				logger->bufferReadStream = NULL;
			}
		}
	}
}

static void LoggerEmptyBufferFile(Logger *logger)
{
	// completely remove the buffer file from storage
	LOGGERDBG(CFSTR("LoggerEmptyBufferFile %@"), logger->bufferFile);
	if (logger->bufferFile != NULL)
	{
		CFIndex bufferSize = 1 + CFStringGetLength(logger->bufferFile) * 3;
		char *buffer = (char *)malloc(bufferSize);
		if (buffer != NULL)
		{
			if (CFStringGetFileSystemRepresentation(logger->bufferFile, buffer, bufferSize))
			{
				// remove file
				unlink(buffer);
			}
			free(buffer);
		}
	}
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Internal message port callback
// -----------------------------------------------------------------------------
static CFDataRef LoggerMessagePortCallout(CFMessagePortRef local, SInt32 msgid, CFDataRef data, void* info)
{
	// We got message data on the message port, add it to the logger queue and immediately
	// try to write it. Note that calling conventions require that we make a copy of the data
	// if we want to reuse it past the scope of this callout
	Logger *logger = (Logger *)info;
	assert(logger != NULL);
	
	if (!logger->connected && !logger->bufferLogsUntilConnection)
		return NULL;

	if (!logger->connected && logger->bufferFile)
	{
		// we're buffering to a file. Create the file stream if needed
		if (logger->bufferWriteStream == NULL)
			LoggerCreateBufferWriteStream(logger);
		if (logger->bufferWriteStream != NULL)
		{
			// write data to buffer file (note that we don't check for incomplete writes)
			CFWriteStreamWrite(logger->bufferWriteStream, CFDataGetBytePtr(data), CFDataGetLength(data));
			return NULL;
		}
	}

	CFMutableDataRef d = CFDataCreateMutableCopy(NULL, CFDataGetLength(data), data);
	CFArrayAppendValue(logger->logQueue, d);
	CFRelease(d);
	LoggerWriteMoreData(logger);
	return NULL;
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Bonjour browsing
// -----------------------------------------------------------------------------
static void LoggerStartBonjourBrowsing(Logger *logger)
{
	LOGGERDBG(CFSTR("LoggerStartBonjourBrowsing"));
	
	if (logger->browseOnlyLocalDomain)
	{
		LOGGERDBG(CFSTR("Logger configured to search only the local domain, searching for services on: local."));
		if (!LoggerBrowseBonjourForServices(logger, CFSTR("local.")))
		{
			LOGGERDBG(CFSTR("*** Logger: could not browse for services in domain local., reverting to console logging. ***"));
			logger->logToConsole = YES;
		}
	}
	else
	{
		LOGGERDBG(CFSTR("Logger configured to search all domains, browsing for domains first"));
		CFNetServiceClientContext context = {0, (void *)logger, NULL, NULL, NULL};
		CFRunLoopRef runLoop = CFRunLoopGetCurrent();
		logger->bonjourDomainBrowser = CFNetServiceBrowserCreate(NULL, &LoggerServiceBrowserCallBack, &context);
		CFNetServiceBrowserScheduleWithRunLoop(logger->bonjourDomainBrowser, runLoop, kCFRunLoopCommonModes);
		if (!CFNetServiceBrowserSearchForDomains(logger->bonjourDomainBrowser, false, NULL))
		{
			// An error occurred, revert to console logging
			LOGGERDBG(CFSTR("*** Logger: could not browse for domains, reverting to console logging. ***"));
			CFNetServiceBrowserUnscheduleFromRunLoop(logger->bonjourDomainBrowser, runLoop, kCFRunLoopCommonModes);
			CFRelease(logger->bonjourDomainBrowser);
			logger->bonjourDomainBrowser = NULL;
			logger->logToConsole = YES;
		}
	}
}

static void LoggerStopBonjourBrowsing(Logger *logger)
{
	LOGGERDBG(CFSTR("LoggerStopBonjourBrowsing"));
	
	// stop browsing for domains
	if (logger->bonjourDomainBrowser != NULL)
	{
		CFNetServiceBrowserStopSearch(logger->bonjourDomainBrowser, NULL);
		CFNetServiceBrowserUnscheduleFromRunLoop(logger->bonjourDomainBrowser, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
		CFNetServiceBrowserInvalidate(logger->bonjourDomainBrowser);
		CFRelease(logger->bonjourDomainBrowser);
		logger->bonjourDomainBrowser = NULL;
	}
	
	// stop browsing for services
	for (CFIndex idx = 0; idx < CFArrayGetCount(logger->bonjourServiceBrowsers); idx++)
	{
		CFNetServiceBrowserRef browser = (CFNetServiceBrowserRef)CFArrayGetValueAtIndex(logger->bonjourServiceBrowsers, idx);
		CFNetServiceBrowserStopSearch(browser, NULL);
		CFNetServiceBrowserUnscheduleFromRunLoop(browser, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
		CFNetServiceBrowserInvalidate(browser);
	}
	CFArrayRemoveAllValues(logger->bonjourServiceBrowsers);
	
	// Forget all services
	CFArrayRemoveAllValues(logger->bonjourServices);
}

static BOOL LoggerBrowseBonjourForServices(Logger *logger, CFStringRef domainName)
{
	BOOL result = NO;
	CFNetServiceClientContext context = {0, (void *)logger, NULL, NULL, NULL};
	CFRunLoopRef runLoop = CFRunLoopGetCurrent();
	
	CFNetServiceBrowserRef browser = CFNetServiceBrowserCreate(NULL, (CFNetServiceBrowserClientCallBack)&LoggerServiceBrowserCallBack, &context);
	CFNetServiceBrowserScheduleWithRunLoop(browser, runLoop, kCFRunLoopCommonModes);
	CFStreamError error;
	if (!CFNetServiceBrowserSearchForServices(browser, domainName, LOGGER_SERVICE_TYPE, &error))
	{
		LOGGERDBG(CFSTR("Logger can't start search on domain: %@ (error %d)"), domainName, error.error);
		CFNetServiceBrowserUnscheduleFromRunLoop(browser, runLoop, kCFRunLoopCommonModes);
		CFNetServiceBrowserInvalidate(browser);
	}
	else
	{
		LOGGERDBG(CFSTR("Logger started search for services of type %@ in domain %@"), LOGGER_SERVICE_TYPE, domainName);
		CFArrayAppendValue(logger->bonjourServiceBrowsers, browser);
		result = YES;
	}
	CFRelease(browser);
	return result;
}

static void LoggerServiceBrowserCallBack (CFNetServiceBrowserRef browser,
										  CFOptionFlags flags,
										  CFTypeRef domainOrService,
										  CFStreamError* error,
										  void* info)
{
	LOGGERDBG(CFSTR("LoggerServiceBrowserCallback browser=%@ flags=0x%04x domainOrService=%@ error=%d"), browser, flags, domainOrService, error==NULL ? 0 : error->error);
	
	Logger *logger = (Logger *)info;
	assert(logger != NULL);
	
	if (flags & kCFNetServiceFlagRemove)
	{
		if (!(flags & kCFNetServiceFlagIsDomain))
		{
			CFNetServiceRef service = (CFNetServiceRef)domainOrService;
			for (CFIndex idx = 0; idx < CFArrayGetCount(logger->bonjourServices); idx++)
			{
				if (CFArrayGetValueAtIndex(logger->bonjourServices, idx) == service)
				{
					CFNetServiceUnscheduleFromRunLoop(service, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
					CFNetServiceClientContext context = {0, NULL, NULL, NULL, NULL};
					CFNetServiceSetClient(service, NULL, &context);
					CFNetServiceCancel(service);
					CFArrayRemoveValueAtIndex(logger->bonjourServices, idx);
					break;
				}
			}
		}
	}
	else
	{
		if (flags & kCFNetServiceFlagIsDomain)
		{
			// start searching for services in this domain
			LoggerBrowseBonjourForServices(logger, (CFStringRef)domainOrService);
		}
		else
		{
			// a service has been found, try resolving it
			LOGGERDBG(CFSTR("Logger found service: %@"), domainOrService);
			CFNetServiceRef service = (CFNetServiceRef)domainOrService;
			if (service != NULL)
			{
				CFArrayAppendValue(logger->bonjourServices, service);
				LoggerTryConnect(logger);
			}
		}
	}
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Reachability
// -----------------------------------------------------------------------------
static void LoggerStartReachabilityChecking(Logger *logger)
{
	if (logger->host != NULL && logger->reachability == NULL)
	{
		LOGGERDBG(CFSTR("Starting SCNetworkReachability to wait for host %@ to be reachable"), logger->host);

		CFIndex length = CFStringGetLength(logger->host) * 3;
		char *buffer = (char *)malloc(length + 1);
		CFStringGetBytes(logger->host, CFRangeMake(0, CFStringGetLength(logger->host)), kCFStringEncodingUTF8, '?', false, (UInt8 *)buffer, length, &length);
		buffer[length] = 0;
		
		logger->reachability = SCNetworkReachabilityCreateWithName(NULL, buffer);
		
		SCNetworkReachabilityContext context = {0, logger, NULL, NULL, NULL};
		SCNetworkReachabilitySetCallback(logger->reachability, &LoggerReachabilityCallBack, &context);
		SCNetworkReachabilityScheduleWithRunLoop(logger->reachability, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);

		free(buffer);
	}
}

static void LoggerStopReachabilityChecking(Logger *logger)
{
	if (logger->reachability)
	{
		LOGGERDBG(CFSTR("Stopping SCNetworkReachability"));
		SCNetworkReachabilityUnscheduleFromRunLoop(logger->reachability, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
		CFRelease(logger->reachability);
		logger->reachability = NULL;
	}
}

static void LoggerReachabilityCallBack(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info)
{
	Logger *logger = (Logger *)info;
	assert(logger != NULL);
	LOGGERDBG(CFSTR("LoggerReachabilityCallBack called with flags=0x%08lx"), flags);
	if (flags & kSCNetworkReachabilityFlagsReachable)
	{
		// target host became reachable. If we have not other open connection,
		// try direct connection to the host
		if (logger->logStream == NULL && logger->host != NULL)
		{
			LOGGERDBG(CFSTR("-> host %@ became reachable, trying to connect."), logger->host);
			LoggerTryConnect(logger);
		}
	}
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Stream management
// -----------------------------------------------------------------------------
static BOOL LoggerConfigureAndOpenStream(Logger *logger)
{
	// configure and open stream
	LOGGERDBG(CFSTR("LoggerConfigureAndOpenStream configuring and opening log stream"));
	CFStreamClientContext context = {0, (void *)logger, NULL, NULL, NULL};
	if (CFWriteStreamSetClient(logger->logStream,
							   (kCFStreamEventOpenCompleted |
								kCFStreamEventCanAcceptBytes |
								kCFStreamEventErrorOccurred |
								kCFStreamEventEndEncountered),
							   &LoggerWriteStreamCallback, &context))
	{
		CFWriteStreamScheduleWithRunLoop(logger->logStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
		if (CFWriteStreamOpen(logger->logStream))
		{
			LOGGERDBG(CFSTR("-> stream open attempt, waiting for open completion"));
			return YES;
		}
		LOGGERDBG(CFSTR("-> stream open failed."));
		CFWriteStreamUnscheduleFromRunLoop(logger->logStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
		CFWriteStreamSetClient(logger->logStream, kCFStreamEventNone, NULL, &context);
	}
	else
	{
		LOGGERDBG(CFSTR("-> stream set client failed."));
	}
	CFRelease(logger->logStream);
	logger->logStream = NULL;
	return NO;
}

static void LoggerTryConnect(Logger *logger)
{
	// Try connecting to the next address in the sConnectAttempts array
	LOGGERDBG(CFSTR("LoggerTryConnect, %d services registered, current stream=%@"), CFArrayGetCount(logger->bonjourServices), logger->logStream);
	
	// If we already have a connection established or being attempted, stop here
	if (logger->logStream != NULL)
	{
		LOGGERDBG(CFSTR("-> another connection is opened or in progress, giving up for now"));
		return;
	}

	// If there are discovered Bonjour services, try them now
	while (CFArrayGetCount(logger->bonjourServices))
	{
		CFNetServiceRef service = (CFNetServiceRef)CFArrayGetValueAtIndex(logger->bonjourServices, 0);
		LOGGERDBG(CFSTR("-> Trying to open write stream to service %@"), service);
		CFStreamCreatePairWithSocketToNetService(NULL, service, NULL, &logger->logStream);
		CFArrayRemoveValueAtIndex(logger->bonjourServices, 0);
		if (logger->logStream == NULL)
		{
			// create pair failed
			LOGGERDBG(CFSTR("-> failed."));
		}
		else if (LoggerConfigureAndOpenStream(logger))
		{
			// open is now in progress
			return;
		}
	}

	// If there is a host to directly connect to, try it now (this will happen before
	// Bonjour kicks in, Bonjour being handled as a fallback solution if direct Host
	// fails)
	if (logger->host != NULL)
	{
		LOGGERDBG(CFSTR("-> Trying to open direct connection to host %@ port %u"), logger->host, logger->port);
		CFStreamCreatePairWithSocketToHost(NULL, logger->host, logger->port, NULL, &logger->logStream);
		if (logger->logStream == NULL)
		{
			// Create stream failed
			LOGGERDBG(CFSTR("-> failed."));
		}
		else if (LoggerConfigureAndOpenStream(logger))
		{
			// open is now in progress
			return;
		}
		// Could not connect to host: start Reachability so we know when target host becomes reachable
		// and can try to connect again
		LoggerStartReachabilityChecking(logger);
	}
	
	// Finally, if Bonjour is enabled and not started yet, start it now.
	if (logger->browseBonjour &&
		(logger->bonjourDomainBrowser == NULL || CFArrayGetCount(logger->bonjourServiceBrowsers) == 0))
	{
		LoggerStartBonjourBrowsing(logger);
	}
}

static void LoggerWriteStreamCallback(CFWriteStreamRef ws, CFStreamEventType event, void* info)
{
	Logger *logger = (Logger *)info;
	assert(ws == logger->logStream);
	switch (event)
	{
		case kCFStreamEventOpenCompleted:
			// A stream open was complete. Cancel all bonjour browsing,
			// service resolution and connection attempts, and try to
			// write existing buffer contents
			LOGGERDBG(CFSTR("Logger CONNECTED"));
			logger->connected = YES;
			LoggerStopBonjourBrowsing(logger);
			LoggerStopReachabilityChecking(logger);
			if (logger->bufferWriteStream != NULL)
			{
				// now that a connection is acquired, we can stop logging to a file
				CFWriteStreamClose(logger->bufferWriteStream);
				CFRelease(logger->bufferWriteStream);
				logger->bufferWriteStream = NULL;
			}
			if (logger->bufferFile != NULL)
			{
				// if a buffer file was defined, try to read its contents
				LoggerCreateBufferReadStream(logger);
			}
			LoggerPushClientInfoToFrontOfQueue(logger);
			LoggerWriteMoreData(logger);
			break;
			
		case kCFStreamEventCanAcceptBytes:
			LoggerWriteMoreData(logger);
			break;
			
		case kCFStreamEventErrorOccurred: {
			CFErrorRef error = CFWriteStreamCopyError(ws);
			LOGGERDBG(CFSTR("Logger stream error: %@"), error);
			CFRelease(error);
			// Fall-thru
		}
			
		case kCFStreamEventEndEncountered:
			if (logger->connected)
			{
				LOGGERDBG(CFSTR("Logger DISCONNECTED"));
				logger->connected = NO;
			}
			CFWriteStreamClose(logger->logStream);
			CFRelease(logger->logStream);
			logger->logStream = NULL;
			logger->sendBufferUsed = 0;
			logger->sendBufferOffset = 0;
			if (logger->bufferReadStream != NULL)
			{
				// In the case the connection drops before we have flushed the
				// whole contents of the file, we choose to keep it integrally
				// and retransmit it when reconnecting to the viewer. The reason
				// of this choice is that we may have transmitted only part of
				// a message, and this may cause errors on the desktop side.
				CFReadStreamClose(logger->bufferReadStream);
				CFRelease(logger->bufferReadStream);
				logger->bufferReadStream = NULL;
			}
			if (logger->host != NULL && logger->browseBonjour == NO)
				LoggerStartReachabilityChecking(logger);
			else
				LoggerTryConnect(logger);
			break;
	}
}
// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Internal encoding functions
// -----------------------------------------------------------------------------
static void EncodeTimestamp(CFMutableDataRef encoder)
{
	struct timeval t;
	if (gettimeofday(&t, NULL) == 0)
	{
		if (sizeof(t.tv_sec) == 8)
		{
			EncodeLoggerInt64(encoder, t.tv_sec, PART_KEY_TIMESTAMP_S);
			EncodeLoggerInt64(encoder, t.tv_usec, PART_KEY_TIMESTAMP_US);
		}
		else
		{
			EncodeLoggerInt32(encoder, t.tv_sec, PART_KEY_TIMESTAMP_S);
			EncodeLoggerInt32(encoder, t.tv_usec, PART_KEY_TIMESTAMP_US);
		}
	}
	else
	{
		time_t ts = time(NULL);
		if (sizeof(ts) == 8)
			EncodeLoggerInt64(encoder, ts, PART_KEY_TIMESTAMP_S);
		else
			EncodeLoggerInt32(encoder, ts, PART_KEY_TIMESTAMP_S);
	}
}

static void EncodeTimestampAndThreadID(CFMutableDataRef encoder)
{
	EncodeTimestamp(encoder);

#if ALLOW_COCOA_USE
	// Getting the thread number is tedious, to say the least. Since there is
	// no direct way to get it, we have to do it sideways. Note that it can be dangerous
	// to use any Cocoa call when in a multithreaded application that only uses non-Cocoa threads
	// and for which Cocoa's multithreading has not been activated. We test for this case.
	if ([NSThread isMultiThreaded] || [NSThread isMainThread])
	{
		NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
		NSThread *thread = [NSThread currentThread];
		NSString *name = [thread name];
		if (name == nil)
		{
			if ([thread isMainThread])
			{
				name = @"Main thread";
			}
			else
			{
				name = [thread description];
				NSRange range = [name rangeOfString:@"num = "];
				if (range.location != NSNotFound)
				{
					name = [NSString stringWithFormat:@"Thread %@",
							[name substringWithRange:NSMakeRange(range.location + range.length,
																 [name length] - range.location - range.length - 1)]];
				}
				else
				{
					name = [NSString stringWithFormat:@"Thread %", pthread_self()];
				}
			}
		}
		EncodeLoggerString(encoder, (CFStringRef)name, PART_KEY_THREAD_ID);
		[pool release];
	}
#endif
}

static CFMutableDataRef CreateLoggerData()
{
	CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
	CFDataIncreaseLength(data, 6);
	UInt8 *p = CFDataGetMutableBytePtr(data);
	p[3] = 2;		// size 0x00000002 in big endian
	return data;
}

static void UpdateLoggerDataHeader(CFMutableDataRef data)
{
	// update the data header with updated part count and size
	UInt8 *p = CFDataGetMutableBytePtr(data);
	uint32_t size = htonl(CFDataGetLength(data) - 4);
	uint16_t partCount = htons(ntohs(*(uint16_t *)(p + 4)) + 1);
	memcpy(p, &size, 4);
	memcpy(p+4, &partCount, 2);
}

static void EncodeLoggerInt16(CFMutableDataRef data, int16_t anInt, int key)
{
	uint16_t partData = htonl(anInt);
	uint8_t keyAndType[2] = {(uint8_t)key, PART_TYPE_INT16};
	CFDataAppendBytes(data, (const UInt8 *)&keyAndType, 2);
	CFDataAppendBytes(data, (const UInt8 *)&partData, 2);
	UpdateLoggerDataHeader(data);
}

static void EncodeLoggerInt32(CFMutableDataRef data, int32_t anInt, int key)
{
	uint32_t partData = htonl(anInt);
	uint8_t keyAndType[2] = {(uint8_t)key, PART_TYPE_INT32};
	CFDataAppendBytes(data, (const UInt8 *)&keyAndType, 2);
	CFDataAppendBytes(data, (const UInt8 *)&partData, 4);
	UpdateLoggerDataHeader(data);
}

static void EncodeLoggerInt64(CFMutableDataRef data, int64_t anInt, int key)
{
	uint32_t partData[2] = {htonl(anInt >> 32), htonl(anInt)};
	uint8_t keyAndType[2] = {(uint8_t)key, PART_TYPE_INT64};
	CFDataAppendBytes(data, (const UInt8 *)&keyAndType, 2);
	CFDataAppendBytes(data, (const UInt8 *)&partData, 8);
	UpdateLoggerDataHeader(data);
}

static void EncodeLoggerString(CFMutableDataRef data, CFStringRef aString, int key)
{
	if (aString == NULL)
		aString = CFSTR("");

	// All strings are UTF-8 encoded
	uint8_t keyAndType[2] = {(uint8_t)key, PART_TYPE_STRING};
	uint32_t partSize = 0;
	uint8_t *bytes = NULL;
	
	CFIndex stringLength = CFStringGetLength(aString);
	CFIndex bytesLength = stringLength * 4;
	if (stringLength)
	{
		bytes = (uint8_t *)malloc(stringLength * 4 + 4);
		CFStringGetBytes(aString, CFRangeMake(0, stringLength), kCFStringEncodingUTF8, '?', false, bytes, bytesLength, &bytesLength);
		partSize = htonl(bytesLength);
	}
	
	CFDataAppendBytes(data, (const UInt8 *)&keyAndType, 2);
	CFDataAppendBytes(data, (const UInt8 *)&partSize, 4);
	if (partSize)
		CFDataAppendBytes(data, bytes, bytesLength);
	
	if (bytes != NULL)
		free(bytes);
	UpdateLoggerDataHeader(data);
}

static void EncodeLoggerData(CFMutableDataRef data, CFDataRef theData, int key, int partType)
{
	uint8_t keyAndType[2] = {(uint8_t)key, (uint8_t)partType};
	CFIndex dataLength = CFDataGetLength(theData);
	uint32_t partSize = htonl(dataLength);
	CFDataAppendBytes(data, (const UInt8 *)&keyAndType, 2);
	CFDataAppendBytes(data, (const UInt8 *)&partSize, 4);
	if (partSize)
		CFDataAppendBytes(data, CFDataGetBytePtr(theData), dataLength);
	UpdateLoggerDataHeader(data);
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Private logging functions
// -----------------------------------------------------------------------------
static void	LoggerPushClientInfoToFrontOfQueue(Logger *logger)
{
	// Extract client information from the main bundle, as well as platform info,
	// and assmble it to a message that will be put in front of the queue
	// Helps desktop viewer display who's talking to it
	// Note that we must be called from the logger work thread, as we don't
	// run through the message port to transmit this message to the queue
	CFBundleRef bundle = CFBundleGetMainBundle();
	if (bundle == NULL)
		return;
	CFMutableDataRef encoder = CreateLoggerData();
	if (encoder != NULL)
	{
		EncodeTimestamp(encoder);
		EncodeLoggerInt32(encoder, LOGMSG_TYPE_CLIENTINFO, PART_KEY_MESSAGE_TYPE);

		CFStringRef version = (CFStringRef)CFBundleGetValueForInfoDictionaryKey(bundle, kCFBundleVersionKey);
		if (version != NULL && CFGetTypeID(version) == CFStringGetTypeID())
			EncodeLoggerString(encoder, version, PART_KEY_CLIENT_VERSION);
		CFStringRef name = (CFStringRef)CFBundleGetValueForInfoDictionaryKey(bundle, kCFBundleNameKey);
		if (name != NULL)
			EncodeLoggerString(encoder, name, PART_KEY_CLIENT_NAME);

#if TARGET_OS_IPHONE && ALLOW_COCOA_USE
		if ([NSThread isMultiThreaded] || [NSThread isMainThread])
		{
			NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
			UIDevice *device = [UIDevice currentDevice];
			EncodeLoggerString(encoder, (CFStringRef)device.uniqueIdentifier, PART_KEY_UNIQUEID);
			EncodeLoggerString(encoder, (CFStringRef)device.systemVersion, PART_KEY_OS_VERSION);
			EncodeLoggerString(encoder, (CFStringRef)device.systemName, PART_KEY_OS_NAME);
			EncodeLoggerString(encoder, (CFStringRef)device.model, PART_KEY_CLIENT_MODEL);
			[pool release];
		}
#endif
		CFArrayInsertValueAtIndex(logger->logQueue, 0, encoder);
		CFRelease(encoder);
	}
}

static void PushMessageToLoggerQueue(Logger *logger, CFDataRef message)
{
	// Send the data to the port on the logger thread's runloop, this way we don't have to use
	// locks to communicate message to the logger queue.
	// Issue: if the run loop is blocking on something for too long, it also blocks the sender's
	// thread. In a future release, use a private queue and a runloop source to avoid this.
	if (logger->messagePort != NULL)
	{
		SInt32 err;
		int loops = 0;
		while ((err = CFMessagePortSendRequest(logger->messagePort, 0, message, 0.1, 0, NULL, NULL)) == kCFMessagePortSendTimeout)
			loops++;
		if (err != kCFMessagePortSuccess)
		{
			LOGGERDBG(CFSTR("-> CFMessagePortSendRequest returned %ld"), err);
		}
		else if (loops != 0)
		{
			LOGGERDBG(CFSTR("-> CFMessagePortSendRequest with 0.1 timeout looped %d times before sending succeeded"), loops);
		}
	}
}

static void LogMessageTo_internal(Logger *logger, NSString *domain, int level, NSString *format, va_list args)
{
	if (logger == NULL)
	{
		logger = LoggerGetDefaultLogger();
		LoggerStart(logger);
	}

	int32_t seq = OSAtomicIncrement32Barrier(&logger->messageSeq);
	LOGGERDBG(CFSTR("%ld LogMessage"), seq);

#if ALLOW_COCOA_USE
	// Go though NSString to avoid low-level logging of CF datastructures (i.e. too detailed NSDictionary, etc)
	CFStringRef msgString = (CFStringRef)[[NSString alloc] initWithFormat:format arguments:args];
#else
	CFStringRef msgString = CFStringCreateWithFormatAndArguments(NULL, NULL, (CFStringRef)format, args);
#endif
	if (msgString != NULL)
	{
		if (logger->logToConsole)
		{
			// Gracefully degrade to logging the message to console
			CFShow(msgString);
		}
		else
		{
			CFMutableDataRef encoder = CreateLoggerData();
			if (encoder != NULL)
			{
				EncodeTimestampAndThreadID(encoder);
				EncodeLoggerInt32(encoder, LOGMSG_TYPE_LOG, PART_KEY_MESSAGE_TYPE);
				EncodeLoggerInt32(encoder, seq, PART_KEY_MESSAGE_SEQ);
				if (domain != nil && [domain length])
					EncodeLoggerString(encoder, (CFStringRef)domain, PART_KEY_TAG);
				if (level)
					EncodeLoggerInt32(encoder, level, PART_KEY_LEVEL);
				EncodeLoggerString(encoder, msgString, PART_KEY_MESSAGE);
				PushMessageToLoggerQueue(logger, encoder);
				CFRelease(encoder);
			}
			else
			{
				LOGGERDBG(CFSTR("-> failed creating encoder"));
			}

		}
		CFRelease(msgString);
	}
}

static void LogImageTo_internal(Logger *logger, NSString *domain, int level, int width, int height, NSData *data)
{
	if (logger == NULL)
	{
		logger = LoggerGetDefaultLogger();
		LoggerStart(logger);
	}

	int32_t seq = OSAtomicIncrement32Barrier(&logger->messageSeq);
	LOGGERDBG(CFSTR("%ld LogImage"), seq);

	if (logger->logToConsole)
	{
		char s[32];
		sprintf(s, "<image %dx%d>", width, height);
		CFStringRef str = CFStringCreateWithBytes(NULL, (const UInt8 *)s, strlen(s), kCFStringEncodingASCII, false);
		CFShow(str);
		CFRelease(str);
		return;
	}
	CFMutableDataRef encoder = CreateLoggerData();
	if (encoder != NULL)
	{
		EncodeTimestampAndThreadID(encoder);
		EncodeLoggerInt32(encoder, LOGMSG_TYPE_LOG, PART_KEY_MESSAGE_TYPE);
		EncodeLoggerInt32(encoder, seq, PART_KEY_MESSAGE_SEQ);
		if (domain != nil && [domain length])
			EncodeLoggerString(encoder, (CFStringRef)domain, PART_KEY_TAG);
		if (level)
			EncodeLoggerInt32(encoder, level, PART_KEY_LEVEL);
		if (width && height)
		{
			EncodeLoggerInt32(encoder, width, PART_KEY_IMAGE_WIDTH);
			EncodeLoggerInt32(encoder, height, PART_KEY_IMAGE_HEIGHT);
		}
		EncodeLoggerData(encoder, (CFDataRef)data, PART_KEY_MESSAGE, PART_TYPE_IMAGE);

		PushMessageToLoggerQueue(logger, encoder);
		CFRelease(encoder);
	}
	else
	{
		LOGGERDBG(CFSTR("-> failed creating encoder"));
	}

}

static void LogDataTo_internal(Logger *logger, NSString *domain, int level, NSData *data)
{
	if (logger == NULL)
	{
		logger = LoggerGetDefaultLogger();
		LoggerStart(logger);
	}

	int32_t seq = OSAtomicIncrement32Barrier(&logger->messageSeq);
	LOGGERDBG(CFSTR("%ld LogData"), seq);

	if (logger->logToConsole)
	{
		CFShow(data);
		return;
	}
	CFMutableDataRef encoder = CreateLoggerData();
	if (encoder != NULL)
	{
		EncodeTimestampAndThreadID(encoder);
		EncodeLoggerInt32(encoder, LOGMSG_TYPE_LOG, PART_KEY_MESSAGE_TYPE);
		EncodeLoggerInt32(encoder, seq, PART_KEY_MESSAGE_SEQ);
		if (domain != nil && [domain length])
			EncodeLoggerString(encoder, (CFStringRef)domain, PART_KEY_TAG);
		if (level)
			EncodeLoggerInt32(encoder, level, PART_KEY_LEVEL);
		EncodeLoggerData(encoder, (CFDataRef)data, PART_KEY_MESSAGE, PART_TYPE_BINARY);
		
		PushMessageToLoggerQueue(logger, encoder);
		CFRelease(encoder);
	}
	else
	{
		LOGGERDBG(CFSTR("-> failed creating encoder"));
	}
}

static void LogStartBlockTo_internal(Logger *logger, NSString *format, va_list args)
{
	if (logger == NULL)
	{
		logger = LoggerGetDefaultLogger();
		LoggerStart(logger);
	}

	int32_t seq = OSAtomicIncrement32Barrier(&logger->messageSeq);
	LOGGERDBG(CFSTR("%ld LogStartBlock"), seq);

	if (logger->logToConsole)
	{
		if (format != nil)
		{
			CFStringRef msgString = CFStringCreateWithFormatAndArguments(NULL, NULL, (CFStringRef)format, args);
			if (msgString != NULL)
			{
				CFShow(msgString);
				CFRelease(msgString);
			}
		}
		return;
	}

	CFMutableDataRef encoder = CreateLoggerData();
	if (encoder != NULL)
	{
		EncodeTimestampAndThreadID(encoder);
		EncodeLoggerInt32(encoder, LOGMSG_TYPE_BLOCKSTART, PART_KEY_MESSAGE_TYPE);
		EncodeLoggerInt32(encoder, seq, PART_KEY_MESSAGE_SEQ);

		CFStringRef msgString = NULL;
		if (format != nil)
		{
			msgString = CFStringCreateWithFormatAndArguments(NULL, NULL, (CFStringRef)format, args);
			if (msgString != NULL)
			{
				EncodeLoggerString(encoder, msgString, PART_KEY_MESSAGE);
				CFRelease(msgString);
			}
		}
		
		PushMessageToLoggerQueue(logger, encoder);
		CFRelease(encoder);
	}
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Public logging functions
// -----------------------------------------------------------------------------
void LogMessageCompatTo(Logger *logger, NSString *format, ...)
{
	va_list args;
	va_start(args, format);
	LogMessageTo_internal(logger, nil, 0, format, args);
	va_end(args);
}

void LogMessageCompat(NSString *format, ...)
{
	va_list args;
	va_start(args, format);
	LogMessageTo_internal(NULL, nil, 0, format, args);
	va_end(args);
}

void LogMessageTo(Logger *logger, NSString *domain, int level, NSString *format, ...)
{
	va_list args;
	va_start(args, format);
	LogMessageTo_internal(logger, domain, level, format, args);
	va_end(args);
}

void LogMessageTo_va(Logger *logger, NSString *domain, int level, NSString *format, va_list args)
{
	LogMessageTo_internal(logger, domain, level, format, args);
}

void LogMessage(NSString *domain, int level, NSString *format, ...)
{
	va_list args;
	va_start(args, format);
	LogMessageTo_internal(NULL, domain, level, format, args);
	va_end(args);
}

void LogMessage_va(NSString *domain, int level, NSString *format, va_list args)
{
	LogMessageTo_internal(NULL, domain, level, format, args);
}

void LogData(NSString *domain, int level, NSData *data)
{
	LogDataTo_internal(NULL, domain, level, data);
}

void LogDataTo(Logger *logger, NSString *domain, int level, NSData *data)
{
	LogDataTo_internal(logger, domain, level, data);
}

void LogImageData(NSString *domain, int level, int width, int height, NSData *data)
{
	LogImageTo_internal(NULL, domain, level, width, height, data);
}

void LogImageDataTo(Logger *logger, NSString *domain, int level, int width, int height, NSData *data)
{
	LogImageTo_internal(logger, domain, level, width, height, data);
}

void LogStartBlock(NSString *format, ...)
{
	va_list args;
	va_start(args, format);
	LogStartBlockTo_internal(NULL, format, args);
	va_end(args);
}

void LogStartBlockTo(Logger *logger, NSString *format, ...)
{
	va_list args;
	va_start(args, format);
	LogStartBlockTo_internal(logger, format, args);
	va_end(args);
}

void LogEndBlockTo(Logger *logger)
{
	if (logger == NULL)
	{
		logger = LoggerGetDefaultLogger();
		LoggerStart(logger);
	}

	if (logger->logToConsole)
		return;
	
	int32_t seq = OSAtomicIncrement32Barrier(&logger->messageSeq);
	LOGGERDBG(CFSTR("%ld LogEndBlock"), seq);

	CFMutableDataRef encoder = CreateLoggerData();
	if (encoder != NULL)
	{
		EncodeTimestampAndThreadID(encoder);
		EncodeLoggerInt32(encoder, LOGMSG_TYPE_BLOCKEND, PART_KEY_MESSAGE_TYPE);
		EncodeLoggerInt32(encoder, seq, PART_KEY_MESSAGE_SEQ);
		PushMessageToLoggerQueue(logger, encoder);
		CFRelease(encoder);
	}
	else
	{
		LOGGERDBG(CFSTR("-> failed creating encoder"));
	}

}

void LogEndBlock()
{
	LogEndBlockTo(NULL);
}
