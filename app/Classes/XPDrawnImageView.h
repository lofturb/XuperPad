//
//  XPDrawnImageView.h
//

#import <UIKit/UIKit.h>

typedef NS_ENUM(NSInteger, XPDrawnImageMode) {
  XPDrawnImageModeFill,
  XPDrawnImageModeFit
};

@interface XPDrawnImageView : UIView

@property (nonatomic, strong) UIImage *image;
@property (nonatomic, assign) XPDrawnImageMode imageMode;
@property (nonatomic, assign) CGFloat cornerRadius;
@property (nonatomic, strong) UIColor *fillColor;
@property (nonatomic, assign) CGFloat borderWidth;
@property (nonatomic, strong) UIColor *borderColor;

@end
