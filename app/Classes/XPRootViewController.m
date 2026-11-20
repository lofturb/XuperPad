//
//  XPRootViewController.m
//

#import "XPRootViewController.h"
#import "XPCatalogViewController.h"
#import "XPTabBar.h"
#import "XPTheme.h"

static const CGFloat XPRootTabBarHeight = 52.0f;

@interface XPRootViewController () <UINavigationControllerDelegate>
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) XPTabBar *tabBarView;
@property (nonatomic, strong) UINavigationController *catalogNavigation;
@property (nonatomic, strong) UINavigationController *liveNavigation;
@property (nonatomic, assign) NSUInteger selectedSection;
@property (nonatomic, assign) BOOL tabBarVisible;
@end

@implementation XPRootViewController

- (void)viewDidLoad
{
  [super viewDidLoad];
  self.view.backgroundColor = XPColorBackground();
  self.edgesForExtendedLayout = UIRectEdgeAll;
  self.selectedSection = 0;
  self.tabBarVisible = YES;

  self.containerView = [[UIView alloc] initWithFrame:self.view.bounds];
  self.containerView.backgroundColor = XPColorBackground();
  [self.view addSubview:self.containerView];

  XPCatalogViewController *catalog = [[XPCatalogViewController alloc] init];
  catalog.screenTitle = @"Catálogo";
  self.catalogNavigation = [[UINavigationController alloc] initWithRootViewController:catalog];
  self.catalogNavigation.delegate = self;
  [self.catalogNavigation setNavigationBarHidden:YES animated:NO];

  XPCatalogViewController *live = [[XPCatalogViewController alloc] init];
  live.screenTitle = @"TV en vivo";
  live.showsLiveChannels = YES;
  self.liveNavigation = [[UINavigationController alloc] initWithRootViewController:live];
  self.liveNavigation.delegate = self;
  [self.liveNavigation setNavigationBarHidden:YES animated:NO];

  [self addChildViewController:self.catalogNavigation];
  [self.containerView addSubview:self.catalogNavigation.view];
  [self.catalogNavigation didMoveToParentViewController:self];

  [self addChildViewController:self.liveNavigation];
  [self.containerView addSubview:self.liveNavigation.view];
  [self.liveNavigation didMoveToParentViewController:self];
  self.liveNavigation.view.hidden = YES;

  self.tabBarView = [[XPTabBar alloc] initWithTitles:@[ @"Catálogo", @"TV en vivo" ]
                                                icons:@[ @"grid", @"live" ]];
  [self.view addSubview:self.tabBarView];

  __weak XPRootViewController *weakSelf = self;
  self.tabBarView.selectionHandler = ^(NSUInteger index) {
    [weakSelf selectSectionAtIndex:index];
  };
}

- (void)viewDidLayoutSubviews
{
  [super viewDidLayoutSubviews];
  CGFloat width = CGRectGetWidth(self.view.bounds);
  CGFloat height = CGRectGetHeight(self.view.bounds);
  CGFloat tabHeight = self.tabBarVisible ? XPRootTabBarHeight : 0.0f;

  self.containerView.frame = CGRectMake(0, 0, width, MAX(0.0f, height - tabHeight));
  self.catalogNavigation.view.frame = self.containerView.bounds;
  self.liveNavigation.view.frame = self.containerView.bounds;

  self.tabBarView.frame = CGRectMake(0, MAX(0.0f, height - tabHeight), width, tabHeight);
  self.tabBarView.hidden = !self.tabBarVisible;
}

- (void)selectSectionAtIndex:(NSUInteger)index
{
  if (index > 1 || index == self.selectedSection) {
    return;
  }
  UINavigationController *target = (index == 0) ? self.catalogNavigation : self.liveNavigation;
  UINavigationController *other = (index == 0) ? self.liveNavigation : self.catalogNavigation;

  [other popToRootViewControllerAnimated:NO];
  self.selectedSection = index;
  self.catalogNavigation.view.hidden = (index != 0);
  self.liveNavigation.view.hidden = (index != 1);
  self.tabBarVisible = YES;
  [self.view setNeedsLayout];
  [self.view layoutIfNeeded];

  if (target.viewControllers.count == 1) {
    return;
  }
}

- (void)navigationController:(UINavigationController *)navigationController
      willShowViewController:(UIViewController *)viewController
                    animated:(BOOL)animated
{
  BOOL atRoot = navigationController.viewControllers.count <= 1;
  if (atRoot == self.tabBarVisible) {
    return;
  }
  self.tabBarVisible = atRoot;
  [self.view setNeedsLayout];
  if (animated) {
    [UIView animateWithDuration:0.22 animations:^{
      [self.view layoutIfNeeded];
    }];
  } else {
    [self.view layoutIfNeeded];
  }
}

@end
