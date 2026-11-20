//
//  XPChipButton.m
//

#import "XPChipButton.h"
#import "XPTheme.h"

@implementation XPChipButton

- (instancetype)initWithTitle:(NSString *)title
{
  self = [super initWithFrame:CGRectZero];
  if (self) {
    _chipTitle = [title copy];
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    self.selected = NO;
  }
  return self;
}

- (void)setChipTitle:(NSString *)chipTitle
{
  _chipTitle = [chipTitle copy];
  [self setNeedsDisplay];
}

- (void)setSelected:(BOOL)selected
{
  [super setSelected:selected];
  [self setNeedsDisplay];
}

- (void)setHighlighted:(BOOL)highlighted
{
  [super setHighlighted:highlighted];
  [UIView animateWithDuration:0.12 animations:^{
    self.alpha = highlighted ? 0.7f : 1.0f;
  }];
}

- (void)drawRect:(CGRect)rect
{
  CGContextRef context = UIGraphicsGetCurrentContext();
  if (context == NULL) {
    return;
  }
  CGRect area = CGRectInset(self.bounds, 0.5f, 0.5f);
  if (area.size.width <= 2 || area.size.height <= 2) {
    return;
  }

  if (self.selected) {
    XPDrawHorizontalGradient(context, area, XPColorAccent(), XPColorAccentAlt());
  } else {
    [[XPColorSurfaceAlt() colorWithAlphaComponent:0.85f] setFill];
    [XPRoundedPath(area, area.size.height / 2.0f) fill];
  }

  NSString *title = self.chipTitle;
  if (title.length == 0) {
    return;
  }
  UIColor *textColor = self.selected ? [UIColor whiteColor] : XPColorTextPrimary();
  NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
  style.alignment = NSTextAlignmentCenter;
  style.lineBreakMode = NSLineBreakByTruncatingTail;
  NSDictionary *attributes = @{ NSFontAttributeName : XPFontCaption(11.5f),
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
