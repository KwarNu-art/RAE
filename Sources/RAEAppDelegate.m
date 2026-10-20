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

@end
