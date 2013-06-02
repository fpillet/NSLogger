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

@protocol BITCrashReportManagerDelegate;

@interface BITHockeyManager : NSObject {
@private
  NSString *_appIdentifier;
  NSString *_companyName;
  
  BOOL _loggingEnabled;
  BOOL _exceptionInterceptionEnabled;
  BOOL _askUserDetails;
  
  NSTimeInterval _maxTimeIntervalOfCrashForReturnMainApplicationDelay;
}

#pragma mark - Public Properties

@property (nonatomic, readonly) NSString *appIdentifier;

// Enable debug logging; ONLY ENABLE THIS FOR DEBUGGING!
//
// Default: NO
@property (nonatomic, assign, getter=isLoggingEnabled) BOOL loggingEnabled;

// Enable catching uncaught exceptions and let them crash the app and get a crash report
//
// Default: NO
@property (nonatomic, assign, getter=isExceptionInterceptionEnabled) BOOL exceptionInterceptionEnabled;


// defines if the user interface should ask for name and email
//
// Default: NO
@property (nonatomic, assign) BOOL askUserDetails;

// Defines the maximum time interval after the app start and the crash, that will cause showing the app window after sending is complete instead of with the start of the sending process. Default is 5 seconds.
@property (nonatomic, readwrite) NSTimeInterval maxTimeIntervalOfCrashForReturnMainApplicationDelay;

#pragma mark - Public Methods

// Returns the shared manager object
+ (BITHockeyManager *)sharedHockeyManager;

// Configure HockeyApp with a single app identifier and delegate; use this
// only for debug or beta versions of your app!
- (void)configureWithIdentifier:(NSString *)newAppIdentifier companyName:(NSString *)newCompanyName crashReportManagerDelegate:(id <BITCrashReportManagerDelegate>) crashReportManagerDelegate;

- (void)startManager;

@end
