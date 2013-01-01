/*
 * LoggerPrefsWindowController.m
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

#include <sys/time.h>
#import "LoggerPrefsWindowController.h"
#import "AppDelegate.h"
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
	kFileFunctionBackgroundColor,
	kCellBackgroundColor
};

NSString *const kPrefsChangedNotification = @"PrefsChangedNotification";

@implementation SampleMessageControl

-(BOOL)isFlipped {
	return YES;
}

@end

@interface LoggerPrefsWindowController () {
	IBOutlet NSToolbar *toolbar;
	IBOutlet NSToolbarItem *itmGeneral;
	IBOutlet NSToolbarItem *itmNetwork;
	IBOutlet NSToolbarItem *itmColours;
	
	IBOutlet NSView *vwGeneral;
	IBOutlet NSView *vwNetwork;
	IBOutlet NSView *vwColours;
	
	IBOutlet NSControl *sampleMessage;
	IBOutlet NSControl *sampleDataMessage;
	
	IBOutlet NSTextField *timestampFontName;
	IBOutlet NSTextField *threadIDFontName;
	IBOutlet NSTextField *tagFontName;
	IBOutlet NSTextField *textFontName;
	IBOutlet NSTextField *dataFontName;
	IBOutlet NSTextField *fileFunctionFontName;
	
	IBOutlet NSColorWell *timestampForegroundColor;
	IBOutlet NSColorWell *threadIDForegroundColor;
	IBOutlet NSColorWell *tagLevelForegroundColor;
	IBOutlet NSColorWell *textForegroundColor;
	IBOutlet NSColorWell *dataForegroundColor;
	IBOutlet NSColorWell *fileFunctionForegroundColor;
	IBOutlet NSColorWell *fileFunctionBackgroundColor;
	IBOutlet NSColorWell *cellBackgroundColor;
	
	IBOutlet NSComboBox *cmbLevel;
	NSView *blankView;
	NSMutableArray *cellColours;
}

-(void)updateUI;
-(NSMutableDictionary *)copyNetworkPrefs;

@end

@implementation LoggerPrefsWindowController

-(id)initWithWindowNibName:(NSString *)windowNibName {
	if ((self = [super initWithWindowNibName:windowNibName]) != nil) {
		// Extract current prefs for bindings. We don't want to rely on a global NSUserDefaultsController
		networkPrefs = [self copyNetworkPrefs];

		// make a deep copy of default attributes by going back and forth with
		// an archiver
		NSData *data = [NSKeyedArchiver archivedDataWithRootObject:[LoggerMessageCell defaultAttributes]];
		attributes = [NSKeyedUnarchiver unarchiveObjectWithData:data];
		blankView = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
	}
	return self;
}

-(void)awakeFromNib {
	cellColours = app.cellColours;
	// Prepare a couple fake messages to get a sample display
	struct timeval tv;
	gettimeofday(&tv, NULL);
	
	LoggerMessage *prevMsg = [[LoggerMessage alloc] init];
	if (tv.tv_usec) {
		tv.tv_usec = 0;
	} else {
		tv.tv_sec--;
		tv.tv_usec = 500000;
	}
	prevMsg.timestamp = tv;
	
	fakeConnection = [[LoggerConnection alloc] init];
	
	LoggerMessage *msg = [[LoggerMessage alloc] init];
	msg.timestamp = tv;
	msg.tag = @"database";
	msg.message = @"Example message text";
	msg.threadID = @"Main thread";
	msg.level = 0;
	msg.contentsType = kMessageString;
	msg.cachedCellSize = sampleMessage.frame.size;
	[msg setFilename:@"file.m" connection:fakeConnection];
	msg.lineNumber = 100;
	[msg setFunctionName:@"-[MyClass aMethod:withParameters:]" connection:fakeConnection];
	
	LoggerMessageCell *cell = [[LoggerMessageCell alloc] init];
	cell.message = msg;
	cell.previousMessage = prevMsg;
	cell.shouldShowFunctionNames = YES;
	[sampleMessage setCell:cell];
	
	uint8_t bytes[32];
	for (int i = 0; i < sizeof(bytes); i++) {
		bytes[i] = (uint8_t)arc4random();
	}
	
	cell = [[LoggerMessageCell alloc] init];
	msg = [[LoggerMessage alloc] init];
	msg.timestamp = tv;
	msg.tag = @"network";
	msg.message = [NSData dataWithBytes:bytes length:sizeof(bytes)];
	msg.threadID = @"Main thread";
	msg.level = 1;
	msg.contentsType = kMessageData;
	msg.cachedCellSize = sampleDataMessage.frame.size;
	cell.message = msg;
	cell.previousMessage = prevMsg;
	[sampleDataMessage setCell:cell];
	
	[self setView:vwGeneral];
//	[itmGeneral setEnabled:YES];
	[toolbar setSelectedItemIdentifier:@"General"];
	[self updateUI];
	[sampleMessage setNeedsDisplay];
	[sampleDataMessage setNeedsDisplay];
}

-(NSMutableDictionary *)copyNetworkPrefs {
	NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
	return [[NSMutableDictionary alloc] initWithObjectsAndKeys:
			[ud objectForKey:kPrefPublishesBonjourService], kPrefPublishesBonjourService,
			[ud objectForKey:kPrefBonjourServiceName], kPrefBonjourServiceName,
			[ud objectForKey:kPrefHasDirectTCPIPResponder], kPrefHasDirectTCPIPResponder,
			[ud objectForKey:kPrefDirectTCPIPResponderPort], kPrefDirectTCPIPResponderPort,
			nil];
}

-(IBAction)showPane:(id)sender {
    NSToolbarItem *tbi = (NSToolbarItem*)sender;
	switch (tbi.tag) {
		case 0:
			[self setView:vwGeneral];
			break;
			
		case 1:
			[self setView:vwNetwork];
			break;
			
		case 2:
			[self setView:vwColours];
			break;
	}
}

-(void)setView:(NSView *)vw {
	NSWindow *window = [self window];
	NSRect r = [window frame];
	NSView *old = [window contentView];
	float ht = r.size.height - old.frame.size.height;
	// resize
	r.size = vw.frame.size;
	r.size.height += ht;
	[window setContentView:blankView];
	[window setFrame:r display:NO animate:NO];
	[window setContentView:vw];
	// Change title
	NSString *buf = @"";
	if (vw == vwGeneral) {
		buf = @"General";
	} else if (vw == vwNetwork) {
		buf = @"Network";
	} else if (vw == vwColours) {
		buf = @"Fonts & Colours";
	}
	[window setTitle:buf];
}

-(BOOL)hasNetworkChanges {
	// Check whether attributes or network settings have changed
	for (NSString *key in networkPrefs) {
		if (![[[NSUserDefaults standardUserDefaults] objectForKey:key] isEqual:networkPrefs[key]]) {
			return YES;
		}
	}
	return NO;
}

-(BOOL)hasFontChanges {
	return NO == [[LoggerMessageCell defaultAttributes] isEqual:attributes];
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Close & Apply management
// -----------------------------------------------------------------------------
-(BOOL)windowShouldClose:(id)sender {
	if (![networkDefaultsController commitEditing]) {
		return NO;
	}
	if ([self hasNetworkChanges] || [self hasFontChanges]) {
		NSAlert *alert = [[NSAlert alloc] init];
		[alert setMessageText:NSLocalizedString(@"Would you like to apply your changes before closing the Preferences window?", @"")];
		[alert addButtonWithTitle:NSLocalizedString(@"Apply", @"")];
		[alert addButtonWithTitle:NSLocalizedString(@"Cancel", @"")];
		[alert addButtonWithTitle:NSLocalizedString(@"Don't Apply", @"")];
		[alert beginSheetModalForWindow:[self window]
		 modalDelegate:self
		 didEndSelector:@selector(alertDidEnd:returnCode:contextInfo:)
		 contextInfo:NULL];
		return NO;
	}
	return YES;
}

-(void)alertDidEnd:(NSAlert *)alert returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo {
	[[alert window] orderOut:self];
	if (returnCode == NSAlertFirstButtonReturn) {
		// Apply (and close window)
		if ([self hasNetworkChanges]) {
			[self applyNetworkChanges:nil];
		}
		if ([self hasFontChanges]) {
			[self applyFontChanges:nil];
		}
		[[self window] performSelector:@selector(close)withObject:nil afterDelay:0];
	} else if (returnCode == NSAlertSecondButtonReturn)   {
		// Cancel (don't close window)
		// nothing more to do
	} else {
		// Don't Apply (and close window)
		[[self window] performSelector:@selector(close)withObject:nil afterDelay:0];
	}
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Network preferences
// -----------------------------------------------------------------------------
-(IBAction)restoreNetworkDefaults:(id)sender {
	[networkDefaultsController commitEditing];
	NSDictionary *dict = [AppDelegate defaultPreferences];
	for (NSString *key in dict) {
		if (networkPrefs[key] != nil) {
			[[networkDefaultsController selection] setValue:dict[key] forKey:key];
		}
	}
}

-(void)applyNetworkChanges:(id)sender {
	if ([networkDefaultsController commitEditing]) {
		NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
		for (NSString *key in [networkPrefs allKeys]) {
			[ud setObject:networkPrefs[key] forKey:key];
		}
		[ud synchronize];
		[[NSNotificationCenter defaultCenter] postNotificationName:kPrefsChangedNotification object:self];
	}
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Font preferences
// -----------------------------------------------------------------------------
-(IBAction)applyFontChanges:(id)sender {
	// Set cell attributes
	[[LoggerMessageCell class] setDefaultAttributes:attributes];
	// Save cell colours
	[app saveCellColours];
	[[NSUserDefaults standardUserDefaults] synchronize];
	[[NSNotificationCenter defaultCenter] postNotificationName:kPrefsChangedNotification object:self];
}

-(IBAction)restoreFontDefaults:(id)sender {
	// Reset cell attributes
	NSData *data = [NSKeyedArchiver archivedDataWithRootObject:[LoggerMessageCell defaultAttributesDictionary]];
	attributes = [NSKeyedUnarchiver unarchiveObjectWithData:data];
	// Reset cell colours
	for (int i=0; i<5; i++) {
		[cellColours replaceObjectAtIndex:i withObject:[NSColor colorWithDeviceWhite:0.97f alpha:1.0f]];
	}
	// Set sample cells
	((LoggerMessageCell *)[sampleMessage cell]).messageAttributes = attributes;
	((LoggerMessageCell *)[sampleDataMessage cell]).messageAttributes = attributes;
	[sampleMessage setNeedsDisplay];
	[sampleDataMessage setNeedsDisplay];
	[self updateUI];
}

-(NSFont *)fontForCurrentFontSelection {
	NSFont *font;

	switch (currentFontSelection) {
		case kTimestampFont:
			font = attributes[@"timestamp"][NSFontAttributeName];
			break;

		case kThreadIDFont:
			font = attributes[@"threadID"][NSFontAttributeName];
			break;

		case kTagAndLevelFont:
			font = attributes[@"tag"][NSFontAttributeName];
			break;

		case kDataFont:
			font = attributes[@"data"][NSFontAttributeName];
			break;

		case kFileFunctionFont:
			font = attributes[@"fileLineFunction"][NSFontAttributeName];
			break;

		default:
			font = attributes[@"text"][NSFontAttributeName];
			break;
	}
	return font;
}

-(IBAction)selectFont:(id)sender {
	currentFontSelection = [(NSView *) sender tag];
	[[NSFontManager sharedFontManager] setTarget:self];
	[[NSFontPanel sharedFontPanel] setPanelFont:[self fontForCurrentFontSelection] isMultiple:NO];
	[[NSFontPanel sharedFontPanel] makeKeyAndOrderFront:self];
}

-(IBAction)selectColor:(id)sender {
	NSString *attrName = NSForegroundColorAttributeName, *dictName = nil, *dictName2 = nil;
	int tag = [(NSView *) sender tag];

	if (tag == kTimestampFontColor) {
		dictName = @"timestamp";
	} else if (tag == kThreadIDFontColor) {
		dictName = @"threadID";
	} else if (tag == kTagAndLevelFontColor) {
		dictName = @"tag";
		dictName2 = @"level";
	} else if (tag == kTextFontColor)   {
		dictName = @"text";
	} else if (tag == kDataFontColor) {
		dictName = @"data";
	} else if (tag == kFileFunctionFontColor) {
		dictName = @"fileLineFunction";
	} else if (tag == kFileFunctionBackgroundColor) {
		dictName = @"fileLineFunction";
		attrName = NSBackgroundColorAttributeName;
	} else if (tag == kCellBackgroundColor) {
		int ndx = [cmbLevel indexOfSelectedItem];
		[cellColours replaceObjectAtIndex:ndx withObject:[sender color]];
		[sampleMessage setNeedsDisplay];
		[sampleDataMessage setNeedsDisplay];
	}
	if (dictName != nil) {
		attributes[dictName][attrName] = [sender color];
		if (dictName2 != nil) {
			attributes[dictName2][attrName] = [sender color];
		}
		((LoggerMessageCell *)[sampleMessage cell]).messageAttributes = attributes;
		((LoggerMessageCell *)[sampleDataMessage cell]).messageAttributes = attributes;
		[sampleMessage setNeedsDisplay];
		[sampleDataMessage setNeedsDisplay];
	}
}

-(IBAction)selectLevel:(id)sender {
	int ndx = [cmbLevel indexOfSelectedItem];
	cellBackgroundColor.color = cellColours[ndx];
}

-(void)changeFont:(id)sender {
	NSFont *newFont = [sender convertFont:[self fontForCurrentFontSelection]];

	switch (currentFontSelection) {
		case kTimestampFont:
			attributes[@"timestamp"][NSFontAttributeName] = newFont;
			attributes[@"timedelta"][NSFontAttributeName] = newFont;
			break;

		case kThreadIDFont:
			attributes[@"threadID"][NSFontAttributeName] = newFont;
			break;

		case kTagAndLevelFont:
			attributes[@"tag"][NSFontAttributeName] = newFont;
			attributes[@"level"][NSFontAttributeName] = newFont;
			break;

		case kDataFont:
			attributes[@"data"][NSFontAttributeName] = newFont;
			break;

		case kFileFunctionFont:
			attributes[@"fileLineFunction"][NSFontAttributeName] = newFont;
			break;

		default: {
				attributes[@"text"][NSFontAttributeName] = newFont;
				attributes[@"mark"][NSFontAttributeName] = newFont;
				break;
			}
	}
	((LoggerMessageCell *)[sampleMessage cell]).messageAttributes = attributes;
	((LoggerMessageCell *)[sampleDataMessage cell]).messageAttributes = attributes;
	[sampleMessage setNeedsDisplay];
	[sampleDataMessage setNeedsDisplay];
	[self updateUI];
}

-(NSString *)fontNameForFont:(NSFont *)aFont {
	return [NSString stringWithFormat:@"%@ %.1f", [aFont displayName], [aFont pointSize]];
}

-(void)updateColor:(NSColorWell *)well ofDict:(NSString *)dictName attribute:(NSString *)attrName {
	NSColor *color = attributes[dictName][attrName];

	if (color == nil) {
		if ([attrName isEqualToString:NSForegroundColorAttributeName]) {
			color = [NSColor blackColor];
		} else {
			color = [NSColor clearColor];
		}
	}
	[well setColor:color];
}

-(void)updateUI {
	[timestampFontName setStringValue:[self fontNameForFont:attributes[@"timestamp"][NSFontAttributeName]]];
	[threadIDFontName setStringValue:[self fontNameForFont:attributes[@"threadID"][NSFontAttributeName]]];
	[tagFontName setStringValue:[self fontNameForFont:attributes[@"tag"][NSFontAttributeName]]];
	[textFontName setStringValue:[self fontNameForFont:attributes[@"text"][NSFontAttributeName]]];
	[dataFontName setStringValue:[self fontNameForFont:attributes[@"data"][NSFontAttributeName]]];
	[fileFunctionFontName setStringValue:[self fontNameForFont:attributes[@"fileLineFunction"][NSFontAttributeName]]];

	[self updateColor:timestampForegroundColor ofDict:@"timestamp" attribute:NSForegroundColorAttributeName];
	[self updateColor:threadIDForegroundColor ofDict:@"threadID" attribute:NSForegroundColorAttributeName];
	[self updateColor:tagLevelForegroundColor ofDict:@"tag" attribute:NSForegroundColorAttributeName];
	[self updateColor:textForegroundColor ofDict:@"text" attribute:NSForegroundColorAttributeName];
	[self updateColor:dataForegroundColor ofDict:@"data" attribute:NSForegroundColorAttributeName];
	[self updateColor:fileFunctionForegroundColor ofDict:@"fileLineFunction" attribute:NSForegroundColorAttributeName];
	[self updateColor:fileFunctionBackgroundColor ofDict:@"fileLineFunction" attribute:NSBackgroundColorAttributeName];
	// Is there a selection in the level drop down?
	if (![cmbLevel objectValueOfSelectedItem]) {
		// Select first item
		[cmbLevel selectItemAtIndex:0];
	}
	[cmbLevel setObjectValue:[cmbLevel objectValueOfSelectedItem]];
	cellBackgroundColor.color = cellColours[0];
}

@end