//
//  XPStatusView.h
//

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, XPStatusMode) {
  XPStatusModeHidden,
  XPStatusModeLoading,
  XPStatusModeMessage
};

@interface XPStatusView : UIView

- (void)showLoading;
- (void)showMessage:(NSString *)message retry:(BOOL)retry;
- (void)hideStatus;

@property (nonatomic, copy) void (^retryHandler)(void);

@end
