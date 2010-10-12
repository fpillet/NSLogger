//
//  BWGradientBoxInspector.m
//  BWToolkit
//
//  Created by Brandon Walkin (www.brandonwalkin.com)
//  All code is provided under the New BSD license.
//

#import "BWGradientBoxInspector.h"
#import "NSEvent+BWAdditions.h"
#import "NSView+BWAdditions.h"

static float heightDelta = 33;
static float animationDuration = 0.1;

@interface BWGradientBoxInspector (BWGBIPrivate)
- (void)updateWellVisibility;
@end

@implementation BWGradientBoxInspector

@synthesize fillPopupSelection, gradientWell, colorWell, wellContainer;

- (void)awakeFromNib
{
	[super awakeFromNib];
	
	largeViewHeight = [[self view] frame].size.height;
	smallViewHeight = largeViewHeight - heightDelta;
}

- (NSString *)viewNibName 
{
    return @"BWGradientBoxInspector";
}

- (void)refresh 
{
	[super refresh];
	
	box = [[self inspectedObjects] objectAtIndex:0];
	[self updateWellVisibility];

	// Update the popup selections in case of an undo operation
	if ([box hasGradient])
		[self setFillPopupSelection:2];
	else if ([box hasFillColor])
		[self setFillPopupSelection:1];
	else
		[self setFillPopupSelection:0];
	
}

+ (BOOL)supportsMultipleObjectInspection
{
	return NO;
}

- (void)setFillPopupSelection:(int)anInt
{
	fillPopupSelection = anInt;
	
	if (fillPopupSelection == 0)
	{
		[box setHasGradient:NO];
		[box setHasFillColor:NO];
	}
	else if (fillPopupSelection == 1)
	{
		[box setHasGradient:NO];
		[box setHasFillColor:YES];
		[gradientWell setHidden:YES];
		[colorWell setHidden:NO];
		[colorWell setEnabled:YES];
	}
	else
	{
		[box setHasGradient:YES];
		[box setHasFillColor:NO];
		[gradientWell setHidden:NO];
		[colorWell setHidden:YES];
		[colorWell setEnabled:NO];
	}
}

- (void)updateWellVisibility
{	
	BOOL willCollapse;
	NSRect targetFrame = [[self view] frame];
	float viewHeight = [[self view] frame].size.height;
	
	if ((int)viewHeight == (int)largeViewHeight && ![box hasGradient] && ![box hasFillColor])
		willCollapse = YES;
	else if ((int)viewHeight == (int)smallViewHeight && ([box hasGradient] || [box hasFillColor]))
		willCollapse = NO;
	else
		return;

	targetFrame.size.height = willCollapse ? smallViewHeight : largeViewHeight;
	float alpha = willCollapse ? 0 : 1;
	float duration = [NSEvent bwShiftKeyIsDown] ? animationDuration * 10 : animationDuration;
	
	[NSAnimationContext beginGrouping];
	[[NSAnimationContext currentContext] setDuration:duration];
	[[wellContainer bwAnimator] setAlphaValue:alpha];
	[[[self view] bwAnimator] setFrame:targetFrame];
	[NSAnimationContext endGrouping];
}

@end
