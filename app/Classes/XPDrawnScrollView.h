//
//  XPDrawnScrollView.h
//

#import <UIKit/UIKit.h>

@interface XPDrawnScrollView : UIView

@property (nonatomic, assign) CGSize contentSize;
@property (nonatomic, assign) CGPoint contentOffset;
@property (nonatomic, assign) BOOL scrollsHorizontally;
@property (nonatomic, assign) BOOL scrollsVertically;

- (void)setContentOffset:(CGPoint)contentOffset animated:(BOOL)animated;

@end
