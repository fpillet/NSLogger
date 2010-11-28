/*
 * LoggerWindowController.m
 *
 * BSD license follows (http://www.opensource.org/licenses/bsd-license.php)
 * 
 * Copyright (c) 2010 Florent Pillet <fpillet@gmail.com> All Rights Reserved.
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
#import "LoggerUtils.h"
#import "LoggerAppDelegate.h"
#import "LoggerCommon.h"

@interface LoggerWindowController ()
@property (nonatomic, retain) NSString *info;
@property (nonatomic, retain) NSString *filterString;
@property (nonatomic, retain) NSString *filterTag;
- (void)rebuildQuickFilterPopup;
- (void)updateClientInfo;
- (void)updateFilterPredicate;
- (void)refreshAllMessages:(NSArray *)selectMessages;
- (void)filterIncomingMessages:(NSArray *)messages withFilter:(NSPredicate *)aFilter;
- (NSPredicate *)currentFilterPredicate;
- (void)tileLogTable:(BOOL)force;
- (void)rebuildMarksSubmenu;
@end

static NSString * const kNSLoggerFilterPasteboardType = @"com.florentpillet.NSLoggerFilter";

// -----------------------------------------------------------------------------
#pragma mark -
#pragma Standard LoggerTableView
// -----------------------------------------------------------------------------
@implementation LoggerTableView
- (BOOL)canDragRowsWithIndexes:(NSIndexSet *)rowIndexes atPoint:(NSPoint)mouseDownPoint
{
	// Don't understand why I have to override this method, but it's the only
	// way I could get dragging from table to work. Tried various additional
	// things with no luck...
	return YES;
}
@end


@implementation LoggerWindowController

@synthesize info, filterString, filterTag;
@synthesize attachedConnection;
@synthesize messagesSelected, hasQuickFilter;
@dynamic showFunctionNames;

// -----------------------------------------------------------------------------
#pragma mark -
#pragma Standard NSWindowController stuff
// -----------------------------------------------------------------------------
- (id)initWithWindowNibName:(NSString *)nibName
{
	if ((self = [super initWithWindowNibName:nibName]) != nil)
	{
		messageFilteringQueue = dispatch_queue_create("com.florentpillet.nslogger.messageFiltering", NULL);
		displayedMessages = [[NSMutableArray alloc] initWithCapacity:4096];
		tags = [[NSMutableSet alloc] init];
		[self setShouldCloseDocument:YES];
	}
	return self;
}

- (void)dealloc
{
	[detailsWindowController release];
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[filterSetsListController removeObserver:self forKeyPath:@"arrangedObjects"];
	[filterListController removeObserver:self forKeyPath:@"selectedObjects"];
	dispatch_release(messageFilteringQueue);
	[attachedConnection release];
	[info release];
	[filterString release];
	[filterTag release];
	[filterPredicate release];
	[displayedMessages release];
	[tags release];
	[messageCell release];
	[clientInfoCell release];
	[markerCell release];
	[super dealloc];
}

- (void)windowDidLoad
{
	messageCell = [[LoggerMessageCell alloc] init];
	clientInfoCell = [[LoggerClientInfoCell alloc] init];
	markerCell = [[LoggerMarkerCell alloc] init];

	[logTable setIntercellSpacing:NSMakeSize(0,0)];
	[logTable setTarget:self];
	[logTable setDoubleAction:@selector(openDetailsWindow:)];

	[logTable registerForDraggedTypes:[NSArray arrayWithObject:NSPasteboardTypeString]];
	[logTable setDraggingSourceOperationMask:NSDragOperationNone forLocal:YES];
	[logTable setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];

	[filterSetsTable registerForDraggedTypes:[NSArray arrayWithObject:kNSLoggerFilterPasteboardType]];
	[filterSetsTable setIntercellSpacing:NSMakeSize(0,0)];

	[filterTable registerForDraggedTypes:[NSArray arrayWithObject:kNSLoggerFilterPasteboardType]];
	[filterTable setVerticalMotionCanBeginDrag:YES];
	[filterTable setTarget:self];
	[filterTable setIntercellSpacing:NSMakeSize(0,0)];
	[filterTable setDoubleAction:@selector(startEditingFilter:)];

	[filterSetsListController addObserver:self forKeyPath:@"arrangedObjects" options:0 context:NULL];
	[filterListController addObserver:self forKeyPath:@"selectedObjects" options:0 context:NULL];

	buttonBar.splitViewDelegate = self;

	[self rebuildQuickFilterPopup];
	[self updateFilterPredicate];
	loadComplete = YES;
	[logTable sizeToFit];

	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(applyFontChanges)
												 name:kMessageAttributesChangedNotification
											   object:nil];
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(tileLogTableNotification:)
												 name:@"TileLogTableNotification"
											   object:nil];
}

- (NSString *)windowTitleForDocumentDisplayName:(NSString *)displayName
{
	if ([[self document] fileURL] != nil)
		return displayName;
	if (attachedConnection.connected)
		return [attachedConnection clientAppDescription];
	return [NSString stringWithFormat:NSLocalizedString(@"%@ (disconnected)", @""),
			[attachedConnection clientDescription]];
}

- (void)updateClientInfo
{
	// Update the source label
	assert([NSThread isMainThread]);
	[self synchronizeWindowTitleWithDocumentName];
}

- (NSPredicate *)alwaysVisibleEntriesPredicate
{
	NSExpression *lhs = [NSExpression expressionForKeyPath:@"type"];
	NSExpression *rhs = [NSExpression expressionForConstantValue:[NSSet setWithObjects:
																  [NSNumber numberWithInteger:LOGMSG_TYPE_MARK],
																  [NSNumber numberWithInteger:LOGMSG_TYPE_CLIENTINFO],
																  [NSNumber numberWithInteger:LOGMSG_TYPE_DISCONNECT],
																  nil]];
	return [NSComparisonPredicate predicateWithLeftExpression:lhs
											  rightExpression:rhs
													 modifier:NSDirectPredicateModifier
														 type:NSInPredicateOperatorType
													  options:0];
}

- (void)updateFilterPredicate
{
	NSPredicate *p = [self currentFilterPredicate];
	NSMutableArray *andPredicates = [[NSMutableArray alloc] initWithCapacity:2];
	if (logLevel)
	{
		NSExpression *lhs = [NSExpression expressionForKeyPath:@"level"];
		NSExpression *rhs = [NSExpression expressionForConstantValue:[NSNumber numberWithInteger:logLevel]];
		[andPredicates addObject:[NSComparisonPredicate predicateWithLeftExpression:lhs
																	rightExpression:rhs
																		   modifier:NSDirectPredicateModifier
																			   type:NSLessThanPredicateOperatorType
																			options:0]];
	}
	if (filterTag != nil)
	{
		NSExpression *lhs = [NSExpression expressionForKeyPath:@"tag"];
		NSExpression *rhs = [NSExpression expressionForConstantValue:filterTag];
		[andPredicates addObject:[NSComparisonPredicate predicateWithLeftExpression:lhs
																	rightExpression:rhs
																		   modifier:NSDirectPredicateModifier
																			   type:NSEqualToPredicateOperatorType
																			options:0]];
	}
	if ([filterString length])
	{
		NSExpression *lhs = [NSExpression expressionForKeyPath:@"messageText"];
		NSExpression *rhs = [NSExpression expressionForConstantValue:filterString];
		[andPredicates addObject:[NSComparisonPredicate predicateWithLeftExpression:lhs
																	rightExpression:rhs
																		   modifier:NSDirectPredicateModifier
																			   type:NSContainsPredicateOperatorType
																			options:NSCaseInsensitivePredicateOption]];
	}
	if ([andPredicates count])
	{
		[andPredicates addObject:p];
		p = [NSCompoundPredicate andPredicateWithSubpredicates:andPredicates];
	}
	p = [NSCompoundPredicate orPredicateWithSubpredicates:[NSArray arrayWithObjects:[self alwaysVisibleEntriesPredicate], p, nil]];
	[filterPredicate autorelease];
	filterPredicate = [p retain];
	[andPredicates release];
}

- (void)refreshMessagesIfPredicateChanged
{
	assert([NSThread isMainThread]);
	NSPredicate *currentPredicate = [[filterPredicate retain] autorelease];
	[self updateFilterPredicate];
	if (![filterPredicate isEqual:currentPredicate])
	{
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshAllMessages:) object:nil];
		[self rebuildQuickFilterPopup];
		[self performSelector:@selector(refreshAllMessages:) withObject:nil afterDelay:0];
	}
}

- (void)tileLogTableRowsInRange:(NSRange)range force:(BOOL)force
{
	NSUInteger displayed = [displayedMessages count];
	NSSize sz = [logTable frame].size;
	NSMutableIndexSet *indexSet = [[NSMutableIndexSet alloc] init];
	for (NSUInteger row = 0; row < range.length && (row+range.location) < displayed; row++)
	{
		LoggerMessage *msg = [displayedMessages objectAtIndex:row+range.location];
		NSSize cachedSize = msg.cachedCellSize;
		if (force || cachedSize.width != sz.width)
		{
			CGFloat cachedHeight = cachedSize.height;
			CGFloat newHeight = cachedHeight;
			if (force)
				msg.cachedCellSize = NSZeroSize;
			switch (msg.type)
			{
				case LOGMSG_TYPE_LOG:
				case LOGMSG_TYPE_BLOCKSTART:
				case LOGMSG_TYPE_BLOCKEND:
					newHeight = [LoggerMessageCell heightForCellWithMessage:msg maxSize:sz showFunctionNames:showFunctionNames];
					break;
				case LOGMSG_TYPE_CLIENTINFO:
				case LOGMSG_TYPE_DISCONNECT:
					newHeight = [LoggerClientInfoCell heightForCellWithMessage:msg maxSize:sz showFunctionNames:showFunctionNames];
					break;
				case LOGMSG_TYPE_MARK:
					newHeight = [LoggerMarkerCell heightForCellWithMessage:msg maxSize:sz showFunctionNames:showFunctionNames];
					break;
			}
			if (newHeight != cachedHeight)
				[indexSet addIndex:row+range.location];
		}
	}
	if ([indexSet count])
		[logTable noteHeightOfRowsWithIndexesChanged:indexSet];
	[indexSet release];
}

- (void)tileLogTable:(BOOL)force
{
	if (force || tableNeedsTiling)
	{
		// tile the visible rows (and a bit more) first, then tile all the rest
		// this gives us a better perceived speed
		NSRect r = [[logTable superview] convertRect:[[logTable superview] bounds] toView:logTable];
		NSRange visibleRows = [logTable rowsInRect:r];
		visibleRows.location = MAX(0, visibleRows.location - 5);
		visibleRows.length = MIN(visibleRows.location + visibleRows.length + 10, [displayedMessages count] - visibleRows.location);
		[self tileLogTableRowsInRange:visibleRows force:force];
		for (NSUInteger i = 0; i < [displayedMessages count]; i += 50)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				NSRange range = NSMakeRange(i, MIN(50, [displayedMessages count] - i));
				if (range.length > 0)
					[self tileLogTableRowsInRange:range force:force];
			});
		}
		tableTiledSinceLastRefresh = YES;
	}
	tableNeedsTiling = NO;
}

- (void)tileLogTableNotification:(NSNotification *)note
{
	[self tileLogTable:NO];
}

- (void)applyFontChanges
{
	[self tileLogTable:YES];
	[logTable reloadData];
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Splitview delegate
// -----------------------------------------------------------------------------
- (void)splitViewDidResizeSubviews:(NSNotification *)notification
{
	tableNeedsTiling = YES;
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Window delegate
// -----------------------------------------------------------------------------
- (void)windowDidResize:(NSNotification *)notification
{
	if (![[self window] inLiveResize])
		[self tileLogTable:YES];
}

- (void)windowDidEndLiveResize:(NSNotification *)notification
{
	[self tileLogTable:YES];
}

- (void)windowDidBecomeMain:(NSNotification *)notification
{
	NSColor *bgColor = [NSColor colorWithCalibratedRed:(218.0 / 255.0)
												 green:(221.0 / 255.0)
												  blue:(229.0 / 255.0)
												 alpha:1.0f];
	[filterSetsTable setBackgroundColor:bgColor];
	[filterTable setBackgroundColor:bgColor];
}

- (void)windowDidResignMain:(NSNotification *)notification
{
	// constants by Brandon Walkin
	NSColor *bgColor = [NSColor colorWithCalibratedRed:(234.0 / 255.0)
												 green:(234.0 / 255.0)
												  blue:(234.0 / 255.0)
												 alpha:1.0f];
	[filterSetsTable setBackgroundColor:bgColor];
	[filterTable setBackgroundColor:bgColor];
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Quick filter
// -----------------------------------------------------------------------------
- (void)rebuildQuickFilterPopup
{
	NSMenu *menu = [quickFilter menu];
	
	// remove all tags
	while ([[menu itemAtIndex:[menu numberOfItems]-1] tag] != -1)
		[menu removeItemAtIndex:[menu numberOfItems]-1];

	// set selected level checkmark
	NSString *levelTitle = nil;
	for (NSMenuItem *menuItem in [menu itemArray])
	{
		if ([menuItem isSeparatorItem])
			continue;
		if ([menuItem tag] == logLevel)
		{
			[menuItem setState:NSOnState];
			levelTitle = [menuItem title];
		}
		else
			[menuItem setState:NSOffState];
	}

	NSString *tagTitle;
	NSMenuItem *item = [[menu itemArray] lastObject];
	if (filterTag == nil)
	{
		[item setState:NSOnState];
		tagTitle = [item title];
	}
	else
	{
		[item setState:NSOffState];
		tagTitle = [NSString stringWithFormat:NSLocalizedString(@"Tag: %@", @""), filterTag];
	}

	for (NSString *tag in [[tags allObjects] sortedArrayUsingSelector:@selector(localizedCompare:)])
	{
		item = [[NSMenuItem alloc] initWithTitle:tag action:@selector(selectQuickFilterTag:) keyEquivalent:@""];
		[item setRepresentedObject:tag];
		[item setIndentationLevel:1];
		if ([filterTag isEqualToString:tag])
			[item setState:NSOnState];
		[menu addItem:item];
		[item release];
	}

	[quickFilter setTitle:[NSString stringWithFormat:@"%@ | %@", levelTitle, tagTitle]];
	
	self.hasQuickFilter = (filterString != nil || filterTag != nil || logLevel != 0);
}

- (void)addTags:(NSArray *)newTags
{
	// complete the set of "seen" tags in messages
	// if changed, update the quick filter popup
	NSUInteger numTags = [tags count];
	[tags addObjectsFromArray:newTags];
	if ([tags count] != numTags)
		[self rebuildQuickFilterPopup];
}

- (IBAction)selectQuickFilterTag:(id)sender
{
	if (filterTag != [sender representedObject])
	{
		self.filterTag = [sender representedObject];
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshMessagesIfPredicateChanged) object:nil];
		[self performSelector:@selector(refreshMessagesIfPredicateChanged) withObject:nil afterDelay:0];
	}
}

- (IBAction)selectQuickFilterLevel:(id)sender
{
	int level = [sender tag];
	if (level != logLevel)
	{
		logLevel = level;
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshMessagesIfPredicateChanged) object:nil];
		[self performSelector:@selector(refreshMessagesIfPredicateChanged) withObject:nil afterDelay:0];
	}
}

- (IBAction)resetQuickFilter:(id)sender
{
	[filterString release];
	filterString = @"";
	[filterTag release];
	filterTag = nil;
	logLevel = 0;
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
	if (attachedConnection.connected)
	{
		NSRect r = [[logTable superview] convertRect:[[logTable superview] bounds] toView:logTable];
		NSRange visibleRows = [logTable rowsInRect:r];
		BOOL lastVisible = (visibleRows.location == NSNotFound ||
							visibleRows.length == 0 ||
							(visibleRows.location + visibleRows.length) >= lastMessageRow);
		[logTable noteNumberOfRowsChanged];
		if (lastVisible)
			[logTable scrollRowToVisible:[displayedMessages count] - 1];
		lastMessageRow = [displayedMessages count];
	}
	else
	{
		[logTable noteNumberOfRowsChanged];
	}
	self.info = [NSString stringWithFormat:NSLocalizedString(@"%u messages", @""), [displayedMessages count]];
}

- (void)appendMessagesToTable:(NSArray *)messages
{
	assert([NSThread isMainThread]);
	[displayedMessages addObjectsFromArray:messages];

	// schedule a table reload. Do this asynchronously (and cancellable-y) so we can limit the
	// number of reload requests in case of high load
//	if (attachedConnection.connected)
//	{
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(messagesAppendedToTable) object:nil];
		[self performSelector:@selector(messagesAppendedToTable) withObject:nil afterDelay:0];
//	}
//	else
//	{
//		[self messagesAppendedToTable];
//		[[self window] displayIfNeeded];
//	}
}

- (IBAction)openDetailsWindow:(id)sender
{
	// open a details view window for the selected messages
	if (detailsWindowController == nil)
	{
		detailsWindowController = [[LoggerDetailsWindowController alloc] initWithWindowNibName:@"LoggerDetailsWindow"];
		[detailsWindowController window];	// force window to load
		[[self document] addWindowController:detailsWindowController];
	}
	[detailsWindowController setMessages:[displayedMessages objectsAtIndexes:[logTable selectedRowIndexes]]];
	[detailsWindowController showWindow:self];
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Filtering
// -----------------------------------------------------------------------------
- (void)refreshAllMessages:(NSArray *)selectedMessages
{
	assert([NSThread isMainThread]);
	@synchronized (attachedConnection.messages)
	{
		id messageToMakeVisible = [selectedMessages objectAtIndex:0];
		if (messageToMakeVisible == nil)
		{
			// Remember the currently selected messages
			NSIndexSet *selectedRows = [logTable selectedRowIndexes];
			if ([selectedRows count])
				selectedMessages = [displayedMessages objectsAtIndexes:selectedRows];

			NSRect r = [[logTable superview] convertRect:[[logTable superview] bounds] toView:logTable];
			NSRange visibleRows = [logTable rowsInRect:r];
			if (visibleRows.length != 0)
			{
				NSIndexSet *selectedVisible = [selectedRows indexesInRange:visibleRows options:0 passingTest:^(NSUInteger idx, BOOL *stop){return YES;}];
				if ([selectedVisible count])
					messageToMakeVisible = [displayedMessages objectAtIndex:[selectedVisible firstIndex]];
				else
					messageToMakeVisible = [displayedMessages objectAtIndex:visibleRows.location];
			}
		}

		// Process logs by chunks (@@@ TODO: due to the serial scheduling of events, I'm not sure splitting
		// in chunks brings any value -- may simplify this code and process everything at once, filtering
		// is in any case much faster than display)
		NSUInteger numMessages = [attachedConnection.messages count];
		for (int i = 0; i < numMessages;)
		{
			if (i == 0)
			{
				dispatch_async(messageFilteringQueue, ^{
					dispatch_async(dispatch_get_main_queue(), ^{
						lastMessageRow = 0;
						[displayedMessages removeAllObjects];
						[logTable reloadData];
						self.info = NSLocalizedString(@"No message", @"");
					});
				});
			}
			NSUInteger length = MIN(4096, numMessages - i);
			if (length)
			{
				dispatch_async(messageFilteringQueue, ^{
					[self filterIncomingMessages:[attachedConnection.messages subarrayWithRange:NSMakeRange(i, length)]
									  withFilter:filterPredicate];
				});
			}
			i += length;
		}

		// Stuff we want to do only when filtering is complete. To do this, we enqueue
		// one more operation to the message filtering queue, with the only goal of
		// being executed only at the end of the filtering process
		dispatch_async(messageFilteringQueue, ^{
			dispatch_async(dispatch_get_main_queue(), ^{
				if (tableTiledSinceLastRefresh)
				{
					// Here's the drill: if the table has been tiled since the last refresh,
					// and we're now changing our view of filters, in most cases messages
					// that were not on screen at the time the size changed have invalid cached
					// size. We need to re-tile the table, but want to go through -tileLogTable
					// which takes care of doing it first for visible items, giving a perception
					// of speed. Therefore, we schedule a block on the filtering serial queue
					// which will get executed AFTER all the messages have been refreshed, and
					// will in turn schedule a table retiling. Pfew.
					[self tileLogTable:YES];
					tableTiledSinceLastRefresh = NO;
				}
				
				// perform table updates now, so we can properly reselect afterwards
				[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(messagesAppendedToTable) object:nil];
				[self messagesAppendedToTable];

				if ([selectedMessages count])
				{
					// If there were selected rows, try to reselect them
					NSMutableIndexSet *newSelectionIndexes = [[NSMutableIndexSet alloc] init];
					for (id msg in selectedMessages)
					{
						NSInteger msgIndex = [displayedMessages indexOfObjectIdenticalTo:msg];
						if (msgIndex != NSNotFound)
							[newSelectionIndexes addIndex:(NSUInteger)msgIndex];
					}
					if ([newSelectionIndexes count])
					{
						[logTable selectRowIndexes:newSelectionIndexes byExtendingSelection:NO];
						[[self window] makeFirstResponder:logTable];
					}
					[newSelectionIndexes release];
				}
				if (messageToMakeVisible != nil)
				{
					// Restore the logical location in the message flow, to keep the user
					// in-context
					NSUInteger msgIndex;
					id msg = messageToMakeVisible;
					@synchronized(attachedConnection.messages)
					{
						while ((msgIndex = [displayedMessages indexOfObjectIdenticalTo:msg]) == NSNotFound)
						{
							NSUInteger where = [attachedConnection.messages indexOfObjectIdenticalTo:msg];
							if (where == 0)
								msgIndex = 0;
							else
								msg = [attachedConnection.messages objectAtIndex:where-1];
						}
						if (msgIndex != NSNotFound)
							[logTable scrollRowToVisible:msgIndex];
					}
				}
				[self rebuildMarksSubmenu];
			});
		});
	}
	tableTiledSinceLastRefresh = NO;
}

- (void)filterIncomingMessages:(NSArray *)messages
{
	assert([NSThread isMainThread]);
	dispatch_async(messageFilteringQueue, ^{
		[self filterIncomingMessages:(NSArray *)messages
						  withFilter:filterPredicate];
	});
}

- (void)filterIncomingMessages:(NSArray *)messages
					withFilter:(NSPredicate *)aFilter
{
	// collect all tags
	NSArray *msgTags = [messages valueForKeyPath:@"@distinctUnionOfObjects.tag"];

	// find out which messages we want to keep. Executed on the message filtering queue
	NSArray *filteredMessages = [messages filteredArrayUsingPredicate:aFilter];
	if ([filteredMessages count])
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			[self appendMessagesToTable:filteredMessages];
			[self addTags:msgTags];
		});
	}
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Properties and bindings
// -----------------------------------------------------------------------------
- (void)setAttachedConnection:(LoggerConnection *)aConnection
{
	if (aConnection != nil)
	{
		attachedConnection = [aConnection retain];
		attachedConnection.attachedToWindow = YES;
		dispatch_async(dispatch_get_main_queue(), ^{
			[self updateClientInfo];
			[self refreshAllMessages:nil];
		});
	}
	else if (attachedConnection != nil)
	{
		attachedConnection.attachedToWindow = NO;
		[attachedConnection release];
		attachedConnection = nil;
	}
}

- (void)setFilterString:(NSString *)newString
{
	if (newString == nil)
		newString = @"";

	if (newString != filterString && ![filterString isEqualToString:newString])
	{
		[filterString autorelease];
		filterString = [newString copy];
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshMessagesIfPredicateChanged) object:nil];
		[self performSelector:@selector(refreshMessagesIfPredicateChanged) withObject:nil afterDelay:0];
		self.hasQuickFilter = (filterString != nil || filterTag != nil || logLevel != 0);
	}
}

- (void)setShowFunctionNames:(NSNumber *)value
{
	BOOL b = [value boolValue];
	if (b != showFunctionNames)
	{
		[self willChangeValueForKey:@"showFunctionNames"];
		showFunctionNames = b;
		[self tileLogTable:YES];
		dispatch_async(dispatch_get_main_queue(), ^{
			[logTable reloadData];
		});
		[self didChangeValueForKey:@"showFunctionNames"];
		dispatch_async(dispatch_get_main_queue(), ^{
			[showFunctionNamesButton setState:showFunctionNames];
		});
	}
}

- (NSNumber *)showFunctionNames
{
	return [NSNumber numberWithInt:(showFunctionNames ? NSOnState : NSOffState)];
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark LoggerConnectionDelegate
// -----------------------------------------------------------------------------
- (void)connection:(LoggerConnection *)theConnection
didReceiveMessages:(NSArray *)theMessages
			 range:(NSRange)rangeInMessagesList
{
	if (loadComplete)
	{
		// We need to hop thru the main thread to have a recent and stable copy of the filter string and current filter
		dispatch_async(dispatch_get_main_queue(), ^{
			[self filterIncomingMessages:theMessages];
		});
	}
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
	if (object == attachedConnection)
	{
		if ([keyPath isEqualToString:@"clientIDReceived"])
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				[self updateClientInfo];
			});			
		}
	}
	else if (object == filterListController)
	{
		if ([keyPath isEqualToString:@"selectedObjects"] && [filterListController selectionIndex] != NSNotFound)
		{
			[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshMessagesIfPredicateChanged) object:nil];
			[self performSelector:@selector(refreshMessagesIfPredicateChanged) withObject:nil afterDelay:0];
		}
	}
	else if (object == filterSetsListController)
	{
		if ([keyPath isEqualToString:@"arrangedObjects"])
		{
			// we'll be called when arrangedObjects change, that is when a filter set is added,
			// removed or renamed. Use this occasion to save the filters definition.
			[(LoggerAppDelegate *)[NSApp delegate] saveFiltersDefinition];
		}
	}
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark NSTableDelegate
// -----------------------------------------------------------------------------
- (NSCell *)tableView:(NSTableView *)tableView dataCellForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (tableView == logTable && row >= 0 && row < [displayedMessages count])
	{
		LoggerMessage *msg = [displayedMessages objectAtIndex:row];
		switch (msg.type)
		{
			case LOGMSG_TYPE_LOG:
			case LOGMSG_TYPE_BLOCKSTART:
			case LOGMSG_TYPE_BLOCKEND:
				return messageCell;
			case LOGMSG_TYPE_CLIENTINFO:
			case LOGMSG_TYPE_DISCONNECT:
				return clientInfoCell;
			case LOGMSG_TYPE_MARK:
				return markerCell;
			default:
				assert(false);
				break;
		}
	}
	return nil;
}

- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if (aTableView == logTable && rowIndex >= 0 && rowIndex < [displayedMessages count])
	{
		// setup the message to be displayed
		LoggerMessageCell *cell = (LoggerMessageCell *)aCell;
		cell.message = [displayedMessages objectAtIndex:rowIndex];
		cell.shouldShowFunctionNames = showFunctionNames;

		// if previous message is a Mark, go back a bit more to get the real previous message
		// if previous message is ClientInfo, don't use it.
		NSInteger idx = rowIndex - 1;
		LoggerMessage *prev = nil;
		while (prev == nil && idx >= 0)
		{
			prev = [displayedMessages objectAtIndex:idx--];
			if (prev.type == LOGMSG_TYPE_CLIENTINFO || prev.type == LOGMSG_TYPE_MARK)
				prev = nil;
		} 
		
		cell.previousMessage = prev;
	}
	else if (aTableView == filterSetsTable)
	{
		NSArray *filterSetsList = [filterSetsListController arrangedObjects];
		if (rowIndex >= 0 && rowIndex < [filterSetsList count])
		{
			NSTextFieldCell *tc = (NSTextFieldCell *)aCell;
			NSDictionary *filterSet = [filterSetsList objectAtIndex:rowIndex];
			if ([[filterSet objectForKey:@"uid"] integerValue] == 1)
				[tc setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
			else
				[tc setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
		}
	}
	else if (aTableView == filterTable)
	{
		// want the "All Logs" entry (immutable) in Bold
		NSArray *filterList = [filterListController arrangedObjects];
		if (rowIndex >= 0 && rowIndex < [filterList count])
		{
			NSTextFieldCell *tc = (NSTextFieldCell *)aCell;
			NSDictionary *filter = [filterList objectAtIndex:rowIndex];
			if ([[filter objectForKey:@"uid"] integerValue] == 1)
				[tc setFont:[NSFont boldSystemFontOfSize:[NSFont systemFontSize]]];
			else
				[tc setFont:[NSFont systemFontOfSize:[NSFont systemFontSize]]];
		}
	}
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
	assert([NSThread isMainThread]);
	if (tableView == logTable && row >= 0 && row < [displayedMessages count])
	{
		// we play tricks to speed up live resizing and others: the cell will
		// always display using its cached size, which is only recomputed the
		// first time and when tileLogTable is called. Due to the large number
		// of entries we can have in the table, this is a requirement.
		LoggerMessage *message = [displayedMessages objectAtIndex:row];
		NSSize sz = [tableView frame].size;
		NSSize cachedSize = message.cachedCellSize;
		if (cachedSize.width == sz.width)
			return cachedSize.height;
		CGFloat newHeight = cachedSize.height;

		// don't recompute immediately while in live resize
		if (newHeight != 0 && [[self window] inLiveResize])
			return newHeight;
		
		switch (message.type)
		{
			case LOGMSG_TYPE_LOG:
			case LOGMSG_TYPE_BLOCKSTART:
			case LOGMSG_TYPE_BLOCKEND:
				newHeight = [LoggerMessageCell heightForCellWithMessage:message
																maxSize:sz
													  showFunctionNames:showFunctionNames];
				break;
			case LOGMSG_TYPE_CLIENTINFO:
			case LOGMSG_TYPE_DISCONNECT:
				newHeight = [LoggerClientInfoCell heightForCellWithMessage:message
																   maxSize:sz
														 showFunctionNames:NO];
				break;
				
			case LOGMSG_TYPE_MARK:
				newHeight = [LoggerMarkerCell heightForCellWithMessage:message
															   maxSize:sz
													 showFunctionNames:NO];
				break;

			default:
				break;
		}
		if (cachedSize.height != newHeight)
			[tableView performSelector:@selector(noteHeightOfRowsWithIndexesChanged:) withObject:[NSIndexSet indexSetWithIndex:row] afterDelay:0];
		return newHeight;
	}
	return [tableView rowHeight];
}

- (void)tableViewSelectionDidChange:(NSNotification *)aNotification
{
	if ([aNotification object] == logTable)
	{
		self.messagesSelected = ([logTable selectedRow] >= 0);
		if (messagesSelected && detailsWindowController != nil && [[detailsWindowController window] isVisible])
			[detailsWindowController setMessages:[displayedMessages objectsAtIndexes:[logTable selectedRowIndexes]]];
	}
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark NSTableDataSource
// -----------------------------------------------------------------------------
- (int)numberOfRowsInTableView:(NSTableView *)tableView
{
	return [displayedMessages count];
}

- (id)tableView:(NSTableView *)tableView
	objectValueForTableColumn:(NSTableColumn *)tableColumn
	row:(int)rowIndex
{
	if (rowIndex >= 0 && rowIndex < [displayedMessages count])
		return [displayedMessages objectAtIndex:rowIndex];
	return nil;
}

- (BOOL)tableView:(NSTableView *)tv writeRowsWithIndexes:(NSIndexSet *)rowIndexes toPasteboard:(NSPasteboard*)pboard
{
	if (tv == logTable)
	{
		NSArray *draggedMessages = [displayedMessages objectsAtIndexes:rowIndexes];
		NSMutableString *string = [[NSMutableString alloc] initWithCapacity:[draggedMessages count] * 128];
		for (LoggerMessage *msg in draggedMessages)
			[string appendString:[msg textRepresentation]];
		[pboard writeObjects:[NSArray arrayWithObject:string]];
		[string release];
		return YES;
	}
	if (tv == filterTable)
	{
		NSPasteboardItem *item = [[NSPasteboardItem alloc] init];
		NSArray *filters = [[filterListController arrangedObjects] objectsAtIndexes:rowIndexes];
		[item setData:[NSKeyedArchiver archivedDataWithRootObject:filters] forType:kNSLoggerFilterPasteboardType];
		[pboard writeObjects:[NSArray arrayWithObject:item]];
		[item release];
		return YES;
	}
	return NO;
}

- (NSDragOperation)tableView:(NSTableView*)tv validateDrop:(id <NSDraggingInfo>)dragInfo proposedRow:(NSInteger)row proposedDropOperation:(NSTableViewDropOperation)op
{
	if (tv == filterSetsTable)
	{
		NSArray *filterSets = [filterSetsListController arrangedObjects];
		if (row >= 0 && row < [filterSets count] && row != [filterSetsListController selectionIndex])
		{
			if (op != NSTableViewDropOn)
				[filterSetsTable setDropRow:row dropOperation:NSTableViewDropOn];
			return NSDragOperationCopy;
		}
	}
	else if (tv == filterTable && [dragInfo draggingSource] != filterTable)
	{
		NSArray *filters = [filterListController arrangedObjects];
		if (row >= 0 && row < [filters count])
		{
			// highlight entire table
			[filterTable setDropRow:-1 dropOperation:NSTableViewDropOn];
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
	if (tv == filterSetsTable)
	{
		// Only add those filters which don't exist yet
		NSArray *filterSets = [filterSetsListController arrangedObjects];
		NSMutableDictionary *filterSet = [filterSets objectAtIndex:row];
		NSMutableArray *existingFilters = [filterSet mutableArrayValueForKey:@"filters"];
		for (NSMutableDictionary *filter in newFilters)
		{
			if ([existingFilters indexOfObject:filter] == NSNotFound)
			{
				[existingFilters addObject:filter];
				added = YES;
			}
		}
		[filterSetsListController setSelectedObjects:[NSArray arrayWithObject:filterSet]];
	}
	else if (tv == filterTable)
	{
		NSMutableArray *addedFilters = [[NSMutableArray alloc] init];
		for (NSMutableDictionary *filter in newFilters)
		{
			if ([[filterListController arrangedObjects] indexOfObject:filter] == NSNotFound)
			{
				[filterListController addObject:filter];
				[addedFilters addObject:filter];
				added = YES;
			}
		}
		if (added)
			[filterListController setSelectedObjects:addedFilters];
		[addedFilters release];
	}
	if (added)
		[(LoggerAppDelegate *)[NSApp delegate] saveFiltersDefinition];
	return added;
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Filter sets management
// -----------------------------------------------------------------------------
- (IBAction)addFilterSet:(id)sender
{
	NSDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
						  [(LoggerAppDelegate *)[NSApp delegate] nextUniqueFilterIdentifier:[filterSetsListController arrangedObjects]], @"uid",
						  NSLocalizedString(@"New Filter Set", @""), @"title",
						  [(LoggerAppDelegate *)[NSApp delegate] defaultFilters], @"filters",
						  nil];
	[filterSetsListController addObject:dict];
	NSUInteger index = [[filterSetsListController arrangedObjects] indexOfObject:dict];
	[filterSetsTable editColumn:0 row:index withEvent:nil select:YES];
}

- (IBAction)deleteSelectedFilterSet:(id)sender
{
	// @@@ TODO: make this undoable
	[filterSetsListController removeObjects:[filterSetsListController selectedObjects]];
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Filter editor
// -----------------------------------------------------------------------------
- (NSPredicate *)currentFilterPredicate
{
	// the current filter is the aggregate (OR clause) of all the selected filters
	NSArray *predicates = [[filterListController selectedObjects] valueForKey:@"predicate"];
	if (![predicates count])
		return [NSPredicate predicateWithValue:YES];
	if ([predicates count] == 1)
		return [predicates lastObject];
	return [NSCompoundPredicate orPredicateWithSubpredicates:predicates];
}

- (IBAction)addFilter:(id)sender
{
	NSDictionary *filterSet = [[filterSetsListController selectedObjects] lastObject];
	assert(filterSet != nil);
	NSDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
						  [(LoggerAppDelegate *)[NSApp delegate] nextUniqueFilterIdentifier:[filterSet objectForKey:@"filters"]], @"uid",
						  NSLocalizedString(@"New filter", @""), @"title",
						  [NSCompoundPredicate andPredicateWithSubpredicates:[NSArray array]], @"predicate",
						  nil];
	[filterListController addObject:dict];
	[filterListController setSelectedObjects:[NSArray arrayWithObject:dict]];
	[self startEditingFilter:self];
}

- (IBAction)startEditingFilter:(id)sender
{
	// start editing filter, unless no selection (happens when double-clicking the header)
	// or when trying to edit the "All Logs" entry which is immutable
	NSDictionary *dict = [[filterListController selectedObjects] lastObject];
	if (dict == nil || [[dict objectForKey:@"uid"] integerValue] == 1)
		return;
	[filterName setStringValue:[dict objectForKey:@"title"]];
	NSPredicate *predicate = [dict objectForKey:@"predicate"];
	[filterEditor setObjectValue:[[predicate copy] autorelease]];

	[NSApp beginSheet:filterEditorWindow
	   modalForWindow:[self window]
		modalDelegate:self
	   didEndSelector:@selector(filterEditSheetDidEnd:returnCode:contextInfo:)
		  contextInfo:NULL];
}

- (IBAction)cancelFilterEdition:(id)sender
{
	[NSApp endSheet:filterEditorWindow returnCode:0];
}

- (IBAction)validateFilterEdition:(id)sender
{
	[NSApp endSheet:filterEditorWindow returnCode:1];
}

- (void)filterEditSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
	if (returnCode)
	{
		// update filter & refresh list
		// @@@ TODO: make this undoable
		NSMutableDictionary *dict = [[filterListController selectedObjects] lastObject];
		NSPredicate *predicate = [filterEditor predicate];
		if (predicate == nil)
			predicate = [NSCompoundPredicate orPredicateWithSubpredicates:[NSArray array]];
		[dict setObject:predicate forKey:@"predicate"];
		NSString *title = [[filterName stringValue] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if ([title length])
			[dict setObject:title forKey:@"title"];
		[filterListController setSelectedObjects:[NSArray arrayWithObject:dict]];
		
		[(LoggerAppDelegate *)[NSApp delegate] saveFiltersDefinition];
	}
	[filterEditorWindow orderOut:self];
}

- (IBAction)deleteSelectedFilters:(id)sender
{
	// @@@ TODO: make this undoable
	[filterListController removeObjects:[filterListController selectedObjects]];
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Markers
// -----------------------------------------------------------------------------
- (void)rebuildMarksSubmenu
{
	NSMenuItem *marksSubmenu = [[[[NSApp mainMenu] itemWithTag:TOOLS_MENU_ITEM_TAG] submenu] itemWithTag:TOOLS_MENU_JUMP_TO_MARK_TAG];
	NSExpression *lhs = [NSExpression expressionForKeyPath:@"type"];
	NSExpression *rhs = [NSExpression expressionForConstantValue:[NSNumber numberWithInteger:LOGMSG_TYPE_MARK]];
	NSPredicate *predicate = [NSComparisonPredicate predicateWithLeftExpression:lhs
																rightExpression:rhs
																	   modifier:NSDirectPredicateModifier
																		   type:NSEqualToPredicateOperatorType
																		options:0];
	NSArray *marks = [displayedMessages filteredArrayUsingPredicate:predicate];
	NSMenu *menu = [marksSubmenu submenu];
	[menu removeAllItems];
	if (![marks count])
	{
		NSMenuItem *noMarkItem = [[NSMenuItem alloc] initWithTitle:NSLocalizedString(@"No Mark", @"")
															action:nil
													 keyEquivalent:@""];
		[noMarkItem setEnabled:NO];
		[menu addItem:noMarkItem];
		[noMarkItem release];
	}
	else for (LoggerMessage *mark in marks)
	{
		NSMenuItem *markItem = [[NSMenuItem alloc] initWithTitle:mark.message
														  action:@selector(jumpToMark:)
												   keyEquivalent:@""];
		[markItem setRepresentedObject:mark];
		[markItem setTarget:self];
		[menu addItem:markItem];
		[markItem release];
	}
}

- (void)jumpToMark:(NSMenuItem *)markMenuItem
{
	LoggerMessage *mark = [markMenuItem representedObject];
	NSUInteger idx = [displayedMessages indexOfObjectIdenticalTo:mark];
	if (idx == NSNotFound)
	{
		// actually, shouldn't happen
		NSBeep();
	}
	else
	{
		[logTable scrollRowToVisible:idx];
		[logTable selectRowIndexes:[NSIndexSet indexSetWithIndex:idx] byExtendingSelection:NO];
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
	dispatch_async(messageFilteringQueue, ^{
		// then we serialize all operations modifying the messages list in the connection's
		// message processing queue
		dispatch_async(attachedConnection.messageProcessingQueue, ^{
			NSRange range;
			@synchronized(attachedConnection.messages)
			{
				range.location = [attachedConnection.messages count];
				range.length = 1;
				if (beforeMessage != nil)
				{
					NSUInteger pos = [attachedConnection.messages indexOfObjectIdenticalTo:beforeMessage];
					if (pos != NSNotFound)
						range.location = pos;
				}
				[attachedConnection.messages insertObject:mark atIndex:range.location];
			}
			dispatch_async(dispatch_get_main_queue(), ^{
				[[self document] updateChangeCount:NSChangeDone];
				[self refreshAllMessages:[NSArray arrayWithObjects:mark, beforeMessage, nil]];
			});
		});
	});

	[mark release];
}

- (void)addMarkWithTitleBeforeMessage:(LoggerMessage *)aMessage
{
	NSString *s = [NSString stringWithFormat:NSLocalizedString(@"Mark - %@", @""),
				   [NSDateFormatter localizedStringFromDate:[NSDate date]
												  dateStyle:NSDateFormatterShortStyle
												  timeStyle:NSDateFormatterMediumStyle]];
	[markTitleField setStringValue:s];
	
	[NSApp beginSheet:markTitleWindow
	   modalForWindow:[self window]
		modalDelegate:self
	   didEndSelector:@selector(addMarkSheetDidEnd:returnCode:contextInfo:)
		  contextInfo:[aMessage retain]];
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
	NSUInteger rowIndex = [logTable selectedRow];
	if (rowIndex >= 0 && rowIndex < [displayedMessages count])
		[self addMarkWithTitleBeforeMessage:[displayedMessages objectAtIndex:rowIndex]];
}

- (IBAction)deleteMark:(id)sender
{
	NSUInteger rowIndex = [logTable selectedRow];
	if (rowIndex >= 0 && rowIndex < [displayedMessages count])
	{
		LoggerMessage *markMessage = [displayedMessages objectAtIndex:rowIndex];
		assert(markMessage.type == LOGMSG_TYPE_MARK);
		[displayedMessages removeObjectAtIndex:rowIndex];
		[logTable reloadData];
		[self rebuildMarksSubmenu];
		dispatch_async(messageFilteringQueue, ^{
			// then we serialize all operations modifying the messages list in the connection's
			// message processing queue
			dispatch_async(attachedConnection.messageProcessingQueue, ^{
				@synchronized(attachedConnection.messages) {
					[attachedConnection.messages removeObjectIdenticalTo:markMessage];
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
	[NSApp endSheet:markTitleWindow returnCode:0];
}

- (IBAction)validateAddMark:(id)sender
{
	[NSApp endSheet:markTitleWindow returnCode:1];
}

- (void)addMarkSheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
{
	if (returnCode)
		[self addMarkWithTitleString:[markTitleField stringValue] beforeMessage:(LoggerMessage *)contextInfo];
	if (contextInfo != NULL)
		[(id)contextInfo release];
	[markTitleWindow orderOut:self];
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
		NSUInteger rowIndex = [logTable selectedRow];
		if (rowIndex >= 0 && rowIndex < [displayedMessages count])
		{
			LoggerMessage *markMessage = [displayedMessages objectAtIndex:rowIndex];
			return (markMessage.type == LOGMSG_TYPE_MARK);
		}
		return NO;
	}
	return YES;
}

@end

