#import <UIKit/UIKit.h>

#import "XPDecoder.h"

typedef NS_ENUM(NSInteger, XPGLScalingMode) {
  XPGLScalingModeFit = 0,
  XPGLScalingModeFill = 1,
  XPGLScalingModeStretch = 2
};

@interface XPGLView : UIView

@property (nonatomic, assign) XPGLScalingMode scalingMode;

- (void)displayFrame:(XPVideoFrameData *)frame;
- (void)clearFrame;

@end
