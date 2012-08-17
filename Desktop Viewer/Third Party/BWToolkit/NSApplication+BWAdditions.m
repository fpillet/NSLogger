//
//  NSApplication+BWAdditions.m
//  BWToolkit
//
//  Created by Brandon Walkin (www.brandonwalkin.com)
//  All code is provided under the New BSD license.
//

#import "NSApplication+BWAdditions.h"

@implementation NSApplication (BWAdditions)

+ (BOOL)bwIsOnLeopard 
{
	NSInteger majorVersion = 10;
	NSInteger minorVersion = 8;
	@autoreleasepool {
		NSString* versionString = [[NSDictionary dictionaryWithContentsOfFile: @"/System/Library/CoreServices/SystemVersion.plist"] objectForKey: @"ProductVersion"];
		NSArray* versionStrings = [versionString componentsSeparatedByString: @"."];
		if ( versionStrings.count >= 1 ) majorVersion = [[versionStrings objectAtIndex: 0] integerValue];
		if ( versionStrings.count >= 2 ) minorVersion = [[versionStrings objectAtIndex: 1] integerValue];
	}

	return majorVersion == 10 && minorVersion == 5;
}

@end
