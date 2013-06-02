// 
//  Author: Andreas Linde <mail@andreaslinde.de>
// 
//  Copyright (c) 2012-2013 HockeyApp, Bit Stadium GmbH. All rights reserved.
//  See LICENSE.txt for author information.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

#import <HockeySDK/BITHockeyManager.h>
#import <HockeySDK/BITCrashReportManager.h>
#import <HockeySDK/BITCrashReportManagerDelegate.h>
#import <HockeySDK/BITSystemProfile.h>

#ifndef HOCKEYSDK_IDENTIFIER
#define HOCKEYSDK_IDENTIFIER @"net.hockeyapp.sdk.mac"
#define HOCKEYSDK_SETTINGS @"BITCrashManager.plist"
#define HOCKEYSDK_BUNDLE [NSBundle bundleWithIdentifier:HOCKEYSDK_IDENTIFIER]
#define HockeySDKLocalizedString(key,comment) NSLocalizedStringFromTableInBundle(key, @"HockeySDK", HOCKEYSDK_BUNDLE, comment)
#define HockeySDKLog(fmt, ...) do { if([BITHockeyManager sharedHockeyManager].isLoggingEnabled) { NSLog((@"[HockeySDK] %s/%d " fmt), __PRETTY_FUNCTION__, __LINE__, ##__VA_ARGS__); }} while(0)
#endif
