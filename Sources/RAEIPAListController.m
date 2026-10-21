#import "RAEIPAListController.h"
#import "RAEUI.h"

@interface RAEIPAListController ()
@property (nonatomic, strong) NSArray<NSDictionary *> *items;   // @{path, size, date}
@property (nonatomic) BOOL searching;
@end

@implementation RAEIPAListController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"IPAs on this iPhone";
    self.items = @[];
    self.searching = YES;
    [self scan];
}

// Looks in the usual places for downloads, Filza, Safari and this app's own Documents folder.
- (void)scan {
    NSArray *roots = @[
        [NSHomeDirectory() stringByAppendingPathComponent:@"Documents"], NSTemporaryDirectory(),
        @"/var/mobile/Documents", @"/var/mobile/Downloads", @"/var/mobile/Media/Downloads",
        @"/var/mobile/Media/Documents", @"/var/mobile/Media", @"/var/jb/var/mobile/Documents",
        @"/var/jb/var/mobile/Downloads", @"/var/mobile/Library/Mobile Documents/com~apple~CloudDocs",
    ];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSMutableDictionary *found = [NSMutableDictionary dictionary];
        for (NSString *root in roots) {
            NSDirectoryEnumerator *e = [fm enumeratorAtPath:root];
            for (NSString *rel in e) {
                if (e.level > 4) { [e skipDescendants]; continue; }
                NSString *last = rel.lastPathComponent;
                if ([last hasPrefix:@"."] || [last.pathExtension isEqualToString:@"app"]) { [e skipDescendants]; continue; }
                if (![last.pathExtension.lowercaseString isEqualToString:@"ipa"]) continue;
                NSString *path = [root stringByAppendingPathComponent:rel];
                NSDictionary *attrs = [fm attributesOfItemAtPath:path error:NULL];
                if (!attrs || found[path]) continue;
                found[path] = @{@"path": path, @"size": attrs[NSFileSize] ?: @0, @"date": attrs[NSFileModificationDate] ?: NSDate.distantPast};
            }
        }
        NSArray *sorted = [found.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            return [b[@"date"] compare:a[@"date"]];
        }];
        dispatch_async(dispatch_get_main_queue(), ^{
            self.items = sorted;
            self.searching = NO;
            [self.tableView reloadData];
        });
    });
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return MAX((NSInteger)self.items.count, 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    return @"Looks in Documents, Downloads, Filza and iCloud Drive. You can also put an IPA in Files > On My iPhone > RAE, or share it to RAE from Filza or Files with \"Open in RAE\".";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    if (!self.items.count) {
        cell.textLabel.text = self.searching ? @"Searching…" : @"No IPA found";
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.detailTextLabel.text = self.searching ? nil : @"Download or copy a decrypted IPA to this iPhone first.";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    NSDictionary *item = self.items[indexPath.row];
    cell.textLabel.text = [item[@"path"] lastPathComponent];
    NSString *size = [NSByteCountFormatter stringFromByteCount:[item[@"size"] longLongValue] countStyle:NSByteCountFormatterCountStyleFile];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@", size, [item[@"path"] stringByDeletingLastPathComponent]];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.imageView.image = [UIImage systemImageNamed:@"shippingbox"];
    cell.imageView.tintColor = RAEAccent();
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.row >= (NSInteger)self.items.count) return;
    NSURL *url = [NSURL fileURLWithPath:self.items[indexPath.row][@"path"]];
    void (^pick)(NSURL *) = self.onPick;
    [self.navigationController popViewControllerAnimated:YES];
    if (pick) pick(url);
}

@end
