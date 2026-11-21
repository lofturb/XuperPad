#import <UIKit/UIKit.h>

#import "XPDecoder.h"

@interface XPGLView : UIView

- (void)displayFrame:(XPVideoFrameData *)frame;
- (void)clearFrame;

@end
