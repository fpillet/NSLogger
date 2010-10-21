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
#import "LoggerAppDelegate.h"
#import "LoggerNativeTransport.h"
#import "LoggerWindowController.h"
#import "LoggerDocument.h"
#import "LoggerStatusWindowController.h"
#import "LoggerPrefsWindowController.h"

NSString * const kPrefPublishesBonjourService = @"publishesBonjourService";
NSString * const kPrefHasDirectTCPIPResponder = @"hasDirectTCPIPResponder";
NSString * const kPrefDirectTCPIPResponderPort = @"directTCPIPResponderPort";

@implementation LoggerAppDelegate

@synthesize transports, filters, filtersSortDescriptors, statusController;

- (id) init
{
	if ((self = [super init]) != nil)
	{
		transports = [[NSMutableArray alloc] init];

		// default filter ordering
		self.filtersSortDescriptors = [NSArray arrayWithObject:[[[NSSortDescriptor alloc] initWithKey:@"title" ascending:YES] autorelease]];

		// resurrect filters before the app nib loads
		NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
		NSData *filterData = [defaults objectForKey:@"filters"];
		if (filterData != nil)
		{
			filters = [[NSKeyedUnarchiver unarchiveObjectWithData:filterData] retain];
			if (![filters isKindOfClass:[NSMutableArray class]])
			{
				[filters release];
				filters = nil;
			}
		}
		if (filters == nil)
			filters = [[NSMutableArray alloc] init];
		if (![filters count])
		{
			// Create a few default filters
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
		}
	}
	return self;
}

- (void)dealloc
{
	[transports release];
	[super dealloc];
}

- (void)saveFiltersDefinition
{
	@try
	{
		NSData *filtersData = [NSKeyedArchiver archivedDataWithRootObject:filters];
		if (filtersData != nil)
			[[NSUserDefaults standardUserDefaults] setObject:filtersData forKey:@"filters"];
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

- (NSNumber *)nextUniqueFilterIdentifier
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

@end

