#import "RAEUI.h"

UIColor *RAEAccent(void) { return [UIColor colorWithRed:0.35 green:0.40 blue:1.0 alpha:1.0]; }

@implementation UIViewController (RAE)

- (void)rae_alert:(NSString *)title message:(NSString *)message {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
    [a addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:a animated:YES completion:nil];
}

- (UIAlertController *)rae_showBusy:(NSString *)message {
    UIAlertController *box = [UIAlertController alertControllerWithTitle:@"Working" message:[message stringByAppendingString:@"\n\n"]
                                                          preferredStyle:UIAlertControllerStyleAlert];
    UIActivityIndicatorView *spinner = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    spinner.translatesAutoresizingMaskIntoConstraints = NO;
    [spinner startAnimating];
    [box.view addSubview:spinner];
    [NSLayoutConstraint activateConstraints:@[
        [spinner.centerXAnchor constraintEqualToAnchor:box.view.centerXAnchor],
        [spinner.bottomAnchor constraintEqualToAnchor:box.view.bottomAnchor constant:-18],
    ]];
    [self presentViewController:box animated:YES completion:nil];
    return box;
}

- (void)rae_hideBusy:(UIAlertController *)box completion:(void (^)(void))completion {
    [box dismissViewControllerAnimated:YES completion:completion];
}

- (void)rae_shareItems:(NSArray *)items from:(UIView *)source {
    UIActivityViewController *share = [[UIActivityViewController alloc] initWithActivityItems:items applicationActivities:nil];
    share.popoverPresentationController.sourceView = source ?: self.view;
    share.popoverPresentationController.sourceRect = (source ?: self.view).bounds;
    [self presentViewController:share animated:YES completion:nil];
}

@end
