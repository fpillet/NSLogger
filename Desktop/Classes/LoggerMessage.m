/*
 * LoggerMessage.m
 *
 * BSD license follows (http://www.opensource.org/licenses/bsd-license.php)
 * 
 * Copyright (c) 2010-2018 Florent Pillet <fpillet@gmail.com> All Rights Reserved.
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
#import <objc/runtime.h>
#import "LoggerMessage.h"
#import "LoggerCommon.h"
#import "LoggerConnection.h"

static NSString *emptyTag = @"";
static NSMutableArray *sTags = nil;

@implementation LoggerMessage

- (id)init
{
	if ((self = [super init]) != nil)
	{
		_tag = emptyTag;
		_filename = @"";
		_functionName = @"";
	}
	return self;
}

- (NSImage *)image
{
	if (self.contentsType != kMessageImage)
		return nil;
	if (_image == nil)
		_image = [[NSImage alloc] initWithData:_message];
	return _image;
}

- (NSSize)imageSize
{
	if (_imageSize.width == 0 || _imageSize.height == 0)
		_imageSize = self.image.size;
	return _imageSize;
}

- (NSString *)textRepresentation
{
	// Prepare a text representation of the message, suitable for export of text field display
	time_t sec = _timestamp.tv_sec;
	struct tm *t = localtime(&sec);

	if (_contentsType == kMessageString)
	{
		if (_type == LOGMSG_TYPE_MARK)
			return [NSString stringWithFormat:@"%@\n", _message];

		/* commmon case */
		
		// if message is empty, use the function name (typical case of using a log to record
		// a "waypoint" in the code flow)
		NSString *s = _message;
		if (![s length] && [_functionName length])
			s = _functionName;

		return [NSString stringWithFormat:@"[%-8lu] %02d:%02d:%02d.%03d | %@ | %@ | %@\n",
				_sequence,
				t->tm_hour, t->tm_min, t->tm_sec, _timestamp.tv_usec / 1000,
				(_tag == NULL) ? @"-" : _tag,
				_threadID,
				s];
	}
	
	NSString *header = [NSString stringWithFormat:@"[%-8lu] %02d:%02d:%02d.%03d | %@ | %@ | ",
						_sequence, t->tm_hour, t->tm_min, t->tm_sec, _timestamp.tv_usec / 1000,
						(_tag == NULL) ? @"-" : _tag,
						_threadID];

	if (_contentsType == kMessageImage)
		return [NSString stringWithFormat:@"%@IMAGE size=%dx%d px\n", header, (int)self.imageSize.width, (int)self.imageSize.height];

	assert([_message isKindOfClass:[NSData class]]);
	NSMutableString *s = [[NSMutableString alloc] init];
	[s appendString:header];
	NSUInteger offset = 0, dataLen = [(NSData *)_message length];
	NSString *str;
	int offsetPad = (int)ceil(ceil(log2f(dataLen)) / 4.f);
	char buffer[1+offsetPad+2+16*3+1+16+1+1+1];
	buffer[0] = '\0';
	const unsigned char *q = [(NSData *)_message bytes];
	if (dataLen == 1)
		[s appendString:NSLocalizedString(@"Raw data, 1 byte:\n", @"")];
	else
		[s appendFormat:NSLocalizedString(@"Raw data, %u bytes:\n", @""), dataLen];
	while (dataLen)
	{
		int i, b = sprintf(buffer, " %0*x: ", offsetPad, (unsigned)offset);
		for (i=0; i < 16 && i < dataLen; i++)
			sprintf(&buffer[b+3*i], "%02x ", (int)q[i]);
		for (int j=i; j < 16; j++)
			strcat(buffer, "   ");
		
		b = (int)strlen(buffer);
		buffer[b++] = '\'';
		for (i=0; i < 16 && i < dataLen; i++)
		{
			if (q[i] >= 32 && q[i] < 128)
				buffer[b++] = q[i];
			else
				buffer[b++] = ' ';
		}
		for (int j=i; j < 16; j++)
			buffer[b++] = ' ';
		buffer[b++] = '\'';
		buffer[b++] = '\n';
		buffer[b] = 0;
		
		str = [[NSString alloc] initWithBytes:buffer length:strlen(buffer) encoding:NSISOLatin1StringEncoding];
		[s appendString:str];

		dataLen -= i;
		offset += i;
		q += i;
	}
	return s;
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark NSCoding
// -----------------------------------------------------------------------------
- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]) != nil)
	{
		_timestamp.tv_sec = (__darwin_time_t)[decoder decodeInt64ForKey:@"s"];
		_timestamp.tv_usec = (__darwin_suseconds_t)[decoder decodeInt64ForKey:@"us"];
		_parts = [decoder decodeObjectForKey:@"p"];
		_message = [decoder decodeObjectForKey:@"m"];
		_sequence = [decoder decodeIntForKey:@"n"];
		_threadID = [decoder decodeObjectForKey:@"t"];
		_level = [decoder decodeIntForKey:@"l"];
		_type = [decoder decodeIntForKey:@"mt"];
		_contentsType = [decoder decodeIntForKey:@"ct"];
		
		// reload the filename / function name / line number. Since this is a pool
		// kept by the LoggerConnection itself, we use the runtime's associated objects
		// feature to get a hold on the LoggerConnection object
		LoggerConnection *cnx = objc_getAssociatedObject(decoder, &sConnectionAssociatedObjectKey);
		NSString *s = [decoder decodeObjectForKey:@"f"];
		if (s != nil)
			[self setFilename:s connection:cnx];
		else
			_filename = @"";
		s = [decoder decodeObjectForKey:@"fn"];
		if (s != nil)
			[self setFunctionName:s connection:cnx];
		else
			_functionName = @"";
		_lineNumber = [decoder decodeIntForKey:@"ln"];

		self.tag = [decoder decodeObjectForKey:@"tag"];
	}
	return self;
}

- (void)encodeWithCoder:(NSCoder *)encoder
{
	// try to omit info with zero value to save space when saving
	[encoder encodeInt64:_timestamp.tv_sec forKey:@"s"];
	[encoder encodeInt64:_timestamp.tv_usec forKey:@"us"];
	if ([_tag length])
		[encoder encodeObject:_tag forKey:@"tag"];
	if (_parts != nil)
		[encoder encodeObject:_parts forKey:@"p"];
	if (_message != nil)
		[encoder encodeObject:_message forKey:@"m"];
	[encoder encodeInt:(int)_sequence forKey:@"n"];
	if ([_threadID length])
		[encoder encodeObject:_threadID forKey:@"t"];
	if (_level)
		[encoder encodeInt:_level forKey:@"l"];
	if (_type)
		[encoder encodeInt:_type forKey:@"mt"];
	if (_contentsType)
		[encoder encodeInt:_contentsType forKey:@"ct"];
	if (_filename != nil)
		[encoder encodeObject:_filename forKey:@"f"];
	if (_functionName != nil)
		[encoder encodeObject:_functionName forKey:@"fn"];
	if (_lineNumber != 0)
		[encoder encodeInt:_lineNumber forKey:@"ln"];
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark NSCopying
// -----------------------------------------------------------------------------
- (id)copyWithZone:(NSZone *)zone
{
	// Used only for displaying, we can afford not providing a real copy here
    return self;
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Special methods for use by predicates
// -----------------------------------------------------------------------------
- (NSString *)messageText
{
	if (_contentsType == kMessageString)
		return _message;
	return @"";
}

- (NSString *)messageType
{
	if (_contentsType == kMessageString)
		return @"text";
	if (_contentsType == kMessageData)
		return @"data";
	return @"img";
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Other
// -----------------------------------------------------------------------------
- (void)setTag:(NSString *)aTag
{
	// we're accumulating the various domains in a global list
	// so as to reduce memory use
	if (aTag == nil)
		return;
	NSUInteger pos = [sTags indexOfObject:aTag];
	if (pos == NSNotFound || sTags == nil)
	{
		if (sTags == nil)
			sTags = [[NSMutableArray alloc] init];
		[sTags addObject:aTag];
		_tag = aTag;
	}
	else
		_tag = [sTags objectAtIndex:pos];
}

- (void)setFilename:(NSString *)aFilename connection:(LoggerConnection *)aConnection
{
	NSString *s = [aConnection.filenames member:aFilename];
	if (s == nil)
	{
		[aConnection.filenames addObject:aFilename];
		_filename = aFilename;
	}
	else
		_filename = s;
}

- (void)setFunctionName:(NSString *)aFunctionName connection:(LoggerConnection *)aConnection
{
	NSString *s = [aConnection.functionNames member:aFunctionName];
	if (s == nil)
	{
		[aConnection.functionNames addObject:aFunctionName];
		_functionName = aFunctionName;
	}
	else
		_functionName = s;
}

- (void)computeTimeDelta:(struct timeval *)td since:(LoggerMessage *)previousMessage
{
	assert(previousMessage != NULL);
	double t1 = (double)_timestamp.tv_sec + ((double)_timestamp.tv_usec) / 1000000.0;
	double t2 = (double)previousMessage->_timestamp.tv_sec + ((double)previousMessage->_timestamp.tv_usec) / 1000000.0;
	double t = t1 - t2;
	td->tv_sec = (__darwin_time_t)t;
	td->tv_usec = (__darwin_suseconds_t)((t - (double)td->tv_sec) * 1000000.0);
}

-(NSString *)description
{
	NSString *typeString = ((_type == LOGMSG_TYPE_LOG) ? @"Log" :
							(_type == LOGMSG_TYPE_CLIENTINFO) ? @"ClientInfo" :
							(_type == LOGMSG_TYPE_DISCONNECT) ? @"Disconnect" :
							(_type == LOGMSG_TYPE_BLOCKSTART) ? @"BlockStart" :
							(_type == LOGMSG_TYPE_BLOCKEND) ? @"BlockEnd" :
							(_type == LOGMSG_TYPE_MARK) ? @"Mark" :
							@"Unknown");
	NSString *desc;
	if (_contentsType == kMessageData)
		desc = [NSString stringWithFormat:@"{data %u bytes}", (unsigned)[_message length]];
	else if (_contentsType == kMessageImage)
		desc = [NSString stringWithFormat:@"{image w=%d h=%d}", (int)[self imageSize].width, (int)[self imageSize].height];
	else
		desc = (NSString *)_message;
	
	return [NSString stringWithFormat:@"<%@ %p seq=%d type=%@ thread=%@ tag=%@ level=%d message=%@>",
			[self class], self, (int)_sequence, typeString, _threadID, _tag, (int)_level, desc];
}

@end
