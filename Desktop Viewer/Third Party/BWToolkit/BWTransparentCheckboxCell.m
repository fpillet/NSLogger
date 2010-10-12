//
//  BWTransparentCheckboxCell.m
//  BWToolkit
//
//  Created by Brandon Walkin (www.brandonwalkin.com)
//  All code is provided under the New BSD license.
//

#import "BWTransparentCheckboxCell.h"
#import "BWTransparentTableView.h"
#import "NSApplication+BWAdditions.h"

static NSImage *checkboxOffN, *checkboxOffP, *checkboxOnN, *checkboxOnP;
static NSColor *enabledColor, *disabledColor;
static NSShadow *contentShadow;

@interface NSCell (BWTCCPrivate)
- (NSDictionary *)_textAttributes;
@end

@interface BWTransparentCheckboxCell (BWTCCPrivate)
- (NSColor *)interiorColor;
- (BOOL)isInTableView;
@end

@implementation BWTransparentCheckboxCell

+ (void)initialize;
{
	NSBundle *bundle = [NSBundle bundleForClass:[BWTransparentCheckboxCell class]];
	
	checkboxOffN = [[NSImage alloc] initWithContentsOfFile:[bundle pathForImageResource:@"TransparentCheckboxOffN.tiff"]];
	checkboxOffP = [[NSImage alloc] initWithContentsOfFile:[bundle pathForImageResource:@"TransparentCheckboxOffP.tiff"]];
	checkboxOnN = [[NSImage alloc] initWithContentsOfFile:[bundle pathForImageResource:@"TransparentCheckboxOnN.tiff"]];
	checkboxOnP = [[NSImage alloc] initWithContentsOfFile:[bundle pathForImageResource:@"TransparentCheckboxOnP.tiff"]];
	
	[checkboxOffN setFlipped:YES];
	[checkboxOffP setFlipped:YES];
	[checkboxOnN setFlipped:YES];
	[checkboxOnP setFlipped:YES];
	
	enabledColor = [[NSColor whiteColor] retain];
	disabledColor = [[NSColor colorWithCalibratedWhite:0.6 alpha:1] retain];
	
	contentShadow = [[NSShadow alloc] init];
	[contentShadow setShadowOffset:NSMakeSize(0,-1)];
}

- (NSDictionary *)_textAttributes
{
	NSMutableDictionary *attributes = [[[NSMutableDictionary alloc] init] autorelease];
	[attributes addEntriesFromDictionary:[super _textAttributes]];
	[attributes setObject:[self interiorColor] forKey:NSForegroundColorAttributeName];
	
	if ([self isInTableView])
	{
		[attributes setObject:[NSFont systemFontOfSize:11] forKey:NSFontAttributeName];
	}
	else
	{	
		[attributes setObject:[NSFont boldSystemFontOfSize:11] forKey:NSFontAttributeName];
		[attributes setObject:contentShadow forKey:NSShadowAttributeName];
	}
	
	return attributes;
}

- (BOOL)isInTableView
{
	return [[self controlView] isMemberOfClass:[BWTransparentTableView class]];
}

- (NSRect)drawTitle:(NSAttributedString *)title withFrame:(NSRect)frame inView:(NSView *)controlView
{	
	if ([self isInTableView])
		return [super drawTitle:title withFrame:frame inView:controlView];
	
	CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
	CGContextSaveGState(context);
	CGContextSetShouldSmoothFonts(context, NO);

	NSRect rect = [super drawTitle:title withFrame:frame inView:controlView];
	
	CGContextRestoreGState(context);
	
	return rect;
}

- (NSColor *)interiorColor
{
	NSColor *interiorColor;
	
	if ([[self controlView] isMemberOfClass:[BWTransparentTableView class]])
	{
		// Make the text white if the row is selected
		if ([self backgroundStyle] != 1)
			interiorColor = [NSColor colorWithCalibratedWhite:(198.0f / 255.0f) alpha:1];
		else
			interiorColor = [NSColor whiteColor];
	}
	else 
	{
		interiorColor = [self isEnabled] ? enabledColor : disabledColor;
	}
	
	return interiorColor;
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	if ([self isInTableView])
		cellFrame.origin.x += 4;
	
	[super drawInteriorWithFrame:cellFrame inView:controlView];
}

- (void)drawImage:(NSImage*)image withFrame:(NSRect)frame inView:(NSView*)controlView
{	
	CGFloat y = NSMaxY(frame) - (frame.size.height - checkboxOffN.size.height) / 2.0 - 15;
	CGFloat x = frame.origin.x + 1;
	NSPoint point = NSMakePoint(x, roundf(y));
	
	CGFloat alpha = [self isEnabled] ? 1.0 : 0.6;
	
	if ([self isHighlighted] && [self intValue])
		[checkboxOnP drawAtPoint:point fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:alpha];
	else if (![self isHighlighted] && [self intValue])
		[checkboxOnN drawAtPoint:point fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:alpha];
	else if (![self isHighlighted] && ![self intValue])
		[checkboxOffN drawAtPoint:point fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:alpha];
	else if ([self isHighlighted] && ![self intValue])
		[checkboxOffP drawAtPoint:point fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:alpha];
}

- (NSControlSize)controlSize
{
	return NSSmallControlSize;
}

- (void)setControlSize:(NSControlSize)size
{
	
}

@end
