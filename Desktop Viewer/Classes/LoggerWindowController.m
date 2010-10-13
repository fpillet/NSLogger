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
#import "LoggerMessageCell.h"
#import "LoggerMessage.h"
#import "LoggerUtils.h"
#import "LoggerAppDelegate.h"

@interface LoggerWindowController (Private)
- (void)updateClientInfo;
- (void)updateFilterPredicate:(NSPredicate *)currentFilterPredicate;
- (void)refreshAllMessages;
- (void)filterIncomingMessages:(NSArray *)messages withFilter:(NSPredicate *)aFilter;
- (NSPredicate *)currentFilterPredicate;
@end

@implementation LoggerWindowController

@synthesize info, filterString;
@synthesize attachedConnection;

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
		[self setShouldCloseDocument:YES];
	}
	return self;
}

- (void)dealloc
{
	[filterListController removeObserver:self forKeyPath:@"selectedObjects"];
	dispatch_release(messageFilteringQueue);
	[attachedConnection release];
	[info release];
	[filterString release];
	[filterPredicate release];
	[displayedMessages release];
	[super dealloc];
}

- (void)windowDidLoad
{
	NSTableColumn *tc = [logTable tableColumnWithIdentifier:@"message"];
	LoggerMessageCell *cell = [[LoggerMessageCell alloc] init];
	[tc setDataCell:cell];
	[cell release];
	[logTable setIntercellSpacing:NSMakeSize(0, 0)];
	[filterTable setTarget:self];
	[filterTable setDoubleAction:@selector(startEditingFilter:)];
	[filterListController addObserver:self forKeyPath:@"selectedObjects" options:0 context:NULL];
	[self updateFilterPredicate:nil];
	loadComplete = YES;
	if (attachedConnection != nil)
		[self refreshAllMessages];
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

- (void)updateFilterPredicate:(NSPredicate *)currentFilterPredicate
{
	[filterPredicate autorelease];
	if (currentFilterPredicate == nil)
		currentFilterPredicate = [self currentFilterPredicate];
	NSPredicate *p = currentFilterPredicate;
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
	filterPredicate = [p retain];
	[andPredicates release];
}

- (void)refreshMessagesIfPredicateChanged:(NSPredicate *)currentFilterPredicate
{
	assert([NSThread isMainThread]);
	NSPredicate *currentPredicate = [filterPredicate retain];
	[self updateFilterPredicate:currentFilterPredicate];
	if (![filterPredicate isEqual:currentPredicate])
	{
		[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshAllMessages) object:nil];
		[self performSelector:@selector(refreshAllMessages) withObject:nil afterDelay:0];
	}
	[currentPredicate release];	
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Table management
// -----------------------------------------------------------------------------
- (void)appendMessagesToTable:(NSArray *)messages
{
	assert([NSThread isMainThread]);
	[displayedMessages addObjectsFromArray:messages];

	// schedule a table reload. Do this asynchronously (and cancellable-y) so we can limit the
	// number of reload requests in case of high load
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(messagesAppendedToTable) object:nil];
	[self performSelector:@selector(messagesAppendedToTable) withObject:nil afterDelay:0];
}

- (void)messagesAppendedToTable
{
	assert([NSThread isMainThread]);
	NSRect r = [[logTable superview] convertRect:[[logTable superview] bounds] toView:logTable];
	NSRange visibleRows = [logTable rowsInRect:r];
	BOOL lastVisible = (visibleRows.location == NSNotFound ||
						visibleRows.length == 0 ||
						(visibleRows.location + visibleRows.length) >= lastMessageRow);
	[logTable reloadData];
	if (lastVisible)
		[logTable scrollRowToVisible:[displayedMessages count] - 1];
	lastMessageRow = [displayedMessages count];
	self.info = [NSString stringWithFormat:NSLocalizedString(@"%u messages", @""), [displayedMessages count]];
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Filtering
// -----------------------------------------------------------------------------
- (void)refreshAllMessages
{
	assert([NSThread isMainThread]);
	lastMessageRow = 0;
	[displayedMessages removeAllObjects];
	[logTable reloadData];
	@synchronized (attachedConnection.messages)
	{
		// Process logs by bunches of 500
		NSUInteger numMessages = [attachedConnection.messages count];
		for (int i = 0; i < numMessages; i += 500)
		{
			NSUInteger length = MIN(500, numMessages - i);
			if (!length)
				break;
			[self filterIncomingMessages:[attachedConnection.messages subarrayWithRange:NSMakeRange(i, length)]
							  withFilter:filterPredicate];
		}
	}
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
	// find out which messages we want to keep. Executed on the message filtering queue
	NSArray *filteredMessages = [messages filteredArrayUsingPredicate:aFilter];
	if ([filteredMessages count])
	{
		dispatch_async(dispatch_get_main_queue(), ^{
			[self appendMessagesToTable:filteredMessages];
		});
	}
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark Properties accessors
// -----------------------------------------------------------------------------
- (void)setAttachedConnection:(LoggerConnection *)aConnection
{
	[attachedConnection release];
	if (aConnection != nil)
	{
		attachedConnection = [aConnection retain];
		[self performSelectorOnMainThread:@selector(updateClientInfo) withObject:nil waitUntilDone:NO];
		[self performSelectorOnMainThread:@selector(refreshAllMessages) withObject:nil waitUntilDone:NO];
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
		[self updateFilterPredicate:nil];
		[self refreshAllMessages];
	}
}

- (NSNumber *)logLevel
{
	return [NSNumber numberWithInteger:logLevel];
}

- (void)setLogLevel:(NSNumber *)newLogLevel
{
	int l = [newLogLevel integerValue];
	if (l == -1)
		l = 0;
	if (l != logLevel)
	{
		[self willChangeValueForKey:@"logLevel"];
		logLevel = l;
		[self didChangeValueForKey:@"logLevel"];
		[self updateFilterPredicate:nil];
		[self refreshAllMessages];
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
			[self performSelectorOnMainThread:@selector(refreshMessagesIfPredicateChanged:) withObject:nil waitUntilDone:NO];
		}
	}
}

// -----------------------------------------------------------------------------
#pragma mark -
#pragma mark NSTableDelegate
// -----------------------------------------------------------------------------
- (void)tableView:(NSTableView *)aTableView willDisplayCell:(id)aCell forTableColumn:(NSTableColumn *)aTableColumn row:(NSInteger)rowIndex
{
	if (aTableView == logTable)
	{
		// setup the message to be displayed
		LoggerMessageCell *cell = (LoggerMessageCell *)aCell;
		cell.message = [displayedMessages objectAtIndex:rowIndex];
		if (rowIndex)
			cell.previousMessage = [displayedMessages objectAtIndex:rowIndex-1];
		else
			cell.previousMessage = nil;
	}
}

- (CGFloat)tableView:(NSTableView *)tableView heightOfRow:(NSInteger)row
{
	assert([NSThread isMainThread]);
	if (tableView == logTable)
	{
		LoggerMessage *msg = [displayedMessages objectAtIndex:row];
		CGFloat cachedHeight = msg.cachedCellSize.height;
		CGFloat newHeight = [LoggerMessageCell heightForCellWithMessage:msg
																maxSize:[tableView frame].size];
		if (cachedHeight && newHeight != cachedHeight)
			[logTable noteHeightOfRowsWithIndexesChanged:[NSIndexSet indexSetWithIndex:row]];
		return newHeight;
	}
	return [tableView rowHeight];
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
	return [displayedMessages objectAtIndex:rowIndex];
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
	NSDictionary *dict = [[filterListController selectedObjects] lastObject];
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
		NSMutableDictionary *dict = [[filterListController selectedObjects] lastObject];
		NSPredicate *predicate = [filterEditor predicate];
		if (predicate == nil)
			predicate = [NSCompoundPredicate orPredicateWithSubpredicates:[NSArray array]];
		[dict setObject:predicate forKey:@"predicate"];
		NSString *title = [filterName stringValue];
		if ([title length])
			[dict setObject:title forKey:@"title"];
		[filterListController setSelectedObjects:[NSArray arrayWithObject:dict]];
		
		[(LoggerAppDelegate *)[NSApp delegate] saveFiltersDefinition];
	}
	[filterEditorWindow orderOut:self];
}

- (IBAction)filterPredicateChanged:(id)sender
{
	// Perform live update while editing predicate
	[self refreshMessagesIfPredicateChanged:[filterEditor predicate]];
}

@end
