#import <UIKit/UIKit.h>

@class XPSubtitleCue;

@interface XPSubtitleOverlay : UIView

- (void)showCue:(XPSubtitleCue *)cue;
- (void)clearCue;

@end
