//
//  XPRootViewController.m
//

#import "XPRootViewController.h"
#import "XPCatalogViewController.h"
#import "XPLibraryViewController.h"
#import "XPSettingsViewController.h"
#import "XPTabBar.h"
#import "XPTheme.h"
#import "XPDrawnNavigationController.h"

static const CGFloat XPRootTabBarHeight = 52.0f;
static const NSUInteger XPRootSectionCount = 4;

@interface XPRootViewController ()
@property (nonatomic, strong) UIView *containerView;
@property (nonatomic, strong) XPTabBar *tabBarView;
@property (nonatomic, strong) XPDrawnNavigationController *catalogNavigation;
@property (nonatomic, strong) XPDrawnNavigationController *liveNavigation;
@property (nonatomic, strong) XPDrawnNavigationController *libraryNavigation;
@property (nonatomic, strong) XPDrawnNavigationController *settingsNavigation;
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
  catalog.screenTitle = @"Catalogo";
  self.catalogNavigation = [[XPDrawnNavigationController alloc] initWithRootViewController:catalog];

  XPCatalogViewController *live = [[XPCatalogViewController alloc] init];
  live.screenTitle = @"TV en vivo";
  live.showsLiveChannels = YES;
  self.liveNavigation = [[XPDrawnNavigationController alloc] initWithRootViewController:live];

  XPLibraryViewController *library = [[XPLibraryViewController alloc] init];
  library.screenTitle = @"Mi lista";
  self.libraryNavigation = [[XPDrawnNavigationController alloc] initWithRootViewController:library];

  XPSettingsViewController *settings = [[XPSettingsViewController alloc] init];
  settings.screenTitle = @"Ajustes";
  self.settingsNavigation = [[XPDrawnNavigationController alloc] initWithRootViewController:settings];

  __weak XPRootViewController *weakSelf = self;
  for (NSUInteger index = 0; index < XPRootSectionCount; index++) {
    XPDrawnNavigationController *navigation = [self navigationAtIndex:index];
    [self addChildViewController:navigation];
    [self.containerView addSubview:navigation.view];
    [navigation didMoveToParentViewController:self];
    navigation.view.hidden = (index != 0);
    navigation.stackChangeHandler = ^{
      [weakSelf updateTabBarForVisibleStack];
    };
  }

  self.tabBarView = [[XPTabBar alloc] initWithTitles:@[ @"Catalogo", @"TV en vivo", @"Mi lista", @"Ajustes" ]
                                                icons:@[ @"grid", @"live", @"list", @"gear" ]];
  [self.view addSubview:self.tabBarView];

  self.tabBarView.selectionHandler = ^(NSUInteger index) {
    [weakSelf selectSectionAtIndex:index];
  };
}

- (XPDrawnNavigationController *)navigationAtIndex:(NSUInteger)index
{
  switch (index) {
    case 1:
      return self.liveNavigation;
    case 2:
      return self.libraryNavigation;
    case 3:
      return self.settingsNavigation;
    default:
      return self.catalogNavigation;
  }
}

- (void)viewDidLayoutSubviews
{
  [super viewDidLayoutSubviews];
  CGFloat width = CGRectGetWidth(self.view.bounds);
  CGFloat height = CGRectGetHeight(self.view.bounds);
  CGFloat tabHeight = self.tabBarVisible ? XPRootTabBarHeight : 0.0f;

  self.containerView.frame = CGRectMake(0, 0, width, MAX(0.0f, height - tabHeight));
  for (NSUInteger index = 0; index < XPRootSectionCount; index++) {
    [self navigationAtIndex:index].view.frame = self.containerView.bounds;
  }

  self.tabBarView.frame = CGRectMake(0, MAX(0.0f, height - tabHeight), width, tabHeight);
  self.tabBarView.hidden = !self.tabBarVisible;
}

- (XPDrawnNavigationController *)visibleNavigation
{
  return [self navigationAtIndex:self.selectedSection];
}

- (void)updateTabBarForVisibleStack
{
  XPDrawnNavigationController *visible = [self visibleNavigation];
  BOOL atRoot = visible.viewControllers.count <= 1;
  if (atRoot == self.tabBarVisible) {
    return;
  }
  self.tabBarVisible = atRoot;
  [self.view setNeedsLayout];
  [UIView animateWithDuration:0.22 animations:^{
    [self.view layoutIfNeeded];
  }];
}

- (void)selectSectionAtIndex:(NSUInteger)index
{
  if (index >= XPRootSectionCount || index == self.selectedSection) {
    return;
  }
  for (NSUInteger other = 0; other < XPRootSectionCount; other++) {
    XPDrawnNavigationController *navigation = [self navigationAtIndex:other];
    if (other != index) {
      [navigation popToRootViewControllerAnimated:NO];
    }
    navigation.view.hidden = (other != index);
  }
  self.selectedSection = index;
  self.tabBarVisible = YES;
  [self.view setNeedsLayout];
  [self.view layoutIfNeeded];
}

@end
