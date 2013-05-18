/*
 * Copyright (c) 2012 David Keegan (http://davidkeegan.com)
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy
 * of this software and associated documentation files (the "Software"), to deal
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
 * copies of the Software, and to permit persons to whom the Software is
 * furnished to do so, subject to the following conditions:
 
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
 * SOFTWARE.
 */

#import "KGNoise.h"

static NSUInteger const kKGNoiseImageSize = 128;
static inline CGFloat *gradientComponentsForColors(UIColor *color1, UIColor *color2)
{
    CGFloat *components = malloc(8*sizeof(CGFloat));
    const CGFloat *alternateBackgroundComponents = CGColorGetComponents([color1 CGColor]);
    if(CGColorGetNumberOfComponents([color1 CGColor]) == 2)
	{
        components[0] = alternateBackgroundComponents[0];
        components[1] = alternateBackgroundComponents[0];
        components[2] = alternateBackgroundComponents[0];
        components[3] = alternateBackgroundComponents[1];
    }
	else
	{
        components[0] = alternateBackgroundComponents[0];
        components[1] = alternateBackgroundComponents[1];
        components[2] = alternateBackgroundComponents[2];
        components[3] = alternateBackgroundComponents[3];
    }

    const CGFloat *backgroundComponents = CGColorGetComponents([color2 CGColor]);
    if(CGColorGetNumberOfComponents([color2 CGColor]) == 2)
	{
        components[4] = backgroundComponents[0];
        components[5] = backgroundComponents[0];
        components[6] = backgroundComponents[0];
        components[7] = backgroundComponents[1];
    }
	else
	{
        components[4] = backgroundComponents[0];
        components[5] = backgroundComponents[1];
        components[6] = backgroundComponents[2];
        components[7] = backgroundComponents[3];
    }
    return components;
}

//------------------------------------------------------------------------------
#pragma mark - KGNoise
//------------------------------------------------------------------------------
@implementation KGNoise

+ (void)drawNoiseWithOpacity:(CGFloat)opacity
{
    [self drawNoiseWithOpacity:opacity andBlendMode:kCGBlendModeScreen];
}

+ (void)drawNoiseWithOpacity:(CGFloat)opacity
				andBlendMode:(CGBlendMode)blendMode
{
    static CGImageRef noiseImageRef = nil;
    static dispatch_once_t oncePredicate;
    dispatch_once(&oncePredicate, ^{
        NSUInteger width = kKGNoiseImageSize, height = width;
        NSUInteger size = width*height;
        char *rgba = (char *)malloc(size); srand(115);
        for(NSUInteger i=0; i < size; ++i)
		{
			rgba[i] = rand()%256;
		}

        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceGray();
        CGContextRef bitmapContext =
        CGBitmapContextCreate(rgba, width, height, 8, width, colorSpace, kCGImageAlphaNone);
        CFRelease(colorSpace);
        noiseImageRef = CGBitmapContextCreateImage(bitmapContext);
        CFRelease(bitmapContext);
        free(rgba);
    });

    CGContextRef context = UIGraphicsGetCurrentContext();
    CGContextSaveGState(context);
    CGContextSetAlpha(context, opacity);
    CGContextSetBlendMode(context, blendMode);

    if([[UIScreen mainScreen] respondsToSelector:@selector(scale)])
	{
        CGFloat scaleFactor = [[UIScreen mainScreen] scale];
        CGContextScaleCTM(context, 1/scaleFactor, 1/scaleFactor);
    }

    CGRect imageRect = (CGRect){CGPointZero, CGImageGetWidth(noiseImageRef), CGImageGetHeight(noiseImageRef)};
    CGContextDrawTiledImage(context, imageRect, noiseImageRef);
    CGContextRestoreGState(context);
}

@end

//------------------------------------------------------------------------------
#pragma mark - KGNoise Color
//------------------------------------------------------------------------------
@implementation UIColor(KGNoise)
- (UIColor *)colorWithNoiseWithOpacity:(CGFloat)opacity
{
    return [self colorWithNoiseWithOpacity:opacity andBlendMode:kCGBlendModeScreen];
}

- (UIColor *)colorWithNoiseWithOpacity:(CGFloat)opacity
						  andBlendMode:(CGBlendMode)blendMode
{
    CGRect rect = {CGPointZero, kKGNoiseImageSize, kKGNoiseImageSize};
    UIGraphicsBeginImageContextWithOptions(rect.size, YES, 0.0f);
    CGContextRef context = UIGraphicsGetCurrentContext();
    [self setFill]; CGContextFillRect(context, rect);
    [KGNoise drawNoiseWithOpacity:opacity andBlendMode:blendMode];
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    return [UIColor colorWithPatternImage:image];
}
@end

//------------------------------------------------------------------------------
#pragma mark - KGNoiseView
//------------------------------------------------------------------------------
@implementation KGNoiseView
- (id)initWithFrame:(CGRect)frameRect
{
    if((self = [super initWithFrame:frameRect]))
	{
        [self setup];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    if((self = [super initWithCoder:aDecoder]))
	{
        [self setup];
    }
    return self;
}

- (void)setup
{
    self.backgroundColor = [UIColor grayColor];
    self.noiseOpacity = 0.1;
    self.noiseBlendMode = kCGBlendModeScreen;
}

- (void)setNoiseOpacity:(CGFloat)noiseOpacity
{
    if(_noiseOpacity != noiseOpacity)
	{
        _noiseOpacity = noiseOpacity;
        [self setNeedsDisplay];
    }
}

- (void)setNoiseBlendMode:(CGBlendMode)noiseBlendMode
{
    if(_noiseBlendMode != noiseBlendMode)
	{
        _noiseBlendMode = noiseBlendMode;
        [self setNeedsDisplay];
    }
}

- (void)drawRect:(CGRect)dirtyRect
{
    CGContextRef context = UIGraphicsGetCurrentContext();    
    [self.backgroundColor setFill];
    CGContextFillRect(context, self.bounds);
    [KGNoise drawNoiseWithOpacity:self.noiseOpacity andBlendMode:self.noiseBlendMode];
}
@end

//------------------------------------------------------------------------------
#pragma mark - KGNoiseLinearGradientView
//------------------------------------------------------------------------------
@implementation KGNoiseLinearGradientView
-(void)dealloc
{
	self.alternateBackgroundColor = nil;
	[super dealloc];
}

- (void)setup
{
    [super setup];
    self.gradientDirection = KGLinearGradientDirection270Degrees;
}

- (void)setAlternateBackgroundColor:(UIColor *)alternateBackgroundColor
{
    if(_alternateBackgroundColor != alternateBackgroundColor)
	{
        _alternateBackgroundColor = alternateBackgroundColor;
        [self setNeedsDisplay];
    }
}


- (void)drawRect:(CGRect)dirtyRect
{
    CGContextRef context = UIGraphicsGetCurrentContext();
    
	// if we don't have an alternate color draw solid
    if(self.alternateBackgroundColor == nil)
	{
        [super drawRect:dirtyRect];
        return;
    }
    
    CGRect bounds = self.bounds;
    CGContextSaveGState(context);    
    CGColorSpaceRef baseSpace = CGColorSpaceCreateDeviceRGB();
    CGFloat *components = gradientComponentsForColors(self.alternateBackgroundColor, self.backgroundColor);    
    CGGradientRef gradient = CGGradientCreateWithColorComponents(baseSpace, components, NULL, 2);
    CGColorSpaceRelease(baseSpace), baseSpace = NULL;
    CGPoint startPoint;
    CGPoint endPoint;
    switch (self.gradientDirection)
	{
        case KGLinearGradientDirection0Degrees:
		{
            startPoint = CGPointMake(CGRectGetMinX(bounds), CGRectGetMidY(bounds));
            endPoint = CGPointMake(CGRectGetMaxX(bounds), CGRectGetMidY(bounds));
            break;
		}

        case KGLinearGradientDirection90Degrees:
		{
            startPoint = CGPointMake(CGRectGetMidX(bounds), CGRectGetMaxY(bounds));
            endPoint = CGPointMake(CGRectGetMidX(bounds), CGRectGetMinY(bounds));
            break;
		}

        case KGLinearGradientDirection180Degrees:
		{
            startPoint = CGPointMake(CGRectGetMaxX(bounds), CGRectGetMidY(bounds));
            endPoint = CGPointMake(CGRectGetMinX(bounds), CGRectGetMidY(bounds));
            break;
		}

        case KGLinearGradientDirection270Degrees:
        default:
		{
            startPoint = CGPointMake(CGRectGetMidX(bounds), CGRectGetMinY(bounds));
            endPoint = CGPointMake(CGRectGetMidX(bounds), CGRectGetMaxY(bounds));
            break;
		}
    }

    CGContextDrawLinearGradient(context, gradient, startPoint, endPoint, 0);
    CGGradientRelease(gradient), gradient = NULL;
    CGContextRestoreGState(context);
    free(components);
    
    [KGNoise drawNoiseWithOpacity:self.noiseOpacity andBlendMode:self.noiseBlendMode];
}
@end

//------------------------------------------------------------------------------
#pragma mark - KGNoiseRadialGradientView
//------------------------------------------------------------------------------
@implementation KGNoiseRadialGradientView
-(void)dealloc
{
	self.alternateBackgroundColor = nil;
	[super dealloc];
}

- (void)setAlternateBackgroundColor:(UIColor *)alternateBackgroundColor
{
    if(_alternateBackgroundColor != alternateBackgroundColor){
        _alternateBackgroundColor = alternateBackgroundColor;
        [self setNeedsDisplay];
    }
}

- (void)drawRect:(CGRect)dirtyRect
{
    CGContextRef context = UIGraphicsGetCurrentContext();
    // if we don't have an alternate color draw solid
    if(self.alternateBackgroundColor == nil)
	{
        [super drawRect:dirtyRect];
        return;
    }

    CGRect bounds = self.bounds;
    CGContextSaveGState(context);
    size_t gradLocationsNum = 2;
    CGFloat gradLocations[2] = {0.0f, 1.0f};
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGFloat *components = gradientComponentsForColors(self.alternateBackgroundColor, self.backgroundColor);
    CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, components, gradLocations, gradLocationsNum);
    CGColorSpaceRelease(colorSpace), colorSpace = NULL;
    CGPoint gradCenter= CGPointMake(round(CGRectGetMidX(bounds)), round(CGRectGetMidY(bounds)));
    CGFloat gradRadius = sqrt(pow((CGRectGetHeight(bounds)/2), 2) + pow((CGRectGetWidth(bounds)/2), 2));
    CGContextDrawRadialGradient(context, gradient, gradCenter, 0, gradCenter, gradRadius, kCGGradientDrawsAfterEndLocation);
    CGGradientRelease(gradient), gradient = NULL;
    CGContextRestoreGState(context);
    free(components);
    
    [KGNoise drawNoiseWithOpacity:self.noiseOpacity andBlendMode:self.noiseBlendMode];
}
@end
