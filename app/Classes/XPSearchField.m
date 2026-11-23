//
//  XPSearchField.m
//

#import "XPSearchField.h"
#import "XPTheme.h"
#import "XPDrawnTextField.h"

@interface XPSearchClearControl : UIControl
@end

@implementation XPSearchClearControl

- (void)drawRect:(CGRect)rect
{
  CGContextRef context = UIGraphicsGetCurrentContext();
  if (context == NULL) {
    return;
  }
  CGFloat side = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
  CGRect area = CGRectMake((CGRectGetWidth(self.bounds) - side) / 2.0f,
                            (CGRectGetHeight(self.bounds) - side) / 2.0f,
                            side,
                            side);
  [[XPColorSurfaceAlt() colorWithAlphaComponent:0.9f] setFill];
  [XPRoundedPath(area, side / 2.0f) fill];
  [XPColorTextMuted() setStroke];
  CGFloat arm = side * 0.22f;
  CGFloat centerX = CGRectGetMidX(area);
  CGFloat centerY = CGRectGetMidY(area);
  UIBezierPath *path = [UIBezierPath bezierPath];
  [path moveToPoint:CGPointMake(centerX - arm, centerY - arm)];
  [path addLineToPoint:CGPointMake(centerX + arm, centerY + arm)];
  [path moveToPoint:CGPointMake(centerX + arm, centerY - arm)];
  [path addLineToPoint:CGPointMake(centerX - arm, centerY + arm)];
  path.lineWidth = 1.4f;
  path.lineCapStyle = kCGLineCapRound;
  [path stroke];
}

@end

@interface XPSearchField () <XPDrawnTextFieldDelegate>
@property (nonatomic, strong) XPDrawnTextField *textField;
@property (nonatomic, strong) XPSearchClearControl *clearControl;
@end

@implementation XPSearchField

- (instancetype)initWithHint:(NSString *)hint
{
  self = [super initWithFrame:CGRectZero];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;

    self.textField = [[XPDrawnTextField alloc] initWithFrame:CGRectZero];
    self.textField.backgroundColor = [UIColor clearColor];
    self.textField.font = XPFontBody(13.0f);
    self.textField.textColor = XPColorTextPrimary();
    self.textField.caretColor = XPColorAccent();
    self.textField.hintText = hint ?: @"";
    self.textField.returnKeyType = UIReturnKeySearch;
    self.textField.autocorrectionType = UITextAutocorrectionTypeNo;
    self.textField.autocapitalizationType = UITextAutocapitalizationTypeNone;
    self.textField.fieldDelegate = self;
    [self addSubview:self.textField];

    self.clearControl = [[XPSearchClearControl alloc] initWithFrame:CGRectZero];
    self.clearControl.backgroundColor = [UIColor clearColor];
    self.clearControl.opaque = NO;
    self.clearControl.hidden = YES;
    [self.clearControl addTarget:self
                           action:@selector(clearRequested:)
                 forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.clearControl];
  }
  return self;
}

- (void)layoutSubviews
{
  [super layoutSubviews];
  CGFloat height = CGRectGetHeight(self.bounds);
  CGFloat clearSide = MIN(18.0f, height - 8.0f);
  self.clearControl.frame = CGRectMake(CGRectGetWidth(self.bounds) - clearSide - 8.0f,
                                        (height - clearSide) / 2.0f,
                                        clearSide,
                                        clearSide);
  CGFloat fieldRight = self.clearControl.hidden
    ? CGRectGetWidth(self.bounds) - 8.0f
    : CGRectGetMinX(self.clearControl.frame) - 4.0f;
  self.textField.frame = CGRectMake(30.0f, 0.0f, fieldRight - 30.0f, height);
}

- (void)drawRect:(CGRect)rect
{
  CGContextRef context = UIGraphicsGetCurrentContext();
  if (context == NULL) {
    return;
  }
  CGRect area = CGRectInset(self.bounds, 0.5f, 0.5f);
  if (area.size.width <= 4 || area.size.height <= 4) {
    return;
  }
  [[XPColorSurface() colorWithAlphaComponent:0.95f] setFill];
  [XPRoundedPath(area, area.size.height / 2.0f) fill];
  [XPColorDivider() setStroke];
  UIBezierPath *border = XPRoundedPath(area, area.size.height / 2.0f);
  border.lineWidth = 1.0f;
  [border stroke];

  CGFloat side = 13.0f;
  CGFloat originY = (CGRectGetHeight(self.bounds) - side) / 2.0f;
  CGRect lens = CGRectMake(10.0f, originY, side - 3.0f, side - 3.0f);
  [XPColorTextMuted() setStroke];
  UIBezierPath *handle = [UIBezierPath bezierPath];
  [handle moveToPoint:CGPointMake(CGRectGetMaxX(lens) + 1.0f, CGRectGetMaxY(lens) + 1.0f)];
  [handle addLineToPoint:CGPointMake(CGRectGetMaxX(lens) + 4.0f, CGRectGetMaxY(lens) + 4.0f)];
  handle.lineWidth = 1.5f;
  handle.lineCapStyle = kCGLineCapRound;
  [handle stroke];

  UIBezierPath *circle = [UIBezierPath bezierPathWithOvalInRect:lens];
  circle.lineWidth = 1.5f;
  [circle stroke];
}

- (void)drawnTextFieldDidChange:(XPDrawnTextField *)field
{
  self.clearControl.hidden = field.text.length == 0;
  [self setNeedsLayout];
}

- (void)drawnTextFieldDidReturn:(XPDrawnTextField *)field
{
  [field resignFirstResponder];
  NSString *text = [field.text stringByTrimmingCharactersInSet:
                      [NSCharacterSet whitespaceAndNewlineCharacterSet]];
  if (self.searchHandler != nil) {
    self.searchHandler(text);
  }
}

- (void)clearRequested:(id)sender
{
  self.textField.text = @"";
  self.clearControl.hidden = YES;
  [self setNeedsLayout];
  if (self.clearHandler != nil) {
    self.clearHandler();
  }
}

@end
