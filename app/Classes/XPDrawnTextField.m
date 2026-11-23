//
//  XPDrawnTextField.m
//

#import "XPDrawnTextField.h"

@interface XPDrawnTextField ()
@property (nonatomic, strong) NSTimer *blinkTimer;
@property (nonatomic, assign) BOOL caretVisible;
@end

@implementation XPDrawnTextField

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.userInteractionEnabled = YES;
    _text = @"";
    _font = [UIFont systemFontOfSize:14.0f];
    _textColor = [UIColor whiteColor];
    _caretColor = [UIColor whiteColor];
    _caretVisible = YES;
    _keyboardType = UIKeyboardTypeDefault;
    _returnKeyType = UIReturnKeyDone;
    _autocapitalizationType = UITextAutocapitalizationTypeNone;
    _autocorrectionType = UITextAutocorrectionTypeNo;
    _secureTextEntry = NO;
  }
  return self;
}

- (void)dealloc
{
  [_blinkTimer invalidate];
  _blinkTimer = nil;
}

#pragma mark - Properties

- (void)setText:(NSString *)text
{
  _text = [text copy] ?: @"";
  [self setNeedsDisplay];
}

- (void)setHintText:(NSString *)hintText
{
  _hintText = [hintText copy];
  [self setNeedsDisplay];
}

- (void)setFont:(UIFont *)font
{
  _font = font ?: [UIFont systemFontOfSize:14.0f];
  [self setNeedsDisplay];
}

- (void)setTextColor:(UIColor *)textColor
{
  _textColor = textColor ?: [UIColor whiteColor];
  [self setNeedsDisplay];
}

- (void)setCaretColor:(UIColor *)caretColor
{
  _caretColor = caretColor ?: [UIColor whiteColor];
  [self setNeedsDisplay];
}

#pragma mark - UIResponder

- (BOOL)canBecomeFirstResponder
{
  return YES;
}

- (BOOL)becomeFirstResponder
{
  BOOL became = [super becomeFirstResponder];
  if (became) {
    [self startCaretBlink];
    [self setNeedsDisplay];
  }
  return became;
}

- (BOOL)resignFirstResponder
{
  BOOL resigned = [super resignFirstResponder];
  if (resigned) {
    [self stopCaretBlink];
    [self setNeedsDisplay];
  }
  return resigned;
}

#pragma mark - Caret

- (void)startCaretBlink
{
  [self.blinkTimer invalidate];
  self.caretVisible = YES;
  self.blinkTimer = [NSTimer scheduledTimerWithTimeInterval:0.53
                                                     target:self
                                                   selector:@selector(toggleCaret)
                                                   userInfo:nil
                                                    repeats:YES];
}

- (void)stopCaretBlink
{
  [self.blinkTimer invalidate];
  self.blinkTimer = nil;
  self.caretVisible = YES;
}

- (void)toggleCaret
{
  self.caretVisible = !self.caretVisible;
  [self setNeedsDisplay];
}

#pragma mark - UIKeyInput

- (BOOL)hasText
{
  return self.text.length > 0;
}

- (void)insertText:(NSString *)text
{
  if (text.length == 0) {
    return;
  }
  if ([text isEqualToString:@"\n"]) {
    id<XPDrawnTextFieldDelegate> delegate = self.fieldDelegate;
    if ([delegate respondsToSelector:@selector(drawnTextFieldDidReturn:)]) {
      [delegate drawnTextFieldDidReturn:self];
    }
    return;
  }
  self.text = [self.text stringByAppendingString:text];
  [self notifyChange];
}

- (void)deleteBackward
{
  if (self.text.length == 0) {
    return;
  }
  NSRange range = [self.text rangeOfComposedCharacterSequenceAtIndex:self.text.length - 1];
  self.text = [self.text stringByReplacingCharactersInRange:range withString:@""];
  [self notifyChange];
}

- (void)notifyChange
{
  self.caretVisible = YES;
  [self setNeedsDisplay];
  id<XPDrawnTextFieldDelegate> delegate = self.fieldDelegate;
  if ([delegate respondsToSelector:@selector(drawnTextFieldDidChange:)]) {
    [delegate drawnTextFieldDidChange:self];
  }
}

#pragma mark - Drawing

- (NSDictionary *)attributesWithColor:(UIColor *)color
{
  return @{ NSFontAttributeName : self.font,
            NSForegroundColorAttributeName : color };
}

- (CGFloat)textWidth
{
  if (self.text.length == 0) {
    return 0.0f;
  }
  NSDictionary *attributes = [self attributesWithColor:self.textColor];
  CGSize size = [self.text sizeWithAttributes:attributes];
  return ceil(size.width);
}

- (void)drawRect:(CGRect)rect
{
  CGRect area = self.bounds;
  if (area.size.width <= 0.0f || area.size.height <= 0.0f) {
    return;
  }

  NSString *text = self.secureTextEntry ? [@"" stringByPaddingToLength:self.text.length
                                                           withString:@"\u2022"
                                                      startingAtIndex:0] : self.text;
  NSString *shown = text.length > 0 ? text : (self.hintText ?: @"");

  NSDictionary *attributes = [self attributesWithColor:(text.length > 0 ? self.textColor
                                                                       : [self.textColor colorWithAlphaComponent:0.45f])];
  CGSize textSize = [shown sizeWithAttributes:attributes];
  CGFloat textY = (area.size.height - textSize.height) / 2.0f;

  [shown drawAtPoint:CGPointMake(0.0f, textY) withAttributes:attributes];

  if (self.isFirstResponder && self.caretVisible) {
    CGFloat caretX = [self textWidth];
    CGFloat caretHeight = MIN(self.font.lineHeight, area.size.height);
    CGFloat caretY = (area.size.height - caretHeight) / 2.0f;
    CGRect caretRect = CGRectMake(caretX + 1.0f, caretY, 1.5f, caretHeight);
    [self.caretColor setFill];
    UIRectFill(caretRect);
  }
}

@end
