//
//  BWSplitViewInspector.m
//  BWToolkit
//
//  Created by Brandon Walkin (www.brandonwalkin.com)
//  All code is provided under the New BSD license.
//

#import "BWSplitViewInspector.h"
#import "NSView+BWAdditions.h"
#import "NSEvent+BWAdditions.h"

@interface BWSplitViewInspector (BWSVIPrivate)
- (void)updateSizeInputFields;
- (BOOL)toggleDividerCheckboxVisibilityWithAnimation:(BOOL)shouldAnimate;
- (void)updateSizeLabels;
- (void)updateUnitPopupSelections;
@end

@implementation BWSplitViewInspector

@synthesize subviewPopupSelection, subviewPopupContent, collapsiblePopupContent, minUnitPopupSelection, maxUnitPopupSelection, splitView, dividerCheckboxCollapsed;

- (NSString *)viewNibName 
{
    return @"BWSplitViewInspector";
}

- (void)awakeFromNib
{
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(controlTextDidEndEditing:) name:NSControlTextDidEndEditingNotification object:minField];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(controlTextDidEndEditing:) name:NSControlTextDidEndEditingNotification object:maxField];
}

- (void)updateSizeLabels
{	
	if ([splitView isVertical])
	{
		[maxLabel setStringValue:@"Max Width"];
		[minLabel setStringValue:@"Min Width"];
	}
	else
	{
		[maxLabel setStringValue:@"Max Height"];
		[minLabel setStringValue:@"Min Height"];
	}
}

- (void)setSplitView:(BWSplitView *)aSplitView
{
    if (splitView != aSplitView) 
	{
        [splitView release];
        splitView = [aSplitView retain];
		
		[self toggleDividerCheckboxVisibilityWithAnimation:NO];
    }
	else
	{
		[self toggleDividerCheckboxVisibilityWithAnimation:YES];
	}
}

- (BOOL)toggleDividerCheckboxVisibilityWithAnimation:(BOOL)shouldAnimate
{
	// Conditions that must be met for a visibility switch to take place. If any of them fail, we return early.
	if (dividerCheckboxCollapsed && [splitView dividerThickness] > 1.01 && [splitView collapsiblePopupSelection] != 0) {
	}
	else if (!dividerCheckboxCollapsed && ([splitView dividerThickness] < 1.01 || [splitView collapsiblePopupSelection] == 0)) {
	}
	else
		return NO;
	
	float alpha, duration = [NSEvent bwShiftKeyIsDown] ? 0.1 * 10 : 0.1;
	NSRect targetFrame = NSZeroRect;
	
	if (dividerCheckboxCollapsed)
	{
		targetFrame = NSMakeRect([[self view] frame].origin.x, [[self view] frame].origin.y, [[self view] frame].size.width, [[self view] frame].size.height + 20);
		alpha = 1.0;
	}
	else
	{
		targetFrame = NSMakeRect([[self view] frame].origin.x, [[self view] frame].origin.y, [[self view] frame].size.width, [[self view] frame].size.height - 20);
		alpha = 0.0;
	}
		
	if (shouldAnimate)
	{
		[NSAnimationContext beginGrouping];
		[[NSAnimationContext currentContext] setDuration:duration];
		[[dividerCheckbox bwAnimator] setAlphaValue:alpha];
		[[[self view] bwAnimator] setFrame:targetFrame];
		[NSAnimationContext endGrouping];
	}
	else
	{
		[dividerCheckbox setAlphaValue:alpha];
		[[self view] setFrame:targetFrame];
	}
	
	dividerCheckboxCollapsed = !dividerCheckboxCollapsed;

	return YES;
}

- (void)refresh 
{
	[super refresh];

	if ([[self inspectedObjects] count] > 0)
	{	
		[autosizingView setSplitView:[[self inspectedObjects] objectAtIndex:0]];
		[autosizingView layoutButtons];

		[self setSplitView:[[self inspectedObjects] objectAtIndex:0]];
		
		// Populate the subview popup button
		NSMutableArray *content = [[NSMutableArray alloc] init];
		
		for (NSView *subview in [splitView subviews])
		{
			int index = [[splitView subviews] indexOfObject:subview];
			NSString *label = [NSString stringWithFormat:@"Subview %d",index];
			
			if (![[subview className] isEqualToString:@"NSView"])
				label = [label stringByAppendingString:[NSString stringWithFormat:@" - %@",[subview className]]];
			
			[content addObject:label];
		}
		
		[self setSubviewPopupContent:content];
		
		// Populate the collapsible popup button
		if ([splitView isVertical])
			[self setCollapsiblePopupContent:[NSMutableArray arrayWithObjects:@"None", @"Left Pane", @"Right Pane",nil]];
		else
			[self setCollapsiblePopupContent:[NSMutableArray arrayWithObjects:@"None", @"Top Pane", @"Bottom Pane",nil]];
		
		[self updateSizeLabels];
		[self updateSizeInputFields];
		[self updateUnitPopupSelections];
	}
}

+ (BOOL)supportsMultipleObjectInspection
{
	return NO;
}

- (void)setMinUnitPopupSelection:(int)index
{
	minUnitPopupSelection = index;
	
	NSNumber *minUnit = [NSNumber numberWithInt:index];
	
	NSMutableDictionary *tempMinUnits = [[[splitView minUnits] mutableCopy] autorelease];
	[tempMinUnits setObject:minUnit forKey:[NSNumber numberWithInt:[self subviewPopupSelection]]];
	[splitView setMinUnits:tempMinUnits];
}

- (void)setMaxUnitPopupSelection:(int)index
{
	maxUnitPopupSelection = index;

	NSNumber *maxUnit = [NSNumber numberWithInt:index];
	
	NSMutableDictionary *tempMaxUnits = [[[splitView maxUnits] mutableCopy] autorelease];
	[tempMaxUnits setObject:maxUnit forKey:[NSNumber numberWithInt:[self subviewPopupSelection]]];
	[splitView setMaxUnits:tempMaxUnits];
}

- (void)updateUnitPopupSelections
{
	minUnitPopupSelection = [[[splitView minUnits] objectForKey:[NSNumber numberWithInt:[self subviewPopupSelection]]] intValue];
	maxUnitPopupSelection = [[[splitView maxUnits] objectForKey:[NSNumber numberWithInt:[self subviewPopupSelection]]] intValue];
}

- (void)controlTextDidEndEditing:(NSNotification *)aNotification
{	
	if ([aNotification object] == minField || aNotification == nil)
	{	
		if ([minField stringValue] != nil && [[minField stringValue] isEqualToString:@""] == NO && [[minField stringValue] isEqualToString:@" "] == NO)
		{
			NSNumber *minValue = [NSNumber numberWithInt:[minField intValue]];
			NSMutableDictionary *tempMinValues = [[[splitView minValues] mutableCopy] autorelease];
			[tempMinValues setObject:minValue forKey:[NSNumber numberWithInt:[self subviewPopupSelection]]];
			[splitView setMinValues:tempMinValues];
		}
		else
		{
			NSMutableDictionary *tempMinValues = [[[splitView minValues] mutableCopy] autorelease];
			[tempMinValues removeObjectForKey:[NSNumber numberWithInt:[self subviewPopupSelection]]];
			[splitView setMinValues:tempMinValues];
		}
	}
	
	if ([aNotification object] == maxField || aNotification == nil)
	{	
		if ([maxField stringValue] != nil && [[maxField stringValue] isEqualToString:@""] == NO && [[maxField stringValue] isEqualToString:@" "] == NO)
		{
			NSNumber *maxValue = [NSNumber numberWithInt:[maxField intValue]];
			NSMutableDictionary *tempMaxValues = [[[splitView maxValues] mutableCopy] autorelease];
			[tempMaxValues setObject:maxValue forKey:[NSNumber numberWithInt:[self subviewPopupSelection]]];
			[splitView setMaxValues:tempMaxValues];
		}
		else
		{
			NSMutableDictionary *tempMaxValues = [[[splitView maxValues] mutableCopy] autorelease];
			[tempMaxValues removeObjectForKey:[NSNumber numberWithInt:[self subviewPopupSelection]]];
			[splitView setMaxValues:tempMaxValues];
		}
	}
}

- (void)setSubviewPopupSelection:(int)index
{ 
	// If someone types into the text field and chooses a different subview without hitting return or clicking out of the field,
	// the controlTextDidEndEditing notification won't fire and the value won't be saved. So we fire it manually here. 
	[self controlTextDidEndEditing:nil];
	
	subviewPopupSelection = index;
	
	// Update the input text fields with the values in the new subview
	[self updateSizeInputFields];
}

- (void)updateSizeInputFields
{
	[minField setObjectValue:[[splitView minValues] objectForKey:[NSNumber numberWithInt:[self subviewPopupSelection]]]];
	[maxField setObjectValue:[[splitView maxValues] objectForKey:[NSNumber numberWithInt:[self subviewPopupSelection]]]];
	
	[self setMinUnitPopupSelection:[[[splitView minUnits] objectForKey:[NSNumber numberWithInt:[self subviewPopupSelection]]] intValue]];
	[self setMaxUnitPopupSelection:[[[splitView maxUnits] objectForKey:[NSNumber numberWithInt:[self subviewPopupSelection]]] intValue]];
}

@end
