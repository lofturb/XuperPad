//
//  XPButton.h
//

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, XPButtonStyle) {
  XPButtonStylePrimary,
  XPButtonStyleGhost
};

@interface XPButton : UIControl

- (instancetype)initWithTitle:(NSString *)title style:(XPButtonStyle)style;

@property (nonatomic, copy) NSString *buttonTitle;
@property (nonatomic, assign) XPButtonStyle buttonStyle;

@end
