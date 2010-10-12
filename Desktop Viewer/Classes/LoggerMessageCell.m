/*
 * LoggerMessageCell.m
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
#include <time.h>
#import "LoggerMessageCell.h"
#import "LoggerMessage.h"
#import "LoggerUtils.h"

#define MINIMUM_CELL_HEIGHT			30.0f
#define INDENTATION_TAB_WIDTH		10.0f			// in pixels

#define TIMESTAMP_COLUMN_WIDTH		80.0f
#define	THREAD_COLUMN_WIDTH			80.0f

static NSMutableDictionary *sDefaultTimestampAttributes = nil;
static NSMutableDictionary *sDefaultTimedeltaAttributes = nil;
static NSMutableDictionary *sDefaultThreadIDAttributes = nil;
static NSMutableDictionary *sDefaultMessageAttributes = nil;
static NSMutableDictionary *sDefaultMessageDataAttributes = nil;
static NSFont *sDefaultFont = nil;
static NSFont *sDefaultMonospacedFont = nil;
static CGFloat sMinimumHeightForCell = 0;

@implementation LoggerMessageCell

@synthesize message, previousMessage;

// -----------------------------------------------------------------------------
// Class methods
// -----------------------------------------------------------------------------
+ (NSColor *)cellStandardBgColor
{
	static NSColor *sColor = nil;
	if (sColor == nil)
		sColor = [[NSColor colorWithCalibratedWhite:0.90 alpha:1.0] retain];
	return sColor;
}

+ (NSColor *)cellSeparatorColor
{
	static NSColor *sColor = nil;
	if (sColor == nil)
		sColor = [[NSColor colorWithCalibratedWhite:0.75 alpha:1.0] retain];
	return sColor;
}

+ (void)setDefaultFont:(NSFont *)aFont monospacedFont:(NSFont *)aMonospacedFont
{
	[sDefaultFont autorelease];
	sDefaultFont = [aFont retain];
	[sDefaultMonospacedFont autorelease];
	sDefaultMonospacedFont = [aMonospacedFont retain];
	[sDefaultTimestampAttributes autorelease];
	sDefaultTimestampAttributes = nil;
	[sDefaultTimedeltaAttributes autorelease];
	sDefaultTimedeltaAttributes = nil;
	[sDefaultThreadIDAttributes autorelease];
	sDefaultThreadIDAttributes = nil;
	[sDefaultMessageAttributes autorelease];
	sDefaultMessageAttributes = nil;
	[sDefaultMessageDataAttributes autorelease];
	sDefaultMessageDataAttributes = nil;
	sMinimumHeightForCell = 0;
}

+ (NSFont *)defaultFont
{
	if (sDefaultFont == nil)
		sDefaultFont = [[NSFont boldSystemFontOfSize:11] retain];
	return sDefaultFont;
}

+ (NSFont *)defaultMonospacedFont
{
	if (sDefaultMonospacedFont == nil)
		sDefaultMonospacedFont = [[NSFont userFixedPitchFontOfSize:11] retain];
	return sDefaultMonospacedFont;
}

+ (NSMutableDictionary *)defaultTextAttributes
{
	NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
	[style setLineBreakMode:NSLineBreakByTruncatingTail];
	NSMutableDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
								   [self defaultFont], NSFontAttributeName,
								   [NSColor blackColor], NSForegroundColorAttributeName,
								   style, NSParagraphStyleAttributeName,
								   nil];
	[style release];
	return dict;
}

+ (NSMutableDictionary *)defaultTimestampAttributes
{
	if (sDefaultTimestampAttributes == nil)
		sDefaultTimestampAttributes = [[self defaultTextAttributes] retain];
	return sDefaultTimestampAttributes;
}

+ (NSMutableDictionary *)defaultTimedeltaAttributes
{
	if (sDefaultTimedeltaAttributes == nil)
	{
		NSMutableDictionary *dict = [[self defaultTimestampAttributes] mutableCopy];
		[dict setObject:[NSColor grayColor] forKey:NSForegroundColorAttributeName];
		sDefaultTimedeltaAttributes = dict;
	}
	return sDefaultTimedeltaAttributes;
}

+ (NSMutableDictionary *)defaultThreadIDAttributes
{
	if (sDefaultThreadIDAttributes == nil)
	{
		NSMutableDictionary *dict = [[self defaultTextAttributes] retain];
		[dict setObject:[NSColor grayColor] forKey:NSForegroundColorAttributeName];
		sDefaultThreadIDAttributes = [dict retain];
	}
	return sDefaultThreadIDAttributes;
}

+ (NSMutableDictionary *)defaultMessageAttributes
{
	if (sDefaultMessageAttributes == nil)
	{
		NSMutableDictionary *dict = [[self defaultTextAttributes] retain];
		NSMutableParagraphStyle *style = [dict objectForKey:NSParagraphStyleAttributeName];
		[style setLineBreakMode:NSLineBreakByWordWrapping];
		sDefaultMessageAttributes = dict;
	}
	return sDefaultMessageAttributes;
}

+ (NSMutableDictionary *)defaultMessageDataAttributes
{
	if (sDefaultMessageDataAttributes == nil)
	{
		NSMutableDictionary *dict = [[self defaultTextAttributes] retain];
		[dict setObject:[self defaultMonospacedFont] forKey:NSFontAttributeName];
		NSMutableParagraphStyle *style = [dict objectForKey:NSParagraphStyleAttributeName];
		[style setLineBreakMode:NSLineBreakByClipping];
		sDefaultMessageDataAttributes = dict;
	}
	return sDefaultMessageDataAttributes;
}

+ (NSArray *)stringsWithData:(NSData *)data
{
	// convert NSData block to hex-ascii strings
	NSMutableArray *strings = [[NSMutableArray alloc] init];
	NSUInteger offset = 0, dataLen = [data length];
	NSString *str;
	char buffer[6+16*3+1+16+1+1];
	buffer[0] = '\0';
	const unsigned char *q = [data bytes];
	while (dataLen)
	{
		int i, b = sprintf(buffer,"%04x: ", offset);
		for (i=0; i < 16 && i < dataLen; i++)
			sprintf(&buffer[b+3*i], "%02x ", (int)q[i]);
		for (int j=i; j < 16; j++)
			strcat(buffer, "   ");
		
		b = strlen(buffer);
		buffer[b++] = '\'';
		for (i=0; i < 16 && i < dataLen; i++)
		{
			if (*q >= 32 && *q < 128)
				buffer[b++] = *q++;
			else
				buffer[b++] = ' ';
		}
		for (int j=i; j < 16; j++)
			buffer[b++] = ' ';
		buffer[b++] = '\'';
		buffer[b] = 0;
		
		str = [[NSString alloc] initWithBytes:buffer length:strlen(buffer) encoding:NSISOLatin1StringEncoding];
		[strings addObject:str];
		[str release];
		
		dataLen -= i;
		offset += i;
		q += i;
	}
	return [strings autorelease];
}

+ (CGFloat)minimumHeightForCell
{
	if (sMinimumHeightForCell == 0)
	{
		NSRect r1 = [@"10:10:10.256" boundingRectWithSize:NSMakeSize(1024, 1024)
												  options:NSStringDrawingUsesLineFragmentOrigin
											   attributes:[self defaultTimestampAttributes]];
		NSRect r2 = [@"+999ms" boundingRectWithSize:NSMakeSize(1024, 1024)
											options:NSStringDrawingUsesLineFragmentOrigin
										 attributes:[self defaultTimedeltaAttributes]];
		sMinimumHeightForCell = NSHeight(r1) + NSHeight(r2) + 6;
	}
	return sMinimumHeightForCell;
}

+ (CGFloat)heightForCellWithMessage:(LoggerMessage *)aMessage maxSize:(NSSize)sz
{
	// return cached cell height if possible
	NSSize cellSize = aMessage.cachedCellSize;
	if (cellSize.width == sz.width)
		return cellSize.height;
	cellSize.width = sz.width;

	sz.width -= TIMESTAMP_COLUMN_WIDTH + THREAD_COLUMN_WIDTH + 4;
	sz.height -= 4;

	switch (aMessage.contentsType)
	{
		case kMessageString: {
			NSRect lr = [aMessage.message boundingRectWithSize:sz
													   options:NSStringDrawingUsesLineFragmentOrigin
													attributes:[self defaultMessageAttributes]];
			sz.height = fminf(NSHeight(lr), sz.height);			
			break;
		}

		case kMessageData: {
			NSUInteger numBytes = [(NSData *)aMessage.message length];
			int nLines = (numBytes >> 4) + ((numBytes & 15) ? 1 : 0);
			NSRect lr = [@"000:" boundingRectWithSize:sz
											  options:NSStringDrawingUsesLineFragmentOrigin
										   attributes:[self defaultMessageDataAttributes]];
			sz.height = NSHeight(lr) * nLines;
			break;
		}
			
		case kMessageImage: {
			NSSize imgSize = aMessage.imageSize;
			sz.height = fminf(fminf(sz.width, sz.height/2), imgSize.height); 
			break;
		}
		default:
			break;
	}

	// cache and return cell height
	cellSize.height = fmaxf(sz.height + 4, [self minimumHeightForCell]);
//if (aMessage.cachedCellSize.height && aMessage.cachedCellSize.height != cellSize.height)
//	NSLog(@"Old height=%d new height=%d aMessage=%@", (int)aMessage.cachedCellSize.height, (int)cellSize.height, aMessage);
	aMessage.cachedCellSize = cellSize;
	return cellSize.height;
}

// -----------------------------------------------------------------------------
// Instance methods
// -----------------------------------------------------------------------------
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView
{
	CGContextRef ctx = (CGContextRef)[[NSGraphicsContext currentContext] graphicsPort];

	BOOL highlighted = [self isHighlighted];
	BOOL flippedDrawing = [controlView isFlipped];
	NSColor *highlightedTextColor = nil;
	if (highlighted)
		highlightedTextColor = [NSColor whiteColor];

	// Update cell frame to take indent into account
	//	cellFrame = NSInsetRect(cellFrame, 4, 0);
	CGFloat indent = message.indent * INDENTATION_TAB_WIDTH;
	if (indent)
	{
		// draw color bars to represent the indentation width
		CGColorRef indentBarColor = CGColorCreateGenericGray(0.90f, 1.0f);
		CGContextSetFillColorWithColor(ctx, indentBarColor);
		for (int i = 0; i < message.indent; i++)
		{
			CGContextFillRect(ctx, CGRectMake(NSMinX(cellFrame) + (i * INDENTATION_TAB_WIDTH) + 2,
											  NSMinY(cellFrame),
											  INDENTATION_TAB_WIDTH - 4,
											  NSHeight(cellFrame)));
		}
		CGColorRelease(indentBarColor);
		cellFrame.origin.x += indent;
		cellFrame.size.width -= indent;
		if (cellFrame.size.width < 30)
			return;
	}
	
	// Draw cell background and bottom separator (using blocks, just for fun)
	if (!highlighted)
	{
		CGColorRef cellBgColor = CGColorCreateGenericGray(0.95f, 1.0f);
		CGContextSetFillColorWithColor(ctx, cellBgColor);
		CGContextFillRect(ctx, NSRectToCGRect(cellFrame));
		CGColorRelease(cellBgColor);
	}

	CGColorRef cellSeparatorDark = CGColorCreateGenericGray(0.75f, 1.0f);
	CGColorRef cellSeparatorLight = CGColorCreateGenericGray(1.0f, 1.0f);
	
	void (^drawSeparators)(CGColorRef, CGFloat) = ^(CGColorRef color, CGFloat offset) {
		CGContextSetLineWidth(ctx, 0.75f);
		CGContextSetStrokeColorWithColor(ctx, color);
		CGContextBeginPath(ctx);
		if (!highlighted) {
			// horizontal bottom separator
			CGContextMoveToPoint(ctx, NSMinX(cellFrame), NSMaxY(cellFrame) - 1 + offset);
			CGContextAddLineToPoint(ctx, NSMaxX(cellFrame), NSMaxY(cellFrame) - 1 + offset);
		}
		// timestamp/thread separator
		CGContextMoveToPoint(ctx, NSMinX(cellFrame) + TIMESTAMP_COLUMN_WIDTH + offset, NSMinY(cellFrame));
		CGContextAddLineToPoint(ctx, NSMinX(cellFrame) + TIMESTAMP_COLUMN_WIDTH + offset, NSMaxY(cellFrame)-1);
		// thread/message separator
		CGContextMoveToPoint(ctx, NSMinX(cellFrame) + TIMESTAMP_COLUMN_WIDTH + THREAD_COLUMN_WIDTH + offset, NSMinY(cellFrame));
		CGContextAddLineToPoint(ctx, NSMinX(cellFrame) + TIMESTAMP_COLUMN_WIDTH + THREAD_COLUMN_WIDTH + offset, NSMaxY(cellFrame)-1);
		CGContextStrokePath(ctx);
	};
	drawSeparators(cellSeparatorDark, 0);
	drawSeparators(cellSeparatorLight, 1);

	// Draw timestamp and time delta column
	NSRect r, tr;
	r = NSMakeRect(NSMinX(cellFrame),
				   NSMinY(cellFrame),
				   TIMESTAMP_COLUMN_WIDTH,
				   NSHeight(cellFrame));
	tr = NSInsetRect(r, 2, 2);

	struct timeval tv = message.timestamp;
	struct timeval td;
	if (previousMessage != nil)
		[message computeTimeDelta:&td since:previousMessage];

	time_t sec = tv.tv_sec;
	struct tm *t = localtime(&sec);
	NSString *timestampStr;
	if (tv.tv_usec == 0)
		timestampStr = [NSString stringWithFormat:@"%02d:%02d:%02d", t->tm_hour, t->tm_min, t->tm_sec];
	else
		timestampStr = [NSString stringWithFormat:@"%02d:%02d:%02d.%03d", t->tm_hour, t->tm_min, t->tm_sec, tv.tv_usec / 1000];
	
	NSString *timeDeltaStr = nil;
	if (previousMessage != nil)
		timeDeltaStr = [LoggerUtils stringWithTimeDelta:&td];

	NSMutableDictionary *attrs = [[self class] defaultTimestampAttributes];
	NSRect bounds = [timestampStr boundingRectWithSize:tr.size
											   options:(NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading)
											attributes:attrs];
	NSRect timeRect, deltaRect;
	if (flippedDrawing)
	{
		timeRect = NSMakeRect(NSMinX(tr), NSMinY(tr), NSWidth(tr), NSHeight(bounds));
		deltaRect = NSMakeRect(NSMinX(tr), NSMaxY(timeRect)+1, NSWidth(tr), NSHeight(tr) - NSHeight(bounds) - 1);
	}
	else
	{
		timeRect = NSMakeRect(NSMinX(tr), NSMaxY(tr) - NSHeight(bounds), NSWidth(tr), NSHeight(bounds));
		deltaRect = NSMakeRect(NSMinX(tr), NSMinY(timeRect) - 1 - NSHeight(bounds), NSWidth(tr), NSHeight(tr) - NSHeight(bounds) - 1);
	}

	if (highlighted)
	{
		attrs = [[attrs mutableCopy] autorelease];
		[attrs setObject:highlightedTextColor forKey:NSForegroundColorAttributeName];
	}
	[timestampStr drawWithRect:timeRect
					   options:(NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading)
					attributes:attrs];

	attrs = [[self class] defaultTimedeltaAttributes];
	if (highlighted)
	{
		attrs = [[attrs mutableCopy] autorelease];
		[attrs setObject:highlightedTextColor forKey:NSForegroundColorAttributeName];
	}
	[timeDeltaStr drawWithRect:deltaRect
					   options:NSStringDrawingUsesLineFragmentOrigin
					attributes:attrs];

	// Draw thread ID
	attrs = [[self class] defaultThreadIDAttributes];
	if (highlighted)
	{
		attrs = [[attrs mutableCopy] autorelease];
		[attrs setObject:highlightedTextColor forKey:NSForegroundColorAttributeName];
	}
	r = NSOffsetRect(r, TIMESTAMP_COLUMN_WIDTH, 0);
	r.size.width = THREAD_COLUMN_WIDTH;
	[message.threadID drawWithRect:NSInsetRect(r, 3, 2)
						   options:NSStringDrawingUsesLineFragmentOrigin
						attributes:attrs];

	// Draw message
	r = NSMakeRect(NSMinX(cellFrame) + TIMESTAMP_COLUMN_WIDTH + THREAD_COLUMN_WIDTH + 2,
				   NSMinY(cellFrame) + 2,
				   NSWidth(cellFrame) - (TIMESTAMP_COLUMN_WIDTH + THREAD_COLUMN_WIDTH) - 4,
				   NSHeight(cellFrame) - 4);

	if (message.contentsType == kMessageString)
	{
		attrs = [[self class] defaultMessageAttributes];
		if (highlighted)
		{
			attrs = [[attrs mutableCopy] autorelease];
			[attrs setObject:highlightedTextColor forKey:NSForegroundColorAttributeName];
		}		
		[(NSString *)message.message drawWithRect:r
										  options:(NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingTruncatesLastVisibleLine)
									   attributes:attrs];
	}
	else if (message.contentsType == kMessageData)
	{
		NSArray *strings = [[self class] stringsWithData:(NSData *)message.message];
		attrs = [[self class] defaultMessageDataAttributes];
		if (highlighted)
		{
			attrs = [[attrs mutableCopy] autorelease];
			[attrs setObject:highlightedTextColor forKey:NSForegroundColorAttributeName];
		}
		CGFloat y = flippedDrawing ? NSMinY(r) : NSMaxY(r);
		CGFloat availHeight = NSHeight(r);
		for (NSString *s in strings)
		{
			NSRect lr = [s boundingRectWithSize:r.size
										options:NSStringDrawingUsesLineFragmentOrigin
									 attributes:attrs];
			[s drawWithRect:NSMakeRect(NSMinX(r),
									   flippedDrawing ? y : y - NSHeight(lr),
									   NSWidth(r),
									   NSHeight(lr))
					options:NSStringDrawingUsesLineFragmentOrigin
				 attributes:attrs];
			availHeight -= NSHeight(lr);
			if (availHeight < NSHeight(lr))
				break;
			if (flippedDrawing)
				y += NSHeight(lr);
			else
				y -= NSHeight(lr);
		}
	}
	else if (message.contentsType == kMessageImage)
	{
		// Make the image fit in the cell
		r = NSInsetRect(r, 2, 2);
		NSSize srcSize = message.imageSize;
		NSSize imgSize = srcSize;
		if (imgSize.width > NSWidth(r))
		{
			CGFloat factor = imgSize.width / NSWidth(r);
			imgSize.height = floorf(imgSize.height / factor);
			imgSize.width = NSWidth(r);
		}
		if (imgSize.height > NSHeight(r))
		{
			CGFloat factor = imgSize.height / NSHeight(r);
			imgSize.width = floorf(imgSize.width / factor);
			imgSize.height = NSHeight(r);
		}
		
		[message.image drawInRect:NSMakeRect(NSMinX(r), NSMinY(r), imgSize.width, imgSize.height)
						 fromRect:NSMakeRect(0, 0, srcSize.width, srcSize.height)
						operation:NSCompositeCopy
						 fraction:1.0f];
	}
}

@end
