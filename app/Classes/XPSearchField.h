//
//  XPSearchField.h
//

#import <UIKit/UIKit.h>

@class XPDrawnTextField;

@interface XPSearchField : UIView

- (instancetype)initWithHint:(NSString *)hint;

@property (nonatomic, copy) void (^searchHandler)(NSString *text);
@property (nonatomic, copy) void (^clearHandler)(void);
@property (nonatomic, strong, readonly) XPDrawnTextField *textField;

@end
