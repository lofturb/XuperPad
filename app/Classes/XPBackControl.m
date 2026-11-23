//
//  XPBackControl.m
//

#import "XPBackControl.h"
#import "XPTheme.h"

static CGFloat const XPBackControlTouchPadding = 14.0f;

@implementation XPBackControl

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    self.accessibilityLabel = @"Atras";
  }
  return self;
}

- (BOOL)pointInside:(CGPoint)point withEvent:(UIEvent *)event
{
  CGRect area = CGRectInset(self.bounds, -XPBackControlTouchPadding, -XPBackControlTouchPadding);
  return CGRectContainsPoint(area, point);
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
  CGFloat side = MIN(CGRectGetWidth(self.bounds), CGRectGetHeight(self.bounds));
  CGRect area = CGRectMake((CGRectGetWidth(self.bounds) - side) / 2.0f,
                            (CGRectGetHeight(self.bounds) - side) / 2.0f,
                            side,
                            side);

  [[XPColorSurfaceAlt() colorWithAlphaComponent:0.92f] setFill];
  [XPRoundedPath(area, side / 2.0f) fill];

  [[UIColor colorWithWhite:1.0f alpha:0.12f] setStroke];
  UIBezierPath *edge = XPRoundedPath(CGRectInset(area, 0.5f, 0.5f), side / 2.0f);
  edge.lineWidth = 1.0f;
  [edge stroke];

  [XPColorTextPrimary() setStroke];
  UIBezierPath *chevron = [UIBezierPath bezierPath];
  [chevron moveToPoint:CGPointMake(CGRectGetMidX(area) + 3.4f, CGRectGetMidY(area) - 6.2f)];
  [chevron addLineToPoint:CGPointMake(CGRectGetMidX(area) - 2.6f, CGRectGetMidY(area))];
  [chevron addLineToPoint:CGPointMake(CGRectGetMidX(area) + 3.4f, CGRectGetMidY(area) + 6.2f)];
  chevron.lineWidth = 2.2f;
  chevron.lineCapStyle = kCGLineCapRound;
  chevron.lineJoinStyle = kCGLineJoinRound;
  [chevron stroke];
}

@end
