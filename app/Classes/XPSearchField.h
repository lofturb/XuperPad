//
//  XPSearchField.h
//

#import <UIKit/UIKit.h>

@interface XPSearchField : UIView

- (instancetype)initWithHint:(NSString *)hint;

@property (nonatomic, copy) void (^searchHandler)(NSString *text);
@property (nonatomic, copy) void (^clearHandler)(void);
@property (nonatomic, strong, readonly) UITextField *textField;

@end
