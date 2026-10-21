#import "RAEAppDelegate.h"
#import "RAEHomeController.h"
#import "RAEUI.h"
#import "RAEStore.h"

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
    // rae://save?claude=KEY&github=TOKEN&model=NAME&repo=OWNER/NAME : saves the keys without needing copy and paste.
    if ([url.scheme.lowercaseString isEqualToString:@"rae"]) {
        NSURLComponents *parts = [NSURLComponents componentsWithURL:url resolvingAgainstBaseURL:NO];
        RAEStore *store = RAEStore.shared;
        NSMutableArray *saved = [NSMutableArray array];
        for (NSURLQueryItem *item in parts.queryItems) {
            NSString *key = item.name.lowercaseString;
            if (!item.value.length) continue;
            if ([key isEqualToString:@"claude"] || [key isEqualToString:@"api"] || [key isEqualToString:@"key"]) { store.anthropicKey = item.value; [saved addObject:@"Claude API key"]; }
            else if ([key isEqualToString:@"github"] || [key isEqualToString:@"token"]) { store.githubToken = item.value; [saved addObject:@"GitHub token"]; }
            else if ([key isEqualToString:@"model"]) { store.model = item.value; [saved addObject:@"Model"]; }
            else if ([key isEqualToString:@"repo"]) { store.buildsRepo = item.value; [saved addObject:@"Repository"]; }
        }
        dispatch_async(dispatch_get_main_queue(), ^{
            UIViewController *top = self.window.rootViewController;
            while (top.presentedViewController) top = top.presentedViewController;
            [top rae_alert:saved.count ? @"Saved ✓" : @"Nothing saved"
                   message:saved.count ? [[saved componentsJoinedByString:@", "] stringByAppendingString:@" saved. They stay saved when you close RAE."]
                                        : @"The link had no keys. Use rae://save?claude=YOUR_KEY&github=YOUR_TOKEN"];
        });
        return YES;
    }
    UINavigationController *nav = (UINavigationController *)self.window.rootViewController;
    RAEHomeController *home = (RAEHomeController *)nav.viewControllers.firstObject;
    if (![home isKindOfClass:RAEHomeController.class] || !url.isFileURL) return NO;
    dispatch_async(dispatch_get_main_queue(), ^{ [home importIPAAtURL:url]; });
    return YES;
}

@end
