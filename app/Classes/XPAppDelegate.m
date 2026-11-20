//
//  XPAppDelegate.m
//

#import "XPAppDelegate.h"
#import "XPRootViewController.h"
#import "XPSeedPool.h"

@implementation XPAppDelegate

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions
{
  self.window = [[UIWindow alloc] initWithFrame:[[UIScreen mainScreen] bounds]];
  self.window.backgroundColor = [UIColor blackColor];

  self.window.rootViewController = [[XPRootViewController alloc] init];
  [self.window makeKeyAndVisible];

  [application setStatusBarStyle:UIStatusBarStyleLightContent];

  [[XPSeedPool sharedPool] refreshWithCompletion:^(NSUInteger availableCount) {
    NSLog(@"[XuperPad] credenciales anonimas disponibles: %lu",
          (unsigned long)availableCount);
  }];

  return YES;
}

@end
