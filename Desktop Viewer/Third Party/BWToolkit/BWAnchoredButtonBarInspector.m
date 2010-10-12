//
//  BWAnchoredButtonBarViewInspector.m
//  BWToolkit
//
//  Created by Brandon Walkin (www.brandonwalkin.com)
//  All code is provided under the New BSD license.
//

#import "BWAnchoredButtonBarInspector.h"
#import "BWAnchoredButtonBar.h"

@implementation BWAnchoredButtonBarInspector

- (NSString *)viewNibName 
{
    return @"BWAnchoredButtonBarInspector";
}

- (void)refresh 
{
	[super refresh];
	
	if ([[self inspectedObjects] count] > 0 && !isAnimating)
	{
		BWAnchoredButtonBar *inspectedButtonBar = [[self inspectedObjects] lastObject];
		
		if ([inspectedButtonBar selectedIndex] == 0)
			[self selectMode:1 withAnimation:NO];
		else if ([inspectedButtonBar selectedIndex] == 1)
			[self selectMode:2 withAnimation:NO];
		else
			[self selectMode:3 withAnimation:NO];
	}
}

- (IBAction)selectMode1:(id)sender
{
	[self selectMode:1 withAnimation:YES];
}

- (IBAction)selectMode2:(id)sender
{
	[self selectMode:2 withAnimation:YES];
}

- (IBAction)selectMode3:(id)sender
{
	[self selectMode:3 withAnimation:YES];
}

- (void)selectMode:(int)modeIndex withAnimation:(BOOL)shouldAnimate
{
	float xOrigin;
	
	if (modeIndex == 1)
		xOrigin = roundf(matrix.frame.origin.x-1);
	else if (modeIndex == 2)
		xOrigin = roundf(matrix.frame.origin.x + NSWidth(matrix.frame) / matrix.numberOfColumns);
	else
		xOrigin = roundf(NSMaxX(matrix.frame) - NSWidth(matrix.frame) / matrix.numberOfColumns + matrix.numberOfColumns - 1);
	
	if (shouldAnimate)
	{
		float deltaX = fabsf(xOrigin - selectionView.frame.origin.x);
		float doubleSpaceMultiplier = 1;
		
		if (deltaX > 65)
			doubleSpaceMultiplier = 1.5;
		
		float duration = 0.1*doubleSpaceMultiplier;
		
		isAnimating = YES;
		
		[NSAnimationContext beginGrouping];
		[[NSAnimationContext currentContext] setDuration:(duration)];
		[[selectionView animator] setFrameOrigin:NSMakePoint(xOrigin,selectionView.frame.origin.y)];
		[NSAnimationContext endGrouping];
		
		[self performSelector:@selector(selectionAnimationDidEnd) withObject:nil afterDelay:duration];
	}
	else
	{
		[selectionView setFrameOrigin:NSMakePoint(xOrigin,selectionView.frame.origin.y)];
	}
}

- (void)selectionAnimationDidEnd
{
	isAnimating = NO;
}

@end
