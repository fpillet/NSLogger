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
#import "LoggerWindowController.h"
#import "LoggerDetailsWindowController.h"
#import "LoggerMessageCell.h"
#import "LoggerClientInfoCell.h"
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
- (void)refreshAllMessages;
- (void)filterIncomingMessages:(NSArray *)messages withFilter:(NSPredicate *)aFilter;
- (NSPredicate *)currentFilterPredicate;
- (void)tileLogTable:(BOOL)force;
@end


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
	[filterListController removeObserver:self forKeyPath:@"selectedObjects"];
	dispatch_release(messageFilteringQueue);
	[attachedConnection release];
	[info release];
	[filterString release];
	[filterTag release];
	[filterPredicate release];
	[displayedMessages release];
	[tags release];
	[clientInfoCell release];
	[super dealloc];
}

- (void)windowDidLoad
{
	messageCell = [[LoggerMessageCell alloc] init];
	clientInfoCell = [[LoggerClientInfoCell alloc] init];

//	NSTableColumn *tc = [logTable tableColumnWithIdentifier:@"message"];
//	LoggerMessageCell *cell = [[LoggerMessageCell alloc] init];
//	[tc setDataCell:cell];
//	[cell release];
	
	[logTable setIntercellSpacing:NSMakeSize(0,0)];
	[logTable setTarget:self];
	[logTable setDoubleAction:@selector(openDetailsWindow:)];

	[logTable registerForDraggedTypes:[NSArray arrayWithObject:NSPasteboardTypeString]];
	[logTable setDraggingSourceOperationMask:NSDragOperationNone forLocal:YES];
	[logTable setDraggingSourceOperationMask:NSDragOperationCopy forLocal:NO];

	[filterTable setTarget:self];
	[filterTable setIntercellSpacing:NSMakeSize(0,0)];
	[filterTable setDoubleAction:@selector(startEditingFilter:)];
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
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshAllMessages) object:nil];
		[self rebuildQuickFilterPopup];
		[self performSelector:@selector(refreshAllMessages) withObject:nil afterDelay:0];
	}
}

- (void)tileLogTableRowsInRange:(NSRange)range
{
	NSUInteger displayed = [displayedMessages count];
	NSSize sz = [logTable frame].size;
	NSMutableIndexSet *indexSet = [[NSMutableIndexSet alloc] init];
	for (NSUInteger row = 0; row < range.length && (row+range.location) < displayed; row++)
	{
		LoggerMessage *msg = [displayedMessages objectAtIndex:row+range.location];
		//msg.cachedCellSize = NSZeroSize;
		CGFloat cachedHeight = msg.cachedCellSize.height;
		CGFloat newHeight = [LoggerMessageCell heightForCellWithMessage:msg maxSize:sz];
		if (newHeight != cachedHeight)
			[indexSet addIndex:row+range.location];
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
		[self tileLogTableRowsInRange:visibleRows];
		for (NSUInteger i = 0; i < [displayedMessages count]; i += 50)
		{
			dispatch_async(dispatch_get_main_queue(), ^{
				NSRange range = NSMakeRange(i, MIN(50, [displayedMessages count] - i));
				if (range.length > 0)
					[self tileLogTableRowsInRange:range];
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
	[filterTable setBackgroundColor:[NSColor colorWithCalibratedRed:(218.0 / 255.0)
															  green:(221.0 / 255.0)
															   blue:(229.0 / 255.0)
															  alpha:1.0f]];
}

- (void)windowDidResignMain:(NSNotification *)notification
{
	// constants by Brandon Walkin
	[filterTable setBackgroundColor:[NSColor colorWithCalibratedRed:(234.0 / 255.0)
															  green:(234.0 / 255.0)
															   blue:(234.0 / 255.0)
															  alpha:1.0f]];
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
	if (attachedConnection.connected)
	{
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(messagesAppendedToTable) object:nil];
		[self performSelector:@selector(messagesAppendedToTable) withObject:nil afterDelay:0];
	}
	else
	{
		[self messagesAppendedToTable];
		[[self window] displayIfNeeded];
	}
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
- (void)refreshAllMessages
{
	assert([NSThread isMainThread]);
	@synchronized (attachedConnection.messages)
	{
		// Process logs by chunks
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
			dispatch_async(messageFilteringQueue, ^{
				dispatch_async(dispatch_get_main_queue(), ^{
					[self tileLogTable:YES];
					tableTiledSinceLastRefresh = NO;
				});
			});
		}
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
	[attachedConnection release];
	if (aConnection != nil)
	{
		attachedConnection = [aConnection retain];
		if (!attachedConnection.connected)
		{
			[self performSelectorOnMainThread:@selector(updateClientInfo) withObject:nil waitUntilDone:NO];
			if (attachedConnection.restoredFromSave)
				[self performSelectorOnMainThread:@selector(refreshAllMessages) withObject:nil waitUntilDone:NO];
		}
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

- (void)remoteConnected:(LoggerConnection *)theConnection
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[attachedConnection addObserver:self forKeyPath:@"clientIDReceived" options:0 context:NULL];
		[self updateClientInfo];
	});
}

- (void)remoteDisconnected:(LoggerConnection *)theConnection
{
	dispatch_async(dispatch_get_main_queue(), ^{
		[attachedConnection removeObserver:self forKeyPath:@"clientIDReceived"];
		[self updateClientInfo];
	});
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark KVO
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
			default:
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
		if (rowIndex)
			cell.previousMessage = [displayedMessages objectAtIndex:rowIndex-1];
		else
			cell.previousMessage = nil;
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
		NSSize cachedSize = message.cachedCellSize;
		if (cachedSize.width != 0)
			return cachedSize.height;
		switch (message.type)
		{
			case LOGMSG_TYPE_LOG:
			case LOGMSG_TYPE_BLOCKSTART:
			case LOGMSG_TYPE_BLOCKEND:
				return [LoggerMessageCell heightForCellWithMessage:message
														   maxSize:[tableView frame].size];
			case LOGMSG_TYPE_CLIENTINFO:
			case LOGMSG_TYPE_DISCONNECT:
				return [LoggerClientInfoCell heightForCellWithMessage:message
															  maxSize:[tableView frame].size];
			default:
				break;
		}
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
	if (tv != logTable)
		return NO;

	NSArray *draggedMessages = [displayedMessages objectsAtIndexes:rowIndexes];
	NSMutableString *string = [[NSMutableString alloc] initWithCapacity:[draggedMessages count] * 128];
	for (LoggerMessage *msg in draggedMessages)
		[string appendString:[msg textRepresentation]];
	[pboard writeObjects:[NSArray arrayWithObject:string]];
	[string release];
    return YES;
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
	NSDictionary *dict = [NSMutableDictionary dictionaryWithObjectsAndKeys:
						  [(LoggerAppDelegate *)[NSApp delegate] nextUniqueFilterIdentifier], @"uid",
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
	   didEndSelector:@selector(sheetDidEnd:returnCode:contextInfo:)
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

- (void)sheetDidEnd:(NSWindow *)sheet returnCode:(NSInteger)returnCode contextInfo:(void *)contextInfo
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

@end

