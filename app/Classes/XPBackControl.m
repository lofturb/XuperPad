//
//  XPBackControl.m
//

#import "XPBackControl.h"
#import "XPTheme.h"

@implementation XPBackControl

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
  }
  return self;
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
  [[XPColorSurfaceAlt() colorWithAlphaComponent:0.9f] setFill];
  [[XPRoundedPath(area, side / 2.0f) fill];

  [XPColorTextPrimary() setStroke];
  UIBezierPath *chevron = [UIBezierPath bezierPath];
  [chevron moveToPoint:CGPointMake(CGRectGetMidX(area) + 3.0f, CGRectGetMinY(area) + 4.0f)];
  [chevron addLineToPoint:CGPointMake(CGRectGetMidX(area) - 3.0f, CGRectGetMidY(area))];
  [chevron addLineToPoint:CGPointMake(CGRectGetMidX(area) + 3.0f, CGRectGetMaxY(area) - 4.0f)];
  chevron.lineWidth = 1.8f;
  chevron.lineCapStyle = kCGLineCapRound;
  chevron.lineJoinStyle = kCGLineJoinRound;
  [chevron stroke];
}

@end
