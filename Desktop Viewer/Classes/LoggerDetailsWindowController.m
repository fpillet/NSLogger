//
//  LoggerDetailsWindowController.m
//  NSLogger
//
//  Created by Florent Pillet on 15/10/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//
#import "LoggerDetailsWindowController.h"
#import "LoggerMessage.h"
#import "LoggerMessageCell.h"

@implementation LoggerDetailsWindowController

@synthesize messages;

- (void)windowDidLoad
{
	// append the text for each message
	NSTextStorage *storage = [detailsView textStorage];
	NSDictionary *textAttributes = [[LoggerMessageCell defaultAttributes] objectForKey:@"text"];
	NSDictionary *dataAttributes = [[LoggerMessageCell defaultAttributes] objectForKey:@"data"];
	for (LoggerMessage *msg in messages)
	{
		if (msg.contentsType == kMessageImage)
			continue;
		NSAttributedString *as = [[NSAttributedString alloc] initWithString:[msg textRepresentation]
																  attributes:(msg.contentsType == kMessageString) ? textAttributes : dataAttributes];

		[storage replaceCharactersInRange:NSMakeRange([storage length], 0) withAttributedString:as];
		[storage replaceCharactersInRange:NSMakeRange([storage length], 0) withString:@"\n"];
		[as release];
	}
}

@end
