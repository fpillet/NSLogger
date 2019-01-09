/*
 * LoggerPrefsWindowController.m
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
#include <sys/time.h>
#import "LoggerPrefsWindowController.h"
#import "LoggerAppDelegate.h"
#import "LoggerMessage.h"
#import "LoggerMessageCell.h"
#import "LoggerConnection.h"

enum {
	kTimestampFont = 1,
	kThreadIDFont,
	kTagAndLevelFont,
	kTextFont,
	kDataFont,
	kFileFunctionFont
};

enum {
	kTimestampFontColor = 1,
	kThreadIDFontColor,
	kTagAndLevelFontColor,
	kTextFontColor,
	kDataFontColor,
	kFileFunctionFontColor,
	kFileFunctionBackgroundColor
};

NSString * const kPrefsChangedNotification = @"PrefsChangedNotification";
void *advancedColorsArrayControllerDidChange = &advancedColorsArrayControllerDidChange;

@implementation SampleMessageControl
- (BOOL)isFlipped
{
	return YES;
}
@end

@interface LoggerPrefsWindowController (Private)
- (void)updateUI;
- (NSMutableDictionary *)copyNetworkPrefs;
@end

@implementation LoggerPrefsWindowController

- (id)initWithWindowNibName:(NSString *)windowNibName
{
	if ((self = [super initWithWindowNibName:windowNibName]) != nil)
	{
		// Extract current prefs for bindings. We don't want to rely on a global NSUserDefaultsController
		_networkPrefs = [self copyNetworkPrefs];

		// make a deep copy of default attributes by going back and forth with
		// an archiver
		NSData *data = [NSKeyedArchiver archivedDataWithRootObject:[LoggerMessageCell defaultAttributes]];
		_attributes = [NSKeyedUnarchiver unarchiveObjectWithData:data];
        _advancedColors = [NSMutableArray arrayWithArray:[[NSUserDefaults standardUserDefaults] objectForKey:@"advancedColors"]];
	}
	return self;
}

- (void)dealloc
{
    [[NSNotificationCenter defaultCenter] removeObserver:self name:NSControlTextDidEndEditingNotification object:nil];
}

- (NSMutableDictionary *)copyNetworkPrefs
{
	NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
	return [@{
		kPrefPublishesBonjourService: [ud objectForKey:kPrefPublishesBonjourService],
		kPrefBonjourServiceName: [ud objectForKey:kPrefBonjourServiceName],
		kPrefHasDirectTCPIPResponder: [ud objectForKey:kPrefHasDirectTCPIPResponder],
		kPrefDirectTCPIPResponderPort: [ud objectForKey:kPrefDirectTCPIPResponderPort]
	} mutableCopy];
}

- (void)awakeFromNib
{
	// Prepare a couple fake messages to get a sample display
	struct timeval tv;
	gettimeofday(&tv, NULL);

	LoggerMessage *prevMsg = [[LoggerMessage alloc] init];
	if (tv.tv_usec)
		tv.tv_usec = 0;
	else
	{
		tv.tv_sec--;
		tv.tv_usec = 500000;
	}
	prevMsg.timestamp = tv;

	_fakeConnection = [[LoggerConnection alloc] init];

	LoggerMessage *msg = [[LoggerMessage alloc] init];
	msg.timestamp = tv;
	msg.tag = @"database";
	msg.message = @"Example message text";
	msg.threadID = @"Main thread";
	msg.level = 0;
	msg.contentsType = kMessageString;
	msg.cachedCellSize = _sampleMessage.frame.size;
	[msg setFilename:@"file.m" connection:_fakeConnection];
	msg.lineNumber = 100;
	[msg setFunctionName:@"-[MyClass aMethod:withParameters:]" connection:_fakeConnection];

	LoggerMessageCell *cell = [[LoggerMessageCell alloc] init];
	cell.message = msg;
	cell.previousMessage = prevMsg;
	cell.shouldShowFunctionNames = YES;
	[_sampleMessage setCell:cell];

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
	msg.cachedCellSize = _sampleDataMessage.frame.size;
	cell.message = msg;
	cell.previousMessage = prevMsg;
	[_sampleDataMessage setCell:cell];

	[self updateUI];
	[_sampleMessage setNeedsDisplay];
	[_sampleDataMessage setNeedsDisplay];
    
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(editingDidEnd:) name:NSControlTextDidEndEditingNotification object:nil];
}

- (BOOL)hasNetworkChanges
{
	// Check whether attributes or network settings have changed
	for (NSString *key in self.networkPrefs)
	{
		if (![[[NSUserDefaults standardUserDefaults] objectForKey:key] isEqual:self.networkPrefs[key]])
			return YES;
	}
	return NO;
}

- (BOOL)hasFontChanges
{
	return ![LoggerMessageCell.defaultAttributes isEqual:self.attributes];
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Close & Apply management
// -----------------------------------------------------------------------------
- (BOOL)windowShouldClose:(id)sender
{
	if (![self commitNetworkEditing])
		return NO;
	if ([self hasNetworkChanges] || [self hasFontChanges])
	{
		NSAlert *alert = [[NSAlert alloc] init];
		[alert setMessageText:NSLocalizedString(@"Would you like to apply your changes before closing the Preferences window?", @"")];
		[alert addButtonWithTitle:NSLocalizedString(@"Apply", @"")];
		[alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
		[alert addButtonWithTitle:NSLocalizedString(@"Ignore", @"")];
        [self.window beginSheet:alert.window
              completionHandler:^(NSModalResponse returnCode) {
                  [alert.window orderOut:self];
                  if (returnCode == NSAlertFirstButtonReturn)
                  {
                      // Apply (and close window)
                      if ([self hasNetworkChanges])
                          [self applyNetworkChanges:nil];
                      if ([self hasFontChanges])
                          [self applyFontChanges:nil];
                      [[self window] performSelector:@selector(close) withObject:nil afterDelay:0];
                  }
                  else if (returnCode == NSAlertSecondButtonReturn)
                  {
                      // Cancel (don't close window)
                      // nothing more to do
                  }
                  else
                  {
                      // Don't Apply (and close window)
                      [self cancelNetworkChanges];
                      [self.window performSelector:@selector(close) withObject:nil afterDelay:0];
                  }
              }];
		return NO;
	}
	return YES;
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Network preferences
// -----------------------------------------------------------------------------
- (IBAction)restoreNetworkDefaults:(id)sender
{
	[self commitNetworkEditing];
	NSDictionary *dict = [LoggerAppDelegate defaultPreferences];
	for (NSString *key in dict)
	{
		if (self.networkPrefs[key] != nil)
			[[self.networkDefaultsController selection] setValue:dict[key] forKey:key];
	}
}

- (void)applyNetworkChanges:(id)sender
{
	if ([self commitNetworkEditing])
	{
		NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
		for (NSString *key in [self.networkPrefs allKeys])
			[ud setObject:self.networkPrefs[key] forKey:key];
		[ud synchronize];
		[[NSNotificationCenter defaultCenter] postNotificationName:kPrefsChangedNotification object:self];
	}
}

- (void)cancelNetworkChanges
{
    NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
    for (NSString *key in [self.networkPrefs allKeys])
        self.networkPrefs[key] = [ud objectForKey:key];
}

- (BOOL)commitNetworkEditing
{
    // due to an issue with bindings, if a field is cleared it is considered "null" and
    // isn't committed. We need to manually make sure that we put empty strings instead
    BOOL result = [self.networkDefaultsController commitEditing];
    if (self.networkPrefs[kPrefBonjourServiceName] == nil) {
        self.networkPrefs[kPrefBonjourServiceName] = @"";
    }
    return result;
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Font preferences
// -----------------------------------------------------------------------------
- (IBAction)applyFontChanges:(id)sender
{
	[[LoggerMessageCell class] setDefaultAttributes:self.attributes];
	[[NSUserDefaults standardUserDefaults] synchronize];
	[[NSNotificationCenter defaultCenter] postNotificationName:kPrefsChangedNotification object:self];
}

- (IBAction)restoreFontDefaults:(id)sender
{
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:[LoggerMessageCell defaultAttributesDictionary]];
	self.attributes = [NSKeyedUnarchiver unarchiveObjectWithData:data];
	((LoggerMessageCell *)[self.sampleMessage cell]).messageAttributes = self.attributes;
	((LoggerMessageCell *)[self.sampleDataMessage cell]).messageAttributes = self.attributes;
	[self.sampleMessage setNeedsDisplay];
	[self.sampleDataMessage setNeedsDisplay];
	[self updateUI];
}

- (NSMutableDictionary *)_blankAdvancedColor {
    NSString *color = @"black";
    if (@available(macOS 10_10, *)) {
        color = @"labelColor";
    }
    return [@{@"comment": @"Any line", @"regexp": @"^.+$", @"colors": color} mutableCopy];
}

- (IBAction)advancedColorsAdd:(id)sender {
    [self.advancedColors addObject:[self _blankAdvancedColor]];
    [self.advancedColorsArrayController rearrangeObjects];
    [self commitAdvancedColorsChanges];
}

- (IBAction)advancedColorsDel:(id)sender {
    NSArray *selection = [self.advancedColorsArrayController selectedObjects];
    [self.advancedColors removeObjectsInArray:selection];
	if (self.advancedColors.count == 0) {
		[self.advancedColors addObject:[self _blankAdvancedColor]];
	}
    [self.advancedColorsArrayController rearrangeObjects];
    [self commitAdvancedColorsChanges];
}

- (NSFont *)fontForCurrentFontSelection
{
	NSFont *font;
	switch (self.currentFontSelection)
	{
		case kTimestampFont:
			font = [self.attributes[@"timestamp"] objectForKey:NSFontAttributeName];
			break;
		case kThreadIDFont:
			font = [self.attributes[@"threadID"] objectForKey:NSFontAttributeName];
			break;
		case kTagAndLevelFont:
			font = [self.attributes[@"tag"] objectForKey:NSFontAttributeName];
			break;
		case kDataFont:
			font = [self.attributes[@"data"] objectForKey:NSFontAttributeName];
			break;
		case kFileFunctionFont:
			font = [self.attributes[@"fileLineFunction"] objectForKey:NSFontAttributeName];
			break;
		default:
			font = [self.attributes[@"text"] objectForKey:NSFontAttributeName];
			break;
	}
	return font;	
}

- (IBAction)selectFont:(id)sender
{
	self.currentFontSelection = (int)[(NSView *)sender tag];
	[[NSFontManager sharedFontManager] setTarget:self];
	[[NSFontPanel sharedFontPanel] setPanelFont:[self fontForCurrentFontSelection] isMultiple:NO];
	[[NSFontPanel sharedFontPanel] makeKeyAndOrderFront:self];
}

- (IBAction)selectColor:(id)sender
{
	NSString *attrName = NSForegroundColorAttributeName, *dictName = nil, *dictName2 = nil;
	int tag = (int)[(NSView *)sender tag];
	if (tag == kTimestampFontColor)
		dictName = @"timestamp";
	else if (tag == kThreadIDFontColor)
		dictName = @"threadID";
	else if (tag == kTagAndLevelFontColor)
	{
		dictName = @"tag";
		dictName2 = @"level";
	}
	else if (tag == kTextFontColor)
		dictName = @"text";
	else if (tag == kDataFontColor)
		dictName = @"data";
	else if (tag == kFileFunctionFontColor)
		dictName = @"fileLineFunction";
	else if (tag == kFileFunctionBackgroundColor)
	{
		dictName = @"fileLineFunction";
		attrName = NSBackgroundColorAttributeName;
	}
	if (dictName != nil)
	{
		[self.attributes[dictName] setObject:[sender color] forKey:attrName];
		if (dictName2 != nil)
			[self.attributes[dictName2] setObject:[sender color] forKey:attrName];
		((LoggerMessageCell *)[self.sampleMessage cell]).messageAttributes = self.attributes;
		((LoggerMessageCell *)[self.sampleDataMessage cell]).messageAttributes = self.attributes;
		[self.sampleMessage setNeedsDisplay];
		[self.sampleDataMessage setNeedsDisplay];
	}
}

- (void)changeFont:(id)sender
{
    NSFont *newFont = [sender convertFont:[self fontForCurrentFontSelection]];
	switch (self.currentFontSelection)
	{
		case kTimestampFont:
			[self.attributes[@"timestamp"] setObject:newFont forKey:NSFontAttributeName];
			[self.attributes[@"timedelta"] setObject:newFont forKey:NSFontAttributeName];
			break;
		case kThreadIDFont:
			[self.attributes[@"threadID"] setObject:newFont forKey:NSFontAttributeName];
			break;
		case kTagAndLevelFont:
			[self.attributes[@"tag"] setObject:newFont forKey:NSFontAttributeName];
			[self.attributes[@"level"] setObject:newFont forKey:NSFontAttributeName];
			break;
		case kDataFont:
			[self.attributes[@"data"] setObject:newFont forKey:NSFontAttributeName];
			break;
		case kFileFunctionFont:
			[self.attributes[@"fileLineFunction"] setObject:newFont forKey:NSFontAttributeName];
			break;
		default: {
			[self.attributes[@"text"] setObject:newFont forKey:NSFontAttributeName];
			[self.attributes[@"mark"] setObject:newFont forKey:NSFontAttributeName];
			break;
		}
	}
	((LoggerMessageCell *)[self.sampleMessage cell]).messageAttributes = self.attributes;
	((LoggerMessageCell *)[self.sampleDataMessage cell]).messageAttributes = self.attributes;
	[self.sampleMessage setNeedsDisplay];
	[self.sampleDataMessage setNeedsDisplay];
	[self updateUI];
}

- (NSString *)fontNameForFont:(NSFont *)aFont
{
	return [NSString stringWithFormat:@"%@ %.1f", [aFont displayName], [aFont pointSize]];
}

- (void)updateColor:(NSColorWell *)well ofDict:(NSString *)dictName attribute:(NSString *)attrName
{
	NSColor *color = [self.attributes[dictName] objectForKey:attrName];
	if (color == nil)
	{
		if ([attrName isEqualToString:NSForegroundColorAttributeName])
			color = [NSColor textColor];
		else
			color = [NSColor clearColor];
	}
	[well setColor:color];
}

- (void)updateUI
{
	[self.timestampFontName setStringValue:[self fontNameForFont:[self.attributes[@"timestamp"] objectForKey:NSFontAttributeName]]];
	[self.threadIDFontName setStringValue:[self fontNameForFont:[self.attributes[@"threadID"] objectForKey:NSFontAttributeName]]];
	[self.tagFontName setStringValue:[self fontNameForFont:[self.attributes[@"tag"] objectForKey:NSFontAttributeName]]];
	[self.textFontName setStringValue:[self fontNameForFont:[self.attributes[@"text"] objectForKey:NSFontAttributeName]]];
	[self.dataFontName setStringValue:[self fontNameForFont:[self.attributes[@"data"] objectForKey:NSFontAttributeName]]];
	[self.fileFunctionFontName setStringValue:[self fontNameForFont:[self.attributes[@"fileLineFunction"] objectForKey:NSFontAttributeName]]];

	[self updateColor:self.timestampForegroundColor ofDict:@"timestamp" attribute:NSForegroundColorAttributeName];
	[self updateColor:self.threadIDForegroundColor ofDict:@"threadID" attribute:NSForegroundColorAttributeName];
	[self updateColor:self.tagLevelForegroundColor ofDict:@"tag" attribute:NSForegroundColorAttributeName];
	[self updateColor:self.textForegroundColor ofDict:@"text" attribute:NSForegroundColorAttributeName];
	[self updateColor:self.dataForegroundColor ofDict:@"data" attribute:NSForegroundColorAttributeName];
	[self updateColor:self.fileFunctionForegroundColor ofDict:@"fileLineFunction" attribute:NSForegroundColorAttributeName];
	[self updateColor:self.fileFunctionBackgroundColor ofDict:@"fileLineFunction" attribute:NSBackgroundColorAttributeName];
}

- (void)commitAdvancedColorsChanges
{
    if ([self.advancedColorsArrayController commitEditing]) {
        NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
        [ud setObject:self.advancedColors forKey:@"advancedColors"];
        [ud synchronize];
        [[NSNotificationCenter defaultCenter] postNotificationName:kPrefsChangedNotification object:self];
    }
}

- (void)editingDidEnd:(NSNotification *)notification
{
    [self commitAdvancedColorsChanges];
}

@end
