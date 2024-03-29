/*
 * LoggerTCPConnection.m
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

#import "LoggerTCPConnection.h"

#define TMP_BUF_SIZE	((size_t)32767)

@implementation LoggerTCPConnection

@synthesize readStream, writeStream, buffer, tmpBuf, tmpBufSize;

- (id)initWithInputStream:(NSInputStream *)anInputStream outputStream:(NSOutputStream *)anOutputStream clientAddress:(NSData *)anAddress;
{
	if ((self = [super initWithAddress:anAddress]) != nil)
	{
		readStream = anInputStream;
        writeStream = anOutputStream;

		tmpBufSize = TMP_BUF_SIZE;
		tmpBuf = (uint8_t *)malloc(TMP_BUF_SIZE);
		if (tmpBuf == NULL)
			return nil;
		
		buffer = [[NSMutableData alloc] initWithCapacity:2048];
	}
	return self;
}

- (void)dealloc
{
	assert(readStream == nil);
	if (tmpBuf != NULL)
		free(tmpBuf);
}

- (void)shutdown
{
    if (writeStream != nil)
    {
        [writeStream close];
        [writeStream setDelegate:nil];
        [writeStream removeFromRunLoop:NSRunLoop.currentRunLoop forMode:NSDefaultRunLoopMode];
		writeStream = nil;
	}
	if (readStream != nil)
	{
		[readStream close];
		[readStream setDelegate:nil];
		[readStream removeFromRunLoop:NSRunLoop.currentRunLoop forMode:NSDefaultRunLoopMode];
		readStream = nil;
	}
	[buffer setLength:0];
	[super shutdown];
}

@end
