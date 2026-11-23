//
//  XPDrawnImageView.m
//

#import "XPDrawnImageView.h"

@implementation XPDrawnImageView

- (instancetype)initWithFrame:(CGRect)frame
{
  self = [super initWithFrame:frame];
  if (self) {
    self.backgroundColor = [UIColor clearColor];
    self.opaque = NO;
    self.contentMode = UIViewContentModeRedraw;
    self.userInteractionEnabled = NO;
    self.clipsToBounds = YES;
    _imageMode = XPDrawnImageModeFill;
    _cornerRadius = 0.0f;
    _fillColor = [UIColor colorWithWhite:0.12f alpha:1.0f];
    _borderWidth = 0.0f;
    _borderColor = nil;
  }
  return self;
}

- (void)setImage:(UIImage *)image
{
  _image = image;
  [self setNeedsDisplay];
}

- (void)setImageMode:(XPDrawnImageMode)imageMode
{
  _imageMode = imageMode;
  [self setNeedsDisplay];
}

- (void)setCornerRadius:(CGFloat)cornerRadius
{
  _cornerRadius = cornerRadius;
  [self setNeedsDisplay];
}

- (void)setFillColor:(UIColor *)fillColor
{
  _fillColor = fillColor ?: [UIColor colorWithWhite:0.12f alpha:1.0f];
  [self setNeedsDisplay];
}

- (void)setBorderWidth:(CGFloat)borderWidth
{
  _borderWidth = borderWidth;
  [self setNeedsDisplay];
}

- (void)setBorderColor:(UIColor *)borderColor
{
  _borderColor = borderColor;
  [self setNeedsDisplay];
}

- (CGRect)imageRectForBounds:(CGRect)bounds size:(CGSize)size
{
  if (size.width <= 0.0f || size.height <= 0.0f) {
    return CGRectZero;
  }
  if (self.imageMode == XPDrawnImageModeFill) {
    CGFloat scale = MAX(bounds.size.width / size.width, bounds.size.height / size.height);
    CGFloat width = size.width * scale;
    CGFloat height = size.height * scale;
    return CGRectMake(CGRectGetMidX(bounds) - width / 2.0f,
                      CGRectGetMidY(bounds) - height / 2.0f,
                      width,
                      height);
  }
  CGFloat scale = MIN(bounds.size.width / size.width, bounds.size.height / size.height);
  CGFloat width = size.width * scale;
  CGFloat height = size.height * scale;
  return CGRectMake(CGRectGetMidX(bounds) - width / 2.0f,
                    CGRectGetMidY(bounds) - height / 2.0f,
                    width,
                    height);
}

- (void)drawRect:(CGRect)rect
{
  CGContextRef context = UIGraphicsGetCurrentContext();
  if (context == NULL) {
    return;
  }
  CGRect area = self.bounds;
  if (area.size.width <= 0.0f || area.size.height <= 0.0f) {
    return;
  }

  UIBezierPath *clip = [UIBezierPath bezierPathWithRoundedRect:area
                                             cornerRadius:self.cornerRadius];
  CGContextSaveGState(context);
  [clip addClip];
  [self.fillColor setFill];
  CGContextFillRect(context, area);

  UIImage *image = self.image;
  if (image != nil) {
    CGRect target = [self imageRectForBounds:area size:image.size];
    if (!CGRectIsEmpty(target)) {
      [image drawInRect:target];
    }
  }
  CGContextRestoreGState(context);

  if (self.borderWidth > 0.0f && self.borderColor != nil) {
    CGFloat inset = self.borderWidth / 2.0f;
    CGRect borderRect = CGRectInset(area, inset, inset);
    UIBezierPath *border =
        [UIBezierPath bezierPathWithRoundedRect:borderRect
                                   cornerRadius:MAX(0.0f, self.cornerRadius - inset)];
    border.lineWidth = self.borderWidth;
    [self.borderColor setStroke];
    [border stroke];
  }
}

@end
