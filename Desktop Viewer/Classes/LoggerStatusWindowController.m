/*
 * LoggerReadyWindowController.h
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
#import "LoggerStatusWindowController.h"
#import "LoggerAppDelegate.h"
#import "LoggerTransport.h"
#import "LoggerConnection.h"

NSString * const kShowStatusInStatusWindowNotification = @"ShowStatusInStatusWindowNotification";

@implementation LoggerStatusWindowController

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[super dealloc];
}

- (void)windowDidLoad
{
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(showStatus:)
												 name:kShowStatusInStatusWindowNotification
											   object:nil];
	
	[infoView setTextColor:[NSColor whiteColor]];
	[[self window] setLevel:NSNormalWindowLevel];
}

- (void)appendStatus:(NSString *)newText
{
	NSTextStorage *storage = [infoView textStorage];
	if ([storage length])
		newText = [@"\n" stringByAppendingString:newText];
	NSAttributedString *as = [[NSAttributedString alloc] initWithString:newText
															 attributes:[NSDictionary dictionaryWithObjectsAndKeys:
																		 [NSColor whiteColor], NSForegroundColorAttributeName,
																		 nil]];
	[storage appendAttributedString:as];
	[as release];
	[infoView scrollRangeToVisible:NSMakeRange([storage length], 0)];
}

- (void)showStatus:(NSNotification *)notification
{
	dispatch_async(dispatch_get_main_queue(), ^{
		// in certain cases, status needs to be accessed from the main thread.
		[self appendStatus:[[notification object] valueForKey:@"status"]];
	});
}

@end
