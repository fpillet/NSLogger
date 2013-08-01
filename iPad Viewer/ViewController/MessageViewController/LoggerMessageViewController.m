/*
 *
 * Modified BSD license.
 *
 * Copyright (c) 2012-2013 Sung-Taek, Kim <stkim1@colorfulglue.com> All Rights
 * Reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions are met:
 *
 * 1. Redistributions of source code must retain the above copyright notice,
 *    this list of conditions and the following disclaimer.
 *
 * 2. Redistributions in binary form must reproduce the above copyright notice,
 *    this list of conditions and the following disclaimer in the documentation
 *    and/or other materials provided with the distribution.
 *
 * 3. Any redistribution is done solely for personal benefit and not for any
 *    commercial purpose or for monetary gain
 *
 * 4. No binary form of source code is submitted to App Store℠ of Apple Inc.
 *
 * 5. Neither the name of the Sung-Taek, Kim nor the names of its contributors
 *    may be used to endorse or promote products derived from  this software
 *    without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 * ANY EXPRESS OR  IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
 * ARE DISCLAIMED. IN NO EVENT SHALL COPYRIGHT HOLDER AND AND CONTRIBUTORS BE
 * LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
 * CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
 * SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
 * INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 * CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 * ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 * POSSIBILITY OF SUCH DAMAGE.
 *
 */

#import <CoreData/CoreData.h>
#import <QuartzCore/QuartzCore.h>
#import "LoggerMessageViewController.h"
#import "LoggerCommon.h"
#import "LoggerMessageData.h"
#import "LoggerMessageCell.h"
#import "LoggerMarkerCell.h"
#import "LoggerClientInfoCell.h"
#import "LoggerConstModel.h"
#import "LoggerConstView.h"

@interface LoggerMessageViewController ()
@property (nonatomic, retain) NSFetchedResultsController	*messageFetchResultController;
@property (nonatomic, retain) NSDictionary					*clientInfo;
-(void)readMessages:(NSNotification *)aNotification;
-(void)insertTableViewSection;
-(void)deleteTableViewSection;
-(void)startTimer;
-(void)stopTimer;
-(void)timerTick:(NSTimer *)timer;
@end

@implementation LoggerMessageViewController{
	NSTimer				*_runTimeCounter;
	CFTimeInterval		_runTimeTicks;
}

//------------------------------------------------------------------------------
#pragma mark - Inherited Methods
//------------------------------------------------------------------------------
-(void)finishViewConstruction
{
	[super finishViewConstruction];

	[self.navigationController.navigationBar setFrame:(CGRect){{0.f,20.f},{self.view.frame.size.width,VIEWCONTROLLER_TITLE_HEIGHT}}];
	[self.navigationController.navigationBar addSubview:self.titleBar];
	
	[[NSNotificationCenter defaultCenter]
	 addObserver:self
	 selector:@selector(readMessages:)
	 name:kShowClientConnectedNotification
	 object:nil];

	[[NSNotificationCenter defaultCenter]
	 addObserver:self
	 selector:@selector(stopTimer)
	 name:kShowClientDisconnectedNotification
	 object:nil];
	
	[[NSNotificationCenter defaultCenter]
	 addObserver:self
	 selector:@selector(stopTimer)
	 name:UIApplicationWillResignActiveNotification
	 object:nil];
}

- (void)viewDidLoad
{
    [super viewDidLoad];

	self.titleBar.backgroundColor = [UIColor colorWithRed:0.73 green:0.73 blue:0.73 alpha:1.000];
    self.titleBar.alternateBackgroundColor = [UIColor colorWithRed:0.94 green:0.94 blue:0.94 alpha:1.000];
    self.titleBar.noiseBlendMode = kCGBlendModeMultiply;
    self.titleBar.noiseOpacity = 0.1;
	
	for (id img in self.searchBar.subviews)
	{
        if ([img isKindOfClass:NSClassFromString(@"UISearchBarBackground")]) {
			[img removeFromSuperview];
        }
    }
	
	[self.timeLabel setFont:[UIFont fontWithName:@"Digital-7" size:_timeLabel.font.pointSize]];
    
	self.toolBar.backgroundColor = [UIColor colorWithRed:0.73 green:0.73 blue:0.73 alpha:1.000];
    self.toolBar.alternateBackgroundColor = [UIColor colorWithRed:0.94 green:0.94 blue:0.94 alpha:1.000];
    self.toolBar.noiseBlendMode = kCGBlendModeMultiply;
    self.toolBar.noiseOpacity = 0.1;
}

-(void)startViewDestruction
{
	[super startViewDestruction];

	[[NSNotificationCenter defaultCenter] removeObserver:self name:UIApplicationWillResignActiveNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:kShowClientConnectedNotification object:nil];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:kShowClientDisconnectedNotification object:nil];
	
	[self stopTimer];
	
	if(_messageFetchResultController != nil)
	{
		self.messageFetchResultController.delegate = nil;
		self.messageFetchResultController = nil;
		[self deleteTableViewSection];
	}

	self.tableView.delegate = nil;
	self.tableView = nil;
	self.titleBar = nil;
	self.searchBar = nil;
	self.titleLabel = nil;
	self.toolBar = nil;
}

-(void)beginInstanceDestruction
{
	[super beginInstanceDestruction];
	self.dataManager = nil;
}

//------------------------------------------------------------------------------
#pragma mark - LoggerMessageViewController Methods
//------------------------------------------------------------------------------
-(void)readMessages:(NSNotification *)aNotification
{
	NSDictionary *userInfo = [aNotification userInfo];
	
	MTLog(@"userInfo %@",userInfo);
	
	uLong clientHash = [[userInfo objectForKey:kClientHash] integerValue];
	int32_t runCount = [[userInfo objectForKey:kClientRunCount] integerValue];
	
	self.clientInfo = nil;
	self.clientInfo = userInfo;

	self.runCountLabel.text = \
		[NSString stringWithFormat:
		 NSLocalizedString(@"Run %d of %d", nil),runCount+1,runCount+1];

	assert([self.dataManager messageDisplayContext] != nil);
	
	if(_messageFetchResultController != nil)
	{
		self.messageFetchResultController.delegate = nil;
		self.messageFetchResultController = nil;
		[self deleteTableViewSection];
	}

	// start timer
	[self startTimer];
	
	// start fetching
	NSFetchRequest *request = [[NSFetchRequest alloc] init];
	
	NSEntityDescription *entity =\
		[NSEntityDescription
		 entityForName:@"LoggerMessageData"
		 inManagedObjectContext:[[self dataManager] messageDisplayContext]];
	[request setShouldRefreshRefetchedObjects:NO];
	[request setEntity:entity];
	[request setFetchBatchSize:20];
	//[request setFetchLimit:40];
	//[request setFetchOffset:0];
	
	[request setPredicate:
	 [NSPredicate
	  predicateWithFormat:
	  @"clientHash == %d AND runCount == %d"
	  ,clientHash
	  ,runCount]];
	
	NSSortDescriptor *sortByTimestamp = \
		[[NSSortDescriptor alloc]
		 initWithKey:@"timestamp"
		 ascending:YES];
	
	NSSortDescriptor *sortBySequence = \
		[[NSSortDescriptor alloc]
		 initWithKey:@"sequence"
		 ascending:YES];
	
	[request setSortDescriptors:@[sortBySequence,sortByTimestamp]];
	
	NSString *cacheName = [NSString stringWithFormat:@"Cache-%lx",clientHash];
	
	[NSFetchedResultsController deleteCacheWithName:cacheName];
	
	NSFetchedResultsController *frc = \
		[[NSFetchedResultsController alloc]
		 initWithFetchRequest:request
		 managedObjectContext:[[self dataManager] messageDisplayContext]
		 sectionNameKeyPath:nil//@"uniqueID"
		 cacheName:cacheName];
	
	NSError *error = nil;
	[frc performFetch:&error];
	
	// alert tableview to prepare for incoming data
	// before fetching started, make sure every setup is completed
	[self setMessageFetchResultController:frc];
	[frc setDelegate:self];
	

	[self insertTableViewSection];
	[self.tableView
	 reloadSections:[NSIndexSet indexSetWithIndex:0]
	 withRowAnimation:UITableViewRowAnimationNone];
	
	[frc release],frc = nil;
	[sortBySequence release],sortBySequence = nil;
	[sortByTimestamp release],sortByTimestamp = nil;
	[request release],request = nil;
}

-(void)insertTableViewSection
{
	NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:0];
	
	[self.tableView
	 insertSections:indexSet
	 withRowAnimation:UITableViewRowAnimationAutomatic];
}


-(void)deleteTableViewSection
{
	NSIndexSet *indexSet = [NSIndexSet indexSetWithIndex:0];
	
	[self.tableView
	 deleteSections:indexSet
	 withRowAnimation:UITableViewRowAnimationAutomatic];
}
//------------------------------------------------------------------------------
#pragma mark Timer Control
//------------------------------------------------------------------------------
- (void)startTimer
{
    if (_runTimeCounter == nil) {
        _runTimeCounter =
			[NSTimer
			 scheduledTimerWithTimeInterval:0.1
			 target:self
			 selector:@selector(timerTick:)
			 userInfo:nil
			 repeats:YES];
    }
}

- (void)stopTimer
{
    [_runTimeCounter invalidate];
    _runTimeCounter = nil;
}

- (void)timerTick:(NSTimer *)timer
{
    _runTimeTicks += 0.1;
    double seconds = fmod(_runTimeTicks, 60.0);
    double minutes = fmod(trunc(_runTimeTicks / 60.0), 60.0);
    double hours = trunc(_runTimeTicks / 3600.0);
    self.timeLabel.text = [NSString stringWithFormat:@"%02.0f:%02.0f:%04.1f", hours, minutes, seconds];
}

//------------------------------------------------------------------------------
#pragma mark - UITableViewDataSource Delegate Methods
//------------------------------------------------------------------------------
- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView
{
	if(_messageFetchResultController == nil)
	{
		return 0;
	}
	
	return 1;
}

- (NSInteger)tableView:(UITableView *)aTableView
 numberOfRowsInSection:(NSInteger)aSection
{
	return [[self.messageFetchResultController fetchedObjects] count];
}

- (UITableViewCell *)tableView:(UITableView *)aTableView
		 cellForRowAtIndexPath:(NSIndexPath *)anIndexPath
{

	if(_messageFetchResultController == nil)
	{
		return nil;
	}
	
	LoggerMessageData *msg = \
		[self.messageFetchResultController objectAtIndexPath:anIndexPath];

	LoggerMessageCell *cell = nil;

	switch ([msg.type shortValue])
	{
		case LOGMSG_TYPE_LOG:
		case LOGMSG_TYPE_BLOCKSTART:
		case LOGMSG_TYPE_BLOCKEND:{
			cell =
				[self.tableView
				 dequeueReusableCellWithIdentifier:kMessageCellReuseID];

			if(cell == nil)
			{
				cell = [[[LoggerMessageCell alloc]
						initWithPreConfig]
						autorelease];

				cell.hostTableView = self.tableView;
				cell.selectionStyle = UITableViewCellSelectionStyleNone;
			}

			break;
		}
			
		case LOGMSG_TYPE_CLIENTINFO:
		case LOGMSG_TYPE_DISCONNECT:{
			cell =
				[self.tableView
				 dequeueReusableCellWithIdentifier:kClientInfoCellReuseID];

			if(cell == nil)
			{
				cell = [[[LoggerClientInfoCell alloc]
						initWithPreConfig]
						autorelease];
				
				cell.hostTableView = self.tableView;
				cell.selectionStyle = UITableViewCellSelectionStyleNone;
			}

			break;
		}

		case LOGMSG_TYPE_MARK:{
			cell =
				[self.tableView
				 dequeueReusableCellWithIdentifier:kMarkerCellReuseID];

			if(cell == nil)
			{
				cell = [[[LoggerMarkerCell alloc]
						initWithPreConfig]
						autorelease];

				cell.hostTableView = self.tableView;
				cell.selectionStyle = UITableViewCellSelectionStyleNone;
			}
			
			break;
		}
	}

	[cell setupForIndexpath:anIndexPath messageData:msg];

	return cell;
}

//------------------------------------------------------------------------------
#pragma mark - UITableViewDelegate Delegate Methods
//------------------------------------------------------------------------------
- (CGFloat)tableView:(UITableView *)aTableView
heightForRowAtIndexPath:(NSIndexPath *)anIndexPath
{
	LoggerMessageData *data = [self.messageFetchResultController objectAtIndexPath:anIndexPath];
	return [[data portraitHeight] floatValue];
}

- (CGFloat)tableView:(UITableView *)tableView
heightForHeaderInSection:(NSInteger)section
{
	return 0.f;
}

- (CGFloat)tableView:(UITableView *)tableView
heightForFooterInSection:(NSInteger)section
{
	// This will create a "invisible" footer
	return 0.f;
}


//------------------------------------------------------------------------------
#pragma mark - NSFetchedResultController Delegate
//------------------------------------------------------------------------------

- (void)controllerWillChangeContent:(NSFetchedResultsController *)controller;
{
	[self.tableView beginUpdates];
}

- (void)controller:(NSFetchedResultsController *)aController
   didChangeObject:(id)anObject
	   atIndexPath:(NSIndexPath *)anIndexPath
	 forChangeType:(NSFetchedResultsChangeType)aType
	  newIndexPath:(NSIndexPath *)aNewIndexPath
{
	UITableView *tableView = self.tableView;

	switch(aType)
	{
		case NSFetchedResultsChangeInsert:{
			[tableView
			 insertRowsAtIndexPaths:@[aNewIndexPath]
			 withRowAnimation:UITableViewRowAnimationFade];
			break;
		}

		case NSFetchedResultsChangeDelete:
		case NSFetchedResultsChangeUpdate:
		case NSFetchedResultsChangeMove:
		default:
            break;
	}

}

- (void)controllerDidChangeContent:(NSFetchedResultsController *)controller
{
	[self.tableView endUpdates];

	NSInteger rowTotal = [self.tableView numberOfRowsInSection:0] - 1;
	[[NSOperationQueue mainQueue]
	addOperationWithBlock:^{
		[self.tableView
		 scrollToRowAtIndexPath:[NSIndexPath indexPathForRow:rowTotal inSection:0]
		 atScrollPosition:UITableViewScrollPositionBottom
		 animated:NO];
	}];
}

@end
