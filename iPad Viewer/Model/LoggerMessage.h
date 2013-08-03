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

#include <time.h>
#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

#import "LoggerCommon.h"
#import "LoggerConstModel.h"

@class LoggerConnection;

@interface LoggerMessage : NSObject
{
	struct timeval				timestamp;		// full timestamp (seconds & microseconds)
    
	NSString					*tag;
	NSString					*filename;
	NSString					*functionName;
	NSMutableDictionary			*parts;			// for non-standard parts transmitted by the clients, store the data in this dictionary
	id							message;		// NSString, NSData or image data
	UIImage						*image;			// if the message is an image, the image gets decoded once it's being accessed
    
	NSUInteger					sequence;		// message's number if order of reception
    
	NSString					*threadID;
    
	int							lineNumber;		// line number in the file, if filename != nil
    
	short						level;
	short						type;
	short						contentsType;	// the type of message data (string, data, image)
    
	// unsaved cached data
	CGSize						imageSize;

	NSString					*_timestampString;
	NSString					*_textRepresentation; // text representation of this message

	// stkim1 Apr.04,2013
	// width of cells in iOS version is fixed so we can pre-calculate and cache
	// heights for two orientations at messageProcessingQueue of LoggerConnection
	BOOL						_truncated;
	CGSize						_portraitMessageSize;
	CGSize						_portraitHintSize;

	CGSize						_landscapeMessageSize;
	CGSize						_landscapeHintSize;
	
	
}
@property (nonatomic, assign) struct timeval		timestamp;
@property (nonatomic, retain) NSString				*tag;
@property (nonatomic, retain) NSString				*filename;
@property (nonatomic, retain) NSString				*functionName;
@property (nonatomic, retain) NSDictionary			*parts;
@property (nonatomic, retain) id					message;
@property (nonatomic, retain) UIImage				*image;
@property (nonatomic, readonly) NSUInteger			sequence;
@property (nonatomic, retain) NSString				*threadID;
@property (nonatomic, assign) int					lineNumber;
@property (nonatomic, assign) short					level;
@property (nonatomic, assign) short					type;
@property (nonatomic, assign) short					contentsType;
@property (nonatomic, readonly) CGSize				imageSize;
@property (nonatomic, readonly) NSString			*timestampString;
@property (nonatomic, readonly) NSString			*textRepresentation;
@property (nonatomic, readonly) NSString			*messageText;
@property (nonatomic, readonly) NSString			*messageType;

@property (nonatomic, readonly, getter = isTruncated) BOOL truncated;
@property (nonatomic, readonly) CGFloat				portraitHeight;
@property (nonatomic, readonly) CGSize				portraitMessageSize;
@property (nonatomic, readonly) CGSize				portraitHintSize;
@property (nonatomic, readonly) CGFloat				landscapeHeight;
@property (nonatomic, readonly) CGSize				landscapeMessageSize;
@property (nonatomic, readonly) CGSize				landscapeHintSize;


- (void)formatMessage;
- (void)makeTerminalMessage;

- (void)computeTimeDelta:(struct timeval *)td since:(LoggerMessage *)previousMessage;
@end