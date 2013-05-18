/*
 *
 * Modified BSD license.
 *
 * Based on source code copyright (c) 2010-2012 Florent Pillet,
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

#import "LoggerMessageSize.h"
#import "LoggerMessage.h"

UIFont			*measureDefaultFont = nil;
UIFont			*measureTagAndLevelFont = nil;
UIFont			*measureMonospacedFont = nil;
NSString		*hintForLongText = nil;
NSString		*hintForLargeData = nil;

@implementation LoggerMessageSize
+ (void)initialize
{
	// load font resource and reuse it throughout app's lifecycle
	// since these font will never go out on main thread for drawing,
	// it is fine to do that
	if(measureDefaultFont == nil)
	{
		measureDefaultFont = \
			[[UIFont fontWithName:kDefaultFontName size:DEFAULT_FONT_SIZE] retain];
	}
	
	if(measureTagAndLevelFont == nil)
	{
		measureTagAndLevelFont = \
			[[UIFont fontWithName:kTagAndLevelFontName size:DEFAULT_TAG_LEVEL_SIZE] retain];
	}
	
	if(measureMonospacedFont == nil)
	{
		measureMonospacedFont = \
			[[UIFont fontWithName:kMonospacedFontName size:DEFAULT_MONOSPACED_SIZE] retain];
	}
	
	// hint text should be short, and small at the bottom so that its size,
	// especially the width, won't exceed the smallest possible width, the portrait width
	
	if(hintForLongText == nil)
	{
		hintForLongText = [NSLocalizedString(kBottomHintText, nil) retain];
	}

	if(hintForLargeData == nil)
	{
		hintForLargeData = [NSLocalizedString(kBottomHintData, nil) retain];
	}
}


+ (CGFloat)minimumHeightForCellOnWidth:(CGFloat)aWidth
{
	UIFont *defaultSizedFont = measureDefaultFont;
	UIFont *tagAndLevelFont  = measureTagAndLevelFont;
	
	CGSize r1 = [@"10:10:10.256"
				 sizeWithFont:defaultSizedFont
				 forWidth:aWidth
				 lineBreakMode:NSLineBreakByWordWrapping];
	
	CGSize r2 = [@"+999ms"
				 sizeWithFont:defaultSizedFont
				 forWidth:aWidth
				 lineBreakMode:NSLineBreakByWordWrapping];
	
	CGSize r3 = [@"Main Thread"
				 sizeWithFont:defaultSizedFont
				 forWidth:aWidth
				 lineBreakMode:NSLineBreakByWordWrapping];
	
	CGSize r4 = [@"qWTy"
				 sizeWithFont:tagAndLevelFont
				 forWidth:aWidth
				 lineBreakMode:NSLineBreakByWordWrapping];
		
	return fmaxf((r1.height + r2.height), (r3.height + r4.height)) + 4;
}

+ (CGFloat)sizeOfFileLineFunctionOnWidth:(CGFloat)aWidth
{
	UIFont *tagAndLevelFont  = measureTagAndLevelFont;
	
	CGSize r = [@"file:100 funcQyTg"
				sizeWithFont:tagAndLevelFont
				forWidth:aWidth
				lineBreakMode:NSLineBreakByWordWrapping];
	
	return r.height + MSG_CELL_TOP_BOTTOM_PADDING;
}

+ (CGSize)sizeOfMessage:(LoggerMessage * const)aMessage
				maxWidth:(CGFloat)aMaxWidth
			   maxHeight:(CGFloat)aMaxHeight
{
	CGFloat minimumHeight = \
		[LoggerMessageSize minimumHeightForCellOnWidth:aMaxWidth];

	UIFont *monospacedFont   = measureMonospacedFont;
	CGSize sz = CGSizeMake(aMaxWidth,aMaxHeight);
	CGSize const maxConstraint = CGSizeMake(aMaxWidth,aMaxHeight);
	
	switch (aMessage.contentsType)
	{
		case kMessageString: {
			
			NSString *s = aMessage.textRepresentation;
			
			// calcuate string drawable size
			CGSize lr = [s
						 sizeWithFont:monospacedFont
						 constrainedToSize:maxConstraint
						 lineBreakMode:NSLineBreakByWordWrapping];


			sz.height = fminf(lr.height, sz.height);
			break;
		}

		case kMessageData: {
			NSUInteger numBytes = [(NSData *)aMessage.message length];
			int nLines = (numBytes >> 4) + ((numBytes & 15) ? 1 : 0) + 1;
			if (nLines > MAX_DATA_LINES)
				nLines = MAX_DATA_LINES + 1;
			CGSize lr = [@"000:"
						 sizeWithFont:monospacedFont
						 constrainedToSize:maxConstraint
						 lineBreakMode:NSLineBreakByWordWrapping];

			sz.height = lr.height * nLines;
			break;
		}

		case kMessageImage: {
			// approximate, compute ratio then refine height
			CGSize imgSize = aMessage.imageSize;
			CGFloat ratio = fmaxf(1.0f, fmaxf(imgSize.width / sz.width, imgSize.height / (sz.height / 2.0f)));
			sz.height = ceilf(imgSize.height / ratio);
			
			break;
		}
		default:
			break;
	}

	//CGFloat displayHeight = sz.height + MSG_CELL_TOP_BOTTOM_PADDING;
	sz.height = fmaxf(sz.height, minimumHeight);

	// return calculated drawing size
	return sz;
}

+ (CGSize)sizeOfHint:(LoggerMessage * const)aMessage
			maxWidth:(CGFloat)aMaxWidth
		   maxHeight:(CGFloat)aMaxHeight
{
	UIFont *monospacedFont   = measureMonospacedFont;
	CGSize sz = CGSizeMake(aMaxWidth,aMaxHeight);
	CGSize const maxConstraint = CGSizeMake(aMaxWidth,aMaxHeight);
	
	switch (aMessage.contentsType)
	{
		case kMessageString: {
			
			CGSize hr =\
				[hintForLongText
				 sizeWithFont:monospacedFont
				 constrainedToSize:maxConstraint
				 lineBreakMode:NSLineBreakByWordWrapping];

			sz.height = fminf(hr.height, sz.height);
			break;
		}
			
		case kMessageData: {
			
			CGSize hr =\
				[hintForLargeData
				 sizeWithFont:monospacedFont
				 constrainedToSize:maxConstraint
				 lineBreakMode:NSLineBreakByWordWrapping];

			sz.height = fminf(hr.height, sz.height);
			break;
		}

		case kMessageImage:
		default:
			break;
	}

	// return calculated drawing size
	return sz;
}


+ (CGSize)sizeOfFileLineFunctionOfMessage:(LoggerMessage * const)aMessage
								   onWidth:(CGFloat)aWidth
{
	return CGSizeZero;
}


@end
