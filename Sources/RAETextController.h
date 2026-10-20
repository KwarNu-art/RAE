#import <UIKit/UIKit.h>

// Read-only text screen with a share button (reports, generated source).
@interface RAETextController : UIViewController
- (instancetype)initWithTitle:(NSString *)title text:(NSString *)text monospaced:(BOOL)monospaced;
@end
