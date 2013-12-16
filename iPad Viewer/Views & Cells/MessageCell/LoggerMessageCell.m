/*
 *
 * Modified BSD license.
 *
 * Based on
 * Copyright (c) 2010-2011 Florent Pillet <fpillet@gmail.com>
 * Copyright (c) 2008 Loren Brichter,
 *
 * Copyright (c) 2012-2013 Sung-Taek, Kim <stkim1@colorfulglue.com> All Rights
 * Reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * 3. Any redistribution is done solely for personal benefit and not for any
 *    commercial purpose or for monetary gain
 *
 * 4. No binary form of source code is submitted to App Store℠ of Apple Inc.
 *
 * 5. Neither the name of the Sung-Taek, Kim nor the names of its contributors
 *    may be used to endorse or promote products derived from  this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR  IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL COPYRIGHT HOLDER AND AND CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *
 */

#import "LoggerMessageCell.h"

NSString * const kMessageCellReuseID = @"messageCell";
UIFont *displayDefaultFont = nil;
UIFont *displayTagAndLevelFont = nil;
UIFont *displayMonospacedFont = nil;

UIColor *defaultBackgroundColor = nil;
UIColor *defaultTagAndLevelColor = nil;

//#define USE_UIKIT_FOR_DRAWING

@interface LoggerMessageView : UIView
@end
@implementation LoggerMessageView
- (void)drawRect:(CGRect)aRect
{
	[(LoggerMessageCell *)[self superview] drawMessageView:aRect];
}
@end

@implementation LoggerMessageCell
{
	CTFrameRef _messageframe;
}
@synthesize hostTableView = _hostTableView;
@synthesize messageData = _messageData;
@synthesize imageData = _imageData;

+(void)initialize
{
	if(displayDefaultFont == nil)
	{
		displayDefaultFont =
			[[UIFont
			  fontWithName:kDefaultFontName
			  size:DEFAULT_FONT_SIZE] retain];
	}
	
	if(displayTagAndLevelFont == nil)
	{
		displayTagAndLevelFont =
			[[UIFont
			  fontWithName:kTagAndLevelFontName
			  size:DEFAULT_TAG_LEVEL_SIZE] retain];
	}
	
	if(displayMonospacedFont == nil)
	{
		displayMonospacedFont =
			[[UIFont
			  fontWithName:kMonospacedFontName
			  size:DEFAULT_MONOSPACED_SIZE] retain];
	}
	
	if(defaultBackgroundColor == nil)
	{
		defaultBackgroundColor =
			[[UIColor
			 colorWithRed:DEAFULT_BACKGROUND_GRAY_VALUE
			 green:DEAFULT_BACKGROUND_GRAY_VALUE
			 blue:DEAFULT_BACKGROUND_GRAY_VALUE
			 alpha:1] retain];
	}
	
	if(defaultTagAndLevelColor == nil)
	{
		defaultTagAndLevelColor =
			[[UIColor
			  colorWithRed:0.51f
			  green:0.57f
			  blue:0.79f
			  alpha:1.0f] retain];
	}
}

+ (UIColor *)colorForTag:(NSString *)tag
{
	// @@@ TODO: tag color customization mechanism
	return defaultTagAndLevelColor;
}

-(id)initWithPreConfig
{
	return
		[self
		 initWithStyle:UITableViewCellStyleDefault
		 reuseIdentifier:kMessageCellReuseID];
}

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier
{
    self = [super initWithStyle:style reuseIdentifier:reuseIdentifier];
    if (self)
	{
		self.accessoryType = UITableViewCellAccessoryNone;
		_messageView = [[LoggerMessageView alloc] initWithFrame:CGRectZero];
		_messageView.opaque = YES;
		[self addSubview:_messageView];
		[_messageView release];
    }
    return self;
}

-(void)dealloc
{
	self.hostTableView = nil;
	self.messageData = nil;
	self.imageData = nil;

	[super dealloc];
}

- (void)setFrame:(CGRect)aFrame
{
	[super setFrame:aFrame];
	CGRect bound = [self bounds];

	// leave room for the seperator line
	//CGRect messageFrame = CGRectInset(bound, 0, 1);

	[_messageView setFrame:bound];
}

- (void)setNeedsDisplay
{
	[super setNeedsDisplay];
	[_messageView setNeedsDisplay];
}

- (void)setNeedsDisplayInRect:(CGRect)rect
{
	[super setNeedsDisplayInRect:rect];
	[_messageView setNeedsDisplayInRect:rect];
}


#if 0
- (void)setNeedsLayout
{
	[super setNeedsLayout];
	[_messageView setNeedsLayout];
}
#endif

-(void)prepareForReuse
{
	[super prepareForReuse];
	
	
	if([self.messageData dataType] == kMessageImage)
	{
		[self.messageData cancelImageForCell:self];
	}

	self.imageData = nil;
	self.messageData = nil;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated
{
    [super setSelected:selected animated:animated];
    // Configure the view for the selected state
}

-(void)setupForIndexpath:(NSIndexPath *)anIndexPath
			 messageData:(LoggerMessageData *)aMessageData
{
	self.messageData = aMessageData;
	self.imageData = nil;

	if([aMessageData dataType] == kMessageImage)
	{
		[aMessageData imageForCell:self];
	}

	[self setNeedsDisplay];
}

// draw image data from ManagedObject model (LoggerMessage)
-(void)setImagedata:(NSData *)anImageData forRect:(CGRect)aRect
{
	// in case this cell is detached from tableview,
	if(self.superview == nil)
	{
		return;
	}
	
	UIImage *image = [[UIImage alloc] initWithData:anImageData];
	self.imageData = image;
	[image release],image = nil;
	
	//[self setNeedsDisplayInRect:aRect];
	[self setNeedsDisplay];
}

//------------------------------------------------------------------------------
#pragma mark - Drawing
//------------------------------------------------------------------------------
- (void)drawTimestampAndDeltaInRect:(CGRect)aDrawRect
			   highlightedTextColor:(UIColor *)aHighlightedTextColor
{
	// Draw timestamp and time delta column
	CGContextRef context = UIGraphicsGetCurrentContext();
	CGContextSaveGState(context);
	
	// flip context vertically
	CGContextSetTextMatrix(context, CGAffineTransformIdentity);
	CGContextTranslateCTM(context, 0, self.bounds.size.height);
	CGContextScaleCTM(context, 1.0, -1.0);

	// clip context
	CGContextClipToRect(context, aDrawRect);
	CGRect tr = CGRectInset(aDrawRect, 2, 2);
	
	
	NSString *s = self.messageData.timestampString;
	CFRange textRange = CFRangeMake(0, s.length);
	
	//  Create an empty mutable string big enough to hold our test
	CFMutableAttributedStringRef as = CFAttributedStringCreateMutable(kCFAllocatorDefault, s.length);
	
	//  Inject our text into it
	CFAttributedStringReplaceString(as, CFRangeMake(0, 0), (CFStringRef) s);
	
	CTFontRef f = [[LoggerTextStyleManager sharedStyleManager] defaultFont];
	CTParagraphStyleRef p = [[LoggerTextStyleManager sharedStyleManager] defaultParagraphStyle];
	
	//  Apply our font and line spacing attributes over the span
	CFAttributedStringSetAttribute(as, textRange, kCTFontAttributeName, f);
	CFAttributedStringSetAttribute(as, textRange, kCTParagraphStyleAttributeName, p);
	
	
	CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString(as);
	CGMutablePathRef path = CGPathCreateMutable();
	CGPathAddRect(path, NULL, tr);
	
	CTFrameRef frame = \
	CTFramesetterCreateFrame(framesetter, CFRangeMake(0, CFAttributedStringGetLength(as)), path, NULL);
	
	CFRelease(path);
	CFRelease(framesetter);
	CFRelease(as);
	
	
	CTFrameDraw(frame, context);
	CFRelease(frame);
	
	CGContextRestoreGState(context);
}

- (void)drawThreadIDAndTagInRect:(CGRect)aDrawRect
			highlightedTextColor:(UIColor *)aHighlightedTextColor
{
	// Draw timestamp and time delta column
	CGContextRef context = UIGraphicsGetCurrentContext();
	CGContextSaveGState(context);
	
	
	// flip coordinate system upside-down
	// flip context vertically
	CGContextSetTextMatrix(context, CGAffineTransformIdentity);
	CGContextTranslateCTM(context, 0, self.bounds.size.height);
	CGContextScaleCTM(context, 1.0, -1.0);
	
	// clip context
	CGContextClipToRect(context, aDrawRect);
	
#if 0
	
	CGRect r = aDrawRect;
	/*
	 // Draw thread ID
	 NSMutableDictionary *attrs = [self threadIDAttributes];
	 if (aHighlightedTextColor != nil)
	 {
	 attrs = [[attrs mutableCopy] autorelease];
	 [attrs setObject:highlightedTextColor forKey:NSForegroundColorAttributeName];
	 }
	 */

	CGSize threadBounds =
		[self.messageData.threadID
		 sizeWithFont:displayDefaultFont
		 forWidth:r.size.width
		 lineBreakMode:NSLineBreakByWordWrapping];

	r.size.height = threadBounds.height;
	
	[[UIColor grayColor] set];

	[self.messageData.threadID
	 drawInRect:CGRectInset(r, 3, 0)
	 withFont:displayDefaultFont
	 lineBreakMode:NSLineBreakByWordWrapping
	 alignment:NSTextAlignmentLeft];
#endif

	
	NSString *s = self.messageData.threadID;
	CFRange textRange = CFRangeMake(0, s.length);
	
	//  Create an empty mutable string big enough to hold our test
	CFMutableAttributedStringRef as = CFAttributedStringCreateMutable(kCFAllocatorDefault, s.length);
	
	//  Inject our text into it
	CFAttributedStringReplaceString(as, CFRangeMake(0, 0), (CFStringRef) s);
	
	CTFontRef f = [[LoggerTextStyleManager sharedStyleManager] defaultTagAndLevelFont];
	CTParagraphStyleRef p = [[LoggerTextStyleManager sharedStyleManager] defaultTagAndLevelParagraphStyle];

	//  Apply our font and line spacing attributes over the span
	CFAttributedStringSetAttribute(as, textRange, kCTFontAttributeName, f);
	CFAttributedStringSetAttribute(as, textRange, kCTParagraphStyleAttributeName, p);
	
	CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString(as);
	CGMutablePathRef path = CGPathCreateMutable();
	CGPathAddRect(path, NULL, CGRectInset(aDrawRect, 3, 0));
	
	CTFrameRef frame = \
	CTFramesetterCreateFrame(framesetter, CFRangeMake(0, CFAttributedStringGetLength(as)), path, NULL);
	
	CFRelease(path);
	CFRelease(framesetter);
	CFRelease(as);
	
	
	CTFrameDraw(frame, context);
	CFRelease(frame);
	
	
	
	
	
	
	
	
#if 0
	
	// Draw tag and level, if provided
	NSString *tag = self.messageData.tag;
	int level = [self.messageData.level intValue];
	if ([tag length] || level)
	{
		CGFloat threadColumnWidth = DEFAULT_THREAD_COLUMN_WIDTH;
		CGSize tagSize = CGSizeZero;
		CGSize levelSize = CGSizeZero;
		NSString *levelString = nil;
		r.origin.y += CGRectGetHeight(r);
		
		// set tag,level text color
		[[UIColor whiteColor] set];

		if ([tag length])
		{
			tagSize =
				[tag
				 sizeWithFont:displayTagAndLevelFont
				 forWidth:threadColumnWidth
				 lineBreakMode:NSLineBreakByWordWrapping];
			
			tagSize.width += 4;
			tagSize.height += 2;
		}
		
		if (level)
		{
			levelString = [NSString stringWithFormat:@"%d", level];
			
			levelSize =
				[levelString
				 sizeWithFont:displayTagAndLevelFont
				 forWidth:threadColumnWidth
				 lineBreakMode:NSLineBreakByWordWrapping];
			
			
			levelSize.width += 4;
			levelSize.height += 2;
		}
		
		CGFloat h = fmaxf(tagSize.height, levelSize.height);
		
		
		
		CGRect tagRect = CGRectMake(CGRectGetMinX(r) + 3,
									CGRectGetMinY(r),
									tagSize.width,h);

		CGRect levelRect = CGRectMake(CGRectGetMaxX(tagRect),
									  CGRectGetMinY(tagRect),
									  levelSize.width,h);

		CGRect tagAndLevelRect = CGRectUnion(tagRect, levelRect);
		
		MakeRoundedPath(context, tagAndLevelRect, 3.0f);
		CGColorRef fillColor = [[LoggerMessageCell colorForTag:tag] CGColor];
		CGContextSetFillColorWithColor(context, fillColor);
		CGContextFillPath(context);
		
		if (levelSize.width)
		{
			UIColor *black = GRAYCOLOR(0.25f);
			CGContextSaveGState(context);
			CGContextSetFillColorWithColor(context, [black CGColor]);
			CGContextClipToRect(context,levelRect);
			MakeRoundedPath(context, tagAndLevelRect, 3.0f);
			CGContextFillPath(context);
			CGContextRestoreGState(context);
		}

		// set text color
		[[UIColor whiteColor] set];
		
		if (tagSize.width)
		{
			[tag
			 drawInRect:CGRectInset(tagRect, 2, 1)
			 withFont:displayTagAndLevelFont
			 lineBreakMode:NSLineBreakByWordWrapping
			 alignment:NSTextAlignmentLeft];
		}

		if (levelSize.width)
		{
			[levelString
			 drawInRect:CGRectInset(levelRect, 2, 1)
			 withFont:displayTagAndLevelFont
			 lineBreakMode:NSLineBreakByWordWrapping
			 alignment:NSTextAlignmentRight];
		}
	}

#endif

	CGSize threadBounds = [LoggerTextStyleManager
						   sizeForStringWithDefaultTagAndLevelFont:self.messageData.threadID
						   constraint:aDrawRect.size];
	
	
	CGRect r = aDrawRect;
	r.size.height = threadBounds.height;	
	
	// Draw tag and level, if provided
	NSString *tag = self.messageData.tag;
	int level = [self.messageData.level intValue];
	if ([tag length] || level)
	{
		CGFloat threadColumnWidth = DEFAULT_THREAD_COLUMN_WIDTH;
		CGSize tagSize = CGSizeZero;
		CGSize levelSize = CGSizeZero;
		NSString *levelString = nil;
		r.origin.y += CGRectGetHeight(r);
		
		// set tag,level text color
		[[UIColor whiteColor] set];
		
		if ([tag length])
		{
			tagSize =
			[tag
			 sizeWithFont:displayTagAndLevelFont
			 forWidth:threadColumnWidth
			 lineBreakMode:NSLineBreakByWordWrapping];
			
			tagSize.width += 4;
			tagSize.height += 2;
		}
		
		if (level)
		{
			levelString = [NSString stringWithFormat:@"%d", level];
			
			levelSize =
			[levelString
			 sizeWithFont:displayTagAndLevelFont
			 forWidth:threadColumnWidth
			 lineBreakMode:NSLineBreakByWordWrapping];
			
			
			levelSize.width += 4;
			levelSize.height += 2;
		}
		
		CGFloat h = fmaxf(tagSize.height, levelSize.height);
		
		
		
		CGRect tagRect = CGRectMake(CGRectGetMinX(r) + 3,
									CGRectGetMinY(r),
									tagSize.width,h);
		
		CGRect levelRect = CGRectMake(CGRectGetMaxX(tagRect),
									  CGRectGetMinY(tagRect),
									  levelSize.width,h);
		
		CGRect tagAndLevelRect = CGRectUnion(tagRect, levelRect);
		
		MakeRoundedPath(context, tagAndLevelRect, 3.0f);
		CGColorRef fillColor = [[LoggerMessageCell colorForTag:tag] CGColor];
		CGContextSetFillColorWithColor(context, fillColor);
		CGContextFillPath(context);
		
		if (levelSize.width)
		{
			UIColor *black = GRAYCOLOR(0.25f);
			CGContextSaveGState(context);
			CGContextSetFillColorWithColor(context, [black CGColor]);
			CGContextClipToRect(context,levelRect);
			MakeRoundedPath(context, tagAndLevelRect, 3.0f);
			CGContextFillPath(context);
			CGContextRestoreGState(context);
		}
		
		// set text color
		[[UIColor whiteColor] set];
		
		if (tagSize.width)
		{
			[tag
			 drawInRect:CGRectInset(tagRect, 2, 1)
			 withFont:displayTagAndLevelFont
			 lineBreakMode:NSLineBreakByWordWrapping
			 alignment:NSTextAlignmentLeft];
		}
		
		if (levelSize.width)
		{
			[levelString
			 drawInRect:CGRectInset(levelRect, 2, 1)
			 withFont:displayTagAndLevelFont
			 lineBreakMode:NSLineBreakByWordWrapping
			 alignment:NSTextAlignmentRight];
		}
	}

	
	
	CGContextRestoreGState(context);
}


- (void)drawMessageInRect:(CGRect)aDrawRect
	 highlightedTextColor:(UIColor *)aHighlightedTextColor
{
	CGContextRef context = UIGraphicsGetCurrentContext();
	CGContextSaveGState(context);

	NSString *s = [self.messageData textRepresentation];

	switch([self.messageData dataType])
	{
		case kMessageString:{

			CGContextSetTextMatrix(context, CGAffineTransformIdentity);
			CGContextTranslateCTM(context, 0, self.bounds.size.height);
			CGContextScaleCTM(context, 1.0, -1.0);

			CFRange textRange = CFRangeMake(0, s.length);
			
			//  Create an empty mutable string big enough to hold our test
			CFMutableAttributedStringRef as = CFAttributedStringCreateMutable(kCFAllocatorDefault, s.length);
			
			//  Inject our text into it
			CFAttributedStringReplaceString(as, CFRangeMake(0, 0), (CFStringRef) s);

			CTFontRef f = [[LoggerTextStyleManager sharedStyleManager] defaultFont];
			CTParagraphStyleRef p = [[LoggerTextStyleManager sharedStyleManager] defaultParagraphStyle];
			
			//  Apply our font and line spacing attributes over the span
			CFAttributedStringSetAttribute(as, textRange, kCTFontAttributeName, f);
			CFAttributedStringSetAttribute(as, textRange, kCTParagraphStyleAttributeName, p);


			CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString(as);
			CGMutablePathRef path = CGPathCreateMutable();
			CGPathAddRect(path, NULL, aDrawRect);

			CTFrameRef frame = \
				CTFramesetterCreateFrame(framesetter, CFRangeMake(0, CFAttributedStringGetLength(as)), path, NULL);
			
			CFRelease(path);
			CFRelease(framesetter);
			CFRelease(as);

			CTFrameDraw(frame, context);
			CFRelease(frame);

			break;
		}
		case kMessageData: {
			
			CGContextSetTextMatrix(context, CGAffineTransformIdentity);
			CGContextTranslateCTM(context, 0, self.bounds.size.height);
			CGContextScaleCTM(context, 1.0, -1.0);
			
			CFRange textRange = CFRangeMake(0, s.length);
			
			//  Create an empty mutable string big enough to hold our test
			CFMutableAttributedStringRef as = CFAttributedStringCreateMutable(kCFAllocatorDefault, s.length);
			
			//  Inject our text into it
			CFAttributedStringReplaceString(as, CFRangeMake(0, 0), (CFStringRef) s);
			
			CTFontRef f = [[LoggerTextStyleManager sharedStyleManager] defaultMonospacedFont];
			CTParagraphStyleRef p = [[LoggerTextStyleManager sharedStyleManager] defaultMonospacedStyle];
			
			//  Apply our font and line spacing attributes over the span
			CFAttributedStringSetAttribute(as, textRange, kCTFontAttributeName, f);
			CFAttributedStringSetAttribute(as, textRange, kCTParagraphStyleAttributeName, p);
			
			CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString(as);
			CGMutablePathRef path = CGPathCreateMutable();
			CGPathAddRect(path, NULL, aDrawRect);
			
			CTFrameRef frame = \
				CTFramesetterCreateFrame(framesetter, CFRangeMake(0, CFAttributedStringGetLength(as)), path, NULL);
			
			CTFrameDraw(frame, context);
			
			CFRelease(path);
			CFRelease(frame);
			CFRelease(framesetter);
			CFRelease(as);

			break;
		}
		case kMessageImage: {
			if(_imageData != nil)
			{
				//TODO:: drawing UIImage takes too much CPU time. find a way to fix it.
				CGRect r = CGRectInset(aDrawRect, 0, 1);
				CGSize srcSize = [_imageData size];
				CGFloat ratio = fmaxf(1.0f, fmaxf(srcSize.width / CGRectGetWidth(r), srcSize.height / CGRectGetHeight(r)));
				CGSize newSize = CGSizeMake(floorf(srcSize.width / ratio), floorf(srcSize.height / ratio));
				//CGRect imageRect = (CGRect){{CGRectGetMinX(r),CGRectGetMinY(r) + CGRectGetHeight(r)},newSize};
				CGRect imageRect = (CGRect){{CGRectGetMinX(r),CGRectGetMinY(r)},newSize};
				[self.imageData drawInRect:imageRect];
				
				self.imageData = nil;
			}
			break;
		}
		default:
			break;
	}
	
	CGContextRestoreGState(context);
	
}

- (void)drawMessageView:(CGRect)cellFrame
{
	CGContextRef context = UIGraphicsGetCurrentContext();
	
	// turn antialiasing off
	CGContextSetShouldAntialias(context, false);

	//fill background with generic gray in value of 0.97f
	UIColor *backgroundColor = defaultBackgroundColor;
	[backgroundColor set];
	
	
	//TODO:: this single call represent 2% of CPU time. find a way to replace it.
	CGContextFillRect(context, cellFrame);
	
	
	// Draw separators
	CGContextSetLineWidth(context, 1.0f);
	CGContextSetLineCap(context, kCGLineCapSquare);
	UIColor *cellSeparatorColor = GRAYCOLOR(0.8f);
#if 0
	if (highlighted)
		cellSeparatorColor = CGColorCreateGenericGray(1.0f, 1.0f);
	else
		cellSeparatorColor = CGColorCreateGenericGray(0.80f, 1.0f);
#endif

	CGContextSetStrokeColorWithColor(context, [cellSeparatorColor CGColor]);
	CGContextBeginPath(context);

	// top ceiling line
	CGContextMoveToPoint(context, CGRectGetMinX(cellFrame), floorf(CGRectGetMinY(cellFrame)));
	CGContextAddLineToPoint(context, CGRectGetMaxX(cellFrame), floorf(CGRectGetMinY(cellFrame)));
	
	// bottom floor line
	CGContextMoveToPoint(context, CGRectGetMinX(cellFrame), floorf(CGRectGetMaxY(cellFrame)));
	CGContextAddLineToPoint(context, CGRectGetMaxX(cellFrame), floorf(CGRectGetMaxY(cellFrame)));

	
	// timestamp/thread separator
	CGContextMoveToPoint(context, floorf(CGRectGetMinX(cellFrame) + TIMESTAMP_COLUMN_WIDTH), CGRectGetMinY(cellFrame));
	CGContextAddLineToPoint(context, floorf(CGRectGetMinX(cellFrame) + TIMESTAMP_COLUMN_WIDTH), floorf(CGRectGetMaxY(cellFrame)-1));
	
	// thread/message separator
	CGFloat threadColumnWidth = DEFAULT_THREAD_COLUMN_WIDTH;
	
	CGContextMoveToPoint(context, floorf(CGRectGetMinX(cellFrame) + TIMESTAMP_COLUMN_WIDTH + threadColumnWidth), CGRectGetMinY(cellFrame));
	CGContextAddLineToPoint(context, floorf(CGRectGetMinX(cellFrame) + TIMESTAMP_COLUMN_WIDTH + threadColumnWidth), floorf(CGRectGetMaxY(cellFrame)-1));
	CGContextStrokePath(context);
    
	// restore antialiasing
	CGContextSetShouldAntialias(context, true);
	
	
	// Draw timestamp and time delta column
	CGRect drawRect = CGRectMake(CGRectGetMinX(cellFrame),
						  CGRectGetMinY(cellFrame),
						  TIMESTAMP_COLUMN_WIDTH,
						  CGRectGetHeight(cellFrame));

	[self drawTimestampAndDeltaInRect:drawRect highlightedTextColor:nil];
	
	// Draw thread ID and tag
	drawRect = CGRectMake(CGRectGetMinX(cellFrame) + TIMESTAMP_COLUMN_WIDTH,
				   CGRectGetMinY(cellFrame),
				   DEFAULT_THREAD_COLUMN_WIDTH,
				   CGRectGetHeight(cellFrame));

	[self drawThreadIDAndTagInRect:drawRect highlightedTextColor:nil];
	

	// Draw message
	drawRect =
		CGRectMake(CGRectGetMinX(cellFrame) + (TIMESTAMP_COLUMN_WIDTH + DEFAULT_THREAD_COLUMN_WIDTH + MSG_CELL_LEFT_PADDING),
				   CGRectGetMinY(cellFrame) + MSG_CELL_TOP_PADDING,
				   CGRectGetWidth(cellFrame) - (TIMESTAMP_COLUMN_WIDTH + DEFAULT_THREAD_COLUMN_WIDTH + MSG_CELL_SIDE_PADDING),
				   CGRectGetHeight(cellFrame) - MSG_CELL_TOP_BOTTOM_PADDING);
		
	[self drawMessageInRect:drawRect highlightedTextColor:nil];	
}
@end
