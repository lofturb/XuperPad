//
//  XPDrawnNavigationController.h
//

#import <UIKit/UIKit.h>

@interface XPDrawnNavigationController : UIViewController

- (instancetype)initWithRootViewController:(UIViewController *)rootViewController;

@property (nonatomic, readonly) NSArray *viewControllers;
@property (nonatomic, readonly) UIViewController *topViewController;
@property (nonatomic, copy) void (^stackChangeHandler)(void);

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated;
- (UIViewController *)popViewControllerAnimated:(BOOL)animated;
- (NSArray *)popToRootViewControllerAnimated:(BOOL)animated;
- (void)setNavigationBarHidden:(BOOL)hidden animated:(BOOL)animated;

@end

@interface UIViewController (XPDrawnNavigation)
- (XPDrawnNavigationController *)xpNavigationController;
@end
