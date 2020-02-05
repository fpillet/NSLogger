/*
 * LoggerWindowController.m
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
#import <sys/time.h>
#import "LoggerWindowController.h"
#import "LoggerDetailsWindowController.h"
#import "LoggerMessageCell.h"
#import "LoggerClientInfoCell.h"
#import "LoggerMarkerCell.h"
#import "LoggerMessage.h"
#import "LoggerAppDelegate.h"
#import "LoggerCommon.h"
#import "LoggerDocument.h"
#import "LoggerSplitView.h"
#import "LoggerUtils.h"

#define kMaxTableRowHeight @"maxTableRowHeight"

@interface LoggerWindowController ()
- (void)rebuildQuickFilterPopup;
- (void)updateClientInfo;
- (void)updateFilterPredicate;
- (void)refreshAllMessages:(NSArray *)selectMessages;
- (void)filterIncomingMessages:(NSArray *)messages withFilter:(NSPredicate *)aFilter tableFrameSize:(NSSize)tableFrameSize;
- (NSPredicate *)filterPredicateFromCurrentSelection;
- (void)tileLogTable:(BOOL)forceUpdate;
- (void)rebuildMarksSubmenu;
- (void)clearMarksSubmenu;
- (void)rebuildRunsSubmenu;
- (void)clearRunsSubmenu;
@end

static NSString * const kNSLoggerFilterPasteboardType = @"com.florentpillet.NSLoggerFilter";
static NSArray *sXcodeFileExtensions = nil;

@implementation LoggerWindowController

// -----------------------------------------------------------------------------
#pragma mark -
#pragma Standard NSWindowController stuff
// -----------------------------------------------------------------------------
- (id)initWithWindowNibName:(NSString *)nibName
{
	if ((self = [super initWithWindowNibName:nibName]) != nil)
	{
		_messageFilteringQueue = dispatch_queue_create("com.florentpillet.nslogger.messageFiltering", NULL);
		_displayedMessages = [[NSMutableArray alloc] initWithCapacity:4096];
		_tags = [[NSMutableSet alloc] init];
		_filterTags = [[NSMutableSet alloc] init];
		_threadColumnWidth = DEFAULT_THREAD_COLUMN_WIDTH;

		[self setShouldCloseDocument:YES];
	}
	return self;
}

- (void)dealloc
{
	[[NSUserDefaults standardUserDefaults] removeObserver:self forKeyPath:kMaxTableRowHeight];
	[NSObject cancelPreviousPerformRequestsWithTarget:self];

	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_filterSetsListController removeObserver:self forKeyPath:@"arrangedObjects"];
	[_filterSetsListController removeObserver:self forKeyPath:@"selectedObjects"];
	[_filterListController removeObserver:self forKeyPath:@"selectedObjects"];

    _logTable.delegate = nil;
    _logTable.dataSource = nil;
	_filterSetsTable.delegate = nil;
    _filterSetsTable.dataSource = nil;
	_filterTable.delegate = nil;
    _filterTable.dataSource = nil;
}

- (NSUndoManager *)undoManager
{
	return [self.document undoManager];
}

- (void)windowDidLoad
{
    if (sXcodeFileExtensions == nil) {
        sXcodeFileExtensions = @[@"m", @"mm", @"h", @"c", @"cp", @"cpp", @"hpp", @"swift"];
    }
    
	if ([[self window] respondsToSelector:@selector(setRestorable:)])
		[[self window] setRestorable:NO];

	_messageCell = [[LoggerMessageCell alloc] init];
	_clientInfoCell = [[LoggerClientInfoCell alloc] init];
	_markerCell = [[LoggerMarkerCell alloc] init];

	[_logTable setIntercellSpacing:NSMakeSize(0,0)];
	[_logTable setTarget:self];
	[_logTable setDoubleAction:@selector(logCellDoubleClicked:)];

	[_logTable registerForDraggedTypes:@[NSPasteboardTypeString]];
	[_logTable setDraggingSourceOperationMask:NSDragOperationNone forLocal:YES];
	[_logTable setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];

	[_filterSetsTable registerForDraggedTypes:@[kNSLoggerFilterPasteboardType]];
	[_filterSetsTable setIntercellSpacing:NSMakeSize(0, 0)];

	[_filterTable registerForDraggedTypes:@[kNSLoggerFilterPasteboardType]];
	[_filterTable setVerticalMotionCanBeginDrag:YES];
	[_filterTable setTarget:self];
	[_filterTable setIntercellSpacing:NSMakeSize(0,0)];
	[_filterTable setDoubleAction:@selector(startEditingFilter:)];

	[_filterSetsListController addObserver:self forKeyPath:@"arrangedObjects" options:0 context:NULL];
	[_filterSetsListController addObserver:self forKeyPath:@"selectedObjects" options:0 context:NULL];
	[_filterListController addObserver:self forKeyPath:@"selectedObjects" options:0 context:NULL];

    _splitView.delegate = self;

	[self rebuildQuickFilterPopup];
	[self updateFilterPredicate];
		
	[_logTable sizeToFit];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(applyFontChanges)
												 name:kMessageAttributesChangedNotification
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(tileLogTableNotification:)
												 name:@"TileLogTableNotification"
											   object:nil];
    
    [[NSUserDefaults standardUserDefaults] addObserver:self forKeyPath:kMaxTableRowHeight options:0 context:NULL];
}

- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName
{
	if ([self.document fileURL] != nil)
		return displayName;
	if (_attachedConnection.connected)
		return [_attachedConnection clientAppDescription];
	return [NSString stringWithFormat:NSLocalizedString(@"%@ (disconnected)", @""),
			[_attachedConnection clientDescription]];
}

- (void)updateClientInfo
{
	// Update the source label
	assert([NSThread isMainThread]);
	[self synchronizeWindowTitleWithDocumentName];
}

- (void)updateMenuBar:(BOOL)documentIsFront
{
	if (documentIsFront)
	{
		[self rebuildMarksSubmenu];
		[self rebuildRunsSubmenu];
	}
	else
	{
		[self clearRunsSubmenu];
		[self clearMarksSubmenu];
	}
}

- (void)tileLogTableMessages:(NSArray *)messages
					withSize:(NSSize)tableSize
				 forceUpdate:(BOOL)forceUpdate
					   group:(dispatch_group_t)group
{
	// check for cancellation
	if (group != NULL && dispatch_get_context(group) == NULL)
		return;

	NSMutableArray *updatedMessages = [[NSMutableArray alloc] initWithCapacity:[messages count]];
    NSSize maxCellSize = tableSize;
    NSInteger maxRowHeight = [[NSUserDefaults standardUserDefaults] integerForKey:kMaxTableRowHeight];
    if (maxRowHeight >= 30 && maxCellSize.height > maxRowHeight)
        maxCellSize.height = maxRowHeight;
    
	for (LoggerMessage *msg in messages)
	{
		// detect cancellation
		if (group != NULL && dispatch_get_context(group) == NULL)
			break;

		// compute size
		NSSize cachedSize = msg.cachedCellSize;
		if (forceUpdate || cachedSize.width != tableSize.width)
		{
			CGFloat cachedHeight = cachedSize.height;
			CGFloat newHeight = cachedHeight;
			if (forceUpdate)
				msg.cachedCellSize = NSZeroSize;
			switch (msg.type)
			{
				case LOGMSG_TYPE_LOG:
				case LOGMSG_TYPE_BLOCKSTART:
				case LOGMSG_TYPE_BLOCKEND:
					newHeight = [LoggerMessageCell heightForCellWithMessage:msg threadColumnWidth:_threadColumnWidth maxSize:maxCellSize showFunctionNames:_showFunctionNames];
					break;
				case LOGMSG_TYPE_CLIENTINFO:
				case LOGMSG_TYPE_DISCONNECT:
					newHeight = [LoggerClientInfoCell heightForCellWithMessage:msg threadColumnWidth:_threadColumnWidth maxSize:maxCellSize showFunctionNames:_showFunctionNames];
					break;
				case LOGMSG_TYPE_MARK:
					newHeight = [LoggerMarkerCell heightForCellWithMessage:msg threadColumnWidth:_threadColumnWidth maxSize:maxCellSize showFunctionNames:_showFunctionNames];
					break;
				default:
					break;
			}
			if (newHeight != cachedHeight)
				[updatedMessages addObject:msg];
			else if (forceUpdate)
				msg.cachedCellSize = cachedSize;
		}
	}
	if ([updatedMessages count])
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			if (group == NULL || dispatch_get_context(group) != NULL)
			{
				NSMutableIndexSet *set = [[NSMutableIndexSet alloc] init];
				for (LoggerMessage *msg in updatedMessages)
				{
					NSUInteger pos = [self.displayedMessages indexOfObjectIdenticalTo:msg];
					if (pos == NSNotFound || pos > self.lastMessageRow)
						break;
					[set addIndex:pos];
				}
				if ([set count])
					[self.logTable noteHeightOfRowsWithIndexesChanged:set];
			}
		});
	}
}

- (void)cancelAsynchronousTiling
{
	if (_lastTilingGroup != NULL)
	{
		dispatch_group_t leaveGroup = _lastTilingGroup;
		dispatch_set_context(leaveGroup, NULL);
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_BACKGROUND, 0), ^{
			// by clearing the context, all further tasks on this group will cancel their work
			// wait until they all went through cancellation before removing the group
			dispatch_group_wait(leaveGroup, 0);
		});
	}
	_lastTilingGroup = NULL;
}

- (void)tileLogTable:(BOOL)forceUpdate
{
	// tile the visible rows (and a bit more) first, then tile all the rest
	// this gives us a better perceived speed
	NSSize tableSize = _logTable.frame.size;
	NSRect r = [_logTable.superview convertRect:[_logTable.superview bounds] toView:_logTable];
	NSRange visibleRows = [_logTable rowsInRect:r];
	visibleRows.location = (NSUInteger) MAX((int)0, (int)visibleRows.location - 10);
	visibleRows.length = MIN(visibleRows.location + visibleRows.length + 10, [_displayedMessages count] - visibleRows.location);
	if (visibleRows.length)
	{
		[self tileLogTableMessages:[_displayedMessages subarrayWithRange:visibleRows]
						  withSize:tableSize
					   forceUpdate:forceUpdate
							 group:NULL];
	}
	
	[self cancelAsynchronousTiling];
	
	// create new group, set it a non-NULL context to indicate that it is running
	_lastTilingGroup = dispatch_group_create();
	dispatch_set_context(_lastTilingGroup, "running");
	
	// perform layout in chunks in the background
	for (NSUInteger i = 0; i < [_displayedMessages count]; i += 1024)
	{
		// tiling is executed on a parallel queue, and checks for cancellation
		// by looking at its group's context object 
		NSRange range = NSMakeRange(i, MIN(1024, [_displayedMessages count] - i));
		if (range.length > 0)
		{
			NSArray *subArray = [_displayedMessages subarrayWithRange:range];
			dispatch_group_t group = _lastTilingGroup;		// careful with self dereference, could use the wrong group at run time, hence the copy here
			dispatch_group_async(group,
								 dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0),
								 ^{
									 [self tileLogTableMessages:subArray
													   withSize:tableSize
													forceUpdate:forceUpdate
														  group:group];
								 });
		}
	}
}

- (void)tileLogTableNotification:(NSNotification *)note
{
	[self tileLogTable:NO];
}

- (void)applyFontChanges
{
	[self tileLogTable:YES];
	[_logTable reloadData];
}

#pragma mark Target Action

- (IBAction)performFindPanelAction:(id)sender {
    [self.window makeFirstResponder:_quickFilterTextField];
}


// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Support for multiple runs in same window
// -----------------------------------------------------------------------------
- (void)rebuildRunsSubmenu
{
	LoggerDocument *doc = (LoggerDocument *)self.document;
	NSMenuItem *runsSubmenu = [[[[NSApp mainMenu] itemWithTag:VIEW_MENU_ITEM_TAG] submenu] itemWithTag:VIEW_MENU_SWITCH_TO_RUN_TAG];
	NSArray *runsNames = [doc attachedLogsPopupNames];
	NSMenu *menu = [runsSubmenu submenu];
	[menu removeAllItems];
	NSInteger i = 0;
	NSInteger currentRun = [[doc indexOfCurrentVisibleLog] integerValue];
	for (NSString *name in runsNames)
	{
		NSMenuItem *runItem = [[NSMenuItem alloc] initWithTitle:name
														 action:@selector(selectRun:)
												  keyEquivalent:@""];
		if (i == currentRun)
			[runItem setState:NSOnState];
		[runItem setTag:i++];
		[runItem setTarget:self];
		[menu addItem:runItem];
	}
}

- (void)clearRunsSubmenu
{
	NSMenuItem *runsSubmenu = [[[[NSApp mainMenu] itemWithTag:VIEW_MENU_ITEM_TAG] submenu] itemWithTag:VIEW_MENU_SWITCH_TO_RUN_TAG];
	NSMenu *menu = [runsSubmenu submenu];
	[menu removeAllItems];
	NSMenuItem *dummyItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"No Run Log", @"") action:nil keyEquivalent:@""];
	[dummyItem setEnabled:NO];
	[menu addItem:dummyItem];
}

- (void)selectRun:(NSMenuItem *)anItem
{
	((LoggerDocument *)self.document).indexOfCurrentVisibleLog = @([anItem tag]);
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Filter predicate assembly
// -----------------------------------------------------------------------------
- (NSPredicate *)filterPredicateFromCurrentSelection
{
	// the current filter is the aggregate (OR clause) of all the selected filters
	NSArray *predicates = [_filterListController.selectedObjects valueForKey:@"predicate"];
	if (![predicates count])
		return nil;
	if ([predicates count] == 1)
		return [predicates lastObject];
	
	// Isolate the NOT type predicates, merge predicates this way:
	// result = (AND all NOT predicates)) AND (OR all ANY/ALL predicates)
	NSMutableArray *anyAllPredicates = [NSMutableArray arrayWithCapacity:[predicates count]];
	NSMutableArray *notPredicates = [NSMutableArray arrayWithCapacity:[predicates count]];
	for (NSCompoundPredicate *pred in predicates)
	{
		if ([pred isKindOfClass:NSCompoundPredicate.class] && [pred compoundPredicateType] == NSNotPredicateType)
			[notPredicates addObject:pred];
		else
			[anyAllPredicates addObject:pred];
	}
	if ([notPredicates count] && [anyAllPredicates count])
	{
		return [NSCompoundPredicate andPredicateWithSubpredicates:
			@[[NSCompoundPredicate andPredicateWithSubpredicates:notPredicates],
				[NSCompoundPredicate orPredicateWithSubpredicates:anyAllPredicates]]];
	}
	if ([notPredicates count])
		return [NSCompoundPredicate andPredicateWithSubpredicates:notPredicates];
	return [NSCompoundPredicate orPredicateWithSubpredicates:predicates];
}

- (NSPredicate *)alwaysVisibleEntriesPredicate
{
	NSExpression *lhs = [NSExpression expressionForKeyPath:@"type"];
	NSExpression *rhs = [NSExpression expressionForConstantValue:[NSSet setWithObjects:
		@LOGMSG_TYPE_MARK,
		@LOGMSG_TYPE_CLIENTINFO,
		@LOGMSG_TYPE_DISCONNECT,
		nil]];
	return [NSComparisonPredicate predicateWithLeftExpression:lhs
											  rightExpression:rhs
													 modifier:NSDirectPredicateModifier
														 type:NSInPredicateOperatorType
													  options:0];
}

- (void)updateFilterPredicate
{
	assert([NSThread isMainThread]);
	NSPredicate *p = [self filterPredicateFromCurrentSelection];
	NSMutableArray *andPredicates = [[NSMutableArray alloc] initWithCapacity:3];
	if (_logLevel != 0)
	{
		NSExpression *lhs = [NSExpression expressionForKeyPath:@"level"];
		NSExpression *rhs = [NSExpression expressionForConstantValue:@(_logLevel)];
		[andPredicates addObject:[NSComparisonPredicate predicateWithLeftExpression:lhs
																	rightExpression:rhs
																		   modifier:NSDirectPredicateModifier
																			   type:NSLessThanPredicateOperatorType
																			options:0]];
	}
	if (_filterTags.count != 0)
	{
		NSMutableArray *filterTagsPredicates = [[NSMutableArray alloc] initWithCapacity:_filterTags.count];
		for (NSString *filterTag in _filterTags) {
			NSExpression *lhs = [NSExpression expressionForKeyPath:@"tag"];
			NSExpression *rhs = [NSExpression expressionForConstantValue:filterTag];
			[filterTagsPredicates addObject:[NSComparisonPredicate predicateWithLeftExpression:lhs
																			   rightExpression:rhs
																					  modifier:NSDirectPredicateModifier
																						  type:NSEqualToPredicateOperatorType
																					   options:0]];
		}
		[andPredicates addObject:[NSCompoundPredicate orPredicateWithSubpredicates:filterTagsPredicates]];
	}
	if ([_filterString length])
	{
		// "refine filter" string looks up in both message text and function name
		NSExpression *lhs = [NSExpression expressionForKeyPath:@"messageText"];
		NSExpression *rhs = [NSExpression expressionForConstantValue:_filterString];
		NSPredicate *messagePredicate = [NSComparisonPredicate predicateWithLeftExpression:lhs
																		   rightExpression:rhs
																				  modifier:NSDirectPredicateModifier
																					  type:NSContainsPredicateOperatorType
																				   options:NSCaseInsensitivePredicateOption];
		lhs = [NSExpression expressionForKeyPath:@"functionName"];
		NSPredicate *functionPredicate = [NSComparisonPredicate predicateWithLeftExpression:lhs
																			rightExpression:rhs
																				   modifier:NSDirectPredicateModifier
																					   type:NSContainsPredicateOperatorType
																					options:NSCaseInsensitivePredicateOption];
		
		[andPredicates addObject:[NSCompoundPredicate orPredicateWithSubpredicates:@[messagePredicate, functionPredicate]]];
	}
	if ([andPredicates count])
	{
		if (p != nil)
			[andPredicates addObject:p];
		p = [NSCompoundPredicate andPredicateWithSubpredicates:andPredicates];
	}
	if (p == nil)
		p = [NSPredicate predicateWithValue:YES];
	else
		p = [NSCompoundPredicate orPredicateWithSubpredicates:@[[self alwaysVisibleEntriesPredicate], p]];
	self.filterPredicate = p;
}

- (void)refreshMessagesIfPredicateChanged
{
	assert([NSThread isMainThread]);
	NSPredicate *currentPredicate = _filterPredicate;
	[self updateFilterPredicate];
	if (![_filterPredicate isEqual:currentPredicate])
	{
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshAllMessages:) object:nil];
		[self rebuildQuickFilterPopup];
		[self performSelector:@selector(refreshAllMessages:) withObject:nil afterDelay:0];
	}
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Per-Application settings
// -----------------------------------------------------------------------------
- (NSDictionary *)settingsForClientApplication
{
	NSString *clientAppIdentifier = [_attachedConnection clientName];
	if (![clientAppIdentifier length])
		return nil;

	NSDictionary *clientSettings = [[NSUserDefaults standardUserDefaults] objectForKey:kPrefClientApplicationSettings];
	if (clientSettings == nil)
		return [NSDictionary dictionary];
	
	NSDictionary *appSettings = clientSettings[clientAppIdentifier];
	if (appSettings == nil)
		return [NSDictionary dictionary];
	return appSettings;
}

- (void)saveSettingsForClientApplication:(NSDictionary *)newSettings
{
	NSString *clientAppIdentifier = [_attachedConnection clientName];
	if (![clientAppIdentifier length])
		return;
	NSUserDefaults *ud = [NSUserDefaults standardUserDefaults];
	NSMutableDictionary *clientSettings = [[ud objectForKey:kPrefClientApplicationSettings] mutableCopy];
	if (clientSettings == nil)
		clientSettings = [NSMutableDictionary dictionary];
	clientSettings[clientAppIdentifier] = newSettings;
	[ud setObject:clientSettings forKey:kPrefClientApplicationSettings];
}

- (void)setSettingForClientApplication:(id)aValue forKey:(NSString *)aKey
{
	NSMutableDictionary *dict = [[self settingsForClientApplication] mutableCopy];
	dict[aKey] = aValue;
	[self saveSettingsForClientApplication:dict];
}

- (void)rememberFiltersSelection
{
	// remember the last filter set selected for this application identifier,
	// we will use it to automatically reassociate it the next time the same
	// application connects or a log file from this application is reopened
	NSDictionary *filterSet = [[_filterSetsListController selectedObjects] lastObject];
	if (filterSet != nil)
		[self setSettingForClientApplication:filterSet[@"uid"] forKey:@"selectedFilterSet"];
}

- (void)restoreClientApplicationSettings
{
	NSDictionary *clientAppSettings = [self settingsForClientApplication];
	if (clientAppSettings == nil)
		return;

	_clientAppSettingsRestored = YES;

	// when an application connects, we restore some saved settings so the user
	// comes back to about the same configuration she was using the last time
	id showFuncs = clientAppSettings[@"_showFunctionNames"];
	if (showFuncs != nil)
		[self setShowFunctionNames:showFuncs];
	
	// try to restore the last filter set that was
	// selected for this application. Usually, you have a filter set per application
	// (this is how it is intended to be used), so it makes sense to preselect it
	// when the application connects.
	NSNumber *filterSetUID = clientAppSettings[@"selectedFilterSet"];
	if (filterSetUID != nil)
	{
		// try retrieving the filter set
		NSArray *matchingFilters = [[_filterSetsListController arrangedObjects] filteredArrayUsingPredicate:
									[NSPredicate predicateWithFormat:@"uid == %@", filterSetUID]];
		if ([matchingFilters count] == 1)
			[_filterSetsListController setSelectedObjects:matchingFilters];
	}
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Splitview delegate
// -----------------------------------------------------------------------------
- (void)splitViewDidResizeSubviews:(NSNotification *)notification
{
//	tableNeedsTiling = YES;
}

//- (void)splitView:(NSSplitView *)sender resizeSubviewsWithOldSize:(NSSize)oldSize {
//    if (sender == splitView) {
//        NSSize newSize = sender.bounds.size;
//        
//        NSView *mainDisplay = [[sender subviews] objectAtIndex:1];
//        NSRect frame = mainDisplay.frame;
//        frame.size.width += newSize.width - oldSize.width;
//        frame.size.height = newSize.height;
//        [mainDisplay setFrame:frame];
//        
//        NSView *sidebar = [[sender subviews] objectAtIndex:0];
//        NSRect sidebarFrame = sidebar.frame;
//        sidebarFrame.size.height = newSize.height;
//        [sidebar setFrame:sidebarFrame];
//    } else {
//        [sender adjustSubviews];
//    }
//}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Window delegate
// -----------------------------------------------------------------------------
- (void)windowDidResize:(NSNotification *)notification
{
	if (![[self window] inLiveResize])
		[self tileLogTable:NO];
}

- (void)windowDidEndLiveResize:(NSNotification *)notification
{
	[self tileLogTable:NO];
}

- (void)windowDidBecomeMain:(NSNotification *)notification
{
	[self updateMenuBar:YES];
    [self setBackgroundColor];
}

- (void)windowDidResignMain:(NSNotification *)notification
{
	[self updateMenuBar:NO];
    [self setBackgroundColor];
}

- (void)setBackgroundColor
{
    NSColor *bgColor = [NSColor controlBackgroundColor];
    [_filterSetsTable setBackgroundColor:bgColor];
    [_filterTable setBackgroundColor:bgColor];
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Quick filter
// -----------------------------------------------------------------------------
- (void)rebuildQuickFilterPopup
{
	NSMenu *menu = [_quickFilter menu];
	
	// remove all _tags
	while ([[menu itemAtIndex:[menu numberOfItems]-1] tag] != -1)
		[menu removeItemAtIndex:[menu numberOfItems]-1];

	// set selected level checkmark
	NSString *levelTitle = nil;
	for (NSMenuItem *menuItem in [menu itemArray])
	{
		if ([menuItem isSeparatorItem])
			continue;
		if ([menuItem tag] == _logLevel)
		{
			[menuItem setState:NSOnState];
			levelTitle = [menuItem title];
		}
		else
			[menuItem setState:NSOffState];
	}

	NSString *tagTitle;
	NSMenuItem *item = [[menu itemArray] lastObject];
	if (_filterTags.count == 0)
	{
		[item setState:NSOnState];
		tagTitle = [item title];
	}
	else
	{
		[item setState:NSOffState];
		tagTitle = [NSString stringWithFormat:NSLocalizedString(@"Tag%@: %@", @""), _filterTags.count > 1 ? @"s" : @"", [_filterTags.allObjects componentsJoinedByString:@","]];
	}

	for (NSString *tag in [[_tags allObjects] sortedArrayUsingSelector:@selector(localizedCompare:)])
	{
		item = [[NSMenuItem alloc] initWithTitle:tag action:@selector(selectQuickFilterTag:) keyEquivalent:@""];
		[item setRepresentedObject:tag];
		[item setIndentationLevel:1];
		if ([_filterTags containsObject:tag])
			[item setState:NSOnState];
		[menu addItem:item];
	}

	[_quickFilter setTitle:[NSString stringWithFormat:@"%@ | %@", levelTitle, tagTitle]];
	
	self.hasQuickFilter = (_filterString != nil || _filterTags.count != 0 || _logLevel != 0);
}

- (void)addTags:(NSArray *)newTags
{
	// complete the set of "seen" _tags in messages
	// if changed, update the quick filter popup
	NSUInteger numTags = [_tags count];
	[_tags addObjectsFromArray:newTags];
	if ([_tags count] != numTags)
		[self rebuildQuickFilterPopup];
}

- (IBAction)selectQuickFilterTag:(id)sender
{
	NSString *newTag = [sender representedObject];

	// Selected All Tags
	if (newTag.length == 0) {
		[_filterTags removeAllObjects];
	}
	// Selected Specific Tag
	else {
		// Determine if Options key was pressed
		NSUInteger flags = [[NSApp currentEvent] modifierFlags];
		BOOL hasOptionKeyPressed = (flags & NSEventModifierFlagOption) != 0;

		// Clear multiple selection or single selection with different tag
		if (!hasOptionKeyPressed && (_filterTags.count != 1 || ![_filterTags containsObject:newTag])) {
			[_filterTags removeAllObjects];
		}

		// Toggle tag
		if ([_filterTags containsObject:newTag]) {
			[_filterTags removeObject:newTag];
		} else {
			[_filterTags addObject:newTag];
		}
	}

	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshMessagesIfPredicateChanged) object:nil];
	[self performSelector:@selector(refreshMessagesIfPredicateChanged) withObject:nil afterDelay:0];
}

- (IBAction)selectQuickFilterLevel:(id)sender
{
	int level = (int)[(NSView *)sender tag];
	if (level != _logLevel)
	{
		_logLevel = level;
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshMessagesIfPredicateChanged) object:nil];
		[self performSelector:@selector(refreshMessagesIfPredicateChanged) withObject:nil afterDelay:0];
	}
}

- (IBAction)resetQuickFilter:(id)sender
{
	_filterString = @"";
	[_filterTags removeAllObjects];
	_logLevel = 0;
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshMessagesIfPredicateChanged) object:nil];
	[self performSelector:@selector(refreshMessagesIfPredicateChanged) withObject:nil afterDelay:0];
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Table management
// -----------------------------------------------------------------------------
- (void)messagesAppendedToTable
{
	assert([NSThread isMainThread]);
	if (_attachedConnection.connected)
	{
		NSRect r = [_logTable.superview convertRect:_logTable.superview.bounds toView:_logTable];
		NSRange visibleRows = [_logTable rowsInRect:r];
		BOOL lastVisible = (visibleRows.location == NSNotFound ||
							visibleRows.length == 0 ||
							(visibleRows.location + visibleRows.length) >= _lastMessageRow);
		[_logTable noteNumberOfRowsChanged];
		if (lastVisible)
			[_logTable scrollRowToVisible:[_displayedMessages count] - 1];
	}
	else
	{
		[_logTable noteNumberOfRowsChanged];
	}
	_lastMessageRow = (int)[_displayedMessages count];
	self.info = [NSString stringWithFormat:NSLocalizedString(@"%u messages", @""), [_displayedMessages count]];
}

- (void)appendMessagesToTable:(NSArray *)messages
{
	assert([NSThread isMainThread]);
	[_displayedMessages addObjectsFromArray:messages];

	// schedule a table reload. Do this asynchronously (and cancellable-y) so we can limit the
	// number of reload requests in case of high load
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(messagesAppendedToTable) object:nil];
	[self performSelector:@selector(messagesAppendedToTable) withObject:nil afterDelay:0];
}

- (IBAction)openDetailsWindow:(id)sender
{
	// open a details view window for the selected messages
	if (_detailsWindowController == nil)
	{
		_detailsWindowController = [[LoggerDetailsWindowController alloc] initWithWindowNibName:@"LoggerDetailsWindow"];
		[_detailsWindowController window];	// force window to load
		[[self document] addWindowController:_detailsWindowController];
	}
	[_detailsWindowController setMessages:[_displayedMessages objectsAtIndexes:[_logTable selectedRowIndexes]]];
	[_detailsWindowController showWindow:self];
}

void runSystemCommand(NSString *cmd)
{
    [[NSTask launchedTaskWithLaunchPath:@"/bin/sh"
                              arguments:@[@"-c", cmd]] waitUntilExit];
}

- (IBAction)openDetailsInExternalEditor:(id)sender
{
	NSArray *msgs = [_displayedMessages objectsAtIndexes:[_logTable selectedRowIndexes]];
    NSString *txtMsg = [[msgs lastObject] textRepresentation];

    NSString *globallyUniqueStr = [[NSProcessInfo processInfo] globallyUniqueString];
    NSString *tempPath = [NSTemporaryDirectory() stringByAppendingPathComponent:globallyUniqueStr];

    [txtMsg writeToFile:tempPath atomically:YES encoding:NSUTF8StringEncoding error:nil];

    NSString *cmd = [NSString stringWithFormat:@"open -t %@", tempPath];
    runSystemCommand(cmd);
}

- (void)openDetailsInIDE
{
	NSInteger row = [_logTable selectedRow];
	if (row >= 0 && row < [_displayedMessages count])
	{
		LoggerMessage *msg = _displayedMessages[(NSUInteger) row];
		NSString *filename = msg.filename;
		if ([filename length])
		{
			NSFileManager *fm = [NSFileManager defaultManager];
			if ([fm fileExistsAtPath:filename])
			{
				// If the file is .h, .m, .c, .cpp, .h, .hpp: open the file
				// using xed. Otherwise, open the file with the Finder. We really don't
				// know which IDE the user is running if it's not Xcode
				// (when logging from Android, could be IntelliJ or Eclipse)
				NSString *extension = [filename pathExtension];
				BOOL useXcode = NO;
				for (NSString *ext in sXcodeFileExtensions)
				{
					if ([ext caseInsensitiveCompare:extension] == NSOrderedSame)
					{
						useXcode = YES;
						break;
					}
				}
				if (useXcode)
				{
					OpenFileInXcode(filename, (NSUInteger) MAX(0, msg.lineNumber));
				}
				else
				{
					[[NSWorkspace sharedWorkspace] openURL:[NSURL fileURLWithPath:filename]];
				}
			}
		}
	}
}

- (void)logCellDoubleClicked:(id)sender
{
    // double click opens the selection in the detail view
	// command-double click opens the source file if it was defined in the log and the file is found (using alt can mess with the results of the AppleScript)
	// alt-doubleclick opens the selection in external editor
	NSEvent *event = [NSApp currentEvent];
    if ([event clickCount] > 1 && ([NSEvent modifierFlags] & (NSFunctionKeyMask | NSCommandKeyMask)) != 0)
    {
		[self openDetailsInIDE];
    }
    else if ([event clickCount] > 1 && ([NSEvent modifierFlags] & NSAlternateKeyMask) != 0)
    {
        [self openDetailsInExternalEditor:sender];
    }
    else if ([event clickCount] > 1)
    {
        [self openDetailsWindow:sender];
	}
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Filtering
// -----------------------------------------------------------------------------
- (void)refreshAllMessages:(NSArray *)selectedMessages
{
	assert([NSThread isMainThread]);
	@synchronized (_attachedConnection.messages)
	{
		BOOL quickFilterWasFirstResponder = ([[self window] firstResponder] == [_quickFilterTextField currentEditor]);
		id messageToMakeVisible = selectedMessages[0];
		if (messageToMakeVisible == nil)
		{
			// Remember the currently selected messages
			NSIndexSet *selectedRows = [_logTable selectedRowIndexes];
			if ([selectedRows count])
				selectedMessages = [_displayedMessages objectsAtIndexes:selectedRows];

			NSRect r = [[_logTable superview] convertRect:[[_logTable superview] bounds] toView:_logTable];
			NSRange visibleRows = [_logTable rowsInRect:r];
			if (visibleRows.length != 0)
			{
				NSIndexSet *selectedVisible = [selectedRows indexesInRange:visibleRows options:0 passingTest:^(NSUInteger idx, BOOL *stop){return YES;}];
				if ([selectedVisible count])
					messageToMakeVisible = _displayedMessages[selectedVisible.firstIndex];
				else
					messageToMakeVisible = _displayedMessages[visibleRows.location];
			}
		}

		LoggerConnection *theConnection = _attachedConnection;

		NSSize tableFrameSize = [_logTable frame].size;
		NSUInteger numMessages = [_attachedConnection.messages count];
		for (int i = 0; i < numMessages;)
		{
			if (i == 0)
			{
				dispatch_async(_messageFilteringQueue, ^{
					dispatch_async(dispatch_get_main_queue(), ^{
						self.lastMessageRow = 0;
						[self.displayedMessages removeAllObjects];
						[self.logTable reloadData];
						self.info = NSLocalizedString(@"No message", @"");
					});
				});
			}
			NSUInteger length = MIN(4096, numMessages - i);
			if (length)
			{
				NSPredicate *aFilter = _filterPredicate;
				NSArray *subArray = [_attachedConnection.messages subarrayWithRange:NSMakeRange(i, length)];
				dispatch_async(_messageFilteringQueue, ^{
					// Check that the connection didn't change
					if (self.attachedConnection == theConnection)
						[self filterIncomingMessages:subArray withFilter:aFilter tableFrameSize:tableFrameSize];
				});
			}
			i += length;
		}

		// Stuff we want to do only when filtering is complete. To do this, we enqueue
		// one more operation to the message filtering queue, with the only goal of
		// being executed only at the end of the filtering process
		dispatch_async(_messageFilteringQueue, ^{
			dispatch_async(dispatch_get_main_queue(), ^{
				// if the connection changed since the last refreshAll call, stop now
				if (self.attachedConnection == theConnection)		// note that block retains self, not self._attachedConnection.
				{
					if (self.lastMessageRow < [self.displayedMessages count])
					{
						// perform table updates now, so we can properly reselect afterwards
						[NSObject cancelPreviousPerformRequestsWithTarget:self
																 selector:@selector(messagesAppendedToTable)
																   object:nil];
						[self messagesAppendedToTable];
					}
					
					if ([selectedMessages count])
					{
						// If there were selected rows, try to reselect them
						NSMutableIndexSet *newSelectionIndexes = [[NSMutableIndexSet alloc] init];
						for (id msg in selectedMessages)
						{
							NSInteger msgIndex = [self.displayedMessages indexOfObjectIdenticalTo:msg];
							if (msgIndex != NSNotFound)
								[newSelectionIndexes addIndex:(NSUInteger)msgIndex];
						}
						if ([newSelectionIndexes count])
						{
							[self.logTable selectRowIndexes:newSelectionIndexes byExtendingSelection:NO];
							if (!quickFilterWasFirstResponder)
								[[self window] makeFirstResponder:self.logTable];
						}
					}
					
					if (messageToMakeVisible != nil)
					{
						// Restore the logical location in the message flow, to keep the user
						// in-context
						NSUInteger msgIndex;
						id msg = messageToMakeVisible;
						@synchronized(self.attachedConnection.messages)
						{
							while ((msgIndex = [self.displayedMessages indexOfObjectIdenticalTo:msg]) == NSNotFound)
							{
								NSUInteger where = [self.attachedConnection.messages indexOfObjectIdenticalTo:msg];
								if (where == NSNotFound)
									break;
								if (where == 0)
								{
									msgIndex = 0;
									break;
								}
								else
									msg = self.attachedConnection.messages[where - 1];
							}
							if (msgIndex != NSNotFound)
								[self.logTable scrollRowToVisible:msgIndex];
						}
					}
					
					[self rebuildMarksSubmenu];
				}
				self.initialRefreshDone = YES;
			});
		});
	}
}

- (void)filterIncomingMessages:(NSArray *)messages
{
	assert([NSThread isMainThread]);
	NSPredicate *aFilter = _filterPredicate;		// catch value now rather than dereference it from self later
	NSSize tableFrameSize = [_logTable frame].size;
	dispatch_async(_messageFilteringQueue, ^{
		[self filterIncomingMessages:(NSArray *)messages withFilter:aFilter tableFrameSize:tableFrameSize];
	});
}

- (void)filterIncomingMessages:(NSArray *)messages
					withFilter:(NSPredicate *)aFilter
				tableFrameSize:(NSSize)tableFrameSize
{
	// collect all _tags
	NSArray *msgTags = [messages valueForKeyPath:@"@distinctUnionOfObjects.tag"];

	// find out which messages we want to keep. Executed on the message filtering queue
	NSArray *filteredMessages = [messages filteredArrayUsingPredicate:aFilter];
	if ([filteredMessages count])
	{
		LoggerConnection *theConnection = _attachedConnection;
		dispatch_async(dispatch_get_main_queue(), ^{
			[self tileLogTableMessages:filteredMessages withSize:tableFrameSize forceUpdate:NO group:NULL];
			if (self.attachedConnection == theConnection)
			{
				[self appendMessagesToTable:filteredMessages];
				[self addTags:msgTags];
			}
		});
	}
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Properties and bindings
// -----------------------------------------------------------------------------
- (void)setAttachedConnection:(LoggerConnection *)aConnection
{
	assert([NSThread isMainThread]);

	if (_attachedConnection != nil)
	{
		// Completely clear log table
		[_logTable deselectAll:self];
		_lastMessageRow = 0;
		[_displayedMessages removeAllObjects];
		self.info = NSLocalizedString(@"No message", @"");
		[_logTable reloadData];
		[self rebuildMarksSubmenu];

		// Close filter editor sheet (with cancel) if open
		if ([_filterEditorWindow isVisible])
			[NSApp endSheet:_filterEditorWindow returnCode:0];

		// Cancel pending tasks
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshAllMessages:) object:nil];
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshMessagesIfPredicateChanged) object:nil];
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(messagesAppendedToTable) object:nil];
		if (_lastTilingGroup != NULL)
		{
			dispatch_set_context(_lastTilingGroup, NULL);
			_lastTilingGroup = NULL;
		}
		
		// Detach previous connection
		_attachedConnection.attachedToWindow = NO;
		_attachedConnection = nil;
	}
	if (aConnection != nil)
	{
		_attachedConnection = aConnection;
		_attachedConnection.attachedToWindow = YES;
		_initialRefreshDone = NO;
		dispatch_async(dispatch_get_main_queue(), ^{
			[self updateClientInfo];
			if (!_clientAppSettingsRestored)
				[self restoreClientApplicationSettings];
			[self rebuildRunsSubmenu];
			[self refreshAllMessages:nil];
		});
	}
}

- (NSNumber *)shouldEnableRunsPopup
{
	NSUInteger numRuns = [((LoggerDocument *)[self document]).attachedLogs count];
	if (![[NSUserDefaults standardUserDefaults] boolForKey:kPrefKeepMultipleRuns] && numRuns <= 1)
		return (id)kCFBooleanFalse;
	return (id)kCFBooleanTrue;
}

- (void)setFilterString:(NSString *)newString
{
	if (newString == nil)
		newString = @"";

	if (newString != _filterString && ![_filterString isEqualToString:newString])
	{
		_filterString = [newString copy];
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshMessagesIfPredicateChanged) object:nil];
		[self performSelector:@selector(refreshMessagesIfPredicateChanged) withObject:nil afterDelay:0];
		self.hasQuickFilter = (_filterString != nil || _filterTags.count != 0 || _logLevel != 0);
	}
}

- (void)setShowFunctionNames:(NSNumber *)value
{
	BOOL b = [value boolValue];
	if (b != _showFunctionNames)
	{
		[self willChangeValueForKey:@"_showFunctionNames"];
		_showFunctionNames = b;
		[self tileLogTable:YES];
		dispatch_async(dispatch_get_main_queue(), ^{
			[self.logTable reloadData];
		});
		[self didChangeValueForKey:@"_showFunctionNames"];

		dispatch_async(dispatch_get_main_queue(), ^{
			[self setSettingForClientApplication:value forKey:@"_showFunctionNames"];
		});
	}
}

- (NSNumber *)showFunctionNames
{
	return @(_showFunctionNames);
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark LoggerConnectionDelegate
// -----------------------------------------------------------------------------
- (void)connection:(LoggerConnection *)theConnection
didReceiveMessages:(NSArray *)theMessages
			 range:(NSRange)rangeInMessagesList
{
	// We need to hop thru the main thread to have a recent and stable copy of the filter string and current filter
	dispatch_async(dispatch_get_main_queue(), ^{
		if (self.initialRefreshDone)
			[self filterIncomingMessages:theMessages];
	});
}

- (void)remoteDisconnected:(LoggerConnection *)theConnection
{
	// we always get called on the main thread
	[self updateClientInfo];
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark KVO / Bindings
// -----------------------------------------------------------------------------
- (void)observeValueForKeyPath:(NSString *)keyPath ofObject:(id)object change:(NSDictionary *)change context:(void *)context
{
	if (object == _attachedConnection)
	{
		if ([keyPath isEqualToString:@"clientIDReceived"])
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				[self updateClientInfo];
				if (!self.clientAppSettingsRestored)
					[self restoreClientApplicationSettings];
			});			
		}
	}
	else if (object == _filterListController)
	{
		if ([keyPath isEqualToString:@"selectedObjects"])
		{
			if ([_filterListController selectionIndex] != NSNotFound)
			{
				[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshMessagesIfPredicateChanged) object:nil];
				[self performSelector:@selector(refreshMessagesIfPredicateChanged) withObject:nil afterDelay:0];
			}
		}
	}
	else if (object == _filterSetsListController)
	{
		if ([keyPath isEqualToString:@"arrangedObjects"])
		{
			// we'll be called when arrangedObjects change, that is when a filter set is added,
			// removed or renamed. Use this occasion to save the filters definition.
			[(LoggerAppDelegate *)[NSApp delegate] saveFiltersDefinition];
		}
		else if ([keyPath isEqualToString:@"selectedObjects"])
		{
			[self rememberFiltersSelection];
		}
	} else if (object == [NSUserDefaults standardUserDefaults])
    {
        if ([keyPath isEqualToString:kMaxTableRowHeight])
        {
            [self tileLogTable:YES];
        }
    }
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark NSTableDelegate
// -----------------------------------------------------------------------------
- (NSCell *)tableView:(NSTableView *)tableView dataCellForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (tableView == _logTable && row >= 0 && row < [_displayedMessages count])
	{
		LoggerMessage *msg = _displayedMessages[(NSUInteger) row];
		switch (msg.type)
		{
			case LOGMSG_TYPE_LOG:
			case LOGMSG_TYPE_BLOCKSTART:
			case LOGMSG_TYPE_BLOCKEND:
				return _messageCell;
			case LOGMSG_TYPE_CLIENTINFO:
			case LOGMSG_TYPE_DISCONNECT:
				return _clientInfoCell;
			case LOGMSG_TYPE_MARK:
				return _markerCell;
			default:
				assert(false);
				break;
		}
	}
	return nil;
}

- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if (aTableView == _logTable && rowIndex >= 0 && rowIndex < [_displayedMessages count])
	{
		// setup the message to be displayed
		LoggerMessageCell *cell = (LoggerMessageCell *)aCell;
		cell.message = _displayedMessages[(NSUInteger) rowIndex];
		cell.shouldShowFunctionNames = _showFunctionNames;

		// if previous message is a Mark, go back a bit more to get the real previous message
		// if previous message is ClientInfo, don't use it.
		NSInteger idx = rowIndex - 1;
		LoggerMessage *prev = nil;
		while (prev == nil && idx >= 0)
		{
			prev = _displayedMessages[(NSUInteger) idx--];
			if (prev.type == LOGMSG_TYPE_CLIENTINFO || prev.type == LOGMSG_TYPE_MARK)
				prev = nil;
		} 
		
		cell.previousMessage = prev;
	}
	else if (aTableView == _filterSetsTable)
	{
		NSArray *filterSetsList = [_filterSetsListController arrangedObjects];
		if (rowIndex >= 0 && rowIndex < [filterSetsList count])
		{
			NSTextFieldCell *tc = (NSTextFieldCell *)aCell;
			NSDictionary *filterSet = filterSetsList[(NSUInteger) rowIndex];
			if ([filterSet[@"uid"] integerValue] == 1)
				[tc setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
			else
				[tc setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
		}
	}
	else if (aTableView == _filterTable)
	{
		// want the "All Logs" entry (immutable) in Bold
		NSArray *filterList = [_filterListController arrangedObjects];
		if (rowIndex >= 0 && rowIndex < [filterList count])
		{
			NSTextFieldCell *tc = (NSTextFieldCell *)aCell;
			NSDictionary *filter = filterList[(NSUInteger) rowIndex];
			if ([filter[@"uid"] integerValue] == 1)
				[tc setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
			else
				[tc setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
		}
	}
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
	assert([NSThread isMainThread]);
	if (tableView == _logTable && row >= 0 && row < [_displayedMessages count])
	{
		// use only cached sizes
		LoggerMessage *message = _displayedMessages[(NSUInteger) row];
		NSSize cachedSize = message.cachedCellSize;
		if (cachedSize.height)
			return cachedSize.height;
	}
	return [tableView rowHeight];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	if ([aNotification object] == _logTable)
	{
		self.messagesSelected = ([_logTable selectedRow] >= 0);
		if (_messagesSelected && _detailsWindowController != nil && [[_detailsWindowController window] isVisible])
			[_detailsWindowController setMessages:[_displayedMessages objectsAtIndexes:[_logTable selectedRowIndexes]]];
	}
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark NSTableDataSource
// -----------------------------------------------------------------------------
- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [_displayedMessages count];
}

- (id)tableView:(NSTableView *)tableView
	objectValueForTableColumn:(NSTableColumn *)tableColumn
	row:(NSInteger)rowIndex
{
	if (rowIndex >= 0 && rowIndex < [_displayedMessages count])
		return _displayedMessages[(NSUInteger) rowIndex];
	return nil;
}

- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard
{
	if (tv == _logTable)
	{
		NSArray *draggedMessages = [_displayedMessages objectsAtIndexes:rowIndexes];
		NSMutableString *string = [[NSMutableString alloc] initWithCapacity:[draggedMessages count] * 128];
		for (LoggerMessage *msg in draggedMessages)
			[string appendString:[msg textRepresentation]];
		[pboard writeObjects:@[string]];
		return YES;
	}
	if (tv == _filterTable)
	{
		NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
		NSArray *filters = [[_filterListController arrangedObjects] objectsAtIndexes:rowIndexes];
		[item setData:[NSKeyedArchiver archivedDataWithRootObject:filters] forType:kNSLoggerFilterPasteboardType];
		[pboard writeObjects:@[item]];
		return YES;
	}
	return NO;
}

- (NSDragOperation)tableView:(NSTableView*)tv validateDrop:(id <NSDraggingInfo>)dragInfo proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)op
{
	if (tv == _filterSetsTable)
	{
		NSArray *filterSets = [_filterSetsListController arrangedObjects];
		if (row >= 0 && row < [filterSets count] && row != [_filterSetsListController selectionIndex])
		{
			if (op != NSTableViewDropOn)
				[_filterSetsTable setDropRow:row dropOperation:NSTableViewDropOn];
			return NSDragOperationCopy;
		}
	}
	else if (tv == _filterTable && [dragInfo draggingSource] != _filterTable)
	{
		NSArray *filters = [_filterListController arrangedObjects];
		if (row >= 0 && row < [filters count])
		{
			// highlight entire table
			[_filterTable setDropRow:-1 dropOperation:NSTableViewDropOn];
			return NSDragOperationCopy;
		}
	}
	return NSDragOperationNone;
}

- (BOOL)tableView:(NSTableView *)tv
	   acceptDrop:(id <NSDraggingInfo>)dragInfo
			  row:(NSInteger)row
	dropOperation:(NSTableViewDropOperation)operation
{
	BOOL added = NO;
	NSPasteboard* pboard = [dragInfo draggingPasteboard];
	NSArray *newFilters = [NSKeyedUnarchiver unarchiveObjectWithData:[pboard dataForType:kNSLoggerFilterPasteboardType]];
	if (tv == _filterSetsTable)
	{
		// Only add those filters which don't exist yet
		NSArray *filterSets = [_filterSetsListController arrangedObjects];
		NSMutableDictionary *filterSet = filterSets[(NSUInteger) row];
		NSMutableArray *existingFilters = [filterSet mutableArrayValueForKey:@"filters"];
		for (NSMutableDictionary *filter in newFilters)
		{
			if ([existingFilters indexOfObject:filter] == NSNotFound)
			{
				[existingFilters addObject:filter];
				added = YES;
			}
		}
		[_filterSetsListController setSelectedObjects:@[filterSet]];
	}
	else if (tv == _filterTable)
	{
		NSMutableArray *addedFilters = [[NSMutableArray alloc] init];
		for (NSMutableDictionary *filter in newFilters)
		{
			if ([[_filterListController arrangedObjects] indexOfObject:filter] == NSNotFound)
			{
				[_filterListController addObject:filter];
				[addedFilters addObject:filter];
				added = YES;
			}
		}
		if (added)
			[_filterListController setSelectedObjects:addedFilters];
	}
	if (added)
		[(LoggerAppDelegate *)[NSApp delegate] saveFiltersDefinition];
	return added;
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Filter sets management
// -----------------------------------------------------------------------------
- (void)undoableAddFilterSet:(id)set
{
	NSUndoManager *um = [self undoManager];
	[um registerUndoWithTarget:self selector:_cmd object:set];
	[um setActionName:NSLocalizedString(@"Add Application Set", @"")];
	if ([um isUndoing])
		[_filterSetsListController removeObject:set];
	else
	{
		[_filterSetsListController addObject:set];
		if (![um isRedoing])
		{
			NSUInteger index = [[_filterSetsListController arrangedObjects] indexOfObject:set];
			[_filterSetsTable editColumn:0 row:index withEvent:nil select:YES];
		}
	}
}

- (void)undoableDeleteFilterSet:(id)set
{
	NSUndoManager *um = [self undoManager];
	[um registerUndoWithTarget:self selector:_cmd object:set];
	[um setActionName:NSLocalizedString(@"Delete Application Set", @"")];
	if ([um isUndoing])
		[_filterSetsListController addObjects:set];
	else
		[_filterSetsListController removeObjects:set];
}

- (IBAction)addFilterSet:(id)sender
{
	id dict = [@{
		@"uid": [(LoggerAppDelegate *) [NSApp delegate] nextUniqueFilterIdentifier:[_filterSetsListController arrangedObjects]], @"title": NSLocalizedString(@"New App. Set", @""),
		@"filters": [(LoggerAppDelegate *) [NSApp delegate] defaultFilters]
	} mutableCopy];
	[self undoableAddFilterSet:dict];
}

- (IBAction)deleteSelectedFilterSet:(id)sender
{
	[self undoableDeleteFilterSet:[_filterSetsListController selectedObjects]];
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Filter editor
// -----------------------------------------------------------------------------
- (void)undoableModifyFilter:(NSDictionary *)filter
{
	NSMutableDictionary *previousFilter = nil;
	for (NSMutableDictionary *dict in [_filterListController content])
	{
		if ([dict[@"uid"] isEqual:filter[@"uid"]])
		{
			previousFilter = dict;
			break;
		}
	}
	assert(previousFilter != nil);
	[[self undoManager] registerUndoWithTarget:self selector:_cmd object:[previousFilter mutableCopy]];
	[[self undoManager] setActionName:NSLocalizedString(@"Modify Filter", @"")];
	[previousFilter addEntriesFromDictionary:filter];
	[_filterListController setSelectedObjects:@[previousFilter]];
}

- (void)undoableCreateFilter:(NSDictionary *)filter
{
	NSUndoManager *um = [self undoManager];
	[um registerUndoWithTarget:self selector:_cmd object:filter];
	[um setActionName:NSLocalizedString(@"Create Filter", @"")];
	if ([um isUndoing])
		[_filterListController removeObject:filter];
	else
	{
		[_filterListController addObject:filter];
		[_filterListController setSelectedObjects:@[filter]];
	}
}

- (void)undoableDeleteFilters:(NSArray *)filters
{
	NSUndoManager *um = [self undoManager];
	[um registerUndoWithTarget:self selector:_cmd object:filters];
	[um setActionName:NSLocalizedString(@"Delete Filters", @"")];
	if ([um isUndoing])
	{
		[_filterListController addObjects:filters];
		[_filterListController setSelectedObjects:filters];
	}
	else
		[_filterListController removeObjects:filters];
}

- (void)openFilterEditSheet:(NSDictionary *)dict
{
	[_filterName setStringValue:dict[@"title"]];
	NSPredicate *predicate = dict[@"predicate"];
	[_filterEditor setObjectValue:[predicate copy]];

    [self.window beginSheet:_filterEditorWindow
          completionHandler:^(NSModalResponse returnCode) {
              if (returnCode) {
                  BOOL exists = [[self.filterListController content] containsObject:dict];

                  NSPredicate *predicate = [self.filterEditor predicate];
                  if (predicate == nil)
                      predicate = [NSCompoundPredicate orPredicateWithSubpredicates:[NSArray array]];

                  NSMutableDictionary *newDict = [dict mutableCopy];
                  newDict[@"predicate"] = predicate;

                  NSString *title = [[self.filterName stringValue] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
                  if ([title length])
                      newDict[@"title"] = title;

                  if (exists)
                      [self undoableModifyFilter:newDict];
                  else
                      [self undoableCreateFilter:newDict];

                  [self.filterListController setSelectedObjects:@[newDict]];

                  [(LoggerAppDelegate *)NSApp.delegate saveFiltersDefinition];
              }
              [self.filterEditorWindow orderOut:self];
          }];
}

- (IBAction)deleteSelectedFilters:(id)sender
{
	[self undoableDeleteFilters:[_filterListController selectedObjects]];
}

- (IBAction)addFilter:(id)sender
{
	NSDictionary *filterSet = [[_filterSetsListController selectedObjects] lastObject];
	assert(filterSet != nil);
	NSDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
		[(LoggerAppDelegate *) NSApp.delegate nextUniqueFilterIdentifier:[filterSet objectForKey:@"filters"]], @"uid",
			NSLocalizedString(@"New filter", @""), @"title",
		[NSCompoundPredicate andPredicateWithSubpredicates:NSArray.array], @"predicate",
			nil];
	[self openFilterEditSheet:dict];
	[_filterEditor addRow:self];
}

- (IBAction)startEditingFilter:(id)sender
{
	// start editing filter, unless no selection (happens when double-clicking the header)
	// or when trying to edit the "All Logs" entry which is immutable
	NSDictionary *dict = [[_filterListController selectedObjects] lastObject];
	if (dict == nil || [dict[@"uid"] integerValue] == 1)
		return;
	[self openFilterEditSheet:dict];
	
}

- (IBAction)cancelFilterEdition:(id)sender
{
	[NSApp endSheet:_filterEditorWindow returnCode:0];
}

- (IBAction)validateFilterEdition:(id)sender
{
	[NSApp endSheet:_filterEditorWindow returnCode:1];
}


- (IBAction)createNewFilterFromQuickFilter:(id) sender
{
	NSDictionary *filterSet = [[_filterSetsListController selectedObjects] lastObject];
	assert(filterSet != nil);
	
	NSMutableArray *predicates = [NSMutableArray arrayWithCapacity:3];
	NSString *newFilterTitle;
	
	if ([_filterString length])
	{
		[predicates addObject:[NSPredicate predicateWithFormat:@"messageText contains %@", _filterString]];
		newFilterTitle = [NSString stringWithFormat:NSLocalizedString(@"Quick Filter: %@", @""), _filterString];
	}
	else
		newFilterTitle = NSLocalizedString(@"Quick Filter", @"");
	
	if (_logLevel)
		[predicates addObject:[NSPredicate predicateWithFormat:@"level <= %d", _logLevel - 1]];

	if (self.filterTags.count > 0) {
		NSMutableArray *filterTagsPredicates = [[NSMutableArray alloc] initWithCapacity:self.filterTags.count];
		for (NSString *filterTag in self.filterTags) {
			[filterTagsPredicates addObject:[NSPredicate predicateWithFormat:@"tag = %@", filterTag]];
		}
		[predicates addObject:[NSCompoundPredicate orPredicateWithSubpredicates:filterTagsPredicates]];
	}
	
	NSDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
		[(LoggerAppDelegate *) NSApp.delegate nextUniqueFilterIdentifier:[filterSet objectForKey:@"filters"]], @"uid",
		newFilterTitle, @"title",
		[NSCompoundPredicate andPredicateWithSubpredicates:predicates], @"predicate",
						  nil];
	[self openFilterEditSheet:dict];
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Markers
// -----------------------------------------------------------------------------
- (void)rebuildMarksSubmenu
{
	NSMenuItem *marksSubmenu = [[[[NSApp mainMenu] itemWithTag:TOOLS_MENU_ITEM_TAG] submenu] itemWithTag:TOOLS_MENU_JUMP_TO_MARK_TAG];
	NSExpression *lhs = [NSExpression expressionForKeyPath:@"type"];
	NSExpression *rhs = [NSExpression expressionForConstantValue:@LOGMSG_TYPE_MARK];
	NSPredicate *predicate = [NSComparisonPredicate predicateWithLeftExpression:lhs
																rightExpression:rhs
																	   modifier:NSDirectPredicateModifier
																		   type:NSEqualToPredicateOperatorType
																		options:0];
	NSArray *marks = [_displayedMessages filteredArrayUsingPredicate:predicate];
	NSMenu *menu = [marksSubmenu submenu];
	[menu removeAllItems];
	if (![marks count])
	{
		NSMenuItem *noMarkItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"No Mark", @"")
															action:nil
													 keyEquivalent:@""];
		[noMarkItem setEnabled:NO];
		[menu addItem:noMarkItem];
	}
	else for (LoggerMessage *mark in marks)
	{
		NSMenuItem *markItem = [[NSMenuItem alloc] initWithTitle:mark.message ?: @""
														  action:@selector(jumpToMark:)
												   keyEquivalent:@""];
		[markItem setRepresentedObject:mark];
		[markItem setTarget:self];
		[menu addItem:markItem];
	}
}

- (void)clearMarksSubmenu
{
	NSMenuItem *marksSubmenu = [[[[NSApp mainMenu] itemWithTag:TOOLS_MENU_ITEM_TAG] submenu] itemWithTag:TOOLS_MENU_JUMP_TO_MARK_TAG];
	NSMenu *menu = [marksSubmenu submenu];
	[menu removeAllItems];
	NSMenuItem *dummyItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"No Mark", @"") action:nil keyEquivalent:@""];
	[dummyItem setEnabled:NO];
	[menu addItem:dummyItem];
}

- (void)jumpToMark:(NSMenuItem *)markMenuItem
{
	LoggerMessage *mark = [markMenuItem representedObject];
	NSUInteger idx = [_displayedMessages indexOfObjectIdenticalTo:mark];
	if (idx == NSNotFound)
	{
		// actually, shouldn't happen
		NSBeep();
	}
	else
	{
		[_logTable scrollRowToVisible:idx];
		[_logTable selectRowIndexes:[NSIndexSet indexSetWithIndex:idx] byExtendingSelection:NO];
		[self.window makeMainWindow];
	}
}

- (void)addMarkWithTitleString:(NSString *)title beforeMessage:(LoggerMessage *)beforeMessage
{
	if (![title length])
	{
		title = [NSString stringWithFormat:NSLocalizedString(@"Mark - %@", @""),
				 [NSDateFormatter localizedStringFromDate:[NSDate date]
												dateStyle:NSDateFormatterShortStyle
												timeStyle:NSDateFormatterMediumStyle]];
	}
	
	LoggerMessage *mark = [[LoggerMessage alloc] init];
	struct timeval tv;
	gettimeofday(&tv, NULL);
	mark.type = LOGMSG_TYPE_MARK;
	mark.timestamp = tv;
	mark.message = title;
	mark.threadID = @"";
	mark.contentsType = kMessageString;
	
	// we want to process the mark after all current scheduled filtering operations
	// (including refresh All) are done
	dispatch_async(_messageFilteringQueue, ^{
		// then we serialize all operations modifying the messages list in the connection's
		// message processing queue
		dispatch_async(self.attachedConnection.messageProcessingQueue, ^{
			@synchronized(self.attachedConnection.messages)
			{
				NSUInteger location = [self.attachedConnection.messages count];
				if (beforeMessage != nil)
				{
					NSUInteger pos = [self.attachedConnection.messages indexOfObjectIdenticalTo:beforeMessage];
					if (pos != NSNotFound)
						location = pos;
				}
				[self.attachedConnection.messages insertObject:mark atIndex:location];
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				[[self document] updateChangeCount:NSChangeDone];
				[self refreshAllMessages:beforeMessage == nil ? @[mark] : @[mark, beforeMessage]];
			});
		});
	});

}

- (void)addMarkWithTitleBeforeMessage:(LoggerMessage *)aMessage
{
	NSString *s = [NSString stringWithFormat:NSLocalizedString(@"Mark - %@", @""),
				   [NSDateFormatter localizedStringFromDate:[NSDate date]
												  dateStyle:NSDateFormatterShortStyle
												  timeStyle:NSDateFormatterMediumStyle]];
	[_markTitleField setStringValue:s];

    [self.window beginSheet:_markTitleWindow
          completionHandler:^(NSModalResponse returnCode) {
              if (returnCode)
                  [self addMarkWithTitleString:[self.markTitleField stringValue] beforeMessage:aMessage];
              [self.markTitleWindow orderOut:self];
          }];
}

- (IBAction)addMark:(id)sender
{
	[self addMarkWithTitleString:nil beforeMessage:nil];
}

- (IBAction)addMarkWithTitle:(id)sender
{
	[self addMarkWithTitleBeforeMessage:nil];
}

- (IBAction)insertMarkWithTitle:(id)sender
{
	NSInteger rowIndex = [_logTable selectedRow];
	if (rowIndex >= 0 && rowIndex < (NSInteger)[_displayedMessages count])
		[self addMarkWithTitleBeforeMessage:_displayedMessages[(NSUInteger) rowIndex]];
}

- (IBAction)deleteMark:(id)sender
{
	NSInteger rowIndex = [_logTable selectedRow];
	if (rowIndex >= 0 && rowIndex < (NSInteger)[_displayedMessages count])
	{
		LoggerMessage *markMessage = _displayedMessages[(NSUInteger) rowIndex];
		assert(markMessage.type == LOGMSG_TYPE_MARK);
		[_displayedMessages removeObjectAtIndex:(NSUInteger)rowIndex];
		[_logTable reloadData];
		[self rebuildMarksSubmenu];
		dispatch_async(_messageFilteringQueue, ^{
			// then we serialize all operations modifying the messages list in the connection's
			// message processing queue
			dispatch_async(self.attachedConnection.messageProcessingQueue, ^{
				@synchronized(self.attachedConnection.messages) {
					[self.attachedConnection.messages removeObjectIdenticalTo:markMessage];
				}
				dispatch_async(dispatch_get_main_queue(), ^{
					[[self document] updateChangeCount:NSChangeDone];
				});
			});
		});
	}
}

- (IBAction)cancelAddMark:(id)sender
{
	[NSApp endSheet:_markTitleWindow returnCode:0];
}

- (IBAction)validateAddMark:(id)sender
{
	[NSApp endSheet:_markTitleWindow returnCode:1];
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark User Interface Items Validation
// -----------------------------------------------------------------------------
- (BOOL)validateUserInterfaceItem:(id)anItem
{
	SEL action = [anItem action];
	if (action == @selector(deleteMark:))
	{
		NSInteger rowIndex = [_logTable selectedRow];
		if (rowIndex >= 0 && rowIndex < (NSInteger)[_displayedMessages count])
		{
			LoggerMessage *markMessage = _displayedMessages[(NSUInteger) rowIndex];
			return (markMessage.type == LOGMSG_TYPE_MARK);
		}
		return NO;
	}
	else if (action == @selector(clearCurrentLog:))
	{
		// Allow "Clear Log" only if the log was not restored from save
		if (_attachedConnection == nil || _attachedConnection.restoredFromSave)
			return NO;
	}
	else if (action == @selector(clearAllLogs:))
	{
		// Allow "Clear All Run Logs" only if the log was not restored from save
		// and there are multiple run logs
		if (_attachedConnection == nil || _attachedConnection.restoredFromSave || [((LoggerDocument *)[self document]).attachedLogs count] <= 1)
			return NO;
	}
	else if (action == @selector(copy:))
	{
		return _logTable.selectedRowIndexes.count > 0;
	}
	return YES;
}

#pragma mark -
#pragma mark - Clipboard actions

- (void)copy:(id)sender
{
	NSArray *selectedMessages = [_displayedMessages objectsAtIndexes:_logTable.selectedRowIndexes];
	if (selectedMessages.count == 0)
		return;
	
	NSArray *messages = [selectedMessages valueForKeyPath:NSStringFromSelector(@selector(message))];
	NSPasteboard *generalPasteboard = [NSPasteboard generalPasteboard];
	[generalPasteboard declareTypes:@[ NSPasteboardTypeString ] owner:nil];
	[generalPasteboard setString:[messages componentsJoinedByString:@"\n"] forType:NSPasteboardTypeString];
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Support for clear current // all logs
// -----------------------------------------------------------------------------
- (BOOL)canClearCurrentLog
{
	return (_attachedConnection != nil && !_attachedConnection.restoredFromSave);
}

- (IBAction)clearCurrentLog:(id)sender
{
	[(LoggerDocument *)[self document] clearLogs:NO];
}

- (BOOL)canClearAllLogs
{
	return (_attachedConnection != nil && !_attachedConnection.restoredFromSave && [((LoggerDocument *)[self document]).attachedLogs count] > 1);
}

- (IBAction)clearAllLogs:(id)sender
{
	[(LoggerDocument *)[self document] clearLogs:YES];
}

@end

