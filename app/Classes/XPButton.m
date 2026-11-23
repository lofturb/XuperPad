//
//  XPButton.m
//

#import "XPButton.h"
#import "XPTheme.h"

@implementation XPButton

- (instancetype)initWithTitle:(NSString *)title style:(XPButtonStyle)style
{
  self = [super initWithFrame:CGRectZero];
  if (self) {
    _buttonTitle = [title copy];
    _buttonStyle = style;
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
  }
  return self;
}

- (void)setButtonTitle:(NSString *)buttonTitle
{
  _buttonTitle = [buttonTitle copy];
  [self setNeedsDisplay];
}

- (void)setButtonStyle:(XPButtonStyle)buttonStyle
{
  _buttonStyle = buttonStyle;
  [self setNeedsDisplay];
}

- (void)setHighlighted:(BOOL)highlighted
{
  [super setHighlighted:highlighted];
  [UIView animateWithDuration:0.12 animations:^{
    self.alpha = highlighted ? 0.78f : 1.0f;
  }];
}

- (void)drawRect:(CGRect)rect
{
  CGContextRef context = UIGraphicsGetCurrentContext();
  if (context == NULL) {
    return;
  }
  CGRect area = CGRectInset(self.bounds, 0.5f, 0.5f);
  if (area.size.width <= 0 || area.size.height <= 0) {
    return;
  }

  if (self.buttonStyle == XPButtonStylePrimary) {
    CGContextSaveGState(context);
    [XPRoundedPath(area, 10.0f) addClip];
    XPDrawHorizontalGradient(context, area, XPColorAccent(), XPColorAccentAlt());
    CGContextRestoreGState(context);
    [[UIColor colorWithWhite:1.0f alpha:0.18f] setStroke];
    UIBezierPath *glow = XPRoundedPath(area, 10.0f);
    glow.lineWidth = 1.0f;
    [glow stroke];
  } else {
    [[XPColorSurfaceAlt() colorWithAlphaComponent:0.75f] setFill];
    [XPRoundedPath(area, 10.0f) fill];
    [XPColorDivider() setStroke];
    UIBezierPath *border = XPRoundedPath(area, 10.0f);
    border.lineWidth = 1.0f;
    [border stroke];
  }

  NSString *title = self.buttonTitle;
  if (title.length == 0) {
    return;
  }
  UIColor *textColor = self.buttonStyle == XPButtonStylePrimary
    ? [UIColor whiteColor]
    : XPColorTextPrimary();
  NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
  style.alignment = NSTextAlignmentCenter;
  style.lineBreakMode = NSLineBreakByTruncatingTail;
  NSDictionary *attributes = @{ NSFontAttributeName : XPFontMedium(14.0f),
                                NSForegroundColorAttributeName : textColor,
                                NSParagraphStyleAttributeName : style };
  CGSize fitted = [title sizeWithAttributes:attributes];
  CGRect textRect = CGRectMake(0,
                                (CGRectGetHeight(self.bounds) - fitted.height) / 2.0f,
                                CGRectGetWidth(self.bounds),
                                fitted.height);
  [title drawInRect:textRect withAttributes:attributes];
}

@end
