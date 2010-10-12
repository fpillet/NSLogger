//
//  LoggerFilterEditorController.h
//  NSLogger
//
//  Created by Florent Pillet on 07/10/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@interface LoggerFilterEditorController : NSObject
{
	IBOutlet NSPredicateEditor *predicateEditor;
	LoggerFilter *filter;
}

@end
