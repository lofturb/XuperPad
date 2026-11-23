//
//  XPDrawnTextField.h
//

#import <UIKit/UIKit.h>

@class XPDrawnTextField;

@protocol XPDrawnTextFieldDelegate <NSObject>
@optional
- (void)drawnTextFieldDidChange:(XPDrawnTextField *)field;
- (void)drawnTextFieldDidReturn:(XPDrawnTextField *)field;
@end

@interface XPDrawnTextField : UIView <UIKeyInput>

@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *hintText;
@property (nonatomic, strong) UIFont *font;
@property (nonatomic, strong) UIColor *textColor;
@property (nonatomic, strong) UIColor *caretColor;
@property (nonatomic, weak) id<XPDrawnTextFieldDelegate> fieldDelegate;
@property (nonatomic, assign) UIKeyboardType keyboardType;
@property (nonatomic, assign) UIReturnKeyType returnKeyType;
@property (nonatomic, assign) UITextAutocapitalizationType autocapitalizationType;
@property (nonatomic, assign) UITextAutocorrectionType autocorrectionType;
@property (nonatomic, assign, getter=isSecureTextEntry) BOOL secureTextEntry;

@end
