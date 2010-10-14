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

#define TIMESTAMP_COLUMN_WIDTH		85.0f
#define	THREAD_COLUMN_WIDTH			85.0f

static NSMutableDictionary *sDefaultAttributes = nil;
static NSColor *sDefaultTagAndLevelColor = nil;
static CGFloat sMinimumHeightForCell = 0;

NSString * const kMessageAttributesChangedNotification = @"MessageAttributesChangedNotification";

@implementation LoggerMessageCell

@synthesize message, previousMessage, messageAttributes;

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

+ (NSDictionary *)defaultAttributesDictionary
{
	NSMutableDictionary *attrs = [NSMutableDictionary dictionary];
	
	NSFont *defaultFont = [[NSFont boldSystemFontOfSize:11] retain];
	NSFont *defaultMonospacedFont = [[NSFont userFixedPitchFontOfSize:11] retain];
	NSFont *defaultTagAndLevelFont = [[NSFont boldSystemFontOfSize:9] retain];
	
	// Default text attributes
	NSMutableDictionary *dict;
	NSMutableParagraphStyle *style = [[NSParagraphStyle defaultParagraphStyle] mutableCopy];
	[style setLineBreakMode:NSLineBreakByTruncatingTail];
	NSMutableDictionary *textAttrs = [NSMutableDictionary dictionaryWithObjectsAndKeys:
									  defaultFont, NSFontAttributeName,
									  [NSColor blackColor], NSForegroundColorAttributeName,
									  style, NSParagraphStyleAttributeName,
									  nil];
	[style release];
	
	// Timestamp attributes
	[attrs setObject:textAttrs forKey:@"timestamp"];
	
	// Time Delta attributes
	dict = [textAttrs mutableCopy];
	[dict setObject:[NSColor grayColor] forKey:NSForegroundColorAttributeName];
	[attrs setObject:dict forKey:@"timedelta"];
	[dict release];
	
	// Thread ID attributes
	dict = [textAttrs mutableCopy];
	[dict setObject:[NSColor grayColor] forKey:NSForegroundColorAttributeName];
	[attrs setObject:dict forKey:@"threadID"];
	[dict release];
	
	// Tag and Level attributes
	dict = [textAttrs mutableCopy];
	[dict setObject:defaultTagAndLevelFont forKey:NSFontAttributeName];
	[dict setObject:[NSColor whiteColor] forKey:NSForegroundColorAttributeName];
	[attrs setObject:dict forKey:@"tag"];
	[attrs setObject:dict forKey:@"level"];
	
	// Text message attributes
	dict = [textAttrs mutableCopy];
	style = [[dict objectForKey:NSParagraphStyleAttributeName] mutableCopy];
	[style setLineBreakMode:NSLineBreakByWordWrapping];
	[dict setObject:style forKey:NSParagraphStyleAttributeName];
	[style release];
	[attrs setObject:dict forKey:@"text"];
	[dict release];
	
	// Data message attributes
	dict = [textAttrs mutableCopy];
	[dict setObject:defaultMonospacedFont forKey:NSFontAttributeName];
	[attrs setObject:dict forKey:@"data"];
	[dict release];
	
	return attrs;
}

+ (NSDictionary *)defaultAttributes
{
	if (sDefaultAttributes == nil)
	{
		// Try to load the default text attributes from user defaults
		NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:@"Message Attributes"];
		if (data != nil)
			sDefaultAttributes = [[NSKeyedUnarchiver unarchiveObjectWithData:data] retain];
		if (sDefaultAttributes == nil)
			[self setDefaultAttributes:[self defaultAttributesDictionary]];
	}
	return sDefaultAttributes;
}

+ (void)setDefaultAttributes:(NSDictionary *)newAttributes
{
	[sDefaultAttributes release];
	sDefaultAttributes = [newAttributes copy];
	sMinimumHeightForCell = 0;
	[[NSUserDefaults standardUserDefaults] setObject:[NSKeyedArchiver archivedDataWithRootObject:sDefaultAttributes] forKey:@"Message Attributes"];
	[[NSNotificationCenter defaultCenter] postNotificationName:kMessageAttributesChangedNotification object:nil];
}

+ (NSColor *)defaultTagAndLevelColor
{
	if (sDefaultTagAndLevelColor == nil)
		sDefaultTagAndLevelColor = [[NSColor colorWithCalibratedRed:0.51f green:0.57f blue:0.79f alpha:1.0f] retain];
	return sDefaultTagAndLevelColor;
}

+ (NSColor *)colorForTag:(NSString *)tag
{
	// @@@ TODO: tag color customization mechanism
	return [self defaultTagAndLevelColor];
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
											   attributes:[[self defaultAttributes] objectForKey:@"timestamp"]];
		NSRect r2 = [@"+999ms" boundingRectWithSize:NSMakeSize(1024, 1024)
											options:NSStringDrawingUsesLineFragmentOrigin
										 attributes:[[self defaultAttributes] objectForKey:@"timedelta"]];
		NSRect r3 = [@"Main Thread" boundingRectWithSize:NSMakeSize(1024, 1024)
												 options:NSStringDrawingUsesLineFragmentOrigin
											  attributes:[[self defaultAttributes] objectForKey:@"threadID"]];
		NSRect r4 = [@"qWTy" boundingRectWithSize:NSMakeSize(1024, 1024)
										  options:NSStringDrawingUsesLineFragmentOrigin
									   attributes:[[self defaultAttributes] objectForKey:@"tag"]];
		sMinimumHeightForCell = fmaxf(NSHeight(r1) + NSHeight(r2), NSHeight(r3) + NSHeight(r4)) + 4;
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

	sz.width -= TIMESTAMP_COLUMN_WIDTH + THREAD_COLUMN_WIDTH + 6;
	sz.height -= 4;

	switch (aMessage.contentsType)
	{
		case kMessageString: {
			NSRect lr = [aMessage.message boundingRectWithSize:sz
													   options:NSStringDrawingUsesLineFragmentOrigin
													attributes:[[self defaultAttributes] objectForKey:@"text"]];
			sz.height = fminf(NSHeight(lr), sz.height);			
			break;
		}

		case kMessageData: {
			NSUInteger numBytes = [(NSData *)aMessage.message length];
			int nLines = (numBytes >> 4) + ((numBytes & 15) ? 1 : 0);
			NSRect lr = [@"000:" boundingRectWithSize:sz
											  options:NSStringDrawingUsesLineFragmentOrigin
										   attributes:[[self defaultAttributes] objectForKey:@"data"]];
			sz.height = NSHeight(lr) * nLines;
			break;
		}
			
		case kMessageImage: {
			NSSize imgSize = aMessage.imageSize;
			sz.height = fminf(fminf(sz.width, sz.height/2), imgSize.height + 1); 
			break;
		}
		default:
			break;
	}

	// cache and return cell height
	cellSize.height = fmaxf(sz.height + 4, [self minimumHeightForCell]);
	aMessage.cachedCellSize = cellSize;
	return cellSize.height;
}

// -----------------------------------------------------------------------------
// Instance methods
// -----------------------------------------------------------------------------
- (id)copyWithZone:(NSZone *)zone
{
	LoggerMessageCell *c = [super copyWithZone:zone];
	c->message = [message retain];
	c->previousMessage = [previousMessage retain];
	c->messageAttributes = [messageAttributes retain];
	return c;
}

- (void)dealloc
{
	[message release];
	[previousMessage release];
	[messageAttributes release];
	[super dealloc];
}

- (NSMutableDictionary *)timestampAttributes
{
	if (messageAttributes == nil)
		return [[[self class] defaultAttributes] objectForKey:@"timestamp"];
	return [messageAttributes objectForKey:@"timestamp"];
}

- (NSMutableDictionary *)timedeltaAttributes
{
	if (messageAttributes == nil)
		return [[[self class] defaultAttributes] objectForKey:@"timedelta"];
	return [messageAttributes objectForKey:@"timedelta"];
}

- (NSMutableDictionary *)threadIDAttributes
{
	if (messageAttributes == nil)
		return [[[self class] defaultAttributes] objectForKey:@"threadID"];
	return [messageAttributes objectForKey:@"threadID"];
}

- (NSMutableDictionary *)tagAttributes
{
	if (messageAttributes == nil)
		return [[[self class] defaultAttributes] objectForKey:@"tag"];
	return [messageAttributes objectForKey:@"tag"];	
}

- (NSMutableDictionary *)levelAttributes
{
	if (messageAttributes == nil)
		return [[[self class] defaultAttributes] objectForKey:@"level"];
	return [messageAttributes objectForKey:@"level"];
}

- (NSMutableDictionary *)messageTextAttributes
{
	if (messageAttributes == nil)
		return [[[self class] defaultAttributes] objectForKey:@"text"];
	return [messageAttributes objectForKey:@"text"];
}

- (NSMutableDictionary *)messageDataAttributes
{
	if (messageAttributes == nil)
		return [[[self class] defaultAttributes] objectForKey:@"data"];
	return [messageAttributes objectForKey:@"data"];
}

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
	
	// Draw cell background and separators
	if (!highlighted)
	{
		CGColorRef cellBgColor = CGColorCreateGenericGray(0.96f, 1.0f);
		CGContextSetFillColorWithColor(ctx, cellBgColor);
		CGContextFillRect(ctx, NSRectToCGRect(cellFrame));
		CGColorRelease(cellBgColor);
	}
	CGContextSetShouldAntialias(ctx, false);
	CGContextSetLineWidth(ctx, 1.0f);
	CGContextSetLineCap(ctx, kCGLineCapSquare);
	CGColorRef cellSeparatorDark = CGColorCreateGenericGray(0.80f, 1.0f);
	CGContextSetStrokeColorWithColor(ctx, cellSeparatorDark);
	CGColorRelease(cellSeparatorDark);
	CGContextBeginPath(ctx);
	if (!highlighted)
	{
		// horizontal bottom separator
		CGContextMoveToPoint(ctx, NSMinX(cellFrame), floorf(NSMaxY(cellFrame)));
		CGContextAddLineToPoint(ctx, NSMaxX(cellFrame), floorf(NSMaxY(cellFrame)));
	}
	// timestamp/thread separator
	CGContextMoveToPoint(ctx, floorf(NSMinX(cellFrame) + TIMESTAMP_COLUMN_WIDTH), NSMinY(cellFrame));
	CGContextAddLineToPoint(ctx, floorf(NSMinX(cellFrame) + TIMESTAMP_COLUMN_WIDTH), floorf(NSMaxY(cellFrame)-2));
	// thread/message separator
	CGContextMoveToPoint(ctx, floorf(NSMinX(cellFrame) + TIMESTAMP_COLUMN_WIDTH + THREAD_COLUMN_WIDTH), NSMinY(cellFrame));
	CGContextAddLineToPoint(ctx, floorf(NSMinX(cellFrame) + TIMESTAMP_COLUMN_WIDTH + THREAD_COLUMN_WIDTH), floorf(NSMaxY(cellFrame)-2));
	CGContextStrokePath(ctx);
	CGContextSetShouldAntialias(ctx, true);
	
	// Draw timestamp and time delta column
	NSRect r, tr;
	r = NSMakeRect(NSMinX(cellFrame),
				   NSMinY(cellFrame),
				   TIMESTAMP_COLUMN_WIDTH,
				   NSHeight(cellFrame));
	CGContextSaveGState(ctx);
	CGContextClipToRect(ctx, NSRectToCGRect(r));
	tr = NSInsetRect(r, 2, 0);

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
		timeDeltaStr = StringWithTimeDelta(&td);

	NSMutableDictionary *attrs = [self timestampAttributes];
	NSRect bounds = [timestampStr boundingRectWithSize:tr.size
											   options:(NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading)
											attributes:attrs];
	NSRect timeRect = NSMakeRect(NSMinX(tr), NSMinY(tr), NSWidth(tr), NSHeight(bounds));
	NSRect deltaRect = NSMakeRect(NSMinX(tr), NSMaxY(timeRect)+1, NSWidth(tr), NSHeight(tr) - NSHeight(bounds) - 1);

	if (highlighted)
	{
		attrs = [[attrs mutableCopy] autorelease];
		[attrs setObject:highlightedTextColor forKey:NSForegroundColorAttributeName];
	}
	[timestampStr drawWithRect:timeRect
					   options:(NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading)
					attributes:attrs];

	attrs = [self timedeltaAttributes];
	if (highlighted)
	{
		attrs = [[attrs mutableCopy] autorelease];
		[attrs setObject:highlightedTextColor forKey:NSForegroundColorAttributeName];
	}
	[timeDeltaStr drawWithRect:deltaRect
					   options:NSStringDrawingUsesLineFragmentOrigin
					attributes:attrs];
	CGContextRestoreGState(ctx);

	// Draw thread ID
	attrs = [self threadIDAttributes];
	if (highlighted)
	{
		attrs = [[attrs mutableCopy] autorelease];
		[attrs setObject:highlightedTextColor forKey:NSForegroundColorAttributeName];
	}
	r = NSOffsetRect(r, TIMESTAMP_COLUMN_WIDTH, 0);
	r.size.width = THREAD_COLUMN_WIDTH;
	CGContextSaveGState(ctx);
	CGContextClipToRect(ctx, NSRectToCGRect(r));
	r.size.height = [message.threadID boundingRectWithSize:NSMakeSize(NSWidth(r), NSHeight(cellFrame))
												   options:NSStringDrawingUsesLineFragmentOrigin
												attributes:attrs].size.height;
	[message.threadID drawWithRect:NSInsetRect(r, 3, 0)
						   options:NSStringDrawingUsesLineFragmentOrigin
						attributes:attrs];

	// Draw tag and level, if provided
	NSString *tag = message.tag;
	int level = message.level;
	if ([tag length] || level)
	{
		NSSize tagSize = NSZeroSize;
		NSSize levelSize = NSZeroSize;
		NSString *levelString = nil;
		r.origin.y += NSHeight(r);
		if ([tag length])
		{
			tagSize = [tag boundingRectWithSize:NSMakeSize(THREAD_COLUMN_WIDTH, NSHeight(cellFrame) - NSHeight(r))
										options:NSStringDrawingUsesLineFragmentOrigin
									 attributes:[self tagAttributes]].size;
			tagSize.width += 4;
			tagSize.height += 2;
		}
		if (level)
		{
			levelString = [NSString stringWithFormat:@"%d", level];
			levelSize = [levelString boundingRectWithSize:NSMakeSize(THREAD_COLUMN_WIDTH, NSHeight(cellFrame) - NSHeight(r))
												  options:NSStringDrawingUsesLineFragmentOrigin
											   attributes:[self levelAttributes]].size;
			levelSize.width += 4;
			levelSize.height += 2;
		}
		CGFloat h = fmaxf(tagSize.height, levelSize.height);
		NSRect tagRect = NSMakeRect(NSMinX(r) + 3,
									NSMinY(r),
									tagSize.width,
									h);
		NSRect levelRect = NSMakeRect(NSMaxX(tagRect),
									  NSMinY(tagRect),
									  levelSize.width,
									  h);
		NSRect tagAndLevelRect = NSUnionRect(tagRect, levelRect);

		MakeRoundedPath(ctx, NSRectToCGRect(tagAndLevelRect), 3.0f);
		CGColorRef fillColor = CreateCGColorFromNSColor([[self class] colorForTag:tag]);
		CGContextSetFillColorWithColor(ctx, fillColor);
		CGColorRelease(fillColor);
		CGContextFillPath(ctx);
		if (levelSize.width)
		{
			CGColorRef black = CGColorCreateGenericGray(0.25f, 1.0f);
			CGContextSetFillColorWithColor(ctx, black);
			CGColorRelease(black);
			CGContextSaveGState(ctx);
			CGContextClipToRect(ctx, NSRectToCGRect(levelRect));
			MakeRoundedPath(ctx, NSRectToCGRect(tagAndLevelRect), 3.0f);
			CGContextFillPath(ctx);
			CGContextRestoreGState(ctx);
		}

		if (tagSize.width)
		{
			[tag drawWithRect:NSInsetRect(tagRect, 2, 1)
					  options:NSStringDrawingUsesLineFragmentOrigin
				   attributes:[self tagAttributes]];
		}
		if (levelSize.width)
		{
			[levelString drawWithRect:NSInsetRect(levelRect, 2, 1)
							  options:NSStringDrawingUsesLineFragmentOrigin
						   attributes:[self levelAttributes]];
		}
	}
	CGContextRestoreGState(ctx);

	// Draw message
	r = NSMakeRect(NSMinX(cellFrame) + TIMESTAMP_COLUMN_WIDTH + THREAD_COLUMN_WIDTH + 3,
				   NSMinY(cellFrame),
				   NSWidth(cellFrame) - (TIMESTAMP_COLUMN_WIDTH + THREAD_COLUMN_WIDTH) - 6,
				   NSHeight(cellFrame));

	if (message.contentsType == kMessageString)
	{
		attrs = [self messageTextAttributes];
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
		attrs = [self messageDataAttributes];
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
		r = NSInsetRect(r, 0, 1);
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
