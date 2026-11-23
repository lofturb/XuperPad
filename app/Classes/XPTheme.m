//
//  XPTheme.m
//

#import "XPTheme.h"

UIColor *XPColorBackground(void)
{
  return [UIColor colorWithRed:6.0f / 255.0f
                         green:8.0f / 255.0f
                          blue:15.0f / 255.0f
                         alpha:1.0f];
}

UIColor *XPColorSurface(void)
{
  return [UIColor colorWithRed:16.0f / 255.0f
                         green:23.0f / 255.0f
                          blue:38.0f / 255.0f
                         alpha:1.0f];
}

UIColor *XPColorSurfaceAlt(void)
{
  return [UIColor colorWithRed:27.0f / 255.0f
                         green:36.0f / 255.0f
                          blue:56.0f / 255.0f
                         alpha:1.0f];
}

UIColor *XPColorAccent(void)
{
  return [UIColor colorWithRed:1.0f
                         green:0.176f
                          blue:0.435f
                         alpha:1.0f];
}

UIColor *XPColorAccentAlt(void)
{
  return [UIColor colorWithRed:0.482f
                         green:0.361f
                          blue:1.0f
                         alpha:1.0f];
}

UIColor *XPColorTextPrimary(void)
{
  return [UIColor colorWithRed:0.961f
                         green:0.969f
                          blue:0.988f
                         alpha:1.0f];
}

UIColor *XPColorTextMuted(void)
{
  return [UIColor colorWithRed:0.592f
                         green:0.631f
                          blue:0.722f
                         alpha:1.0f];
}

UIColor *XPColorDivider(void)
{
  return [UIColor colorWithRed:0.133f
                         green:0.173f
                          blue:0.267f
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
  CGColorRef top = (topColor ?: XPColorBackground()).CGColor;
  CGColorRef bottom = (bottomColor ?: XPColorBackground()).CGColor;
  const void *values[2] = { top, bottom };
  CGFloat locations[2] = { 0.0f, 1.0f };
  CFArrayRef colors = CFArrayCreate(NULL, values, 2, &kCFTypeArrayCallBacks);
  CGGradientRef gradient = NULL;
  if (colors != NULL) {
    gradient = CGGradientCreateWithColors(space, colors, locations);
    CFRelease(colors);
  }
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
  CGColorRef left = (leftColor ?: XPColorAccent()).CGColor;
  CGColorRef right = (rightColor ?: XPColorAccentAlt()).CGColor;
  const void *values[2] = { left, right };
  CGFloat locations[2] = { 0.0f, 1.0f };
  CFArrayRef colors = CFArrayCreate(NULL, values, 2, &kCFTypeArrayCallBacks);
  CGGradientRef gradient = NULL;
  if (colors != NULL) {
    gradient = CGGradientCreateWithColors(space, colors, locations);
    CFRelease(colors);
  }
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
