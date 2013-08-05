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

#import "LoggerTextStyleManager.h"
#import "SynthesizeSingleton.h"
#import "NullStringCheck.h"

@interface LoggerTextStyleManager()
+(CGSize)_sizeForString:(NSString *)aString
			 constraint:(CGSize)aConstraint
				   font:(CTFontRef)aFont
				  style:(CTParagraphStyleRef)aStyle;
@end

@implementation LoggerTextStyleManager
SYNTHESIZE_SINGLETON_FOR_CLASS_WITH_ACCESSOR(LoggerTextStyleManager,sharedStyleManager);

@synthesize defaultFont = _defaultFont;
@synthesize defaultParagraphStyle = _defaultParagraphStyle;

@synthesize defaultTagAndLevelFont = _defaultTagAndLevelFont;
@synthesize defaultTagAndLevelParagraphStyle = _defaultTagAndLevelParagraphStyle;

@synthesize defaultMonospacedFont = _defaultMonospacedFont;
@synthesize defaultMonospacedStyle = _defaultMonospacedStyle;

+(CGSize)_sizeForString:(NSString *)aString constraint:(CGSize)aConstraint font:(CTFontRef)aFont style:(CTParagraphStyleRef)aStyle
{
	
	// calcuate string drawable size
	CFRange textRange = CFRangeMake(0, aString.length);
	
	//  Create an empty mutable string big enough to hold our test
	CFMutableAttributedStringRef string = CFAttributedStringCreateMutable(kCFAllocatorDefault, aString.length);
	
	//  Inject our text into it
	CFAttributedStringReplaceString(string, CFRangeMake(0, 0), (CFStringRef)aString);
	
	//  Apply our font and line spacing attributes over the span
	CFAttributedStringSetAttribute(string, textRange, kCTFontAttributeName, aFont);
	CFAttributedStringSetAttribute(string, textRange, kCTParagraphStyleAttributeName, aStyle);
	
	CTFramesetterRef framesetter = CTFramesetterCreateWithAttributedString(string);
	CFRange fitRange;
	
	CGSize frameSize = CTFramesetterSuggestFrameSizeWithConstraints(framesetter, textRange, NULL, aConstraint, &fitRange);
	
	CFRelease(framesetter);
	CFRelease(string);

	return frameSize;
}


+(CGSize)sizeForStringWithDefaultFont:(NSString *)aString constraint:(CGSize)aConstraint
{
	if(IS_NULL_STRING(aString))
		return CGSizeZero;
	
	CTFontRef font = [[LoggerTextStyleManager sharedStyleManager] defaultFont];
	CTParagraphStyleRef style = [[LoggerTextStyleManager sharedStyleManager] defaultParagraphStyle];

	return [LoggerTextStyleManager
			_sizeForString:aString
			constraint:aConstraint
			font:font
			style:style];
}

+(CGSize)sizeForStringWithDefaultTagAndLevelFont:(NSString *)aString constraint:(CGSize)aConstraint
{
	if(IS_NULL_STRING(aString))
		return CGSizeZero;

	CTFontRef font = [[LoggerTextStyleManager sharedStyleManager] defaultTagAndLevelFont];
	CTParagraphStyleRef style = [[LoggerTextStyleManager sharedStyleManager] defaultTagAndLevelParagraphStyle];
	
	return [LoggerTextStyleManager
			_sizeForString:aString
			constraint:aConstraint
			font:font
			style:style];
}

+(CGSize)sizeForStringWithDefaultMonospacedFont:(NSString *)aString constraint:(CGSize)aConstraint
{
	if(IS_NULL_STRING(aString))
		return CGSizeZero;

	CTFontRef font = [[LoggerTextStyleManager sharedStyleManager] defaultMonospacedFont];
	CTParagraphStyleRef style = [[LoggerTextStyleManager sharedStyleManager] defaultMonospacedStyle];

	return [LoggerTextStyleManager
			_sizeForString:aString
			constraint:aConstraint
			font:font
			style:style];
}

-(id)init
{
	self = [super init];
	if(self)
	{
		CTTextAlignment alignment = kCTTextAlignmentLeft;
		
		//-------------------------- default font ------------------------------
		// we're to use system default helvetica to get a cover for UTF-8 chars, emoji, and many more.
		_defaultFont =  CTFontCreateWithName(CFSTR("Helvetica"),DEFAULT_FONT_SIZE, NULL);
		
		//http://stackoverflow.com/questions/3374591/ctframesettersuggestframesizewithconstraints-sometimes-returns-incorrect-size
		//  When you create an attributed string the default paragraph style has a leading
		//  of 0.0. Create a paragraph style that will set the line adjustment equal to
		//  the leading value of the font.
		CGFloat defaultLeading = CTFontGetLeading(_defaultFont) + CTFontGetDescent(_defaultFont);
		
		CTParagraphStyleSetting defaultStyle[2] = {
			{kCTParagraphStyleSpecifierLineSpacingAdjustment, sizeof (CGFloat), &defaultLeading }
			,{kCTParagraphStyleSpecifierAlignment,sizeof(CTTextAlignment),&alignment}
		};

		_defaultParagraphStyle = CTParagraphStyleCreate(defaultStyle, 2);



		//-------------------------- tag and level font ------------------------
		// in ios, no Lucida Sans. we're going with 'Telugu Sangman MN'
		_defaultTagAndLevelFont =  CTFontCreateWithName(CFSTR("TeluguSangamMN"), DEFAULT_TAG_LEVEL_SIZE, NULL);

		CGFloat tagLevelLeading = CTFontGetLeading(_defaultTagAndLevelFont) + CTFontGetDescent(_defaultTagAndLevelFont);
		
		CTParagraphStyleSetting tagLevelStyle[2] = {
			{kCTParagraphStyleSpecifierLineSpacingAdjustment, sizeof (CGFloat), &tagLevelLeading }
			,{kCTParagraphStyleSpecifierAlignment,sizeof(CTTextAlignment),&alignment}
		};

		_defaultTagAndLevelParagraphStyle = CTParagraphStyleCreate(tagLevelStyle, 2);
		
		
		
		//-------------------------- monospaced font ---------------------------
		// this is for binary, so we're to go with cusom font
		NSString *fontPath =
			[NSString stringWithFormat:@"%@/%@"
			 ,[[NSBundle mainBundle] bundlePath]
			 ,@"NSLoggerResource.bundle/fonts/Inconsolata.ttf"];
		
		CGDataProviderRef fontProvider = CGDataProviderCreateWithFilename([fontPath UTF8String]);
		CGFontRef cgFont = CGFontCreateWithDataProvider(fontProvider);
		_defaultMonospacedFont = CTFontCreateWithGraphicsFont(cgFont,DEFAULT_MONOSPACED_SIZE,NULL,NULL);
		
		CGFloat monospacedLeading = CTFontGetLeading(_defaultMonospacedFont) + CTFontGetDescent(_defaultMonospacedFont);
		
		CTParagraphStyleSetting monospacedStyle[2] = {
			{kCTParagraphStyleSpecifierLineSpacingAdjustment, sizeof (CGFloat), &monospacedLeading }
			,{kCTParagraphStyleSpecifierAlignment,sizeof(CTTextAlignment),&alignment}
		};

		_defaultMonospacedStyle = CTParagraphStyleCreate(monospacedStyle, 2);
		
		CGDataProviderRelease(fontProvider);
		CFRelease(cgFont);

	}
	return self;
}
@end
