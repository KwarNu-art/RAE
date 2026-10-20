#import <UIKit/UIKit.h>

// Shared look and small helpers for every screen.
UIColor *RAEAccent(void);

@interface UIViewController (RAE)
- (void)rae_alert:(NSString *)title message:(NSString *)message;
- (UIAlertController *)rae_showBusy:(NSString *)message;           // modal "working" box without buttons
- (void)rae_hideBusy:(UIAlertController *)box completion:(void (^)(void))completion;
- (void)rae_shareItems:(NSArray *)items from:(UIView *)source;
@end
