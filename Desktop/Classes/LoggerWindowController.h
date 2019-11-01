/*
 * LoggerWindowController.h
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
#import "LoggerConnection.h"
#import "BWToolkitFramework.h"

@class LoggerMessageCell, LoggerClientInfoCell, LoggerMarkerCell, LoggerTableView, LoggerSplitView;
@class LoggerDetailsWindowController;

@interface LoggerWindowController : NSWindowController <NSWindowDelegate, LoggerConnectionDelegate, NSTableViewDataSource, NSTableViewDelegate, NSSplitViewDelegate>
{
	BOOL _showFunctionNames;
}

@property (nonatomic, weak) IBOutlet LoggerTableView *logTable;
@property (nonatomic, weak) IBOutlet NSTableView *filterSetsTable;
@property (nonatomic, weak) IBOutlet NSTableView *filterTable;
@property (nonatomic, weak) IBOutlet NSPopUpButton *quickFilter;
@property (nonatomic, weak) IBOutlet NSButton *showFunctionNamesButton;
@property (nonatomic, weak) IBOutlet NSSearchField *quickFilterTextField;

@property (nonatomic, retain) IBOutlet NSArrayController *filterSetsListController;
@property (nonatomic, retain) IBOutlet NSArrayController *filterListController;

@property (nonatomic, retain) IBOutlet NSWindow *filterEditorWindow;
@property (nonatomic, retain) IBOutlet NSPredicateEditor *filterEditor;
@property (nonatomic, retain) IBOutlet NSTextField *filterName;

@property (nonatomic, retain) IBOutlet NSWindow *markTitleWindow;
@property (nonatomic, retain) IBOutlet NSTextField *markTitleField;
@property (nonatomic, retain) IBOutlet LoggerSplitView *splitView;

@property (nonatomic, retain) LoggerDetailsWindowController *detailsWindowController;

@property (nonatomic, retain) LoggerConnection *attachedConnection;
@property (nonatomic, assign) BOOL messagesSelected;
@property (nonatomic, assign) BOOL hasQuickFilter;
@property (nonatomic, assign) BOOL initialRefreshDone;
@property (nonatomic, assign) BOOL clientAppSettingsRestored;
@property (nonatomic, retain) NSNumber* showFunctionNames;
@property (nonatomic, assign) int lastMessageRow;

@property (nonatomic, retain) NSString *filterString;
@property (nonatomic, retain) NSMutableSet *filterTags;
@property (nonatomic, assign) int logLevel;

@property (nonatomic, retain) NSString *info;
@property (nonatomic, retain) NSMutableArray *displayedMessages;
@property (nonatomic, retain) NSMutableSet *tags;

@property (nonatomic, retain) NSPredicate *filterPredicate;				// created from current selected filters, + quick filter string / tag / log level
@property (nonatomic, retain) LoggerMessageCell *messageCell;
@property (nonatomic, retain) LoggerClientInfoCell *clientInfoCell;
@property (nonatomic, retain) LoggerMarkerCell *markerCell;

@property (nonatomic, assign) CGFloat threadColumnWidth;

@property (nonatomic, retain) dispatch_queue_t messageFilteringQueue;
@property (nonatomic, retain) dispatch_group_t lastTilingGroup;

- (IBAction)openDetailsWindow:(id)sender;

- (IBAction)selectQuickFilterTag:(id)sender;
- (IBAction)selectQuickFilterLevel:(id)sender;
- (IBAction)resetQuickFilter:(id)sender;

- (IBAction)addFilterSet:(id)sender;
- (IBAction)deleteSelectedFilterSet:(id)sender;

- (IBAction)addFilter:(id)sender;
- (IBAction)startEditingFilter:(id)sender;
- (IBAction)cancelFilterEdition:(id)sender;
- (IBAction)validateFilterEdition:(id)sender;
- (IBAction)deleteSelectedFilters:(id)sender;
- (IBAction)createNewFilterFromQuickFilter:(id) sender;

- (IBAction)addMark:(id)sender;
- (IBAction)addMarkWithTitle:(id)sender;
- (IBAction)insertMarkWithTitle:(id)sender;
- (IBAction)cancelAddMark:(id)sender;
- (IBAction)validateAddMark:(id)sender;
- (IBAction)deleteMark:(id)sender;

- (IBAction)clearCurrentLog:(id)sender;
- (IBAction)clearAllLogs:(id)sender;

- (void)updateMenuBar:(BOOL)documentIsFront;

@end

@interface LoggerTableView : NSTableView
{
}
@end

#define	DEFAULT_THREAD_COLUMN_WIDTH	85.0f


