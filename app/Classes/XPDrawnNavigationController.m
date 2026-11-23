//
//  XPDrawnNavigationController.m
//

#import "XPDrawnNavigationController.h"

@interface XPDrawnNavigationController ()
@property (nonatomic, strong) NSMutableArray *stack;
@end

@implementation XPDrawnNavigationController

- (instancetype)initWithRootViewController:(UIViewController *)rootViewController
{
  self = [super initWithNibName:nil bundle:nil];
  if (self) {
    _stack = [[NSMutableArray alloc] init];
    if (rootViewController != nil) {
      [self addChildViewController:rootViewController];
      rootViewController.view.frame = self.view.bounds;
      rootViewController.view.autoresizingMask =
          UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
      [self.view addSubview:rootViewController.view];
      [rootViewController didMoveToParentViewController:self];
      [_stack addObject:rootViewController];
    }
  }
  return self;
}

- (void)viewDidLoad
{
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor clearColor];
  self.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
}

- (NSArray *)viewControllers
{
  return [self.stack copy];
}

- (UIViewController *)topViewController
{
  return self.stack.lastObject;
}

- (void)notifyStackChanged
{
  if (self.stackChangeHandler != nil) {
    self.stackChangeHandler();
  }
}

- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated
{
  if (viewController == nil || [self.stack containsObject:viewController]) {
    return;
  }
  UIViewController *current = self.stack.lastObject;
  [current viewWillDisappear:animated];

  [self addChildViewController:viewController];
  [viewController didMoveToParentViewController:self];
  viewController.view.frame = self.view.bounds;
  viewController.view.autoresizingMask =
      UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
  [self.view addSubview:viewController.view];
  [self.stack addObject:viewController];
  [viewController viewWillAppear:animated];

  if (animated) {
    viewController.view.alpha = 0.0f;
    viewController.view.transform = CGAffineTransformMakeTranslation(24.0f, 0.0f);
    [UIView animateWithDuration:0.24
                     animations:^{
      viewController.view.alpha = 1.0f;
      viewController.view.transform = CGAffineTransformIdentity;
    }
                     completion:^(BOOL finished) {
      [current.view removeFromSuperview];
      [current viewDidDisappear:YES];
      [viewController viewDidAppear:YES];
    }];
  } else {
    [current.view removeFromSuperview];
    [current viewDidDisappear:NO];
    [viewController viewDidAppear:NO];
  }
  [self notifyStackChanged];
}

- (UIViewController *)popViewControllerAnimated:(BOOL)animated
{
  if (self.stack.count <= 1) {
    return nil;
  }
  UIViewController *top = self.stack.lastObject;
  UIViewController *below = self.stack[self.stack.count - 2];
  [top viewWillDisappear:animated];
  [below viewWillAppear:animated];

  below.view.frame = self.view.bounds;
  if (below.view.superview == nil) {
    [self.view insertSubview:below.view atIndex:0];
  }

  [self.stack removeLastObject];

  void (^finish)(BOOL) = ^(BOOL finished) {
    [top.view removeFromSuperview];
    [top removeFromParentViewController];
    [top viewDidDisappear:animated];
    [below viewDidAppear:animated];
  };

  if (animated) {
    below.view.alpha = 0.0f;
    [UIView animateWithDuration:0.22
                     animations:^{
      top.view.alpha = 0.0f;
      top.view.transform = CGAffineTransformMakeTranslation(24.0f, 0.0f);
      below.view.alpha = 1.0f;
    }
                     completion:^(BOOL finished) {
      top.view.transform = CGAffineTransformIdentity;
      finish(finished);
    }];
  } else {
    finish(NO);
  }
  [self notifyStackChanged];
  return top;
}

- (NSArray *)popToRootViewControllerAnimated:(BOOL)animated
{
  if (self.stack.count <= 1) {
    return @[];
  }
  NSMutableArray *removed = [NSMutableArray array];
  while (self.stack.count > 1) {
    UIViewController *top = self.stack.lastObject;
    [top.view removeFromSuperview];
    [top removeFromParentViewController];
    [self.stack removeLastObject];
    [removed addObject:top];
  }
  UIViewController *root = self.stack.firstObject;
  root.view.frame = self.view.bounds;
  root.view.alpha = 1.0f;
  root.view.transform = CGAffineTransformIdentity;
  if (root.view.superview == nil) {
    [self.view addSubview:root.view];
  }
  [self notifyStackChanged];
  return removed;
}

- (void)setNavigationBarHidden:(BOOL)hidden animated:(BOOL)animated
{
}

@end

@implementation UIViewController (XPDrawnNavigation)

- (XPDrawnNavigationController *)xpNavigationController
{
  UIViewController *controller = self.parentViewController;
  while (controller != nil) {
    if ([controller isKindOfClass:[XPDrawnNavigationController class]]) {
      return (XPDrawnNavigationController *)controller;
    }
    controller = controller.parentViewController;
  }
  return nil;
}

@end
