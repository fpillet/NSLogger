/*
 * Author: Andreas Linde <mail@andreaslinde.de>
 *         Kent Sutherland
 *
 * Copyright (c) 2012-2013 HockeyApp, Bit Stadium GmbH.
 * Copyright (c) 2011 Andreas Linde & Kent Sutherland.
 * All rights reserved.
 *
 * Permission is hereby granted, free of charge, to any person
 * obtaining a copy of this software and associated documentation
 * files (the "Software"), to deal in the Software without
 * restriction, including without limitation the rights to use,
 * copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following
 * conditions:
 *
 * The above copyright notice and this permission notice shall be
 * included in all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
 * EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES
 * OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
 * NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT
 * HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY,
 * WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR
 * OTHER DEALINGS IN THE SOFTWARE.
 */

#import <Cocoa/Cocoa.h>
#import <HockeySDK/BITCrashReportManagerDelegate.h>

// flags if the crashlog analyzer is started. since this may theoretically crash we need to track it
#define kHockeySDKAnalyzerStarted @"HockeySDKCrashReportAnalyzerStarted"

// stores the set of crashreports that have been approved but aren't sent yet
#define kHockeySDKApprovedCrashReports @"HockeySDKApprovedCrashReports"

// stores the user name entered in the UI
#define kHockeySDKUserName @"HockeySDKUserName"

// stores the user email address entered in the UI
#define kHockeySDKUserEmail @"HockeySDKUserEmail"


// flags if the crashreporter is activated at all
// set this as bool in user defaults e.g. in the settings, if you want to let the user be able to deactivate it
#define kHockeySDKCrashReportActivated @"HockeySDKCrashReportActivated"

// flags if the crashreporter should automatically send crashes without asking the user again
// set this as bool in user defaults e.g. in the settings, if you want to let the user be able to set this on or off
#define kHockeySDKAutomaticallySendCrashReports @"HockeySDKAutomaticallySendCrashReports"


// hockey api error domain
typedef enum {
  HockeyErrorUnknown,
  HockeyAPIAppVersionRejected,
  HockeyAPIReceivedEmptyResponse,
  HockeyAPIErrorWithStatusCode
} HockeyErrorReason;
extern NSString *const __attribute__((unused)) kHockeyErrorDomain;


typedef enum HockeyCrashAlertType {
  HockeyCrashAlertTypeSend = 0,
  HockeyCrashAlertTypeFeedback = 1,
} HockeyCrashAlertType;

typedef enum HockeyCrashReportStatus {  
  HockeyCrashReportStatusUnknown = 0,
  HockeyCrashReportStatusAssigned = 1,
  HockeyCrashReportStatusSubmitted = 2,
  HockeyCrashReportStatusAvailable = 3,
} HockeyCrashReportStatus;

@class BITCrashReportUI;

@interface BITCrashReportManager : NSObject {
  NSFileManager *_fileManager;

  BOOL _crashIdenticalCurrentVersion;
  BOOL _crashReportActivated;
  BOOL _exceptionInterceptionEnabled;
  
  NSTimeInterval _timeIntervalCrashInLastSessionOccured;
  NSTimeInterval _maxTimeIntervalOfCrashForReturnMainApplicationDelay;
  
  HockeyCrashReportStatus _serverResult;
  NSInteger         _statusCode;
  NSURLConnection   *_urlConnection;
  NSMutableData     *_responseData;

  id<BITCrashReportManagerDelegate> _delegate;

  NSString   *_appIdentifier;
  NSString   *_submissionURL;
  NSString   *_companyName;
  BOOL       _autoSubmitCrashReport;
  BOOL       _askUserDetails;
  
  NSString   *_userName;
  NSString   *_userEmail;
    
  NSMutableArray *_crashFiles;
  NSString       *_crashesDir;
  NSString       *_settingsFile;
  
  BITCrashReportUI *_crashReportUI;

  BOOL                _didCrashInLastSession;
  BOOL                _analyzerStarted;
  NSMutableDictionary *_approvedCrashReports;

  BOOL       _invokedReturnToMainApplication;
}

- (NSString *)modelVersion;

+ (BITCrashReportManager *)sharedCrashReportManager;

// The HockeyApp app identifier (required)
@property (nonatomic, retain) NSString *appIdentifier;

// defines if Uncaught Exception Interception should be used, default to NO
@property (nonatomic, assign) BOOL exceptionInterceptionEnabled;

// defines if the user interface should ask for name and email, default to NO
@property (nonatomic, assign) BOOL askUserDetails;

// defines the company name to be shown in the crash reporting dialog
@property (nonatomic, retain) NSString *companyName;

// defines the users name or user id
@property (nonatomic, copy) NSString *userName;

// defines the users email address
@property (nonatomic, copy) NSString *userEmail;

// delegate is required
@property (nonatomic, assign) id <BITCrashReportManagerDelegate> delegate;

// Indicates if the app crash in the previous session
@property (nonatomic, readonly) BOOL didCrashInLastSession;

// if YES, the crash report will be submitted without asking the user
// if NO, the user will be asked if the crash report can be submitted (default)
@property (nonatomic, assign, getter=isAutoSubmitCrashReport) BOOL autoSubmitCrashReport;

// Defines the maximum time interval after the app start and the crash, that will cause showing the app window after sending is complete instead of with the start of the sending process. Default is 5 seconds.
@property (nonatomic, readwrite) NSTimeInterval maxTimeIntervalOfCrashForReturnMainApplicationDelay;

- (void)returnToMainApplication;
- (void)startManager;

- (void)cancelReport;
- (void)sendReportWithCrash:(NSString*)crashFile crashDescription:(NSString *)crashDescription;

@end
