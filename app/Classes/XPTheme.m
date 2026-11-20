//
//  XPTheme.m
//

#import "XPTheme.h"

UIColor *XPColorBackground(void)
{
  return [UIColor colorWithRed:10.0f / 255.0f
                         green:12.0f / 255.0f
                          blue:18.0f / 255.0f
                         alpha:1.0f];
}

UIColor *XPColorSurface(void)
{
  return [UIColor colorWithRed:20.0f / 255.0f
                         green:24.0f / 255.0f
                          blue:36.0f / 255.0f
                         alpha:1.0f];
}

UIColor *XPColorSurfaceAlt(void)
{
  return [UIColor colorWithRed:30.0f / 255.0f
                         green:36.0f / 255.0f
                          blue:52.0f / 255.0f
                         alpha:1.0f];
}

UIColor *XPColorAccent(void)
{
  return [UIColor colorWithRed:0.91f
                         green:0.15f
                          blue:0.24f
                         alpha:1.0f];
}

UIColor *XPColorAccentAlt(void)
{
  return [UIColor colorWithRed:0.45f
                         green:0.27f
                          blue:0.98f
                         alpha:1.0f];
}

UIColor *XPColorTextPrimary(void)
{
  return [UIColor colorWithRed:0.95f
                         green:0.96f
                          blue:0.98f
                         alpha:1.0f];
}

UIColor *XPColorTextMuted(void)
{
  return [UIColor colorWithRed:0.58f
                         green:0.62f
                          blue:0.70f
                         alpha:1.0f];
}

UIColor *XPColorDivider(void)
{
  return [UIColor colorWithRed:0.16f
                         green:0.19f
                          blue:0.26f
                         alpha:1.0f];
}

UIFont *XPFontDisplay(CGFloat size)
{
  return [UIFont systemFontOfSize:size weight:UIFontWeightBold];
}

UIFont *XPFontMedium(CGFloat size)
{
  return [UIFont systemFontOfSize:size weight:UIFontWeightSemibold];
}

UIFont *XPFontBody(CGFloat size)
{
  return [UIFont systemFontOfSize:size weight:UIFontWeightRegular];
}

UIFont *XPFontCaption(CGFloat size)
{
  return [UIFont systemFontOfSize:size weight:UIFontWeightMedium];
}

UIBezierPath *XPRoundedPath(CGRect rect, CGFloat radius)
{
  CGFloat limit = MIN(rect.size.width, rect.size.height) / 2.0f;
  CGFloat value = MAX(0.0f, MIN(radius, limit));
  return [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:value];
}

void XPDrawVerticalGradient(CGContextRef context, CGRect rect, UIColor *topColor, UIColor *bottomColor)
{
  if (context == NULL) {
    return;
  }
  CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
  if (space == NULL) {
    return;
  }
  NSArray *colors = @[ (topColor ?: XPColorBackground()).CGColor,
                       (bottomColor ?: XPColorBackground()).CGColor ];
  CGFloat locations[2] = { 0.0f, 1.0f };
  CGGradientRef gradient = CGGradientCreateWithColors(space,
                                                      (__bridge CFArrayRef)colors,
                                                      locations);
  if (gradient != NULL) {
    CGContextSaveGState(context);
    CGContextAddRect(context, rect);
    CGContextClip(context);
    CGContextDrawLinearGradient(context,
                                gradient,
                                CGPointMake(CGRectGetMidX(rect), CGRectGetMinY(rect)),
                                CGPointMake(CGRectGetMidX(rect), CGRectGetMaxY(rect)),
                                0);
    CGContextRestoreGState(context);
    CGGradientRelease(gradient);
  }
  CGColorSpaceRelease(space);
}

void XPDrawHorizontalGradient(CGContextRef context, CGRect rect, UIColor *leftColor, UIColor *rightColor)
{
  if (context == NULL) {
    return;
  }
  CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
  if (space == NULL) {
    return;
  }
  NSArray *colors = @[ (leftColor ?: XPColorAccent()).CGColor,
                       (rightColor ?: XPColorAccentAlt()).CGColor ];
  CGFloat locations[2] = { 0.0f, 1.0f };
  CGGradientRef gradient = CGGradientCreateWithColors(space,
                                                      (__bridge CFArrayRef)colors,
                                                      locations);
  if (gradient != NULL) {
    CGContextSaveGState(context);
    CGContextAddRect(context, rect);
    CGContextClip(context);
    CGContextDrawLinearGradient(context,
                                gradient,
                                CGPointMake(CGRectGetMinX(rect), CGRectGetMidY(rect)),
                                CGPointMake(CGRectGetMaxX(rect), CGRectGetMidY(rect)),
                                0);
    CGContextRestoreGState(context);
    CGGradientRelease(gradient);
  }
  CGColorSpaceRelease(space);
}
