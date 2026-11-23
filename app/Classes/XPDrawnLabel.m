//
//  XPDrawnLabel.m
//

#import "XPDrawnLabel.h"

@implementation XPDrawnLabel

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    self.userInteractionEnabled = NO;
    _font = [UIFont systemFontOfSize:13.0f];
    _textColor = [UIColor whiteColor];
    _textAlignment = NSTextAlignmentLeft;
    _numberOfLines = 1;
    _lineBreakMode = NSLineBreakByTruncatingTail;
    _textInsets = UIEdgeInsetsZero;
  }
  return self;
}

- (void)setText:(NSString *)text
{
  _text = [text copy];
  [self setNeedsDisplay];
}

- (void)setFont:(UIFont *)font
{
  _font = font ?: [UIFont systemFontOfSize:13.0f];
  [self setNeedsDisplay];
}

- (void)setTextColor:(UIColor *)textColor
{
  _textColor = textColor ?: [UIColor whiteColor];
  [self setNeedsDisplay];
}

- (void)setTextAlignment:(NSTextAlignment)textAlignment
{
  _textAlignment = textAlignment;
  [self setNeedsDisplay];
}

- (void)setNumberOfLines:(NSInteger)numberOfLines
{
  _numberOfLines = numberOfLines;
  [self setNeedsDisplay];
}

- (void)setLineBreakMode:(NSLineBreakMode)lineBreakMode
{
  _lineBreakMode = lineBreakMode;
  [self setNeedsDisplay];
}

- (void)setTextInsets:(UIEdgeInsets)textInsets
{
  _textInsets = textInsets;
  [self setNeedsDisplay];
}

- (NSDictionary *)textAttributes
{
  NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
  style.alignment = self.textAlignment;
  style.lineBreakMode = self.lineBreakMode;
  return @{ NSFontAttributeName : self.font,
            NSForegroundColorAttributeName : self.textColor,
            NSParagraphStyleAttributeName : style };
}

- (CGRect)fittedRectInBounds:(CGRect)bounds
{
  CGRect area = UIEdgeInsetsInsetRect(bounds, self.textInsets);
  if (area.size.width <= 0.0f || area.size.height <= 0.0f) {
    return CGRectZero;
  }
  NSString *text = self.text ?: @"";
  if (text.length == 0) {
    return CGRectZero;
  }
  NSDictionary *attributes = [self textAttributes];
  CGFloat maxHeight = self.numberOfLines > 0
    ? self.font.lineHeight * (CGFloat)self.numberOfLines + 1.0f
    : CGFLOAT_MAX;
  NSStringDrawingOptions options = NSStringDrawingUsesLineFragmentOrigin;
  if (self.numberOfLines != 1) {
    options |= NSStringDrawingTruncatesLastVisibleLine;
  }
  CGRect fitted = [text boundingRectWithSize:CGSizeMake(area.size.width, maxHeight)
                                     options:options
                                  attributes:attributes
                                     context:nil];
  fitted.size.width = MIN(ceil(fitted.size.width) + 0.5f, area.size.width);
  fitted.size.height = MIN(ceil(fitted.size.height) + 0.5f, area.size.height);
  CGFloat y = CGRectGetMinY(area) + (area.size.height - fitted.size.height) / 2.0f;
  if (y < CGRectGetMinY(area)) {
    y = CGRectGetMinY(area);
  }
  return CGRectMake(CGRectGetMinX(area), y, fitted.size.width, fitted.size.height);
}

- (void)drawRect:(CGRect)rect
{
  NSString *text = self.text;
  if (text.length == 0) {
    return;
  }
  CGRect area = UIEdgeInsetsInsetRect(self.bounds, self.textInsets);
  if (area.size.width <= 0.0f || area.size.height <= 0.0f) {
    return;
  }
  NSDictionary *attributes = [self textAttributes];
  CGFloat maxHeight = self.numberOfLines > 0
    ? self.font.lineHeight * (CGFloat)self.numberOfLines + 1.0f
    : area.size.height;
  NSStringDrawingOptions options = NSStringDrawingUsesLineFragmentOrigin;
  if (self.numberOfLines != 1) {
    options |= NSStringDrawingTruncatesLastVisibleLine;
  }
  CGRect fitted = [text boundingRectWithSize:CGSizeMake(area.size.width, maxHeight)
                                     options:options
                                  attributes:attributes
                                     context:nil];
  CGFloat y = CGRectGetMinY(area) + (area.size.height - fitted.size.height) / 2.0f;
  if (y < CGRectGetMinY(area)) {
    y = CGRectGetMinY(area);
  }
  CGRect target = CGRectMake(CGRectGetMinX(area),
                             y,
                             area.size.width,
                             MIN(ceil(fitted.size.height) + 0.5f, area.size.height));
  [text drawWithRect:target
             options:options
          attributes:attributes
             context:nil];
}

- (CGSize)sizeThatFits:(CGSize)size
{
  CGRect area = CGRectMake(0.0f, 0.0f, size.width, size.height);
  CGRect fitted = [self fittedRectInBounds:area];
  CGFloat width = fitted.size.width + self.textInsets.left + self.textInsets.right;
  CGFloat height = fitted.size.height + self.textInsets.top + self.textInsets.bottom;
  return CGSizeMake(width, height);
}

- (CGSize)intrinsicContentSize
{
  CGFloat width = CGRectGetWidth(self.bounds);
  if (width <= 0.0f) {
    width = CGFLOAT_MAX;
  }
  return [self sizeThatFits:CGSizeMake(width, CGFLOAT_MAX)];
}

@end
