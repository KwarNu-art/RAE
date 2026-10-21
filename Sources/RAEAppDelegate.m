#import "RAEAppDelegate.h"
#import "RAEHomeController.h"
#import "RAEUI.h"

@implementation RAEAppDelegate

- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.tintColor = RAEAccent();
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:[[RAEHomeController alloc] init]];
    self.window.rootViewController = nav;
    [self.window makeKeyAndVisible];
    return YES;
}

// "Open in RAE" from Files, Filza or Safari downloads.
- (BOOL)application:(UIApplication *)app openURL:(NSURL *)url options:(NSDictionary<UIApplicationOpenURLOptionsKey, id> *)options {
    UINavigationController *nav = (UINavigationController *)self.window.rootViewController;
    RAEHomeController *home = (RAEHomeController *)nav.viewControllers.firstObject;
    if (![home isKindOfClass:RAEHomeController.class] || !url.isFileURL) return NO;
    dispatch_async(dispatch_get_main_queue(), ^{ [home importIPAAtURL:url]; });
    return YES;
}

@end
