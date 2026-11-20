//
//  XPAppDelegate.m
//

#import "XPAppDelegate.h"
#import "XPCatalogViewController.h"
#import "XPSeedPool.h"

@implementation XPAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];

  XPCatalogViewController *catalog = [[XPCatalogViewController alloc] init];
  catalog.screenTitle = @"XuperPad";
  UINavigationController *catalogNavigation =
      [[UINavigationController alloc] initWithRootViewController:catalog];

  XPCatalogViewController *live = [[XPCatalogViewController alloc] init];
  live.screenTitle = @"TV en vivo";
  live.showsLiveChannels = YES;
  UINavigationController *liveNavigation =
      [[UINavigationController alloc] initWithRootViewController:live];

  UITabBarController *tabs = [[UITabBarController alloc] init];
  tabs.viewControllers = @[ catalogNavigation, liveNavigation ];
  tabs.tabBar.items = @[
    [[UITabBarItem alloc] initWithTitle:@"Catalogo"
                                  image:nil
                                    tag:0],
    [[UITabBarItem alloc] initWithTitle:@"TV en vivo"
                                  image:nil
                                    tag:1]
  ];

  self.window.rootViewController = tabs;
  [self.window makeKeyAndVisible];

  [[XPSeedPool sharedPool] refreshWithCompletion:^(NSUInteger availableCount) {
    NSLog(@"[XuperPad] credenciales anonimas disponibles: %lu",
          (unsigned long)availableCount);
  }];

  return YES;
}

@end
