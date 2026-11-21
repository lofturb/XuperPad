#import <UIKit/UIKit.h>

@interface XPGLView : UIView

- (void)displayRGBFrame:(NSData *)rgb width:(int)width height:(int)height;
- (void)clearFrame;

@end
