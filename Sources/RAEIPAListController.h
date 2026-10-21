#import <UIKit/UIKit.h>

// A built-in list of the .ipa files found on this iPhone, for when the Files picker cannot show or open them.
@interface RAEIPAListController : UITableViewController
@property (nonatomic, copy) void (^onPick)(NSURL *url);
@end
