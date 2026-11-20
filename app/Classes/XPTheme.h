//
//  XPTheme.h
//

#import <UIKit/UIKit.h>

UIColor *XPColorBackground(void);
UIColor *XPColorSurface(void);
UIColor *XPColorSurfaceAlt(void);
UIColor *XPColorAccent(void);
UIColor *XPColorAccentAlt(void);
UIColor *XPColorTextPrimary(void);
UIColor *XPColorTextMuted(void);
UIColor *XPColorDivider(void);

UIFont *XPFontDisplay(CGFloat size);
UIFont *XPFontMedium(CGFloat size);
UIFont *XPFontBody(CGFloat size);
UIFont *XPFontCaption(CGFloat size);

UIBezierPath *XPRoundedPath(CGRect rect, CGFloat radius);
void XPDrawVerticalGradient(CGContextRef context, CGRect rect, UIColor *topColor, UIColor *bottomColor);
void XPDrawHorizontalGradient(CGContextRef context, CGRect rect, UIColor *leftColor, UIColor *rightColor);
