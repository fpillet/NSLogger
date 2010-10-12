//
//  BWGradientBoxInspector.h
//  BWToolkit
//
//  Created by Brandon Walkin (www.brandonwalkin.com)
//  All code is provided under the New BSD license.
//

#import <InterfaceBuilderKit/InterfaceBuilderKit.h>
#import "BWGradientBox.h"
#import "BWGradientWell.h"

@interface BWGradientBoxInspector : IBInspector 
{
	BWGradientBox *box;
	int fillPopupSelection;
	
	BWGradientWell *gradientWell;
	NSColorWell *colorWell;
	NSView *wellContainer;
	float largeViewHeight, smallViewHeight;
}

@property (nonatomic, retain) IBOutlet BWGradientWell *gradientWell;
@property (nonatomic, retain) IBOutlet NSColorWell *colorWell;
@property (nonatomic, retain) IBOutlet NSView *wellContainer;
@property int fillPopupSelection;

@end
