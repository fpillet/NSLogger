/*
 * LoggerClientInfoCell.m
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
#import "LoggerClientInfoCell.h"
#import "LoggerMessage.h"
#import "LoggerCommon.h"

@interface LoggerClientInfoCell ()
+ (NSDictionary *)clientInfoAttributes:(BOOL)highlighted;
@end

@implementation LoggerClientInfoCell

+ (CGFloat)heightForCellWithMessage:(LoggerMessage *)aMessage maxSize:(NSSize)sz
{
	// return cached cell height if possible
	CGFloat minimumHeight = [self minimumHeightForCell];
	NSSize cellSize = aMessage.cachedCellSize;
	if (cellSize.width == sz.width)
		return cellSize.height;
	
	cellSize.width = sz.width;
	
	// new width is larger, but cell already at minimum height, don't recompute
	if (cellSize.width > 0 && cellSize.width < sz.width && cellSize.height == minimumHeight)
		return minimumHeight;
	
	sz.width -= 8;
	sz.height -= 4;

	NSRect lr = [aMessage.message boundingRectWithSize:sz
											   options:(NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading)
											attributes:[self clientInfoAttributes:NO]];
	sz.height = fminf(NSHeight(lr), sz.height);			

	// cache and return cell height
	cellSize.height = fmaxf(sz.height + 4, minimumHeight);
	aMessage.cachedCellSize = cellSize;
	return cellSize.height;
}

+ (NSDictionary *)clientInfoAttributes:(BOOL)highlighted
{
	NSMutableDictionary *attrs = [[[self defaultAttributes] objectForKey:@"text"] mutableCopy];
	NSMutableParagraphStyle *style = [[attrs objectForKey:NSParagraphStyleAttributeName] mutableCopy];
	[style setAlignment:NSCenterTextAlignment];
	[attrs setObject:style forKey:NSParagraphStyleAttributeName];
	[style release];
	if (highlighted)
		[attrs setObject:[NSColor whiteColor] forKey:NSForegroundColorAttributeName];
	return [attrs autorelease];
}

- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];
	BOOL disconnected = (message.type == LOGMSG_TYPE_DISCONNECT);
	BOOL highlighted = [self isHighlighted];

	// Draw cell background and separators
	if (!highlighted)
	{
		CGColorRef cellBgColor;
		if (disconnected)
			cellBgColor = CGColorCreateGenericRGB(0.8f, 0.f, 0.f, 1.f);
		else
			cellBgColor = CGColorCreateGenericRGB(0.f, 0.8f, 0.f, 1.f);
		CGContextSetFillColorWithColor(ctx, cellBgColor);
		CGContextFillRect(ctx, NSRectToCGRect(cellFrame));
		CGColorRelease(cellBgColor);
	}
	CGContextSetShouldAntialias(ctx, false);
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextSetLineCap(ctx, kCGLineCapSquare);
	CGColorRef cellSeparatorColor = CGColorCreateGenericGray(0.80f, 1.0f);
	CGContextSetStrokeColorWithColor(ctx, cellSeparatorColor);
	CGColorRelease(cellSeparatorColor);
	CGContextBeginPath(ctx);
	CGContextSetShouldAntialias(ctx, true);

	// horizontal bottom separator
	CGContextMoveToPoint(ctx, NSMinX(cellFrame), floorf(NSMaxY(cellFrame)));
	CGContextAddLineToPoint(ctx, NSMaxX(cellFrame), floorf(NSMaxY(cellFrame)));
	
	// If the window is not main, don't change the text color
	if (highlighted && ![[controlView window] isMainWindow])
		highlighted = NO;

	// Draw client info
	NSRect r = NSMakeRect(NSMinX(cellFrame) + 3,
						  NSMinY(cellFrame),
						  NSWidth(cellFrame) - 6,
						  NSHeight(cellFrame));

	NSDictionary *attrs = [[self class] clientInfoAttributes:highlighted];
	NSRect lr = [(NSString *)message.message boundingRectWithSize:r.size
														  options:(NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading)
													   attributes:attrs];
	r.size.height = lr.size.height;
	CGFloat offset = floorf((NSHeight(cellFrame) - NSHeight(lr)) / 2.0f);
	if (offset > 0)
		r.origin.y += offset;
	[(NSString *)message.message drawWithRect:r
									  options:(NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading)
								   attributes:attrs];
}

@end
