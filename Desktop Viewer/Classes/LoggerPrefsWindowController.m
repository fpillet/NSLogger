/*
 * LoggerPrefsWindowController.m
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
#include <sys/time.h>
#import "LoggerPrefsWindowController.h"
#import "LoggerAppDelegate.h"
#import "LoggerMessage.h"
#import "LoggerMessageCell.h"

enum {
	kTimestampFont = 1,
	kThreadIDFont,
	kTagAndLevelFont,
	kTextFont,
	kDataFont
};

NSString * const kPrefsChangedNotification = @"PrefsChangedNotification";

@implementation SampleMessageControl
- (BOOL)isFlipped
{
	return YES;
}
@end

@interface LoggerPrefsWindowController (Private)
- (void)updateFontNames;
@end

@implementation LoggerPrefsWindowController

- (void)dealloc
{
	[attributes release];
	[super dealloc];
}

- (void)windowDidLoad
{
	// make a deep copy of default attributes by going back and forth with
	// an archiver
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:[LoggerMessageCell defaultAttributes]];
	attributes = [[NSKeyedUnarchiver unarchiveObjectWithData:data] retain];

	// Prepare a couple fake messages to get a sample display
	struct timeval tv;
	gettimeofday(&tv, NULL);

	LoggerMessage *prevMsg = [[LoggerMessage alloc] init];
	if (tv.tv_usec)
		tv.tv_usec = 0;
	else {
		tv.tv_sec--;
		tv.tv_usec = 500000;
	}
	prevMsg.timestamp = tv;

	LoggerMessage *msg = [[LoggerMessage alloc] init];
	msg.timestamp = tv;
	msg.tag = @"database";
	msg.message = @"Example message text";
	msg.threadID = @"Main thread";
	msg.level = 1;
	msg.contentsType = kMessageString;

	LoggerMessageCell *cell = [[LoggerMessageCell alloc] init];
	cell.message = msg;
	cell.previousMessage = prevMsg;
	[sampleMessage setCell:cell];
	[cell release];
	[msg release];

	uint8_t bytes[32];
	for (int i = 0; i < sizeof(bytes); i++)
		bytes[i] = (uint8_t)arc4random();

	cell = [[LoggerMessageCell alloc] init];
	msg = [[LoggerMessage alloc] init];
	msg.timestamp = tv;
	msg.tag = @"network";
	msg.message = [NSData dataWithBytes:bytes length:sizeof(bytes)];
	msg.threadID = @"Main thread";
	msg.level = 1;
	msg.contentsType = kMessageData;
	cell.message = msg;
	cell.previousMessage = prevMsg;
	[sampleDataMessage setCell:cell];
	[cell release];
	[msg release];
	[prevMsg release];

	[self updateFontNames];
	[sampleMessage setNeedsDisplay];
	[sampleDataMessage setNeedsDisplay];
}

- (NSFont *)fontForCurrentFontSelection
{
	NSFont *font;
	switch (currentFontSelection)
	{
		case kTimestampFont:
			font = [[attributes objectForKey:@"timestamp"] objectForKey:NSFontAttributeName];
			break;
		case kThreadIDFont:
			font = [[attributes objectForKey:@"threadID"] objectForKey:NSFontAttributeName];
			break;
		case kTagAndLevelFont:
			font = [[attributes objectForKey:@"tag"] objectForKey:NSFontAttributeName];
			break;
		case kDataFont:
			font = [[attributes objectForKey:@"data"] objectForKey:NSFontAttributeName];
			break;
		default:
			font = [[attributes objectForKey:@"text"] objectForKey:NSFontAttributeName];
			break;
	}
	return font;	
}

- (IBAction)applyChanges:(id)sender
{
	[[LoggerMessageCell class] setDefaultAttributes:attributes];

	// note: save is deferred to the next pass of the runloop. When we send out the notification,
	// we also take this into account and deferr the update-from-prefs until the next runloop pass.
	NSUserDefaultsController *udc = [NSUserDefaultsController sharedUserDefaultsController];
	[udc save:self];
	[[NSNotificationCenter defaultCenter] postNotificationName:kPrefsChangedNotification object:self];
}

- (IBAction)cancelChanges:(id)sender
{
	NSUserDefaultsController *udc = [NSUserDefaultsController sharedUserDefaultsController];
	[udc revert:self];
	[[self window] orderOut:sender];
}

- (IBAction)saveChanges:(id)sender
{
	[self applyChanges:sender];
	[[self window] orderOut:sender];
}

- (IBAction)revertToDefaults:(id)sender
{
	[[NSUserDefaultsController sharedUserDefaultsController] revertToInitialValues:self];

	// revert message defaults
	[attributes release];
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:[LoggerMessageCell defaultAttributesDictionary]];
	attributes = [[NSKeyedUnarchiver unarchiveObjectWithData:data] retain];
	((LoggerMessageCell *)[sampleMessage cell]).messageAttributes = attributes;
	((LoggerMessageCell *)[sampleDataMessage cell]).messageAttributes = attributes;
	[sampleMessage setNeedsDisplay];
	[sampleDataMessage setNeedsDisplay];
	[self updateFontNames];
	
	[self applyChanges:self];
}

- (IBAction)selectFont:(id)sender
{
	currentFontSelection = [sender tag];
	[[NSFontManager sharedFontManager] setTarget:self];
	[[NSFontPanel sharedFontPanel] setPanelFont:[self fontForCurrentFontSelection] isMultiple:NO];
	[[NSFontPanel sharedFontPanel] makeKeyAndOrderFront:self];
}

- (void)changeFont:(id)sender
{
    NSFont *newFont = [sender convertFont:[self fontForCurrentFontSelection]];
	switch (currentFontSelection)
	{
		case kTimestampFont:
			[[attributes objectForKey:@"timestamp"] setObject:newFont forKey:NSFontAttributeName];
			[[attributes objectForKey:@"timedelta"] setObject:newFont forKey:NSFontAttributeName];
			break;
		case kThreadIDFont:
			[[attributes objectForKey:@"threadID"] setObject:newFont forKey:NSFontAttributeName];
			break;
		case kTagAndLevelFont:
			[[attributes objectForKey:@"tag"] setObject:newFont forKey:NSFontAttributeName];
			[[attributes objectForKey:@"level"] setObject:newFont forKey:NSFontAttributeName];
			break;
		case kDataFont:
			[[attributes objectForKey:@"data"] setObject:newFont forKey:NSFontAttributeName];
			break;
		default:
			[[attributes objectForKey:@"text"] setObject:newFont forKey:NSFontAttributeName];
			break;
	}
	((LoggerMessageCell *)[sampleMessage cell]).messageAttributes = attributes;
	((LoggerMessageCell *)[sampleDataMessage cell]).messageAttributes = attributes;
	[sampleMessage setNeedsDisplay];
	[sampleDataMessage setNeedsDisplay];
	[self updateFontNames];
}

- (NSString *)fontNameForFont:(NSFont *)aFont
{
	return [NSString stringWithFormat:@"%@ %.1f", [aFont displayName], [aFont pointSize]];
}

- (void)updateFontNames
{
	[timestampFontName setStringValue:[self fontNameForFont:[[attributes objectForKey:@"timestamp"] objectForKey:NSFontAttributeName]]];
	[threadIDFontName setStringValue:[self fontNameForFont:[[attributes objectForKey:@"threadID"] objectForKey:NSFontAttributeName]]];
	[tagFontName setStringValue:[self fontNameForFont:[[attributes objectForKey:@"tag"] objectForKey:NSFontAttributeName]]];
	[textFontName setStringValue:[self fontNameForFont:[[attributes objectForKey:@"text"] objectForKey:NSFontAttributeName]]];
	[dataFontName setStringValue:[self fontNameForFont:[[attributes objectForKey:@"data"] objectForKey:NSFontAttributeName]]];
}

@end
