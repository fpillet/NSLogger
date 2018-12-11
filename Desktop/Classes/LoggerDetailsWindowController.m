/*
 * LoggerDetailsWindowController.m
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
#import "LoggerDetailsWindowController.h"
#import "LoggerWindowController.h"
#import "LoggerDocument.h"
#import "LoggerMessage.h"
#import "LoggerMessageCell.h"

@implementation LoggerDetailsWindowController

- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName
{
	return [[[self document] mainWindowController] windowTitleForDocumentDisplayName:displayName];
}

- (void)windowDidLoad
{
	[self.detailsView setTextContainerInset:NSMakeSize(2, 2)];
}

- (void)windowDidBecomeMain:(NSNotification *)notification
{
	[[self.document mainWindowController] updateMenuBar:YES];
}

- (void)windowDidResignMain:(NSNotification *)notification
{
	[[self.document mainWindowController] updateMenuBar:YES];
}

- (void)setMessages:(NSArray *)messages
{
	// defer text generation to queues
	NSTextStorage *storage = [self.detailsView textStorage];
	[storage replaceCharactersInRange:NSMakeRange(0, [storage length]) withString:@""];

	NSUInteger numMessages = [messages count];
	[self.detailsInfo setStringValue:[NSString stringWithFormat:NSLocalizedString(@"Details for %d log messages", @""), numMessages]];
	[self.progressIndicator setHidden:NO];
	[self.progressIndicator startAnimation:self];

	NSDictionary *textAttributes = LoggerMessageCell.defaultAttributes[@"text"];
	NSDictionary *dataAttributes = LoggerMessageCell.defaultAttributes[@"data"];

	NSUInteger i = 0;
	while (i < numMessages)
	{
		NSRange range = NSMakeRange(i, MIN(numMessages-i, 100));
		if (range.length == 0)
			break;
		i += range.length;

		if (self.detailsQueue == nil)
			self.detailsQueue = dispatch_queue_create("com.florentpillet.nslogger.detailsQueue", NULL);
		
		dispatch_async(self.detailsQueue, ^{
			NSMutableArray *strings = [[NSMutableArray alloc] initWithCapacity:range.length];
			for (LoggerMessage *msg in [messages subarrayWithRange:range])
			{
				NSAttributedString *as = [[NSAttributedString alloc] initWithString:[msg textRepresentation]
																		 attributes:(msg.contentsType == kMessageString) ? textAttributes : dataAttributes];
				[strings addObject:as];
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				[storage beginEditing];
				for (NSAttributedString *as in strings)
					[storage replaceCharactersInRange:NSMakeRange([storage length], 0) withAttributedString:as];
				[storage endEditing];
				if ((range.location + range.length) >= numMessages)
				{
					[self.progressIndicator stopAnimation:self];
					[self.progressIndicator setHidden:YES];
				}
			});
		});
	}
}

@end
