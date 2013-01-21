/*
 * LoggerClient.m
 *
 * version 1.2 10-JAN-2013
 *
 * Main implementation of the NSLogger client side code
 * Part of NSLogger (client side)
 * https://github.com/fpillet/NSLogger
 *
 * BSD license follows (http://www.opensource.org/licenses/bsd-license.php)
 * 
 * Copyright (c) 2010-2013 Florent Pillet All Rights Reserved.
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
 */

#import "LoggerClient.h"

#import <sys/time.h>
#import <fcntl.h>

#if !TARGET_OS_IPHONE
	#import <sys/types.h>
	#import <sys/sysctl.h>
	#import <dlfcn.h>
	
	#if ALLOW_COCOA_USE
	#import <Cocoa/Cocoa.h>
	#endif
#else
	#if ALLOW_COCOA_USE
	#import <UIKit/UIKit.h>
	#endif
#endif

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

/* NSLogger native binary message format:
 * Each message is a dictionary encoded in a compact format. All values are stored
 * in network order (big endian). A message is made of several "parts", which are
 * typed chunks of data, each with a specific purpose (partKey), data type (partType)
 * and data size (partSize).
 *
 *	uint32_t	totalSize		(total size for the whole message)
 *	uint16_t	partCount		(number of parts below)
 *  [repeat partCount times]:
 *		uint8_t		partKey		the part key
 *		uint8_t		partType	(string, binary, image, int16, int32, int64)
 *		uint32_t	partSize	(only for string, binary and image types, others are implicit)
 *		.. `partSize' data bytes
 *
 * Complete message is usually made of:
 *	- a PART_KEY_MESSAGE_TYPE (mandatory) which contains one of the LOGMSG_TYPE_* values
 *  - a PART_KEY_TIMESTAMP_S (mandatory) which is the timestamp returned by gettimeofday() (seconds from 01.01.1970 00:00)
 *	- a PART_KEY_TIMESTAMP_MS (optional) complement of the timestamp seconds, in milliseconds
 *	- a PART_KEY_TIMESTAMP_US (optional) complement of the timestamp seconds and milliseconds, in microseconds
 *	- a PART_KEY_THREAD_ID (mandatory) the ID of the user thread that produced the log entry
 *	- a PART_KEY_TAG (optional) a tag that helps categorizing and filtering logs from your application, and shows up in viewer logs
 *	- a PART_KEY_LEVEL (optional) a log level that helps filtering logs from your application (see as few or as much detail as you need)
 *	- a PART_KEY_MESSAGE which is the message text, binary data or image
 *  - a PART_KEY_MESSAGE_SEQ which is the message sequence number (message# sent by client)
 *	- a PART_KEY_FILENAME (optional) with the filename from which the log was generated
 *	- a PART_KEY_LINENUMBER (optional) the linenumber in the filename at which the log was generated
 *	- a PART_KEY_FUNCTIONNAME (optional) the function / method / selector from which the log was generated
 *  - if logging an image, PART_KEY_IMAGE_WIDTH and PART_KEY_IMAGE_HEIGHT let the desktop know the image size without having to actually decode it
 */

// Constants for the "part key" field
#define	PART_KEY_MESSAGE_TYPE	0
#define	PART_KEY_TIMESTAMP_S	1			// "seconds" component of timestamp
#define PART_KEY_TIMESTAMP_MS	2			// milliseconds component of timestamp (optional, mutually exclusive with PART_KEY_TIMESTAMP_US)
#define PART_KEY_TIMESTAMP_US	3			// microseconds component of timestamp (optional, mutually exclusive with PART_KEY_TIMESTAMP_MS)
#define PART_KEY_THREAD_ID		4
#define	PART_KEY_TAG			5
#define	PART_KEY_LEVEL			6
#define	PART_KEY_MESSAGE		7
#define PART_KEY_IMAGE_WIDTH	8			// messages containing an image should also contain a part with the image size
#define PART_KEY_IMAGE_HEIGHT	9			// (this is mainly for the desktop viewer to compute the cell size without having to immediately decode the image)
#define PART_KEY_MESSAGE_SEQ	10			// the sequential number of this message which indicates the order in which messages are generated
#define PART_KEY_FILENAME		11			// when logging, message can contain a file name
#define PART_KEY_LINENUMBER		12			// as well as a line number
#define PART_KEY_FUNCTIONNAME	13			// and a function or method name

// Constants for parts in LOGMSG_TYPE_CLIENTINFO
#define PART_KEY_CLIENT_NAME	20
#define PART_KEY_CLIENT_VERSION	21
#define PART_KEY_OS_NAME		22
#define PART_KEY_OS_VERSION		23
#define PART_KEY_CLIENT_MODEL	24			// For iPhone, device model (i.e 'iPhone', 'iPad', etc)
#define PART_KEY_UNIQUEID		25			// for remote device identification, part of LOGMSG_TYPE_CLIENTINFO

// Area starting at which you may define your own constants
#define PART_KEY_USER_DEFINED	100

// Constants for the "partType" field
#define	PART_TYPE_STRING		0			// Strings are stored as UTF-8 data
#define PART_TYPE_BINARY		1			// A block of binary data
#define PART_TYPE_INT16			2
#define PART_TYPE_INT32			3
#define	PART_TYPE_INT64			4
#define PART_TYPE_IMAGE			5			// An image, stored in PNG format

// Data values for the PART_KEY_MESSAGE_TYPE parts
#define LOGMSG_TYPE_LOG			0			// A standard log message
#define	LOGMSG_TYPE_BLOCKSTART	1			// The start of a "block" (a group of log entries)
#define	LOGMSG_TYPE_BLOCKEND	2			// The end of the last started "block"
#define LOGMSG_TYPE_CLIENTINFO	3			// Information about the client app
#define LOGMSG_TYPE_DISCONNECT	4			// Pseudo-message on the desktop side to identify client disconnects
#define LOGMSG_TYPE_MARK		5			// Pseudo-message that defines a "mark" that users can place in the log flow

// Default Bonjour service identifiers
#define LOGGER_SERVICE_TYPE_SSL	CFSTR("_nslogger-ssl._tcp")
#define LOGGER_SERVICE_TYPE		CFSTR("_nslogger._tcp")

/* Logger internal debug flags */
// Set to 0 to disable internal debug completely
// Set to 1 to activate console logs when running the logger itself
// Set to 2 to see every logging call issued by the app, too
#define LOGGER_DEBUG 0
#ifdef NSLog
	#undef NSLog
#endif

// Internal debugging stuff for the logger itself
#if LOGGER_DEBUG
	#define LOGGERDBG LoggerDbg
	#if LOGGER_DEBUG > 1
		#define LOGGERDBG2 LoggerDbg
	#else
		#define LOGGERDBG2(format, ...) do{}while(0)
	#endif
	// Internal logging function prototype
	static void LoggerDbg(CFStringRef format, ...);
#else
	#define LOGGERDBG(format, ...) do{}while(0)
	#define LOGGERDBG2(format, ...) do{}while(0)
#endif

// small set of macros for proper ARC/non-ARC compilation support
// with added cruft to support non-clang compilers
#undef LOGGER_ARC_MACROS_DEFINED
#if defined(__has_feature)
	#if __has_feature(objc_arc)
        #define CAST_TO_CFSTRING			__bridge CFStringRef
        #define CAST_TO_NSSTRING			__bridge NSString *
		#define CAST_TO_CFDATA				__bridge CFDataRef
		#define RELEASE(obj)				do{}while(0)
		#define AUTORELEASE_POOL_BEGIN		@autoreleasepool{
		#define AUTORELEASE_POOL_END		}
		#define LOGGER_ARC_MACROS_DEFINED
	#endif
#endif
#if !defined(LOGGER_ARC_MACROS_DEFINED)
	#define CAST_TO_CFSTRING			CFStringRef
    #define CAST_TO_NSSTRING			NSString *
	#define CAST_TO_CFDATA				CFDataRef
	#define RELEASE(obj)				[obj release]
	#define AUTORELEASE_POOL_BEGIN		NSAutoreleasePool *__pool=[[NSAutoreleasePool alloc] init];
	#define AUTORELEASE_POOL_END		[__pool drain];
#endif
#undef LOGGER_ARC_MACROS_DEFINED

#if NSLOG_OVERRIDE
#include <mach/error.h>

/****************************************************************************************
 Dynamically overrides the function implementation referenced by
 originalFunctionAddress with the implentation pointed to by overrideFunctionAddress.
 Optionally returns a pointer to a "reentry island" which, if jumped to, will resume
 the original implementation.
 
 @param	originalFunctionAddress			->	Required address of the function to
 override (with overrideFunctionAddress).
 @param	overrideFunctionAddress			->	Required address to the overriding
 function.
 @param	originalFunctionReentryIsland	<-	Optional pointer to pointer to the
 reentry island. Can be NULL.
 @result									<-	err_cannot_override if the original
 function's implementation begins with
 the 'mfctr' instruction.
 
 ************************************************************************************/
#define	err_cannot_override	(err_local|1)
mach_error_t mach_override_ptr(void *originalFunctionAddress,
							   const void *overrideFunctionAddress,
							   void **originalFunctionReentryIsland);
__attribute__((constructor)) static void replace_NSLog() {
	mach_override_ptr((void *)&NSLog, (void *)&LogMessageCompat, NULL);
	mach_override_ptr((void *)&NSLogv, (void *)&LogMessageCompat_va, NULL);
}
#endif

/* Local prototypes */
static void* LoggerWorkerThread(Logger *logger);
static void LoggerWriteMoreData(Logger *logger);
static void LoggerPushMessageToQueue(Logger *logger, CFDataRef message);

// Bonjour management
static void LoggerStartBonjourBrowsing(Logger *logger);
static void LoggerStopBonjourBrowsing(Logger *logger);
static BOOL LoggerBrowseBonjourForServices(Logger *logger, CFStringRef domainName);
static void LoggerServiceBrowserCallBack(CFNetServiceBrowserRef browser, CFOptionFlags flags, CFTypeRef domainOrService, CFStreamError* error, void *info);

// Reachability and reconnect timer
static void LoggerStartReachabilityChecking(Logger *logger);
static void LoggerStopReachabilityChecking(Logger *logger);
static void LoggerReachabilityCallBack(SCNetworkReachabilityRef target, SCNetworkReachabilityFlags flags, void *info);
static void LoggerTimedReconnectCallback(CFRunLoopTimerRef timer, void *info);

// Connection & stream management
static void LoggerTryConnect(Logger *logger);
static void LoggerWriteStreamCallback(CFWriteStreamRef ws, CFStreamEventType event, void* info);

// File buffering
static void LoggerCreateBufferWriteStream(Logger *logger);
static void LoggerCreateBufferReadStream(Logger *logger);
static void LoggerEmptyBufferFile(Logger *logger);
static void LoggerFileBufferingOptionsChanged(Logger *logger);
static void LoggerFlushQueueToBufferStream(Logger *logger, BOOL firstEntryIsClientInfo);

// Encoding functions
static void	LoggerPushClientInfoToFrontOfQueue(Logger *logger);
static void LoggerMessageAddTimestampAndThreadID(CFMutableDataRef encoder);

static CFMutableDataRef LoggerMessageCreate();
static void LoggerMessageUpdateDataHeader(CFMutableDataRef data);

static void LoggerMessageAddInt32(CFMutableDataRef data, int32_t anInt, int key);
#if __LP64__
static void LoggerMessageAddInt64(CFMutableDataRef data, int64_t anInt, int key);
#endif
static void LoggerMessageAddString(CFMutableDataRef data, CFStringRef aString, int key);
static void LoggerMessageAddData(CFMutableDataRef data, CFDataRef theData, int key, int partType);
static uint32_t LoggerMessageGetSeq(CFDataRef message);

/* Static objects */
static Logger* volatile sDefaultLogger = NULL;
static pthread_mutex_t sDefaultLoggerMutex = PTHREAD_MUTEX_INITIALIZER;

// Console logging
static void LoggerStartGrabbingConsoleTo(Logger *logger);
static void LoggerStopGrabbingConsoleTo(Logger *logger);
static Logger ** consoleGrabbersList = NULL;
static unsigned consoleGrabbersListLength;
static unsigned numActiveConsoleGrabbers = 0;
static pthread_mutex_t consoleGrabbersMutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_t consoleGrabThread;
static int sConsolePipes[4] = { -1, -1, -1, -1 };

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Default logger
// -----------------------------------------------------------------------------
void LoggerSetDefaultLogger(Logger *defaultLogger)
{
	pthread_mutex_lock(&sDefaultLoggerMutex);
	sDefaultLogger = defaultLogger;
	pthread_mutex_unlock(&sDefaultLoggerMutex);
}

Logger *LoggerGetDefaultLogger(void)
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
Logger *LoggerInit(void)
{
	LOGGERDBG(CFSTR("LoggerInit defaultLogger=%p"), sDefaultLogger);
	
	Logger *logger = (Logger *)malloc(sizeof(Logger));
	bzero(logger, sizeof(Logger));

	logger->logQueue = CFArrayCreateMutable(NULL, 32, &kCFTypeArrayCallBacks);
	pthread_mutex_init(&logger->logQueueMutex, NULL);
	pthread_cond_init(&logger->logQueueEmpty, NULL);

	logger->bonjourServiceBrowsers = CFArrayCreateMutable(NULL, 4, &kCFTypeArrayCallBacks);
	logger->bonjourServices = CFArrayCreateMutable(NULL, 4, &kCFTypeArrayCallBacks);

	// for now we don't grow the send buffer, just use one page of memory which should be enouh
	// (bigger messages will be sent separately)
	logger->sendBuffer = (uint8_t *)malloc(4096);
	logger->sendBufferSize = 4096;
	
	logger->options = LOGGER_DEFAULT_OPTIONS;

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

void LoggerSetOptions(Logger *logger, uint32_t options)
{
	LOGGERDBG(CFSTR("LoggerSetOptions options=0x%08lx"), options);

	// If we choose to log to system console (instead of logging to a remote viewer),
	// make sure we are not configured to capture the system console
	if (options & kLoggerOption_LogToConsole)
		options &= ~kLoggerOption_CaptureSystemConsole;

	if (logger == NULL)
		logger = LoggerGetDefaultLogger();
	if (logger != NULL)
		logger->options = options;
}

void LoggerSetupBonjour(Logger *logger, CFStringRef bonjourServiceType, CFStringRef bonjourServiceName)
{
	LOGGERDBG(CFSTR("LoggerSetupBonjour serviceType=%@ serviceName=%@"), bonjourServiceType, bonjourServiceName);

	if (logger == NULL)
		logger = LoggerGetDefaultLogger();
	if (logger != NULL)
	{
		if (bonjourServiceType != NULL)
			CFRetain(bonjourServiceType);
		if (bonjourServiceName != NULL)
			CFRetain(bonjourServiceName);
		if (logger->bonjourServiceType != NULL)
			CFRelease(logger->bonjourServiceType);
		if (logger->bonjourServiceName != NULL)
			CFRelease(logger->bonjourServiceName);
		logger->bonjourServiceType = bonjourServiceType;
		logger->bonjourServiceName = bonjourServiceName;
	}
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
	{
		logger = LoggerGetDefaultLogger();
		if (logger == NULL)
			return;
	}

	BOOL change = ((logger->bufferFile != NULL && absolutePath == NULL) ||
				   (logger->bufferFile == NULL && absolutePath != NULL) ||
				   (logger->bufferFile != NULL && absolutePath != NULL && CFStringCompare(logger->bufferFile, absolutePath, 0) != kCFCompareEqualTo));
	if (change)
	{
		if (logger->bufferFile != NULL)
		{
			CFRelease(logger->bufferFile);
			logger->bufferFile = NULL;
		}
		if (absolutePath != NULL)
			logger->bufferFile = CFStringCreateCopy(NULL, absolutePath);
		if (logger->bufferFileChangedSource != NULL)
			CFRunLoopSourceSignal(logger->bufferFileChangedSource);
	}
}

Logger *LoggerStart(Logger *logger)
{
	// will do nothing if logger is already started
	if (logger == NULL)
		logger = LoggerGetDefaultLogger();

    if (logger != NULL)
	{
        if (logger->workerThread == NULL)
        {
            // Start the work thread which performs the Bonjour search,
            // connects to the logging service and forwards the logs
            LOGGERDBG(CFSTR("LoggerStart logger=%p"), logger);
            pthread_create(&logger->workerThread, NULL, (void *(*)(void *))&LoggerWorkerThread, logger);

	    	// Grab console output if required
        	if (logger->options & kLoggerOption_CaptureSystemConsole)
            	LoggerStartGrabbingConsoleTo(logger);
        }
    }
    else
    {
        LOGGERDBG2(CFSTR("-> could not create logger"));
    }
	return logger;
}

void LoggerStop(Logger *logger)
{
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
            LoggerStopGrabbingConsoleTo(logger);
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
		if (logger->bonjourServiceType != NULL)
			CFRelease(logger->bonjourServiceType);
		if (logger->bonjourServiceName != NULL)
			CFRelease(logger->bonjourServiceName);

		// to make sure potential errors are catched, set the whole structure
		// to a value that will make code crash if it tries using pointers to it.
		memset(logger, 0x55, sizeof(Logger));

		free(logger);
	}
}

void LoggerFlush(Logger *logger, BOOL waitForConnection)
{
	// Special case: if nothing has ever been logged, don't bother
	if (logger == NULL && sDefaultLogger == NULL)
		return;
	if (logger == NULL)
		logger = LoggerGetDefaultLogger();
	if (logger != NULL &&
		pthread_self() != logger->workerThread &&
		(logger->connected || logger->bufferFile != NULL || waitForConnection))
	{
		pthread_mutex_lock(&logger->logQueueMutex);
		if (CFArrayGetCount(logger->logQueue) > 0)
			pthread_cond_wait(&logger->logQueueEmpty, &logger->logQueueMutex);
		pthread_mutex_unlock(&logger->logQueueMutex);
	}
}

#if LOGGER_DEBUG
static void LoggerDbg(CFStringRef format, ...)
{
	// Internal debugging function
	// (what do you think, that we use the Logger to debug itself ??)
	if (format != NULL)
	{
		AUTORELEASE_POOL_BEGIN
		va_list	args;	
		va_start(args, format);
		CFStringRef s = CFStringCreateWithFormatAndArguments(NULL, NULL, (CFStringRef)format, args);
		va_end(args);
		if (s != NULL)
		{
			CFShow(s);
			CFRelease(s);
		}
		AUTORELEASE_POOL_END
	}
}
#endif

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Main processing
// -----------------------------------------------------------------------------
static void *LoggerWorkerThread(Logger *logger)
{
	LOGGERDBG(CFSTR("Start LoggerWorkerThread"));

#if !TARGET_OS_IPHONE
	// Register thread with Garbage Collector on Mac OS X if we're running an OS version that has GC
    void (*registerThreadWithCollector_fn)(void);
    registerThreadWithCollector_fn = (void(*)(void)) dlsym(RTLD_NEXT, "objc_registerThreadWithCollector");
    if (registerThreadWithCollector_fn)
        (*registerThreadWithCollector_fn)();
#endif

	// Create and get the runLoop for this thread
	CFRunLoopRef runLoop = CFRunLoopGetCurrent();

	// Create the run loop source that signals when messages have been added to the runloop
	// this will directly trigger a WriteMoreData() call, which will or won't write depending
	// on whether we're connected and there's space available in the stream
	CFRunLoopSourceContext context;
	bzero(&context, sizeof(context));
	context.info = logger;
	context.perform = (void *)&LoggerWriteMoreData;
	logger->messagePushedSource = CFRunLoopSourceCreate(NULL, 0, &context);
	if (logger->messagePushedSource == NULL)
	{
		// Failing to create the runloop source for pushing messages is a major failure.
		// This NSLog is intentional. We WANT console output in this case
		NSLog(@"*** NSLogger: Worker thread failed creating runLoop source, switching to console logging.");
		logger->options |= kLoggerOption_LogToConsole;
		logger->workerThread = NULL;
		return NULL;
	}
	CFRunLoopAddSource(runLoop, logger->messagePushedSource, kCFRunLoopDefaultMode);

	// Create the buffering stream if needed
	if (logger->bufferFile != NULL)
		LoggerCreateBufferWriteStream(logger);
	
	// Create the runloop source that lets us know when file buffering options change
	context.perform = (void *)&LoggerFileBufferingOptionsChanged;
	logger->bufferFileChangedSource = CFRunLoopSourceCreate(NULL, 0, &context);
	if (logger->bufferFileChangedSource == NULL)
	{
		// This failure MUST be logged to console
		NSLog(@"*** NSLogger Warning: failed creating a runLoop source for file buffering options change.");
	}
	else
		CFRunLoopAddSource(runLoop, logger->bufferFileChangedSource, kCFRunLoopDefaultMode);

	// Start Bonjour browsing, wait for remote logging service to be found
	if (logger->host == NULL && (logger->options & kLoggerOption_BrowseBonjour))
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
	NSTimeInterval timeout = 0.10;
	while (!logger->quit)
	{
		int result = CFRunLoopRunInMode(kCFRunLoopDefaultMode, timeout, true);
		if (result == kCFRunLoopRunFinished || result == kCFRunLoopRunStopped)
			break;
		if (result == kCFRunLoopRunHandledSource)
		{
			timeout = 0.0;
			continue;
		}
		timeout = fmin(0.10, timeout+0.0005);

		// Make sure we restart connection attempts if we get disconnected
		if (!logger->connected &&
			!CFArrayGetCount(logger->bonjourServices) &&
			!CFArrayGetCount(logger->bonjourServiceBrowsers) &&
			!CFArrayGetCount(logger->bonjourServices))
		{
			if (logger->options & kLoggerOption_BrowseBonjour)
				LoggerStartBonjourBrowsing(logger);
			else if (logger->host != NULL && logger->reachability == NULL && logger->checkHostTimer == NULL)
				LoggerTryConnect(logger);
		}
	}

	// Cleanup
	if (logger->options & kLoggerOption_BrowseBonjour)
		LoggerStopBonjourBrowsing(logger);
	LoggerStopReachabilityChecking(logger);

	if (logger->logStream != NULL)
	{
		CFWriteStreamSetClient(logger->logStream, 0, NULL, NULL);
		CFWriteStreamClose(logger->logStream);
		CFRelease(logger->logStream);
		logger->logStream = NULL;
	}

	if (logger->bufferWriteStream == NULL && logger->bufferFile != NULL)
	{
		// If there are messages in the queue and LoggerStop() was called and
		// a buffer file was set just before LoggerStop() was called, flush
		// the log queue to the buffer file
		pthread_mutex_lock(&logger->logQueueMutex);
		CFIndex outstandingMessages = CFArrayGetCount(logger->logQueue);
		pthread_mutex_unlock(&logger->logQueueMutex);
		if (outstandingMessages)
			LoggerCreateBufferWriteStream(logger);
	}

	if (logger->bufferWriteStream != NULL)
	{
		CFWriteStreamClose(logger->bufferWriteStream);
		CFRelease(logger->bufferWriteStream);
		logger->bufferWriteStream = NULL;
	}

	if (logger->messagePushedSource != NULL)
	{
		CFRunLoopSourceInvalidate(logger->messagePushedSource);
		CFRelease(logger->messagePushedSource);
		logger->messagePushedSource = NULL;
	}
	
	if (logger->bufferFileChangedSource != NULL)
	{
		CFRunLoopSourceInvalidate(logger->bufferFileChangedSource);
		CFRelease(logger->bufferFileChangedSource);
		logger->bufferFileChangedSource = NULL;
	}

	// if the client ever tries to log again against us, make sure that logs at least
	// go to console
	logger->options |= kLoggerOption_LogToConsole;
	logger->workerThread = NULL;
	return NULL;
}

static CFStringRef LoggerCreateStringRepresentationFromBinaryData(CFDataRef data)
{
	CFMutableStringRef s = CFStringCreateMutable(NULL, 0);
	unsigned int offset = 0;
	unsigned int dataLen = (unsigned int)CFDataGetLength(data);
	char buffer[1+6+16*3+1+16+1+1+1];
	buffer[0] = '\0';
	const unsigned char *q = (unsigned char *)CFDataGetBytePtr(data);
	if (dataLen == 1)
		CFStringAppend(s, CFSTR("Raw data, 1 byte:\n"));
	else
		CFStringAppendFormat(s, NULL, CFSTR("Raw data, %u bytes:\n"), dataLen);
	while (dataLen)
	{
		int i, j, b = sprintf(buffer," %04x: ", offset);
		for (i=0; i < 16 && i < (int)dataLen; i++)
			sprintf(&buffer[b+3*i], "%02x ", (int)q[i]);
		for (j=i; j < 16; j++)
			strcat(buffer, "   ");
		
		b = (int)strlen(buffer);
		buffer[b++] = '\'';
		for (i=0; i < 16 && i < (int)dataLen; i++, q++)
		{
			if (*q >= 32 && *q < 128)
				buffer[b++] = *q;
			else
				buffer[b++] = ' ';
		}
		for (j=i; j < 16; j++)
			buffer[b++] = ' ';
		buffer[b++] = '\'';
		buffer[b++] = '\n';
		buffer[b] = 0;
		
		CFStringRef bufferStr = CFStringCreateWithBytesNoCopy(NULL, (const UInt8 *)buffer, strlen(buffer), kCFStringEncodingISOLatin1, false, kCFAllocatorNull);
		CFStringAppend(s, bufferStr);
		CFRelease(bufferStr);
		
		dataLen -= i;
		offset += i;
	}
	return s;
}

static void LoggerLogToConsole(CFDataRef data)
{
	// Decode and log a message to the console. Doing this from the worker thread
	// allow us to serialize logging, which is a benefit that NSLog() doesn't have.
	// Only drawback is that we have to decode our own message, but that is a minor hassle.
	if (data == NULL)
	{
		CFShow(CFSTR("LoggerLogToConsole: data is NULL"));
		return;
	}
	struct timeval timestamp;
	bzero(&timestamp, sizeof(timestamp));
	int type = LOGMSG_TYPE_LOG, contentsType = PART_TYPE_STRING;
	int imgWidth=0, imgHeight=0;
	CFStringRef message = NULL;
	CFStringRef thread = NULL;

	// decode message contents
	uint8_t *p = (uint8_t *)CFDataGetBytePtr(data) + 4;
	uint16_t partCount;
	memcpy(&partCount, p, 2);
	partCount = ntohs(partCount);
	p += 2;
	while (partCount--)
	{
		uint8_t partKey = *p++;
		uint8_t partType = *p++;
		uint32_t partSize;
		if (partType == PART_TYPE_INT16)
			partSize = 2;
		else if (partType == PART_TYPE_INT32)
			partSize = 4;
		else if (partType == PART_TYPE_INT64)
			partSize = 8;
		else
		{
			memcpy(&partSize, p, 4);
			p += 4;
			partSize = ntohl(partSize);
		}
		CFTypeRef part = NULL;
		uint32_t value32 = 0;
		uint64_t value64 = 0;
		if (partSize > 0)
		{
			if (partType == PART_TYPE_STRING)
			{
				// trim whitespace and newline at both ends of the string
				uint8_t *q = p;
				uint32_t l = partSize;
				while (l && (*q == ' ' || *q == '\t' || *q == '\n' || *q == '\r'))
					q++, l--;
				uint8_t *r = q + l - 1;
				while (l && (*r == ' ' || *r == '\t' || *r == '\n' || *r == '\r'))
					r--, l--;
				part = CFStringCreateWithBytesNoCopy(NULL, q, l, kCFStringEncodingUTF8, false, kCFAllocatorNull);
			}
			else if (partType == PART_TYPE_BINARY)
			{
				part = CFDataCreateWithBytesNoCopy(NULL, p, partSize, kCFAllocatorNull);
			}
			else if (partType == PART_TYPE_IMAGE)
			{
				// ignore image data, we can't log it to console
			}
			else if (partType == PART_TYPE_INT16)
			{
				value32 = ((uint32_t)p[0]) << 8 | (uint32_t)p[1];
			}
			else if (partType == PART_TYPE_INT32)
			{
				memcpy(&value32, p, 4);
				value32 = ntohl(value32);
			}
			else if (partType == PART_TYPE_INT64)
			{
				memcpy(&value64, p, 8);
				value64 = CFSwapInt64BigToHost(value64);
			}
			p += partSize;
		}
		switch (partKey)
		{
			case PART_KEY_MESSAGE_TYPE:
				type = (int)value32;
				break;
			case PART_KEY_TIMESTAMP_S:			// timestamp with seconds-level resolution
				timestamp.tv_sec = (partType == PART_TYPE_INT64) ? (__darwin_time_t)value64 : (__darwin_time_t)value32;
				break;
			case PART_KEY_TIMESTAMP_MS:			// millisecond part of the timestamp (optional)
				timestamp.tv_usec = ((partType == PART_TYPE_INT64) ? (__darwin_suseconds_t)value64 : (__darwin_suseconds_t)value32) * 1000;
				break;
			case PART_KEY_TIMESTAMP_US:			// microsecond part of the timestamp (optional)
				timestamp.tv_usec = (partType == PART_TYPE_INT64) ? (__darwin_suseconds_t)value64 : (__darwin_suseconds_t)value32;
				break;
			case PART_KEY_THREAD_ID:
				if (thread == NULL)				// useless test, we know what we're doing but clang analyzer doesn't...
				{
					if (partType == PART_TYPE_INT32)
						thread = CFStringCreateWithFormat(NULL, NULL, CFSTR("thread 0x%08x"), value32);
					else if (partType == PART_TYPE_INT64)
						thread = CFStringCreateWithFormat(NULL, NULL, CFSTR("thread 0x%qx"), value64);
					else if (partType == PART_TYPE_STRING && part != NULL)
						thread = CFRetain(part);
				}
				break;
			case PART_KEY_MESSAGE:
				if (part != NULL)
				{
					if (partType == PART_TYPE_STRING)
						message = CFRetain(part);
					else if (partType == PART_TYPE_BINARY)
						message = LoggerCreateStringRepresentationFromBinaryData(part);
				}
				contentsType = partType;
				break;
			case PART_KEY_IMAGE_WIDTH:
				imgWidth = (partType == PART_TYPE_INT32 ? (int)value32 : (int)value64);
				break;
			case PART_KEY_IMAGE_HEIGHT:
				imgHeight = (partType == PART_TYPE_INT32 ? (int)value32 : (int)value64);
				break;
			default:
				break;
		}
		if (part != NULL)
			CFRelease(part);
	}

	// Prepare the final representation and log to console
	CFMutableStringRef s = CFStringCreateMutable(NULL, 0);

	char buf[32];
	struct tm t;
	gmtime_r(&timestamp.tv_sec, &t);
	strftime(buf, sizeof(buf)-1, "%T", &t);
	CFStringRef ts = CFStringCreateWithBytesNoCopy(NULL, (const UInt8 *)buf, strlen(buf), kCFStringEncodingASCII, false, kCFAllocatorNull);
	CFStringAppend(s, ts);
	CFRelease(ts);

	if (contentsType == PART_TYPE_IMAGE)
		message = CFStringCreateWithFormat(NULL, NULL, CFSTR("<image width=%d height=%d>"), imgWidth, imgHeight);

	char threadNamePadding[20];
	threadNamePadding[0] = 0;
	if (thread != NULL && CFStringGetLength(thread) < 16)
	{
		int n = 16 - (int)CFStringGetLength(thread);
		memset(threadNamePadding, ' ', n);
		threadNamePadding[n] = 0;
	}
	CFStringAppendFormat(s, NULL, CFSTR(".%04d %s%@ | %@"),
						 (int)(timestamp.tv_usec / 1000),
						 threadNamePadding, (thread == NULL) ? CFSTR("") : thread,
						 (message != NULL) ? message : CFSTR(""));

	if (thread != NULL)
		CFRelease(thread);
	if (message != NULL)
		CFRelease(message);

	if (type == LOGMSG_TYPE_LOG || type == LOGMSG_TYPE_MARK)
		CFShow(s);

	CFRelease(s);
}

static void LoggerWriteMoreData(Logger *logger)
{
	if (!logger->connected)
	{
		if (logger->options & kLoggerOption_LogToConsole)
		{
			pthread_mutex_lock(&logger->logQueueMutex);
			while (CFArrayGetCount(logger->logQueue))
			{
				LoggerLogToConsole((CFDataRef)CFArrayGetValueAtIndex(logger->logQueue, 0));
				CFArrayRemoveValueAtIndex(logger->logQueue, 0);
			}
			pthread_mutex_unlock(&logger->logQueueMutex);
			pthread_cond_broadcast(&logger->logQueueEmpty);
		}
		else if (logger->bufferWriteStream != NULL)
		{
			LoggerFlushQueueToBufferStream(logger, NO);
		}
        else if (!(logger->options & kLoggerOption_BufferLogsUntilConnection))
        {
            /* No client connected
             * User don't want to log to console
             * User don't want to log to file
             * and user don't want us to buffer it in memory
             * So let's just sack the whole queue
             */
			pthread_mutex_lock(&logger->logQueueMutex);
			while (CFArrayGetCount(logger->logQueue))
			{
				CFArrayRemoveValueAtIndex(logger->logQueue, 0);
			}
			pthread_mutex_unlock(&logger->logQueueMutex);
			pthread_cond_broadcast(&logger->logQueueEmpty);
        }

		return;
	}
	
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
			else
			{
				pthread_mutex_lock(&logger->logQueueMutex);
				while (CFArrayGetCount(logger->logQueue))
				{
					CFDataRef d = (CFDataRef)CFArrayGetValueAtIndex(logger->logQueue, 0);
					CFIndex dsize = CFDataGetLength(d);
					if ((logger->sendBufferUsed + dsize) > logger->sendBufferSize)
						break;
					memcpy(logger->sendBuffer + logger->sendBufferUsed, CFDataGetBytePtr(d), dsize);
					logger->sendBufferUsed += dsize;
					CFArrayRemoveValueAtIndex(logger->logQueue, 0);
					logger->incompleteSendOfFirstItem = NO;
				}
				pthread_mutex_unlock(&logger->logQueueMutex);
			}
			if (logger->sendBufferUsed == 0) 
			{
				// are we done yet?
				pthread_mutex_lock(&logger->logQueueMutex);
				if (CFArrayGetCount(logger->logQueue) == 0)
				{
					pthread_mutex_unlock(&logger->logQueueMutex);
					pthread_cond_broadcast(&logger->logQueueEmpty);
					return;
				}

				// first item is too big to fit in a single packet, send it separately
				sendFirstItem = (CFMutableDataRef)CFArrayGetValueAtIndex(logger->logQueue, 0);
				logger->incompleteSendOfFirstItem = YES;
				pthread_mutex_unlock(&logger->logQueueMutex);
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
				// @@@ NOTE: IF WE GET DISCONNECTED WHILE DOING THIS, THINGS WILL GO WRONG
				// NEED TO UPDATE THIS LOGIC
				CFDataReplaceBytes((CFMutableDataRef)sendFirstItem, CFRangeMake(0, written), NULL, 0);
				return;
			}
			
			// we are done sending the first item in the queue, remove it now
			pthread_mutex_lock(&logger->logQueueMutex);
			CFArrayRemoveValueAtIndex(logger->logQueue, 0);
			logger->incompleteSendOfFirstItem = NO;
			pthread_mutex_unlock(&logger->logQueueMutex);
			logger->sendBufferOffset = 0;
		}
		
		pthread_mutex_lock(&logger->logQueueMutex);
		int remainingMsgs = CFArrayGetCount(logger->logQueue);
		pthread_mutex_unlock(&logger->logQueueMutex);
		if (remainingMsgs == 0)
			pthread_cond_broadcast(&logger->logQueueEmpty);
	}
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Console logging
// -----------------------------------------------------------------------------
static void LoggerLogFromFile(int fd)
{
#define BUFSIZE 1000
	UInt8 buf[ BUFSIZE ];
	ssize_t bytes_read = 0;
	while ( (bytes_read = read(fd, buf, BUFSIZE)) > 0 )
	{
		if (buf[bytes_read-1] == '\n')
			--bytes_read;

		CFStringRef messageString = CFStringCreateWithBytes( NULL, buf, bytes_read, kCFStringEncodingASCII, false );
		if (messageString != NULL)
		{
			pthread_mutex_lock( &consoleGrabbersMutex );
			for ( unsigned grabberIndex = 0; grabberIndex < consoleGrabbersListLength; grabberIndex++ )
			{
				if ( consoleGrabbersList[grabberIndex] != NULL )
				{
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wformat-security"
					LogMessageTo(consoleGrabbersList[grabberIndex], @"console", 1, (CAST_TO_NSSTRING) messageString );
#pragma clang dianostic pop
				}
			}
			pthread_mutex_unlock( &consoleGrabbersMutex );
			CFRelease(messageString);
		}
	}
}

static void * LoggerConsoleGrabThread(void * context)
{

	int fdout = sConsolePipes[ 0 ];
	int flags = fcntl(fdout, F_GETFL, 0);
	fcntl(fdout, F_SETFL, flags | O_NONBLOCK);

	int fderr = sConsolePipes[ 2 ];
	flags = fcntl(fderr, F_GETFL, 0);
	fcntl(fderr, F_SETFL, flags | O_NONBLOCK);

	while ( 1 )
	{
		fd_set set;
		FD_ZERO(&set);
		FD_SET(fdout, &set);
		FD_SET(fderr, &set);

		int ret = select(fderr + 1, &set, NULL, NULL, NULL);

		if (ret <= 0)
		{
			// ==0: time expired without activity
			// < 0: error occurred
			break;
		}

		/* Drop the message if there are no listeners. I don't know how to cancel the redirection. */
		if (numActiveConsoleGrabbers == 0)
			continue;

		if (FD_ISSET(fdout, &set))
			LoggerLogFromFile(fdout);
		if (FD_ISSET(fderr, &set ))
			LoggerLogFromFile(fderr);
	}

	return NULL;
}

static void LoggerStartConsoleRedirection()
{
	if (sConsolePipes[0] == -1)
	{
		if (-1 != pipe(sConsolePipes))
			dup2(sConsolePipes[1], 1 /*stdout*/);
	}

	if (sConsolePipes[2] == -1)
	{
		if (-1 != pipe(&sConsolePipes[2]))
			dup2(sConsolePipes[3], 2 /*stderr*/);
	}

	pthread_create(&consoleGrabThread, NULL, &LoggerConsoleGrabThread, NULL);
}

static void LoggerStartGrabbingConsoleTo(Logger *logger)
{
	if (!(logger->options & kLoggerOption_CaptureSystemConsole))
		return;

	pthread_mutex_lock( &consoleGrabbersMutex );

	consoleGrabbersList = realloc( consoleGrabbersList, ++consoleGrabbersListLength * sizeof(Logger *) );
	consoleGrabbersList[numActiveConsoleGrabbers++] = logger;

	pthread_mutex_unlock( &consoleGrabbersMutex );

	/* Start redirection if necessary */
	LoggerStartConsoleRedirection();
}

static void LoggerStopGrabbingConsoleTo(Logger *logger)
{
	if (numActiveConsoleGrabbers == 0)
		return;
	if (!(logger->options & kLoggerOption_CaptureSystemConsole))
		return;

	pthread_mutex_lock(&consoleGrabbersMutex);

	if (--numActiveConsoleGrabbers == 0)
	{
		consoleGrabbersListLength = 0;
		free(consoleGrabbersList);
		consoleGrabbersList = NULL;
	}
	else
	{
		for (unsigned grabberIndex = 0; grabberIndex < consoleGrabbersListLength; grabberIndex++)
		{
			if (consoleGrabbersList[grabberIndex] == logger)
			{
				consoleGrabbersList[grabberIndex] = NULL;
				break;
			}
		}
	}

	pthread_mutex_unlock(&consoleGrabbersMutex);
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
			// Set flag to append new data to buffer file
			CFWriteStreamSetProperty(logger->bufferWriteStream, kCFStreamPropertyAppendToFile, kCFBooleanTrue);

			// Open the buffer stream for writing
			if (!CFWriteStreamOpen(logger->bufferWriteStream))
			{
				CFRelease(logger->bufferWriteStream);
				logger->bufferWriteStream = NULL;
			}
			else
			{
				// Write client info and flush the queue contents to buffer file
				LoggerPushClientInfoToFrontOfQueue(logger);
				LoggerFlushQueueToBufferStream(logger, YES);
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

static void LoggerFileBufferingOptionsChanged(Logger *logger)
{
	// File buffering options changed:
	// - close the current buffer file stream, if any
	// - create a new one, if needed
	LOGGERDBG(CFSTR("LoggerFileBufferingOptionsChanged bufferFile=%@"), logger->bufferFile);
	if (logger->bufferWriteStream != NULL)
	{
		CFWriteStreamClose(logger->bufferWriteStream);
		CFRelease(logger->bufferWriteStream);
		logger->bufferWriteStream = NULL;
	}
	if (logger->bufferFile  != NULL)
		LoggerCreateBufferWriteStream(logger);
}

static void LoggerFlushQueueToBufferStream(Logger *logger, BOOL firstEntryIsClientInfo)
{
	LOGGERDBG(CFSTR("LoggerFlushQueueToBufferStream"));
	pthread_mutex_lock(&logger->logQueueMutex);
	if (logger->incompleteSendOfFirstItem)
	{
		// drop anything being sent
		logger->sendBufferUsed = 0;
		logger->sendBufferOffset = 0;
	}
	logger->incompleteSendOfFirstItem = NO;

	// Write outstanding messages to the buffer file (streams don't detect disconnection
	// until the next write, where we could lose one or more messages)
	if (!firstEntryIsClientInfo && logger->sendBufferUsed)
		CFWriteStreamWrite(logger->bufferWriteStream, logger->sendBuffer + logger->sendBufferOffset, logger->sendBufferUsed - logger->sendBufferOffset);
	
	int n = 0;
	while (CFArrayGetCount(logger->logQueue))
	{
		CFDataRef data = CFArrayGetValueAtIndex(logger->logQueue, 0);
		CFIndex dataLength = CFDataGetLength(data);
		CFIndex written = CFWriteStreamWrite(logger->bufferWriteStream, CFDataGetBytePtr(data), dataLength);
		if (written != dataLength)
		{
			// couldn't write all data to file, maybe storage run out of space?
			CFShow(CFSTR("NSLogger Error: failed flushing the whole queue to buffer file:"));
			CFShow(logger->bufferFile);
			break;
		}
		CFArrayRemoveValueAtIndex(logger->logQueue, 0);
		if (n == 0 && firstEntryIsClientInfo && logger->sendBufferUsed)
		{
			// try hard: write any outstanding messages to the buffer file, after the client info
			CFWriteStreamWrite(logger->bufferWriteStream, logger->sendBuffer + logger->sendBufferOffset, logger->sendBufferUsed - logger->sendBufferOffset);
		}
		n++;
	}
	logger->sendBufferUsed = 0;
	logger->sendBufferOffset = 0;
	pthread_mutex_unlock(&logger->logQueueMutex);	
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Bonjour browsing
// -----------------------------------------------------------------------------
static void LoggerStartBonjourBrowsing(Logger *logger)
{
	LOGGERDBG(CFSTR("LoggerStartBonjourBrowsing"));
	
	if (logger->options & kLoggerOption_BrowseOnlyLocalDomain)
	{
		LOGGERDBG(CFSTR("Logger configured to search only the local domain, searching for services on: local."));
		if (!LoggerBrowseBonjourForServices(logger, CFSTR("local.")) && logger->host == NULL)
		{
			LOGGERDBG(CFSTR("*** Logger: could not browse for services in domain local., no remote host configured: reverting to console logging. ***"));
			logger->options |= kLoggerOption_LogToConsole;
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
			// An error occurred, revert to console logging if there is no remote host
			LOGGERDBG(CFSTR("*** Logger: could not browse for domains, reverting to console logging. ***"));
			CFNetServiceBrowserUnscheduleFromRunLoop(logger->bonjourDomainBrowser, runLoop, kCFRunLoopCommonModes);
			CFRelease(logger->bonjourDomainBrowser);
			logger->bonjourDomainBrowser = NULL;
			if (logger->host == NULL)
				logger->options |= kLoggerOption_LogToConsole;
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
	CFIndex idx;
	for (idx = 0; idx < CFArrayGetCount(logger->bonjourServiceBrowsers); idx++)
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

	// try to use the user-specfied service type if any, fallback on our
	// default service type
	CFStringRef serviceType = logger->bonjourServiceType;
	if (serviceType == NULL)
	{
		if (logger->options & kLoggerOption_UseSSL)
			serviceType = LOGGER_SERVICE_TYPE_SSL;
		else
			serviceType = LOGGER_SERVICE_TYPE;
	}
	if (!CFNetServiceBrowserSearchForServices(browser, domainName, serviceType, &error))
	{
		LOGGERDBG(CFSTR("Logger can't start search on domain: %@ (error %d)"), domainName, error.error);
		CFNetServiceBrowserUnscheduleFromRunLoop(browser, runLoop, kCFRunLoopCommonModes);
		CFNetServiceBrowserInvalidate(browser);
	}
	else
	{
		LOGGERDBG(CFSTR("Logger started search for services of type %@ in domain %@"), serviceType, domainName);
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
			CFIndex idx;
			for (idx = 0; idx < CFArrayGetCount(logger->bonjourServices); idx++)
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
			// a service has been found
			LOGGERDBG(CFSTR("Logger found service: %@"), domainOrService);
			CFNetServiceRef service = (CFNetServiceRef)domainOrService;
			if (service != NULL)
			{
				// if the user has specified that Logger shall only connect to the specified
				// Bonjour service name, check it now. This makes things easier in a teamwork
				// environment where multiple instances of NSLogger viewer may run on the
				// same network
				if (logger->bonjourServiceName != NULL)
				{
					LOGGERDBG(CFSTR("-> looking for services of name %@"), logger->bonjourServiceName);
					CFStringRef name = CFNetServiceGetName(service);
					if (name == NULL || kCFCompareEqualTo != CFStringCompare(name, logger->bonjourServiceName, kCFCompareCaseInsensitive | kCFCompareDiacriticInsensitive))
					{
						LOGGERDBG(CFSTR("-> service name %@ does not match requested service name, ignoring."), name, logger->bonjourServiceName);
						return;
					}
				}
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

		// Also start a timer that will try to reconnect every N seconds
		if (logger->checkHostTimer == NULL)
		{
			CFRunLoopTimerContext timerCtx = {
				.version = 0,
				.info = logger,
				.retain = NULL,
				.release = NULL,
				.copyDescription = NULL
			};
			logger->checkHostTimer = CFRunLoopTimerCreate(NULL,
														  CFAbsoluteTimeGetCurrent() + 5,
														  5, // reconnect interval
														  0,
														  0,
														  &LoggerTimedReconnectCallback,
														  &timerCtx);
			if (logger->checkHostTimer != NULL)
			{
				LOGGERDBG(CFSTR("Starting the TimedReconnect timer to regularly retry the connection"));
				CFRunLoopAddTimer(CFRunLoopGetCurrent(), logger->checkHostTimer, kCFRunLoopCommonModes);
			}
		}
	}
}

static void LoggerStopReachabilityChecking(Logger *logger)
{
	if (logger->reachability != NULL)
	{
		LOGGERDBG(CFSTR("Stopping SCNetworkReachability"));
		SCNetworkReachabilityUnscheduleFromRunLoop(logger->reachability, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
		CFRelease((CFTypeRef)logger->reachability);
		logger->reachability = NULL;
	}
	if (logger->checkHostTimer != NULL)
	{
		CFRunLoopTimerInvalidate(logger->checkHostTimer);
		CFRunLoopRemoveTimer(CFRunLoopGetCurrent(), logger->checkHostTimer, kCFRunLoopCommonModes);
		CFRelease(logger->checkHostTimer);
		logger->checkHostTimer = NULL;
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

static void LoggerTimedReconnectCallback(CFRunLoopTimerRef timer, void *info)
{
	Logger *logger = (Logger *)info;
	assert(logger != NULL);
	LOGGERDBG(CFSTR("LoggerTimedReconnectCallback"));
	if (logger->logStream == NULL && logger->host != NULL)
	{
		LOGGERDBG(CFSTR("-> trying to reconnect to host %@"), logger->host);
		LoggerTryConnect(logger);
	}
	else
	{
		LOGGERDBG(CFSTR("-> timer not needed anymore, removing it form runloop"));
		CFRunLoopTimerInvalidate(timer);
		CFRunLoopRemoveTimer(CFRunLoopGetCurrent(), logger->checkHostTimer, kCFRunLoopCommonModes);
		CFRelease(timer);
		logger->checkHostTimer = NULL;
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
							   &LoggerWriteStreamCallback,
							   &context))
	{
		if (logger->options & kLoggerOption_UseSSL)
		{
			// Configure stream to require a SSL connection
			LOGGERDBG(CFSTR("-> configuring SSL"));
			const void *SSLKeys[] = {
				kCFStreamSSLLevel,
				kCFStreamSSLValidatesCertificateChain,
				kCFStreamSSLIsServer,
				kCFStreamSSLPeerName
			};
			const void *SSLValues[] = {
				kCFStreamSocketSecurityLevelNegotiatedSSL,
				kCFBooleanFalse,			// no certificate chain validation (we use a self-signed certificate)
				kCFBooleanFalse,			// not a server
				kCFNull
			};
			
#if TARGET_OS_IPHONE
			// workaround for TLS in iOS 5 as per TN2287
			// see http://developer.apple.com/library/ios/#technotes/tn2287/_index.html#//apple_ref/doc/uid/DTS40011309
			// if we are running iOS 5 or later, use a special mode that allows the stack to downgrade gracefully
	#if ALLOW_COCOA_USE
            AUTORELEASE_POOL_BEGIN
			NSString *versionString = [[UIDevice currentDevice] systemVersion];
			if ([versionString compare:@"5.0" options:NSNumericSearch] != NSOrderedAscending)
				SSLValues[0] = CFSTR("kCFStreamSocketSecurityLevelTLSv1_0SSLv3");
            AUTORELEASE_POOL_END
	#else
			// we can't find out, assume we _may_ be on iOS 5 but can't be certain
			// go for SSLv3 which works without the TLS 1.2 / 1.1 / 1.0 downgrade issue
			SSLValues[0] = kCFStreamSocketSecurityLevelSSLv3;
	#endif
#endif

			CFDictionaryRef SSLDict = CFDictionaryCreate(NULL, SSLKeys, SSLValues, 4, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);
			CFWriteStreamSetProperty(logger->logStream, kCFStreamPropertySSLSettings, SSLDict);
			CFRelease(SSLDict);
		}

		CFWriteStreamScheduleWithRunLoop(logger->logStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
		
		if (CFWriteStreamOpen(logger->logStream))
		{
			LOGGERDBG(CFSTR("-> stream open attempt, waiting for open completion"));
			return YES;
		}

		LOGGERDBG(CFSTR("-> stream open failed."));
		
		CFWriteStreamSetClient(logger->logStream, kCFStreamEventNone, NULL, NULL);
		if (CFWriteStreamGetStatus(logger->logStream) == kCFStreamStatusOpen)
			CFWriteStreamClose(logger->logStream);
		CFWriteStreamUnscheduleFromRunLoop(logger->logStream, CFRunLoopGetCurrent(), kCFRunLoopCommonModes);
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
			if (logger->logStream != NULL)
			{
				CFRelease(logger->logStream);
				logger->logStream = NULL;
			}
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
	if ((logger->options & kLoggerOption_BrowseBonjour) &&
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
			CFWriteStreamSetClient(logger->logStream, 0, NULL, NULL);
			CFWriteStreamUnscheduleFromRunLoop(logger->logStream, CFRunLoopGetCurrent(), kCFRunLoopDefaultMode);
			CFWriteStreamClose(logger->logStream);
			
			CFRelease(logger->logStream);
			logger->logStream = NULL;

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
			if (logger->bufferFile != NULL && logger->bufferWriteStream == NULL)
				LoggerCreateBufferWriteStream(logger);
			
			if (logger->host != NULL && !(logger->options & kLoggerOption_BrowseBonjour))
				LoggerStartReachabilityChecking(logger);
			else
				LoggerTryConnect(logger);
			break;
        // avoid warnings when building; cover all enum cases.
        case kCFStreamEventNone:
        case kCFStreamEventHasBytesAvailable:
            break;
	}
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Internal encoding functions
// -----------------------------------------------------------------------------
static void LoggerMessageAddTimestamp(CFMutableDataRef encoder)
{
	struct timeval t;
	if (gettimeofday(&t, NULL) == 0)
	{
#if __LP64__
		LoggerMessageAddInt64(encoder, t.tv_sec, PART_KEY_TIMESTAMP_S);
		LoggerMessageAddInt64(encoder, t.tv_usec, PART_KEY_TIMESTAMP_US);
#else
		LoggerMessageAddInt32(encoder, t.tv_sec, PART_KEY_TIMESTAMP_S);
		LoggerMessageAddInt32(encoder, t.tv_usec, PART_KEY_TIMESTAMP_US);
#endif
	}
	else
	{
		time_t ts = time(NULL);
#if __LP64__
		LoggerMessageAddInt64(encoder, ts, PART_KEY_TIMESTAMP_S);
#else
		LoggerMessageAddInt32(encoder, ts, PART_KEY_TIMESTAMP_S);
#endif
	}
}

static void LoggerMessageAddTimestampAndThreadID(CFMutableDataRef encoder)
{
	LoggerMessageAddTimestamp(encoder);

	BOOL hasThreadName = NO;
#if ALLOW_COCOA_USE
	// Getting the thread number is tedious, to say the least. Since there is
	// no direct way to get it, we have to do it sideways. Note that it can be dangerous
	// to use any Cocoa call when in a multithreaded application that only uses non-Cocoa threads
	// and for which Cocoa's multithreading has not been activated. We test for this case.
	if ([NSThread isMultiThreaded] || [NSThread isMainThread])
	{
		AUTORELEASE_POOL_BEGIN
		NSThread *thread = [NSThread currentThread];
		NSString *name = [thread name];
		if (![name length])
		{
			if ([thread isMainThread])
				name = @"Main thread";
			else
			{
				// use the thread dictionary to store and retrieve the computed thread name
				NSMutableDictionary *threadDict = [thread threadDictionary];
				name = [threadDict objectForKey:@"__$NSLoggerThreadName$__"];
				if (name == nil)
				{
					// optimize CPU use by computing the thread name once and storing it back
					// in the thread dictionary
					name = [thread description];
					NSRange range = [name rangeOfString:@"num = "];
					if (range.location != NSNotFound)
					{
						name = [NSString stringWithFormat:@"Thread %@",
								[name substringWithRange:NSMakeRange(range.location + range.length,
																	 [name length] - range.location - range.length - 1)]];
						[threadDict setObject:name forKey:@"__$NSLoggerThreadName$__"];
					}
				}
			}
		}
		if (name != nil)
		{
			LoggerMessageAddString(encoder, (CAST_TO_CFSTRING)name, PART_KEY_THREAD_ID);
			hasThreadName = YES;
		}
		AUTORELEASE_POOL_END
	}
#endif
	if (!hasThreadName)
	{
#if __LP64__
		LoggerMessageAddInt64(encoder, (int64_t)pthread_self(), PART_KEY_THREAD_ID);
#else
		LoggerMessageAddInt32(encoder, (int32_t)pthread_self(), PART_KEY_THREAD_ID);
#endif
	}
}

static void LoggerMessageUpdateDataHeader(CFMutableDataRef data)
{
	// update the data header with updated part count and size
	UInt8 *p = CFDataGetMutableBytePtr(data);
	uint32_t size = htonl(CFDataGetLength(data) - 4);
	uint16_t partCount = htons(ntohs(*(uint16_t *)(p + 4)) + 1);
	memcpy(p, &size, 4);
	memcpy(p+4, &partCount, 2);
}

static CFMutableDataRef LoggerMessageCreate()
{
	CFMutableDataRef data = CFDataCreateMutable(NULL, 0);
	CFDataIncreaseLength(data, 6);
	UInt8 *p = CFDataGetMutableBytePtr(data);
	p[3] = 2;		// size 0x00000002 in big endian
	return data;
}

static void LoggerMessageAddInt32(CFMutableDataRef data, int32_t anInt, int key)
{
	uint32_t partData = htonl(anInt);
	uint8_t keyAndType[2] = {(uint8_t)key, PART_TYPE_INT32};
	CFDataAppendBytes(data, (const UInt8 *)&keyAndType, 2);
	CFDataAppendBytes(data, (const UInt8 *)&partData, 4);
	LoggerMessageUpdateDataHeader(data);
}

#if __LP64__
static void LoggerMessageAddInt64(CFMutableDataRef data, int64_t anInt, int key)
{
	uint32_t partData[2] = {htonl((uint32_t)(anInt >> 32)), htonl((uint32_t)anInt)};
	uint8_t keyAndType[2] = {(uint8_t)key, PART_TYPE_INT64};
	CFDataAppendBytes(data, (const UInt8 *)&keyAndType, 2);
	CFDataAppendBytes(data, (const UInt8 *)&partData, 8);
	LoggerMessageUpdateDataHeader(data);
}
#endif

static void LoggerMessageAddCString(CFMutableDataRef data, const char *aString, int key)
{
	if (aString == NULL || *aString == 0)
		return;
	
	// convert to UTF-8
	int len = (int)strlen(aString);
	uint8_t *buf = malloc(2 * len);
	if (buf != NULL)
	{
		int i, n = 0;
		for (i = 0; i < len; i++)
		{
			uint8_t c = (uint8_t)(*aString++);
			if (c < 0x80)
				buf[n++] = c;
			else {
				buf[n++] = 0xC0 | (c >> 6);
				buf[n++] = (c & 0x6F) | 0x80;
			}
		}
		if (n)
		{
			uint32_t partSize = htonl(n);
			uint8_t keyAndType[2] = {(uint8_t)key, PART_TYPE_STRING};
			CFDataAppendBytes(data, (const UInt8 *)&keyAndType, 2);
			CFDataAppendBytes(data, (const UInt8 *)&partSize, 4);
			CFDataAppendBytes(data, buf, n);
			LoggerMessageUpdateDataHeader(data);
		}
		free(buf);
	}
}

static void LoggerMessageAddString(CFMutableDataRef data, CFStringRef aString, int key)
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
		bytes = (uint8_t *)malloc((size_t)stringLength * 4 + 4);
		CFStringGetBytes(aString, CFRangeMake(0, stringLength), kCFStringEncodingUTF8, '?', false, bytes, bytesLength, &bytesLength);
		partSize = htonl(bytesLength);
	}
	
	CFDataAppendBytes(data, (const UInt8 *)&keyAndType, 2);
	CFDataAppendBytes(data, (const UInt8 *)&partSize, 4);
	if (partSize)
		CFDataAppendBytes(data, bytes, bytesLength);
	
	if (bytes != NULL)
		free(bytes);
	LoggerMessageUpdateDataHeader(data);
}

static void LoggerMessageAddData(CFMutableDataRef data, CFDataRef theData, int key, int partType)
{
	if (theData != NULL)
	{
		uint8_t keyAndType[2] = {(uint8_t)key, (uint8_t)partType};
		CFIndex dataLength = CFDataGetLength(theData);
		uint32_t partSize = htonl(dataLength);
		CFDataAppendBytes(data, (const UInt8 *)&keyAndType, 2);
		CFDataAppendBytes(data, (const UInt8 *)&partSize, 4);
		if (partSize)
			CFDataAppendBytes(data, CFDataGetBytePtr(theData), dataLength);
		LoggerMessageUpdateDataHeader(data);
	}
}

static uint32_t LoggerMessageGetSeq(CFDataRef message)
{
	// Extract the sequence number from a message. When pushing messages to the queue,
	// we use this to guarantee the logging order according to the seq#
	uint32_t seq = 0;
	uint8_t *p = (uint8_t *)CFDataGetBytePtr(message) + 4;
	uint16_t partCount;
	memcpy(&partCount, p, 2);
	partCount = ntohs(partCount);
	p += 2;
	while (partCount--)
	{
		uint8_t partKey = *p++;
		uint8_t partType = *p++;
		uint32_t partSize;
		if (partType == PART_TYPE_INT16)
			partSize = 2;
		else if (partType == PART_TYPE_INT32)
			partSize = 4;
		else if (partType == PART_TYPE_INT64)
			partSize = 8;
		else
		{
			memcpy(&partSize, p, 4);
			p += 4;
			partSize = ntohl(partSize);
		}
		if (partKey == PART_KEY_MESSAGE_SEQ)
		{
			memcpy(&seq, p, sizeof(uint32_t));
			seq = ntohl(seq);
			break;
		}
		p += partSize;
	}
	return seq;
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
	CFMutableDataRef encoder = LoggerMessageCreate();
	if (encoder != NULL)
	{
		LoggerMessageAddTimestamp(encoder);
		LoggerMessageAddInt32(encoder, LOGMSG_TYPE_CLIENTINFO, PART_KEY_MESSAGE_TYPE);

		CFStringRef version = (CFStringRef)CFBundleGetValueForInfoDictionaryKey(bundle, kCFBundleVersionKey);
		if (version != NULL && CFGetTypeID(version) == CFStringGetTypeID())
			LoggerMessageAddString(encoder, version, PART_KEY_CLIENT_VERSION);
		CFStringRef name = (CFStringRef)CFBundleGetValueForInfoDictionaryKey(bundle, kCFBundleNameKey);
		if (name != NULL)
			LoggerMessageAddString(encoder, name, PART_KEY_CLIENT_NAME);

#if TARGET_OS_IPHONE && ALLOW_COCOA_USE
		if ([NSThread isMultiThreaded] || [NSThread isMainThread])
		{
			AUTORELEASE_POOL_BEGIN
			UIDevice *device = [UIDevice currentDevice];
			LoggerMessageAddString(encoder, (CAST_TO_CFSTRING)device.name, PART_KEY_UNIQUEID);
			LoggerMessageAddString(encoder, (CAST_TO_CFSTRING)device.systemVersion, PART_KEY_OS_VERSION);
			LoggerMessageAddString(encoder, (CAST_TO_CFSTRING)device.systemName, PART_KEY_OS_NAME);
			LoggerMessageAddString(encoder, (CAST_TO_CFSTRING)device.model, PART_KEY_CLIENT_MODEL);
			AUTORELEASE_POOL_END
		}
#elif TARGET_OS_MAC
		SInt32 versionMajor, versionMinor, versionFix;
		Gestalt(gestaltSystemVersionMajor, &versionMajor);
		Gestalt(gestaltSystemVersionMinor, &versionMinor);
		Gestalt(gestaltSystemVersionBugFix, &versionFix);
		CFStringRef osVersion = CFStringCreateWithFormat(NULL, NULL, CFSTR("%d.%d.%d"), versionMajor, versionMinor, versionFix);
		LoggerMessageAddString(encoder, osVersion, PART_KEY_OS_VERSION);
		CFRelease(osVersion);
		LoggerMessageAddString(encoder, CFSTR("Mac OS X"), PART_KEY_OS_NAME);

		char buf[64];
		size_t len;
		int ncpu = 0;
		bzero(buf, sizeof(buf));
		len = sizeof(buf)-1;
		sysctlbyname("hw.model", buf, &len, NULL, 0);
		len = sizeof(ncpu);
		sysctlbyname("hw.ncpu", &ncpu, &len, NULL, 0);
		sprintf(buf+strlen(buf), " - %d * ", ncpu);
		len = sizeof(buf)-strlen(buf)-1;
		sysctlbyname("hw.machine", buf+strlen(buf), &len, NULL, 0);
		
		CFStringRef s = CFStringCreateWithCString(NULL, buf, kCFStringEncodingASCII);
		LoggerMessageAddString(encoder, s, PART_KEY_CLIENT_MODEL);
		CFRelease(s);
#endif
		pthread_mutex_lock(&logger->logQueueMutex);
		CFArrayInsertValueAtIndex(logger->logQueue, logger->incompleteSendOfFirstItem ? 1 : 0, encoder);
		pthread_mutex_unlock(&logger->logQueueMutex);

		CFRelease(encoder);
	}
}

static void LoggerPushMessageToQueue(Logger *logger, CFDataRef message)
{
	// Add the message to the log queue and signal the runLoop source that will trigger
	// a send on the worker thread.
	pthread_mutex_lock(&logger->logQueueMutex);
	CFIndex idx = CFArrayGetCount(logger->logQueue);
	if (idx)
	{
		// to prevent out-of-order messages (as much as possible), we try to transmit messages in the
		// order their sequence number was generated. Since the seq is generated first-thing,
		// we can provide fine-grained ordering that gives a reasonable idea of the order
		// the logging calls were made (useful for precise information about multithreading code)
		uint32_t lastSeq, seq = LoggerMessageGetSeq(message);
		do {
			lastSeq = LoggerMessageGetSeq(CFArrayGetValueAtIndex(logger->logQueue, idx-1));
		} while (lastSeq > seq && --idx > 0);
	}
	if (idx >= 0)
		CFArrayInsertValueAtIndex(logger->logQueue, idx, message);
	else
		CFArrayAppendValue(logger->logQueue, message);
	pthread_mutex_unlock(&logger->logQueueMutex);
	
	if (logger->messagePushedSource != NULL)
	{
		// One case where the pushed source may be NULL is if the client code
		// immediately starts logging without initializing the logger first.
		// In this case, the worker thread has not completed startup, so we don't need
		// to fire the runLoop source
		CFRunLoopSourceSignal(logger->messagePushedSource);
	}
	else if (logger->workerThread == NULL && (logger->options & kLoggerOption_LogToConsole))
	{
		// In this case, a failure creating the message runLoop source forces us
		// to always log to console
		pthread_mutex_lock(&logger->logQueueMutex);
		while (CFArrayGetCount(logger->logQueue))
		{
			LoggerLogToConsole(CFArrayGetValueAtIndex(logger->logQueue, 0));
			CFArrayRemoveValueAtIndex(logger->logQueue, 0);
		}
		pthread_mutex_unlock(&logger->logQueueMutex);
		pthread_cond_broadcast(&logger->logQueueEmpty);		// in case other threads are waiting for a flush
	}
}

static void LogMessageTo_internal(Logger *logger,
								  const char *filename,
								  int lineNumber,
								  const char *functionName,
								  NSString *domain,
								  int level,
								  NSString *format,
								  va_list args)
{
	logger = LoggerStart(logger);	// start if needed
    if (logger != NULL)
	{
        int32_t seq = OSAtomicIncrement32Barrier(&logger->messageSeq);
        LOGGERDBG2(CFSTR("%ld LogMessage"), seq);

        CFMutableDataRef encoder = LoggerMessageCreate();
        if (encoder != NULL)
        {
            LoggerMessageAddTimestampAndThreadID(encoder);
            LoggerMessageAddInt32(encoder, LOGMSG_TYPE_LOG, PART_KEY_MESSAGE_TYPE);
            LoggerMessageAddInt32(encoder, seq, PART_KEY_MESSAGE_SEQ);
            if (domain != nil && [domain length])
                LoggerMessageAddString(encoder, (CAST_TO_CFSTRING)domain, PART_KEY_TAG);
            if (level)
                LoggerMessageAddInt32(encoder, level, PART_KEY_LEVEL);
            if (filename != NULL)
                LoggerMessageAddCString(encoder, filename, PART_KEY_FILENAME);
            if (lineNumber)
                LoggerMessageAddInt32(encoder, lineNumber, PART_KEY_LINENUMBER);
            if (functionName != NULL)
                LoggerMessageAddCString(encoder, functionName, PART_KEY_FUNCTIONNAME);

#if ALLOW_COCOA_USE
            // Go though NSString to avoid low-level logging of CF datastructures (i.e. too detailed NSDictionary, etc)
            NSString *msgString = [[NSString alloc] initWithFormat:format arguments:args];
            if (msgString != nil)
            {
                LoggerMessageAddString(encoder, (CAST_TO_CFSTRING)msgString, PART_KEY_MESSAGE);
                RELEASE(msgString);
            }
#else
            CFStringRef msgString = CFStringCreateWithFormatAndArguments(NULL, NULL, (CFStringRef)format, args);
            if (msgString != NULL)
            {
                LoggerMessageAddString(encoder, msgString, PART_KEY_MESSAGE);
                CFRelease(msgString);
            }
#endif
            
            LoggerPushMessageToQueue(logger, encoder);
            CFRelease(encoder);
        }
        else
        {
            LOGGERDBG2(CFSTR("-> failed creating encoder"));
        }
    }
}

static void LogImageTo_internal(Logger *logger,
								const char *filename,
								int lineNumber,
								const char *functionName,
								NSString *domain,
								int level,
								int width,
								int height,
								NSData *data)
{
	logger = LoggerStart(logger);		// start if needed
	if (logger != NULL)
	{
		int32_t seq = OSAtomicIncrement32Barrier(&logger->messageSeq);
		LOGGERDBG2(CFSTR("%ld LogImage"), seq);

		CFMutableDataRef encoder = LoggerMessageCreate();
		if (encoder != NULL)
		{
			LoggerMessageAddTimestampAndThreadID(encoder);
			LoggerMessageAddInt32(encoder, LOGMSG_TYPE_LOG, PART_KEY_MESSAGE_TYPE);
			LoggerMessageAddInt32(encoder, seq, PART_KEY_MESSAGE_SEQ);
			if (domain != nil && [domain length])
				LoggerMessageAddString(encoder, (CAST_TO_CFSTRING)domain, PART_KEY_TAG);
			if (level)
				LoggerMessageAddInt32(encoder, level, PART_KEY_LEVEL);
			if (width && height)
			{
				LoggerMessageAddInt32(encoder, width, PART_KEY_IMAGE_WIDTH);
				LoggerMessageAddInt32(encoder, height, PART_KEY_IMAGE_HEIGHT);
			}
			if (filename != NULL)
				LoggerMessageAddCString(encoder, filename, PART_KEY_FILENAME);
			if (lineNumber)
				LoggerMessageAddInt32(encoder, lineNumber, PART_KEY_LINENUMBER);
			if (functionName != NULL)
				LoggerMessageAddCString(encoder, functionName, PART_KEY_FUNCTIONNAME);
			LoggerMessageAddData(encoder, (CAST_TO_CFDATA)data, PART_KEY_MESSAGE, PART_TYPE_IMAGE);

			LoggerPushMessageToQueue(logger, encoder);
			CFRelease(encoder);
		}
		else
		{
			LOGGERDBG2(CFSTR("-> failed creating encoder"));
		}
	}
}

static void LogDataTo_internal(Logger *logger,
							   const char *filename,
							   int lineNumber,
							   const char *functionName,
							   NSString *domain,
							   int level, NSData *data)
{
	logger = LoggerStart(logger);		// start if needed
    if (logger != NULL)
    {
        int32_t seq = OSAtomicIncrement32Barrier(&logger->messageSeq);
        LOGGERDBG2(CFSTR("%ld LogData"), seq);

        CFMutableDataRef encoder = LoggerMessageCreate();
        if (encoder != NULL)
        {
            LoggerMessageAddTimestampAndThreadID(encoder);
            LoggerMessageAddInt32(encoder, LOGMSG_TYPE_LOG, PART_KEY_MESSAGE_TYPE);
            LoggerMessageAddInt32(encoder, seq, PART_KEY_MESSAGE_SEQ);
            if (domain != nil && [domain length])
                LoggerMessageAddString(encoder, (CAST_TO_CFSTRING)domain, PART_KEY_TAG);
            if (level)
                LoggerMessageAddInt32(encoder, level, PART_KEY_LEVEL);
            if (filename != NULL)
                LoggerMessageAddCString(encoder, filename, PART_KEY_FILENAME);
            if (lineNumber)
                LoggerMessageAddInt32(encoder, lineNumber, PART_KEY_LINENUMBER);
            if (functionName != NULL)
                LoggerMessageAddCString(encoder, functionName, PART_KEY_FUNCTIONNAME);
            LoggerMessageAddData(encoder, (CAST_TO_CFDATA)data, PART_KEY_MESSAGE, PART_TYPE_BINARY);
            
            LoggerPushMessageToQueue(logger, encoder);
            CFRelease(encoder);
        }
        else
        {
            LOGGERDBG2(CFSTR("-> failed creating encoder"));
        }
    }
}

static void LogStartBlockTo_internal(Logger *logger, NSString *format, va_list args)
{
	logger = LoggerStart(logger);		// start if needed
	if (logger)
	{
		int32_t seq = OSAtomicIncrement32Barrier(&logger->messageSeq);
		LOGGERDBG2(CFSTR("%ld LogStartBlock"), seq);

		CFMutableDataRef encoder = LoggerMessageCreate();
		if (encoder != NULL)
		{
			LoggerMessageAddTimestampAndThreadID(encoder);
			LoggerMessageAddInt32(encoder, LOGMSG_TYPE_BLOCKSTART, PART_KEY_MESSAGE_TYPE);
			LoggerMessageAddInt32(encoder, seq, PART_KEY_MESSAGE_SEQ);

			if (format != nil)
			{
				CFStringRef msgString = CFStringCreateWithFormatAndArguments(NULL, NULL, (CAST_TO_CFSTRING)format, args);
				if (msgString != NULL)
				{
					LoggerMessageAddString(encoder, msgString, PART_KEY_MESSAGE);
					CFRelease(msgString);
				}
			}
		
			LoggerPushMessageToQueue(logger, encoder);
			CFRelease(encoder);
		}
	}
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Public logging functions
// -----------------------------------------------------------------------------
void LogMessageCompat(NSString *format, ...)
{
	va_list args;
	va_start(args, format);
	LogMessageTo_internal(NULL, NULL, 0, NULL, nil, 0, format, args);
	va_end(args);
}

void LogMessageCompat_va(NSString *format, va_list args)
{
	LogMessageTo_internal(NULL, NULL, 0, NULL, nil, 0, format, args);
}

void LogMessageTo(Logger *logger, NSString *domain, int level, NSString *format, ...)
{
	va_list args;
	va_start(args, format);
	LogMessageTo_internal(logger, NULL, 0, NULL, domain, level, format, args);
	va_end(args);
}

void LogMessageToF(Logger *logger, const char *filename, int lineNumber, const char *functionName, NSString *domain, int level, NSString *format, ...)
{
	va_list args;
	va_start(args, format);
	LogMessageTo_internal(logger, filename, lineNumber, functionName, domain, level, format, args);
	va_end(args);
}

void LogMessageTo_va(Logger *logger, NSString *domain, int level, NSString *format, va_list args)
{
	LogMessageTo_internal(logger, NULL, 0, NULL, domain, level, format, args);
}

void LogMessageToF_va(Logger *logger, const char *filename, int lineNumber, const char *functionName, NSString *domain, int level, NSString *format, va_list args)
{
	LogMessageTo_internal(logger, filename, lineNumber, functionName, domain, level, format, args);
}

void LogMessage(NSString *domain, int level, NSString *format, ...)
{
	va_list args;
	va_start(args, format);
	LogMessageTo_internal(NULL, NULL, 0, NULL, domain, level, format, args);
	va_end(args);
}

void LogMessageF(const char *filename, int lineNumber, const char *functionName, NSString *domain, int level, NSString *format, ...)
{
	va_list args;
	va_start(args, format);
	LogMessageTo_internal(NULL, filename, lineNumber, functionName, domain, level, format, args);
	va_end(args);
}

void LogMessage_va(NSString *domain, int level, NSString *format, va_list args)
{
	LogMessageTo_internal(NULL, NULL, 0, NULL, domain, level, format, args);
}

void LogMessageF_va(const char *filename, int lineNumber, const char *functionName, NSString *domain, int level, NSString *format, va_list args)
{
	LogMessageTo_internal(NULL, filename, lineNumber, functionName, domain, level, format, args);
}

void LogData(NSString *domain, int level, NSData *data)
{
	LogDataTo_internal(NULL, NULL, 0, NULL, domain, level, data);
}

void LogDataF(const char *filename, int lineNumber, const char *functionName, NSString *domain, int level, NSData *data)
{
	LogDataTo_internal(NULL, filename, lineNumber, functionName, domain, level, data);
}

void LogDataTo(Logger *logger, NSString *domain, int level, NSData *data)
{
	LogDataTo_internal(logger, NULL, 0, NULL, domain, level, data);
}

void LogDataToF(Logger *logger, const char *filename, int lineNumber, const char *functionName, NSString *domain, int level, NSData *data)
{
	LogDataTo_internal(logger, filename, lineNumber, functionName, domain, level, data);
}

void LogImageData(NSString *domain, int level, int width, int height, NSData *data)
{
	LogImageTo_internal(NULL, NULL, 0, NULL, domain, level, width, height, data);
}

void LogImageDataF(const char *filename, int lineNumber, const char *functionName, NSString *domain, int level, int width, int height, NSData *data)
{
	LogImageTo_internal(NULL, filename, lineNumber, functionName, domain, level, width, height, data);
}

void LogImageDataTo(Logger *logger, NSString *domain, int level, int width, int height, NSData *data)
{
	LogImageTo_internal(logger, NULL, 0, NULL, domain, level, width, height, data);
}

void LogImageDataToF(Logger *logger, const char *filename, int lineNumber, const char *functionName, NSString *domain, int level, int width, int height, NSData *data)
{
	LogImageTo_internal(logger, filename, lineNumber, functionName, domain, level, width, height, data);
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
	logger = LoggerStart(logger);
    if (logger)
    {
        if (logger->options & kLoggerOption_LogToConsole)
            return;

        int32_t seq = OSAtomicIncrement32Barrier(&logger->messageSeq);
        LOGGERDBG2(CFSTR("%ld LogEndBlock"), seq);

        CFMutableDataRef encoder = LoggerMessageCreate();
        if (encoder != NULL)
        {
            LoggerMessageAddTimestampAndThreadID(encoder);
            LoggerMessageAddInt32(encoder, LOGMSG_TYPE_BLOCKEND, PART_KEY_MESSAGE_TYPE);
            LoggerMessageAddInt32(encoder, seq, PART_KEY_MESSAGE_SEQ);
            LoggerPushMessageToQueue(logger, encoder);
            CFRelease(encoder);
        }
        else
        {
            LOGGERDBG2(CFSTR("-> failed creating encoder"));
        }
    }
}

void LogEndBlock(void)
{
	LogEndBlockTo(NULL);
}

void LogMarkerTo(Logger *logger, NSString *text)
{
	logger = LoggerStart(logger);		// start if needed
	if (logger != NULL)
	{
		int32_t seq = OSAtomicIncrement32Barrier(&logger->messageSeq);
		LOGGERDBG2(CFSTR("%ld LogMarker"), seq);

		CFMutableDataRef encoder = LoggerMessageCreate();
		if (encoder != NULL)
		{
			LoggerMessageAddTimestampAndThreadID(encoder);
			LoggerMessageAddInt32(encoder, LOGMSG_TYPE_MARK, PART_KEY_MESSAGE_TYPE);
			if (text == nil)
			{
				CFDateFormatterRef df = CFDateFormatterCreate(NULL, NULL, kCFDateFormatterShortStyle, kCFDateFormatterMediumStyle);
				CFStringRef str = CFDateFormatterCreateStringWithAbsoluteTime(NULL, df, CFAbsoluteTimeGetCurrent());
				CFRelease(df);
				LoggerMessageAddString(encoder, str, PART_KEY_MESSAGE);
				CFRelease(str);
			}
			else
			{
				LoggerMessageAddString(encoder, (CAST_TO_CFSTRING)text, PART_KEY_MESSAGE);
			}
			LoggerMessageAddInt32(encoder, seq, PART_KEY_MESSAGE_SEQ);
			LoggerPushMessageToQueue(logger, encoder);
			CFRelease(encoder);
		}
		else
		{
			LOGGERDBG2(CFSTR("-> failed creating encoder"));
		}
	}
}

void LogMarker(NSString *text)
{
	LogMarkerTo(NULL, text);
}

#if !TARGET_OS_IPHONE && NSLOG_OVERRIDE

// mach_override.c semver:1.2.0
//   Copyright (c) 2003-2012 Jonathan 'Wolf' Rentzsch: http://rentzsch.com
//   Some rights reserved: http://opensource.org/licenses/mit
//   https://github.com/rentzsch/mach_override
#include <mach-o/dyld.h>
#include <mach/mach_host.h>
#include <mach/mach_init.h>
#include <mach/vm_map.h>
#include <sys/mman.h>
#include <CoreServices/CoreServices.h>

/**************************
 *
 *	Constants
 *
 **************************/
#pragma mark	-
#pragma mark	(Constants)

#if defined(__ppc__) || defined(__POWERPC__)

long kIslandTemplate[] = {
	0x9001FFFC,	//	stw		r0,-4(SP)
	0x3C00DEAD,	//	lis		r0,0xDEAD
	0x6000BEEF,	//	ori		r0,r0,0xBEEF
	0x7C0903A6,	//	mtctr	r0
	0x8001FFFC,	//	lwz		r0,-4(SP)
	0x60000000,	//	nop		; optionally replaced
	0x4E800420 	//	bctr
};

#define kAddressHi			3
#define kAddressLo			5
#define kInstructionHi		10
#define kInstructionLo		11

#elif defined(__i386__)

#define kOriginalInstructionsSize 16

char kIslandTemplate[] = {
	// kOriginalInstructionsSize nop instructions so that we
	// should have enough space to host original instructions
	0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
	0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
	// Now the real jump instruction
	0xE9, 0xEF, 0xBE, 0xAD, 0xDE
};

#define kInstructions	0
#define kJumpAddress    kInstructions + kOriginalInstructionsSize + 1
#elif defined(__x86_64__)

#define kOriginalInstructionsSize 32

#define kJumpAddress    kOriginalInstructionsSize + 6

char kIslandTemplate[] = {
	// kOriginalInstructionsSize nop instructions so that we
	// should have enough space to host original instructions
	0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
	0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
	0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
	0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90, 0x90,
	// Now the real jump instruction
	0xFF, 0x25, 0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00,
	0x00, 0x00, 0x00, 0x00
};

#endif

#define	kAllocateHigh		1
#define	kAllocateNormal		0

/**************************
 *
 *	Data Types
 *
 **************************/
#pragma mark	-
#pragma mark	(Data Types)

typedef	struct	{
	char	instructions[sizeof(kIslandTemplate)];
	int		allocatedHigh;
}	BranchIsland;

/**************************
 *
 *	Funky Protos
 *
 **************************/
#pragma mark	-
#pragma mark	(Funky Protos)

mach_error_t
allocateBranchIsland(
					 BranchIsland	**island,
					 int				allocateHigh,
					 void *originalFunctionAddress);

mach_error_t
freeBranchIsland(
				 BranchIsland	*island );

#if defined(__ppc__) || defined(__POWERPC__)
mach_error_t
setBranchIslandTarget(
					  BranchIsland	*island,
					  const void		*branchTo,
					  long			instruction );
#endif

#if defined(__i386__) || defined(__x86_64__)
mach_error_t
setBranchIslandTarget_i386(
						   BranchIsland	*island,
						   const void		*branchTo,
						   char*			instructions );
void
atomic_mov64(
			 uint64_t *targetAddress,
			 uint64_t value );

static Boolean
eatKnownInstructions(
					 unsigned char	*code,
					 uint64_t		*newInstruction,
					 int				*howManyEaten,
					 char			*originalInstructions,
					 int				*originalInstructionCount,
					 uint8_t			*originalInstructionSizes );

static void
fixupInstructions(
				  void		*originalFunction,
				  void		*escapeIsland,
				  void		*instructionsToFix,
				  int			instructionCount,
				  uint8_t		*instructionSizes );
#endif

/*******************************************************************************
 *
 *	Interface
 *
 *******************************************************************************/
#pragma mark	-
#pragma mark	(Interface)

#if defined(__i386__) || defined(__x86_64__)
mach_error_t makeIslandExecutable(void *address);
mach_error_t makeIslandExecutable(void *address) {
	mach_error_t err = err_none;
    vm_size_t pageSize;
    host_page_size( mach_host_self(), &pageSize );
    uintptr_t page = (uintptr_t)address & ~(uintptr_t)(pageSize-1);
    int e = err_none;
    e |= mprotect((void *)page, pageSize, PROT_EXEC | PROT_READ | PROT_WRITE);
    e |= msync((void *)page, pageSize, MS_INVALIDATE );
    if (e) {
        err = err_cannot_override;
    }
    return err;
}
#endif

mach_error_t
mach_override_ptr(
				  void *originalFunctionAddress,
				  const void *overrideFunctionAddress,
				  void **originalFunctionReentryIsland )
{
	assert( originalFunctionAddress );
	assert( overrideFunctionAddress );
	
	// this addresses overriding such functions as AudioOutputUnitStart()
	// test with modified DefaultOutputUnit project
#if defined(__x86_64__)
    for(;;){
        if(*(uint16_t*)originalFunctionAddress==0x25FF)    // jmp qword near [rip+0x????????]
            originalFunctionAddress=*(void**)((char*)originalFunctionAddress+6+*(int32_t *)((uint16_t*)originalFunctionAddress+1));
        else break;
    }
#elif defined(__i386__)
    for(;;){
        if(*(uint16_t*)originalFunctionAddress==0x25FF)    // jmp *0x????????
            originalFunctionAddress=**(void***)((uint16_t*)originalFunctionAddress+1);
        else break;
    }
#endif
	
	long	*originalFunctionPtr = (long*) originalFunctionAddress;
	mach_error_t	err = err_none;
	
#if defined(__ppc__) || defined(__POWERPC__)
	//	Ensure first instruction isn't 'mfctr'.
#define	kMFCTRMask			0xfc1fffff
#define	kMFCTRInstruction	0x7c0903a6
	
	long	originalInstruction = *originalFunctionPtr;
	if( !err && ((originalInstruction & kMFCTRMask) == kMFCTRInstruction) )
		err = err_cannot_override;
#elif defined(__i386__) || defined(__x86_64__)
	int eatenCount = 0;
	int originalInstructionCount = 0;
	char originalInstructions[kOriginalInstructionsSize];
	uint8_t originalInstructionSizes[kOriginalInstructionsSize];
	uint64_t jumpRelativeInstruction = 0; // JMP
	
	Boolean overridePossible = eatKnownInstructions ((unsigned char *)originalFunctionPtr,
													 &jumpRelativeInstruction, &eatenCount,
													 originalInstructions, &originalInstructionCount,
													 originalInstructionSizes );
	if (eatenCount > kOriginalInstructionsSize) {
		//printf ("Too many instructions eaten\n");
		overridePossible = false;
	}
	if (!overridePossible) err = err_cannot_override;
	if (err) fprintf(stderr, "err = %x %s:%d\n", err, __FILE__, __LINE__);
#endif
	
	//	Make the original function implementation writable.
	if( !err ) {
		err = vm_protect( mach_task_self(),
						 (vm_address_t) originalFunctionPtr, 8, false,
						 (VM_PROT_ALL | VM_PROT_COPY) );
		if( err )
			err = vm_protect( mach_task_self(),
							 (vm_address_t) originalFunctionPtr, 8, false,
							 (VM_PROT_DEFAULT | VM_PROT_COPY) );
	}
	if (err) fprintf(stderr, "err = %x %s:%d\n", err, __FILE__, __LINE__);
	
	//	Allocate and target the escape island to the overriding function.
	BranchIsland	*escapeIsland = NULL;
	if( !err )
		err = allocateBranchIsland( &escapeIsland, kAllocateHigh, originalFunctionAddress );
	if (err) fprintf(stderr, "err = %x %s:%d\n", err, __FILE__, __LINE__);
	
	
#if defined(__ppc__) || defined(__POWERPC__)
	if( !err )
		err = setBranchIslandTarget( escapeIsland, overrideFunctionAddress, 0 );
	
	//	Build the branch absolute instruction to the escape island.
	long	branchAbsoluteInstruction = 0; // Set to 0 just to silence warning.
	if( !err ) {
		long escapeIslandAddress = ((long) escapeIsland) & 0x3FFFFFF;
		branchAbsoluteInstruction = 0x48000002 | escapeIslandAddress;
	}
#elif defined(__i386__) || defined(__x86_64__)
	if (err) fprintf(stderr, "err = %x %s:%d\n", err, __FILE__, __LINE__);
	
	if( !err )
		err = setBranchIslandTarget_i386( escapeIsland, overrideFunctionAddress, 0 );
	
	if (err) fprintf(stderr, "err = %x %s:%d\n", err, __FILE__, __LINE__);
	// Build the jump relative instruction to the escape island
#endif
	
	
#if defined(__i386__) || defined(__x86_64__)
	if (!err) {
		uint64_t addressOffset = ((char*)escapeIsland - (char*)originalFunctionPtr - 5);
		addressOffset = OSSwapInt32(addressOffset);
		
		jumpRelativeInstruction |= 0xE900000000000000LL;
		jumpRelativeInstruction |= ((uint64_t)addressOffset & 0xffffffff) << 24;
		jumpRelativeInstruction = OSSwapInt64(jumpRelativeInstruction);
	}
#endif
	
	//	Optionally allocate & return the reentry island. This may contain relocated
	//  jmp instructions and so has all the same addressing reachability requirements
	//  the escape island has to the original function, except the escape island is
	//  technically our original function.
	BranchIsland	*reentryIsland = NULL;
	if( !err && originalFunctionReentryIsland ) {
		err = allocateBranchIsland( &reentryIsland, kAllocateHigh, escapeIsland);
		if( !err )
			*originalFunctionReentryIsland = reentryIsland;
	}
	
#if defined(__ppc__) || defined(__POWERPC__)
	//	Atomically:
	//	o If the reentry island was allocated:
	//		o Insert the original instruction into the reentry island.
	//		o Target the reentry island at the 2nd instruction of the
	//		  original function.
	//	o Replace the original instruction with the branch absolute.
	if( !err ) {
		int escapeIslandEngaged = false;
		do {
			if( reentryIsland )
				err = setBranchIslandTarget( reentryIsland,
											(void*) (originalFunctionPtr+1), originalInstruction );
			if( !err ) {
				escapeIslandEngaged = CompareAndSwap( originalInstruction,
													 branchAbsoluteInstruction,
													 (UInt32*)originalFunctionPtr );
				if( !escapeIslandEngaged ) {
					//	Someone replaced the instruction out from under us,
					//	re-read the instruction, make sure it's still not
					//	'mfctr' and try again.
					originalInstruction = *originalFunctionPtr;
					if( (originalInstruction & kMFCTRMask) == kMFCTRInstruction)
						err = err_cannot_override;
				}
			}
		} while( !err && !escapeIslandEngaged );
	}
#elif defined(__i386__) || defined(__x86_64__)
	// Atomically:
	//	o If the reentry island was allocated:
	//		o Insert the original instructions into the reentry island.
	//		o Target the reentry island at the first non-replaced
	//        instruction of the original function.
	//	o Replace the original first instructions with the jump relative.
	//
	// Note that on i386, we do not support someone else changing the code under our feet
	if ( !err ) {
		fixupInstructions(originalFunctionPtr, reentryIsland, originalInstructions,
						  originalInstructionCount, originalInstructionSizes );
		
		if( reentryIsland )
			err = setBranchIslandTarget_i386( reentryIsland,
											 (void*) ((char *)originalFunctionPtr+eatenCount), originalInstructions );
		// try making islands executable before planting the jmp
#if defined(__x86_64__) || defined(__i386__)
        if( !err )
            err = makeIslandExecutable(escapeIsland);
        if( !err && reentryIsland )
            err = makeIslandExecutable(reentryIsland);
#endif
		if ( !err )
			atomic_mov64((uint64_t *)originalFunctionPtr, jumpRelativeInstruction);
	}
#endif
	
	//	Clean up on error.
	if( err ) {
		if( reentryIsland )
			freeBranchIsland( reentryIsland );
		if( escapeIsland )
			freeBranchIsland( escapeIsland );
	}
	
	return err;
}

/*******************************************************************************
 *
 *	Implementation
 *
 *******************************************************************************/
#pragma mark	-
#pragma mark	(Implementation)

/*******************************************************************************
 Implementation: Allocates memory for a branch island.
 
 @param	island			<-	The allocated island.
 @param	allocateHigh	->	Whether to allocate the island at the end of the
 address space (for use with the branch absolute
 instruction).
 @result					<-	mach_error_t
 
 ***************************************************************************/

mach_error_t
allocateBranchIsland(
					 BranchIsland	**island,
					 int				allocateHigh,
					 void *originalFunctionAddress)
{
	assert( island );
	
	mach_error_t	err = err_none;
	
	if( allocateHigh ) {
		vm_size_t pageSize;
		err = host_page_size( mach_host_self(), &pageSize );
		if( !err ) {
			assert( sizeof( BranchIsland ) <= pageSize );
#if defined(__ppc__) || defined(__POWERPC__)
			vm_address_t first = 0xfeffffff;
			vm_address_t last = 0xfe000000 + pageSize;
#elif defined(__x86_64__)
			vm_address_t first = ((uint64_t)originalFunctionAddress & ~(uint64_t)(((uint64_t)1 << 31) - 1)) | ((uint64_t)1 << 31); // start in the middle of the page?
			vm_address_t last = 0x0;
#else
			vm_address_t first = 0xffc00000;
			vm_address_t last = 0xfffe0000;
#endif
			
			vm_address_t page = first;
			int allocated = 0;
			vm_map_t task_self = mach_task_self();
			
			while( !err && !allocated && page != last ) {
				
				err = vm_allocate( task_self, &page, pageSize, 0 );
				if( err == err_none )
					allocated = 1;
				else if( err == KERN_NO_SPACE ) {
#if defined(__x86_64__)
					page -= pageSize;
#else
					page += pageSize;
#endif
					err = err_none;
				}
			}
			if( allocated )
				*island = (BranchIsland*) page;
			else if( !allocated && !err )
				err = KERN_NO_SPACE;
		}
	} else {
		void *block = malloc( sizeof( BranchIsland ) );
		if( block )
			*island = block;
		else
			err = KERN_NO_SPACE;
	}
	if( !err )
		(**island).allocatedHigh = allocateHigh;
	
	return err;
}

/*******************************************************************************
 Implementation: Deallocates memory for a branch island.
 
 @param	island	->	The island to deallocate.
 @result			<-	mach_error_t
 
 ***************************************************************************/

mach_error_t
freeBranchIsland(
				 BranchIsland	*island )
{
	assert( island );
	assert( (*(long*)&island->instructions[0]) == kIslandTemplate[0] );
	assert( island->allocatedHigh );
	
	mach_error_t	err = err_none;
	
	if( island->allocatedHigh ) {
		vm_size_t pageSize;
		err = host_page_size( mach_host_self(), &pageSize );
		if( !err ) {
			assert( sizeof( BranchIsland ) <= pageSize );
			err = vm_deallocate(
								mach_task_self(),
								(vm_address_t) island, pageSize );
		}
	} else {
		free( island );
	}
	
	return err;
}

/*******************************************************************************
 Implementation: Sets the branch island's target, with an optional
 instruction.
 
 @param	island		->	The branch island to insert target into.
 @param	branchTo	->	The address of the target.
 @param	instruction	->	Optional instruction to execute prior to branch. Set
 to zero for nop.
 @result				<-	mach_error_t
 
 ***************************************************************************/
#if defined(__ppc__) || defined(__POWERPC__)
mach_error_t
setBranchIslandTarget(
					  BranchIsland	*island,
					  const void		*branchTo,
					  long			instruction )
{
	//	Copy over the template code.
    bcopy( kIslandTemplate, island->instructions, sizeof( kIslandTemplate ) );
    
    //	Fill in the address.
    ((short*)island->instructions)[kAddressLo] = ((long) branchTo) & 0x0000FFFF;
    ((short*)island->instructions)[kAddressHi]
	= (((long) branchTo) >> 16) & 0x0000FFFF;
    
    //	Fill in the (optional) instuction.
    if( instruction != 0 ) {
        ((short*)island->instructions)[kInstructionLo]
		= instruction & 0x0000FFFF;
        ((short*)island->instructions)[kInstructionHi]
		= (instruction >> 16) & 0x0000FFFF;
    }
    
    //MakeDataExecutable( island->instructions, sizeof( kIslandTemplate ) );
	msync( island->instructions, sizeof( kIslandTemplate ), MS_INVALIDATE );
    
    return err_none;
}
#endif

#if defined(__i386__)
mach_error_t
setBranchIslandTarget_i386(
						   BranchIsland	*island,
						   const void		*branchTo,
						   char*			instructions )
{
	
	//	Copy over the template code.
    bcopy( kIslandTemplate, island->instructions, sizeof( kIslandTemplate ) );
	
	// copy original instructions
	if (instructions) {
		bcopy (instructions, island->instructions + kInstructions, kOriginalInstructionsSize);
	}
	
    // Fill in the address.
    int32_t addressOffset = (char *)branchTo - (island->instructions + kJumpAddress + 4);
    *((int32_t *)(island->instructions + kJumpAddress)) = addressOffset;
	
    msync( island->instructions, sizeof( kIslandTemplate ), MS_INVALIDATE );
    return err_none;
}

#elif defined(__x86_64__)
mach_error_t
setBranchIslandTarget_i386(
						   BranchIsland	*island,
						   const void		*branchTo,
						   char*			instructions )
{
    // Copy over the template code.
    bcopy( kIslandTemplate, island->instructions, sizeof( kIslandTemplate ) );
	
    // Copy original instructions.
    if (instructions) {
        bcopy (instructions, island->instructions, kOriginalInstructionsSize);
    }
	
    //	Fill in the address.
    *((uint64_t *)(island->instructions + kJumpAddress)) = (uint64_t)branchTo;
    msync( island->instructions, sizeof( kIslandTemplate ), MS_INVALIDATE );
	
    return err_none;
}
#endif


#if defined(__i386__) || defined(__x86_64__)
// simplistic instruction matching
typedef struct {
	unsigned int length; // max 15
	unsigned char mask[15]; // sequence of bytes in memory order
	unsigned char constraint[15]; // sequence of bytes in memory order
}	AsmInstructionMatch;

#if defined(__i386__)
static AsmInstructionMatch possibleInstructions[] = {
	{ 0x5, {0xFF, 0x00, 0x00, 0x00, 0x00}, {0xE9, 0x00, 0x00, 0x00, 0x00} },	// jmp 0x????????
	{ 0x5, {0xFF, 0xFF, 0xFF, 0xFF, 0xFF}, {0x55, 0x89, 0xe5, 0xc9, 0xc3} },	// push %ebp; mov %esp,%ebp; leave; ret
	{ 0x1, {0xFF}, {0x90} },							// nop
	{ 0x1, {0xFF}, {0x55} },							// push %esp
	{ 0x2, {0xFF, 0xFF}, {0x89, 0xE5} },				                // mov %esp,%ebp
	{ 0x1, {0xFF}, {0x53} },							// push %ebx
	{ 0x3, {0xFF, 0xFF, 0x00}, {0x83, 0xEC, 0x00} },	                        // sub 0x??, %esp
	{ 0x6, {0xFF, 0xFF, 0x00, 0x00, 0x00, 0x00}, {0x81, 0xEC, 0x00, 0x00, 0x00, 0x00} },	// sub 0x??, %esp with 32bit immediate
	{ 0x1, {0xFF}, {0x57} },							// push %edi
	{ 0x1, {0xFF}, {0x56} },							// push %esi
	{ 0x2, {0xFF, 0xFF}, {0x31, 0xC0} },						// xor %eax, %eax
	{ 0x3, {0xFF, 0x4F, 0x00}, {0x8B, 0x45, 0x00} },  // mov $imm(%ebp), %reg
	{ 0x3, {0xFF, 0x4C, 0x00}, {0x8B, 0x40, 0x00} },  // mov $imm(%eax-%edx), %reg
	{ 0x4, {0xFF, 0xFF, 0xFF, 0x00}, {0x8B, 0x4C, 0x24, 0x00} },  // mov $imm(%esp), %ecx
	{ 0x5, {0xFF, 0x00, 0x00, 0x00, 0x00}, {0xB8, 0x00, 0x00, 0x00, 0x00} },	// mov $imm, %eax
	{ 0x0 }
};
#elif defined(__x86_64__)
static AsmInstructionMatch possibleInstructions[] = {
	{ 0x5, {0xFF, 0x00, 0x00, 0x00, 0x00}, {0xE9, 0x00, 0x00, 0x00, 0x00} },	// jmp 0x????????
	{ 0x1, {0xFF}, {0x90} },							// nop
	{ 0x1, {0xF8}, {0x50} },							// push %rX
	{ 0x3, {0xFF, 0xFF, 0xFF}, {0x48, 0x89, 0xE5} },				// mov %rsp,%rbp
	{ 0x4, {0xFF, 0xFF, 0xFF, 0x00}, {0x48, 0x83, 0xEC, 0x00} },	                // sub 0x??, %rsp
	{ 0x4, {0xFB, 0xFF, 0x00, 0x00}, {0x48, 0x89, 0x00, 0x00} },	                // move onto rbp
	{ 0x4, {0xFF, 0xFF, 0xFF, 0xFF}, {0x40, 0x0f, 0xbe, 0xce} },			// movsbl %sil, %ecx
	{ 0x2, {0xFF, 0x00}, {0x41, 0x00} },						// push %rXX
	{ 0x2, {0xFF, 0x00}, {0x85, 0x00} },						// test %rX,%rX
	{ 0x5, {0xF8, 0x00, 0x00, 0x00, 0x00}, {0xB8, 0x00, 0x00, 0x00, 0x00} },   // mov $imm, %reg
	{ 0x3, {0xFF, 0xFF, 0x00}, {0xFF, 0x77, 0x00} },  // pushq $imm(%rdi)
	{ 0x2, {0xFF, 0xFF}, {0x31, 0xC0} },						// xor %eax, %eax
    { 0x2, {0xFF, 0xFF}, {0x89, 0xF8} },			// mov %edi, %eax
	{ 0x0 }
};
#endif

static Boolean codeMatchesInstruction(unsigned char *code, AsmInstructionMatch* instruction)
{
	Boolean match = true;
	
	size_t i;
	for (i=0; i<instruction->length; i++) {
		unsigned char mask = instruction->mask[i];
		unsigned char constraint = instruction->constraint[i];
		unsigned char codeValue = code[i];
		
		match = ((codeValue & mask) == constraint);
		if (!match) break;
	}
	
	return match;
}

#if defined(__i386__) || defined(__x86_64__)
static Boolean
eatKnownInstructions(
					 unsigned char	*code,
					 uint64_t		*newInstruction,
					 int				*howManyEaten,
					 char			*originalInstructions,
					 int				*originalInstructionCount,
					 uint8_t			*originalInstructionSizes )
{
	Boolean allInstructionsKnown = true;
	int totalEaten = 0;
	unsigned char* ptr = code;
	int remainsToEat = 5; // a JMP instruction takes 5 bytes
	int instructionIndex = 0;
	
	if (howManyEaten) *howManyEaten = 0;
	if (originalInstructionCount) *originalInstructionCount = 0;
	while (remainsToEat > 0) {
		Boolean curInstructionKnown = false;
		
		// See if instruction matches one  we know
		AsmInstructionMatch* curInstr = possibleInstructions;
		do {
			if ((curInstructionKnown = codeMatchesInstruction(ptr, curInstr))) break;
			curInstr++;
		} while (curInstr->length > 0);
		
		// if all instruction matches failed, we don't know current instruction then, stop here
		if (!curInstructionKnown) {
			allInstructionsKnown = false;
			fprintf(stderr, "mach_override: some instructions unknown! Need to update mach_override.c\n");
			break;
		}
		
		// At this point, we've matched curInstr
		int eaten = curInstr->length;
		ptr += eaten;
		remainsToEat -= eaten;
		totalEaten += eaten;
		
		if (originalInstructionSizes) originalInstructionSizes[instructionIndex] = eaten;
		instructionIndex += 1;
		if (originalInstructionCount) *originalInstructionCount = instructionIndex;
	}
	
	
	if (howManyEaten) *howManyEaten = totalEaten;
	
	if (originalInstructions) {
		Boolean enoughSpaceForOriginalInstructions = (totalEaten < kOriginalInstructionsSize);
		
		if (enoughSpaceForOriginalInstructions) {
			memset(originalInstructions, 0x90 /* NOP */, kOriginalInstructionsSize); // fill instructions with NOP
			bcopy(code, originalInstructions, totalEaten);
		} else {
			// printf ("Not enough space in island to store original instructions. Adapt the island definition and kOriginalInstructionsSize\n");
			return false;
		}
	}
	
	if (allInstructionsKnown) {
		// save last 3 bytes of first 64bits of codre we'll replace
		uint64_t currentFirst64BitsOfCode = *((uint64_t *)code);
		currentFirst64BitsOfCode = OSSwapInt64(currentFirst64BitsOfCode); // back to memory representation
		currentFirst64BitsOfCode &= 0x0000000000FFFFFFLL;
		
		// keep only last 3 instructions bytes, first 5 will be replaced by JMP instr
		*newInstruction &= 0xFFFFFFFFFF000000LL; // clear last 3 bytes
		*newInstruction |= (currentFirst64BitsOfCode & 0x0000000000FFFFFFLL); // set last 3 bytes
	}
	
	return allInstructionsKnown;
}

static void
fixupInstructions(
				  void		*originalFunction,
				  void		*escapeIsland,
				  void		*instructionsToFix,
				  int			instructionCount,
				  uint8_t		*instructionSizes )
{
	int	index;
	for (index = 0;index < instructionCount;index += 1)
		{
		if (*(uint8_t*)instructionsToFix == 0xE9) // 32-bit jump relative
			{
			uint64_t offset = (uintptr_t)originalFunction - (uintptr_t)escapeIsland;
			uint64_t *jumpOffsetPtr = (uint64_t*)((uintptr_t)instructionsToFix + 1);
			*jumpOffsetPtr += offset;
			}
		
		originalFunction = (void*)((uintptr_t)originalFunction + instructionSizes[index]);
		escapeIsland = (void*)((uintptr_t)escapeIsland + instructionSizes[index]);
		instructionsToFix = (void*)((uintptr_t)instructionsToFix + instructionSizes[index]);
		}
}
#endif

#if defined(__i386__)
__asm(
	  ".text;"
	  ".align 2, 0x90;"
	  "_atomic_mov64:;"
	  "	pushl %ebp;"
	  "	movl %esp, %ebp;"
	  "	pushl %esi;"
	  "	pushl %ebx;"
	  "	pushl %ecx;"
	  "	pushl %eax;"
	  "	pushl %edx;"
	  
	  // atomic push of value to an address
	  // we use cmpxchg8b, which compares content of an address with
	  // edx:eax. If they are equal, it atomically puts 64bit value
	  // ecx:ebx in address.
	  // We thus put contents of address in edx:eax to force ecx:ebx
	  // in address
	  "	mov		8(%ebp), %esi;"  // esi contains target address
	  "	mov		12(%ebp), %ebx;"
	  "	mov		16(%ebp), %ecx;" // ecx:ebx now contains value to put in target address
	  "	mov		(%esi), %eax;"
	  "	mov		4(%esi), %edx;"  // edx:eax now contains value currently contained in target address
	  "	lock; cmpxchg8b	(%esi);" // atomic move.
	  
	  // restore registers
	  "	popl %edx;"
	  "	popl %eax;"
	  "	popl %ecx;"
	  "	popl %ebx;"
	  "	popl %esi;"
	  "	popl %ebp;"
	  "	ret"
	  );
#elif defined(__x86_64__)
void atomic_mov64(
				  uint64_t *targetAddress,
				  uint64_t value )
{
    *targetAddress = value;
}
#endif
#endif
#endif
