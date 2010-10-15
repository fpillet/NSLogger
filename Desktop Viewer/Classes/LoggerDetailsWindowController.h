//
//  LoggerDetailsWindowController.h
//  NSLogger
//
//  Created by Florent Pillet on 15/10/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>


@interface LoggerDetailsWindowController : NSWindowController
{
	IBOutlet NSTextView *detailsView;
	NSArray *messages;
}

@property (nonatomic, retain) NSArray *messages;

@end
