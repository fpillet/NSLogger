/*
 * LoggerMessage.m
 *
 * BSD license follows (http://www.opensource.org/licenses/bsd-license.php)
 * 
 * Copyright (c) 2010-2011 Florent Pillet <fpillet@gmail.com> All Rights Reserved.
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

static NSMutableArray *sTags = nil;

@implementation LoggerMessage

//@synthesize tag, message, threadID;
//@synthesize type, contentsType, level, timestamp;
//@synthesize parts;
//@synthesize cachedCellSize, image, imageSize;
//@synthesize filename, functionName, lineNumber;

@synthesize imageSize = _imageSize;

- (id) init
{
	if ((self = [super init]) != nil)
	{
		_filename = @"";
		_functionName = @"";
	}
	return self;
}

- (void)dealloc
{
}

- (NSImage *)image
{
	if (self.contentsType != kMessageImage)
		return nil;
	if (self.image == nil)
		self.image = [[NSImage alloc] initWithData:self.message];
	return self.image;
}

- (NSSize)imageSize
{
	if (self.imageSize.width == 0 || self.imageSize.height == 0)
		_imageSize = self.image.size;
	return _imageSize;
}

- (NSString *)textRepresentation
{
	// Prepare a text representation of the message, suitable for export of text field display
	time_t sec = self.timestamp.tv_sec;
	struct tm *t = localtime(&sec);

	if (self.contentsType == kMessageString)
	{
		if (self.type == LOGMSG_TYPE_MARK)
			return [NSString stringWithFormat:@"%@\n", self.message];

		/* commmon case */
		
		// if message is empty, use the function name (typical case of using a log to record
		// a "waypoint" in the code flow)
		NSString *s = self.message;
		if (![s length] && [self.functionName length])
			s = self.functionName;

		return [NSString stringWithFormat:@"[%-8lu] %02d:%02d:%02d.%03d | %@ | %@ | %@\n",
				sequence,
				t->tm_hour, t->tm_min, t->tm_sec, self.timestamp.tv_usec / 1000,
				(self.tag == NULL) ? @"-" : self.tag,
				self.threadID,
				self.message];
	}
	
	NSString *header = [NSString stringWithFormat:@"[%-8lu] %02d:%02d:%02d.%03d | %@ | %@ | ",
						sequence, t->tm_hour, t->tm_min, t->tm_sec, self.timestamp.tv_usec / 1000,
						(self.tag == NULL) ? @"-" : self.tag,
						self.threadID];

	if (self.contentsType == kMessageImage)
		return [NSString stringWithFormat:@"%@IMAGE size=%dx%d px\n", header, (int)self.imageSize.width, (int)self.imageSize.height];

	assert([self.message isKindOfClass:[NSData class]]);
	NSMutableString *s = [[NSMutableString alloc] init];
	[s appendString:header];
	NSUInteger offset = 0, dataLen = [self.message length];
	NSString *str;
	char buffer[1+6+16*3+1+16+1+1+1];
	buffer[0] = '\0';
	const unsigned char *q = [self.message bytes];
	if (dataLen == 1)
		[s appendString:NSLocalizedString(@"Raw data, 1 byte:\n", @"")];
	else
		[s appendFormat:NSLocalizedString(@"Raw data, %u bytes:\n", @""), dataLen];
	while (dataLen)
	{
		int i, b = sprintf(buffer," %04x: ", offset);
		for (i=0; i < 16 && i < dataLen; i++)
			sprintf(&buffer[b+3*i], "%02x ", (int)q[i]);
		for (int j=i; j < 16; j++)
			strcat(buffer, "   ");
		
		b = strlen(buffer);
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

- (void)_setImageSize:(CGSize)aSize
{
    _imageSize = aSize;
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark NSCoding
// -----------------------------------------------------------------------------
- (id)initWithCoder:(NSCoder *)decoder
{
	if ((self = [super init]) != nil)
	{
        _timestamp.tv_sec = [decoder decodeInt64ForKey:@"s"];
		_timestamp.tv_usec = [decoder decodeInt64ForKey:@"us"];
		self.parts = [decoder decodeObjectForKey:@"p"];
		self.message = [decoder decodeObjectForKey:@"m"];
		sequence = [decoder decodeIntForKey:@"n"];
		self.threadID = [decoder decodeObjectForKey:@"t"];
		self.level = [decoder decodeIntForKey:@"l"];
		self.type = [decoder decodeIntForKey:@"mt"];
		self.contentsType = [decoder decodeIntForKey:@"ct"];
		
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
	[encoder encodeInt64:self.timestamp.tv_sec forKey:@"s"];
	[encoder encodeInt64:self.timestamp.tv_usec forKey:@"us"];
	if ([self.tag length])
		[encoder encodeObject:self.tag forKey:@"tag"];
	if (self.parts != nil)
		[encoder encodeObject:self.parts forKey:@"p"];
	if (self.message != nil)
		[encoder encodeObject:self.message forKey:@"m"];
	[encoder encodeInt:sequence forKey:@"n"];
	if ([self.threadID length])
		[encoder encodeObject:self.threadID forKey:@"t"];
	if (self.level)
		[encoder encodeInt:self.level forKey:@"l"];
	if (self.type)
		[encoder encodeInt:self.type forKey:@"mt"];
	if (self.contentsType)
		[encoder encodeInt:self.contentsType forKey:@"ct"];
	if (self.filename != nil)
		[encoder encodeObject:self.filename forKey:@"f"];
	if (self.functionName != nil)
		[encoder encodeObject:self.functionName forKey:@"fn"];
	if (self.lineNumber != 0)
		[encoder encodeInt:self.lineNumber forKey:@"ln"];
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
	if (self.contentsType == kMessageString)
		return self.message;
	return @"";
}

- (NSString *)messageType
{
	if (self.contentsType == kMessageString)
		return @"text";
	if (self.contentsType == kMessageData)
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

#ifdef DEBUG
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
	if (self.contentsType == kMessageData)
		desc = [NSString stringWithFormat:@"{data %lu bytes}", (unsigned long)[self.message length]];
	else if (self.contentsType == kMessageImage)
		desc = [NSString stringWithFormat:@"{image w=%d h=%d}", (int)self.imageSize.width, (int)self.imageSize.height];
	else
		desc = (NSString *)self.message;
	
	return [NSString stringWithFormat:@"<%@ %p seq=%lu type=%@ thread=%@ tag=%@ level=%d message=%@>",
			[self class], self, (unsigned long)sequence, typeString, self.threadID, self.tag, (int)self.level, desc];
}
#endif

@end
