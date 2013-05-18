![](https://raw.github.com/kgn/KGNoise/master/screenshot.jpg)

I've been developing this noise drawing code for quite some time. It all started with drawing noise in the title bar of [INAppStoreWindow](https://github.com/indragiek/INAppStoreWindow). The original implementation of the noise drawing for the titlebar used `CIFilter`, but this took up an unusual amount of memory and also didn't look so great. So I began my quest for the best noise drawing solution, this project contains the third version which I feel is finally ready for prime time on the Mac and iOS! 

KGNoise generates random black and white pixels into a static 128x128 image that is then tiled to fill the space. The random pixels are seeded with a value that has been chosen to look the most random, this also means that the noise will look consistent between app launches.

KGNoise is **retina** compatible on both iOS and the Mac. An identical interface is provided for both platforms through the use of compile time `#if` checks.

# Usage

Add `KGNoise.h` and `KGNoise.m` to your project, then import `KGNoise.h`:

```obj-c
#import "KGNoise.h"
```

KGNoise is distributed under the MIT license, see the license file for more information.

# KGNoise

`KGNoise` provides two generic noise drawing functions that you can use in your drawing code.

```obj-c
+ (void)drawNoiseWithOpacity:(CGFloat)opacity;
+ (void)drawNoiseWithOpacity:(CGFloat)opacity andBlendMode:(CGBlendMode)blendMode;
```

# UIColor/NSColor(KGNoise)

```
- (NSColor/UIColor *)colorWithNoiseWithOpacity:(CGFloat)opacity;
- (NSColor/UIColor *)colorWithNoiseWithOpacity:(CGFloat)opacity andBlendMode:(CGBlendMode)blendMode;
```

# KGNoiseView

There is also a subclass of `NSView` or `UIView`, depending on your platform, that you can use out of the box to draw noise on a solid color. The noise opacity, blending mode, and background color are all customizable.

```obj-c
@property (strong, nonatomic) NSColor/UIColor *backgroundColor;
@property (nonatomic) CGFloat noiseOpacity;
@property (nonatomic) CGBlendMode noiseBlendMode;
```

Please note that the standard `backgroundColor` is used for `UIView`, but `backgroundColor` does not exist on `NSView` so it has been added to provide the exact same interface for both platforms.

# KGNoiseLinearGradientView & KGNoiseRadialGradientView

`KGNoiseLinearGradientView` and `KGNoiseRadialGradientView` inherit from `KGNoiseView` and draw a linear or radial gradient respectively. They provide a property to set the alternate background color to be used in the gradient.

```obj-c
@property (strong, nonatomic) NSColor/UIColor *alternateBackgroundColor;
```

In addition, KGNoiseLinearGradientView provides a property to set gradient direction to 0, 90, 180, or 270 degrees.

```obj-c
@property (nonatomic) KGLinearGradientDirection gradientDirection;
```

# KGNoiseExample

This project contains an example project that demonstrates how `KGNoiseView` could be used in a Mac or iOS app.

