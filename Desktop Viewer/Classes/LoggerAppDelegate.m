/*
 * LoggerAppDelegate.h
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
#import <Security/SecItem.h>
#import "LoggerAppDelegate.h"
#import "LoggerNativeTransport.h"
#import "LoggerWindowController.h"
#import "LoggerDocument.h"
#import "LoggerStatusWindowController.h"
#import "LoggerPrefsWindowController.h"

NSString * const kPrefPublishesBonjourService = @"publishesBonjourService";
NSString * const kPrefHasDirectTCPIPResponder = @"hasDirectTCPIPResponder";
NSString * const kPrefDirectTCPIPResponderPort = @"directTCPIPResponderPort";

@interface LoggerAppDelegate ()
- (void)loadServerCerts;
@end

@implementation LoggerAppDelegate
@synthesize transports, filterSets, filtersSortDescriptors, statusController;
@synthesize serverCerts;

- (id) init
{
	if ((self = [super init]) != nil)
	{
		transports = [[NSMutableArray alloc] init];

		// default filter ordering. The first sort descriptor ensures that the object with
		// uid 1 (the "Default Set" filter set or "All Logs" filter) is always on top. Other
		// items are ordered by title.
		self.filtersSortDescriptors = [NSArray arrayWithObjects:
									   [NSSortDescriptor sortDescriptorWithKey:@"uid" ascending:YES
																	comparator:
										^(id uid1, id uid2)
		{
			if ([uid1 integerValue] == 1)
				return (NSComparisonResult)NSOrderedAscending;
			if ([uid2 integerValue] == 1)
				return (NSComparisonResult)NSOrderedDescending;
			return (NSComparisonResult)NSOrderedSame;
		}],
									   [NSSortDescriptor sortDescriptorWithKey:@"title" ascending:YES],
									   nil];
		
		// resurrect filters before the app nib loads
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		NSData *filterSetsData = [defaults objectForKey:@"filterSets"];
		if (filterSetsData != nil)
		{
			filterSets = [[NSKeyedUnarchiver unarchiveObjectWithData:filterSetsData] retain];
			if (![filterSets isKindOfClass:[NSMutableArray class]])
			{
				[filterSets release];
				filterSets = nil;
			}
		}
		if (filterSets == nil)
			filterSets = [[NSMutableArray alloc] init];
		if (![filterSets count])
		{
			NSMutableArray *filters = nil;

			// Try to reload pre-1.0b4 filters (will remove this code soon)
			NSData *filterData = [defaults objectForKey:@"filters"];
			if (filterData != nil)
			{
				filters = [NSKeyedUnarchiver unarchiveObjectWithData:filterData];
				if (![filters isKindOfClass:[NSMutableArray class]])
					filters = nil;
			}
			if (filters == nil)
			{
				// Create a default set
				filters = [self defaultFilters];
			}
			NSMutableDictionary *defaultSet = [[NSMutableDictionary alloc] initWithObjectsAndKeys:
											   NSLocalizedString(@"Default Set", @""), @"title",
											   [NSNumber numberWithInteger:1], @"uid",
											   filters, @"filters",
											   nil];
			[filterSets addObject:defaultSet];
			[defaultSet release];
		}
	}
	return self;
}

- (void)dealloc
{
	if (serverCerts != NULL)
		CFRelease(serverCerts);
	[transports release];
	[super dealloc];
}

- (void)saveFiltersDefinition
{
	@try
	{
		NSData *filterSetsData = [NSKeyedArchiver archivedDataWithRootObject:filterSets];
		if (filterSetsData != nil)
		{
			[[NSUserDefaults standardUserDefaults] setObject:filterSetsData forKey:@"filterSets"];
			// remove pre-1.0b4 filters
			[[NSUserDefaults standardUserDefaults] removeObjectForKey:@"filters"];
		}
	}
	@catch (NSException * e)
	{
		NSLog(@"Catched exception while trying to archive filters: %@", e);
	}
}

- (void)prefsChangeNotification:(NSNotification *)note
{
	[self performSelector:@selector(startStopTransports) withObject:nil afterDelay:0];
}

- (void)startStopTransports
{
	// Start and stop transports as needed
	NSUserDefaultsController *udc = [NSUserDefaultsController sharedUserDefaultsController];
	id udcv = [udc values];
	for (LoggerTransport *transport in transports)
	{
		if ([transport isKindOfClass:[LoggerNativeTransport class]])
		{
			LoggerNativeTransport *t = (LoggerNativeTransport *)transport;
			if (t.publishBonjourService)
			{
				if ([[udcv valueForKey:kPrefPublishesBonjourService] boolValue])
					[t startup];
				else
					[t shutdown];
			}
			else
			{
				if ([[udcv valueForKey:kPrefHasDirectTCPIPResponder] boolValue])
				{
					int port = [[udcv valueForKey:kPrefDirectTCPIPResponderPort] integerValue];
					if (t.listenerPort != port)
					{
						[t shutdown];
						t.listenerPort = port;
					}
					[t startup];
				}
				else
					[t shutdown];
			}
		}
	}
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	// Initialize the user defaults controller
	NSUserDefaultsController *udc = [NSUserDefaultsController sharedUserDefaultsController];
	[udc setInitialValues:[NSDictionary dictionaryWithObjectsAndKeys:
						   [NSNumber numberWithBool:YES], kPrefPublishesBonjourService,
						   [NSNumber numberWithBool:NO], kPrefHasDirectTCPIPResponder,
						   [NSNumber numberWithInteger:0], kPrefDirectTCPIPResponderPort,
						   nil]];
	[udc setAppliesImmediately:NO];
	
	// Listen to prefs change notifications, where we start / stop transports on demand
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(prefsChangeNotification:)
												 name:kPrefsChangedNotification
											   object:nil];
	// Prepare the logger status
	statusController = [[LoggerStatusWindowController alloc] initWithWindowNibName:@"LoggerStatus"];
	[statusController showWindow:self];
	[statusController appendStatus:NSLocalizedString(@"Logger starting up", @"")];

	// Retrieve server certs for SSL encryption
	[self loadServerCerts];
	
	// initialize all supported transports
	LoggerNativeTransport *t = [[LoggerNativeTransport alloc] init];
	t.publishBonjourService = YES;
	[transports addObject:t];
	[t release];
	
	t = [[LoggerNativeTransport alloc] init];
	t.listenerPort = [[NSUserDefaults standardUserDefaults] integerForKey:kPrefDirectTCPIPResponderPort];
	[transports addObject:t];
	[t release];
	
	// start transports
	[self performSelector:@selector(startStopTransports) withObject:nil afterDelay:0];
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
	return NO;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)theApplication
{
	return NO;
}

- (void)newConnection:(LoggerConnection *)aConnection
{
	LoggerDocument *doc = [[LoggerDocument alloc] initWithConnection:aConnection];
	[[NSDocumentController sharedDocumentController] addDocument:doc];
	[doc makeWindowControllers];
	[doc showWindows];
	[doc release];
}

- (NSMutableArray *)defaultFilters
{
	NSMutableArray *filters = [NSMutableArray arrayWithCapacity:4];
	[filters addObject:[NSDictionary dictionaryWithObjectsAndKeys:
						[NSNumber numberWithInteger:1], @"uid",
						NSLocalizedString(@"All logs", @""), @"title",
						[NSPredicate predicateWithValue:YES], @"predicate",
						nil]];
	[filters addObject:[NSDictionary dictionaryWithObjectsAndKeys:
						[NSNumber numberWithInteger:2], @"uid",
						NSLocalizedString(@"Text messages", @""), @"title",
						[NSCompoundPredicate andPredicateWithSubpredicates:[NSArray arrayWithObject:[NSPredicate predicateWithFormat:@"(messageType == \"text\")"]]], @"predicate",
						nil]];
	[filters addObject:[NSDictionary dictionaryWithObjectsAndKeys:
						[NSNumber numberWithInteger:3], @"uid",
						NSLocalizedString(@"Images", @""), @"title",
						[NSCompoundPredicate andPredicateWithSubpredicates:[NSArray arrayWithObject:[NSPredicate predicateWithFormat:@"(messageType == \"img\")"]]], @"predicate",
						nil]];
	[filters addObject:[NSDictionary dictionaryWithObjectsAndKeys:
						[NSNumber numberWithInteger:4], @"uid",
						NSLocalizedString(@"Data blocks", @""), @"title",
						[NSCompoundPredicate andPredicateWithSubpredicates:[NSArray arrayWithObject:[NSPredicate predicateWithFormat:@"(messageType == \"data\")"]]], @"predicate",
						nil]];
	return filters;
}

- (NSNumber *)nextUniqueFilterIdentifier:(NSArray *)filters
{
	// since we're using basic NSDictionary to store filters, we add a filter
	// identifier number so that no two filters are strictly identical -- makes
	// things much easier with NSArrayController
	return [NSNumber numberWithInteger:[[filters valueForKeyPath:@"@max.uid"] integerValue] + 1];
}

- (IBAction)showPreferences:(id)sender
{
	if (prefsController == nil)
		prefsController = [[LoggerPrefsWindowController alloc] initWithWindowNibName:@"LoggerPrefs"];
	[prefsController showWindow:sender];
}

- (void)loadServerCerts
{
	// Load the certificate we need to support encrypted incoming connections via SSL
	//
	// This is a tad more complicated than simply using the SSL API, because we insist
	// on using CFStreams which want certificates in a special form (linked to a keychain)
	// and we want to make this fully transparent to the user.
	//
	// To this end we will:
	// - create our own keychain (first time only)
	// - setup access control to the keychain so that no dialog ever comes up (first time only)
	// - import the self-signed certificate and private key into our keychain (first time only)
	// - retrieve the certificate from our keychain
	// - create the required SecIdentityRef for the certificate to be recognized by the CFStream
	// - keep this in the running app and use for incoming connections
	
	// NSLoggerCert.pem was generated from the command line with:
	// $ openssl req -x509 -nodes -days 3650 -newkey rsa:1024 -keyout NSLoggerCert.pem -out NSLoggerCert.pem

	// Path to our private keychain
	BOOL isDirectory;
	NSFileManager *fm = [NSFileManager defaultManager];
	NSString *path = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) lastObject];
	if ([path length])
	{
		path = [path stringByAppendingPathComponent:[[[NSBundle mainBundle] infoDictionary] objectForKey:(id)kCFBundleNameKey]];
		if (![fm fileExistsAtPath:path isDirectory:&isDirectory] || !isDirectory)
		{
			[fm removeItemAtPath:path error:NULL];
			if (![fm createDirectoryAtPath:path withIntermediateDirectories:YES attributes:nil error:nil])
				path = NSTemporaryDirectory();
		}
	}
	else
	{
		path = NSTemporaryDirectory();
	}

	path = [path stringByAppendingPathComponent:@"NSLogger.keychain"];
	BOOL keychainFileExists = ([fm fileExistsAtPath:path isDirectory:&isDirectory] && !isDirectory);
	if (keychainFileExists && isDirectory)
	{
		[fm removeItemAtPath:path error:nil];
		keychainFileExists = NO;
	}

	// Open or create our private keychain, and unlock it
	OSStatus status = -1;
	const char *keychainPath = [path fileSystemRepresentation];
	if (keychainFileExists)
		status = SecKeychainOpen(keychainPath, &serverKeychain);
	if (status != noErr)
	{
		// Create a trust to prevent confirmation dialog when we access our own keychain
		SecAccessRef accessRef = NULL;
		status = SecAccessCreate(CFSTR("NSLogger SSL encryption access"),
								 NULL,
								 &accessRef);

		status = SecKeychainCreate(keychainPath,
								   8, "NSLogger",	// fixed password (useless, really)
								   false,
								   accessRef,
								   &serverKeychain);
		if (accessRef != NULL)
			CFRelease(accessRef);

		if (status != noErr)
		{
			// we can't support SSL without a proper keychain
			return;
		}
	}
	status = SecKeychainUnlock(serverKeychain, 8, "NSLogger", true);
	if (status != noErr)
	{
		// we can't assert security
		return;
	}

	SecCertificateRef certRef = NULL;
	SecIdentityRef identityRef = NULL;

	// Find the certificate if we have already loaded it, or instantiate and find again
	for (int i = 0; i < 2 && status == noErr; i++)
	{
		// Search for the server certificate in the NSLogger keychain
		SecKeychainSearchRef keychainSearchRef = NULL;
		status = SecKeychainSearchCreateFromAttributes(serverKeychain, kSecCertificateItemClass, NULL, &keychainSearchRef);
		if (status == noErr)
			status = SecKeychainSearchCopyNext(keychainSearchRef, (SecKeychainItemRef *)&certRef);
		CFRelease(keychainSearchRef);
		
		// Did we find the certificate?
		if (status == noErr)
			break;

		// Load the NSLogger self-signed certificate
		NSData *certData = [NSData dataWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"NSLoggerCert" ofType:@"pem"]];

		// Import certificate and private key into our private keychain
		SecKeyImportExportParameters kp;
		bzero(&kp, sizeof(kp));
		kp.version = SEC_KEY_IMPORT_EXPORT_PARAMS_VERSION;
		SecExternalFormat inputFormat = kSecFormatPEMSequence;
		SecExternalItemType itemType = kSecItemTypeAggregate;
		CFArrayRef importedItems = NULL;

		status = SecKeychainItemImport((CFDataRef)certData,
									   CFSTR("NSLoggerCert.pem"),
									   &inputFormat,
									   &itemType,
									   0,				// flags are unused
									   &kp,				// import-export parameters
									   serverKeychain,
									   &importedItems);

		if (importedItems != NULL)
		{
			// Make a couple tweaks:
			// - Set the name of the private key to "NSLogger SSL key"
			// - Set the name of the certificate to "NSLogger SSL certificate"
			const char *keyLabel = "NSLogger SSL key";
			const char *certLabel = "NSLogger SSL certificate";
			for (int i = 0; i < CFArrayGetCount(importedItems); i++)
			{
				SecKeyRef keyRef = (SecKeyRef)CFArrayGetValueAtIndex(importedItems, i);
				const char *label = (SecKeyGetTypeID() == CFGetTypeID(keyRef)) ? keyLabel : certLabel;
				SecKeychainAttribute labelAttr = {
					.tag = kSecLabelItemAttr,
					.length = strlen(label),
					.data = (void *)label
				};
				SecKeychainAttributeList attrList = {
					.count = 1,
					.attr = &labelAttr
				};
				SecKeychainItemModifyContent((SecKeychainItemRef)keyRef, &attrList, 0, NULL);
			}
			CFRelease(importedItems);
		}
	}

	status = SecIdentityCreateWithCertificate(serverKeychain, certRef, &identityRef);
	if (status == noErr)
	{
		CFTypeRef values[] = {
			identityRef, certRef
		};
		serverCerts = CFArrayCreate(NULL, values, 2, &kCFTypeArrayCallBacks);
	}

	if (certRef != NULL)
		CFRelease(certRef);
	if (identityRef != NULL)
		CFRelease(identityRef);
}

@end
