#import "RAEHomeController.h"
#import "RAEProjectController.h"
#import "RAESettingsController.h"
#import "RAEAnalyzer.h"
#import "RAEStore.h"
#import "RAEUI.h"
#import "RAEIPAListController.h"

@interface RAEHomeController () <UIDocumentPickerDelegate>
@end

@implementation RAEHomeController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"RAE";
    self.navigationController.navigationBar.prefersLargeTitles = YES;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithImage:[UIImage systemImageNamed:@"gearshape"]
                                                                              style:UIBarButtonItemStylePlain target:self action:@selector(openSettings)];
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [self.tableView reloadData];
}

- (void)openSettings {
    [self.navigationController pushViewController:[[RAESettingsController alloc] init] animated:YES];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return section == 0 ? 2 : MAX((NSInteger)RAEStore.shared.projects.count, 1);
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 1 ? @"Projects" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Pick a decrypted IPA. RAE reads it on this phone, explains how the app works, and builds a small performance tweak for that one app. It never modifies, cracks or hacks the IPA.";
    return RAEStore.shared.projects.count ? @"Swipe left to delete a project." : nil;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    if (indexPath.section == 0) {
        UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
        cell.textLabel.text = indexPath.row == 0 ? @"Choose a decrypted IPA…" : @"Find IPAs on this iPhone…";
        cell.textLabel.textColor = RAEAccent();
        cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        cell.imageView.image = [UIImage systemImageNamed:indexPath.row == 0 ? @"doc.badge.plus" : @"magnifyingglass"];
        cell.imageView.tintColor = RAEAccent();
        return cell;
    }
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:nil];
    NSArray *projects = RAEStore.shared.projects;
    if (!projects.count) {
        cell.textLabel.text = @"No projects yet";
        cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.detailTextLabel.text = @"Choose an IPA to start.";
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
        return cell;
    }
    NSDictionary *p = projects[indexPath.row];
    NSDictionary *a = p[@"analysis"];
    cell.textLabel.text = p[@"name"];
    BOOL built = [p[@"debPath"] length] && [NSFileManager.defaultManager fileExistsAtPath:p[@"debPath"]];
    cell.detailTextLabel.text = [NSString stringWithFormat:@"%@ · %@ · %@", a[@"bundleId"], a[@"engine"], built ? @".deb ready" : @"not built yet"];
    cell.detailTextLabel.textColor = UIColor.secondaryLabelColor;
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 0) {
        if (indexPath.row == 0) [self pickIPA]; else [self browseIPAs];
        return;
    }
    NSArray *projects = RAEStore.shared.projects;
    if (indexPath.row < (NSInteger)projects.count) {
        [self.navigationController pushViewController:[[RAEProjectController alloc] initWithProject:projects[indexPath.row]] animated:YES];
    }
}

- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    return indexPath.section == 1 && RAEStore.shared.projects.count > 0;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)style forRowAtIndexPath:(NSIndexPath *)indexPath {
    if (style != UITableViewCellEditingStyleDelete) return;
    [RAEStore.shared deleteProject:RAEStore.shared.projects[indexPath.row]];
    [tableView reloadData];
}

#pragma mark - Picking and analysing

- (void)pickIPA {
    // "Open" mode reads the file where it is, which works for jailbroken apps that have no private storage.
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initWithDocumentTypes:@[@"public.item", @"public.data", @"com.apple.itunes.ipa"] inMode:UIDocumentPickerModeOpen];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)browseIPAs {
    RAEIPAListController *list = [[RAEIPAListController alloc] init];
    __weak typeof(self) weakSelf = self;
    list.onPick = ^(NSURL *url) { [weakSelf importIPAAtURL:url]; };
    [self.navigationController pushViewController:list animated:YES];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    // Wait for the picker to finish closing before showing the progress box.
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.45 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self importIPAAtURL:url];
    });
}

// Reads the IPA where it is. Only if it cannot be read there, a copy is made in a folder this app can write to.
// The original file is never changed or deleted.
- (void)importIPAAtURL:(NSURL *)url {
    [self.navigationController popToRootViewControllerAnimated:NO];
    UIViewController *top = self;
    while (top.presentedViewController) top = top.presentedViewController;
    UIAlertController *box = [top rae_showBusy:@"Opening the IPA…"];

    BOOL scoped = [url startAccessingSecurityScopedResource];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSFileManager *fm = NSFileManager.defaultManager;
        NSString *path = url.path;
        NSString *copyDir = nil;
        NSError *error = nil;
        BOOL ready = [fm isReadableFileAtPath:path];

        if (!ready) {
            NSString *name = url.lastPathComponent.length ? url.lastPathComponent : @"app.ipa";
            for (NSString *base in @[RAEStore.supportDirectory, NSTemporaryDirectory(), @"/var/tmp", @"/var/mobile/Documents"]) {
                NSString *dir = [base stringByAppendingPathComponent:[@"import-" stringByAppendingString:NSUUID.UUID.UUIDString]];
                if (![fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:NULL]) continue;
                NSString *dest = [dir stringByAppendingPathComponent:name];
                __block NSError *copyError = nil;
                __block BOOL copied = NO;
                NSError *coordError = nil;
                [[[NSFileCoordinator alloc] initWithFilePresenter:nil]
                    coordinateReadingItemAtURL:url options:NSFileCoordinatorReadingWithoutChanges error:&coordError
                                    byAccessor:^(NSURL *readURL) {
                    copied = [fm copyItemAtURL:readURL toURL:[NSURL fileURLWithPath:dest] error:&copyError];
                }];
                if (copied) { path = dest; copyDir = dir; ready = YES; break; }
                error = copyError ?: coordError;
                [fm removeItemAtPath:dir error:NULL];
            }
        }

        NSDictionary *analysis = nil;
        NSString *facts = nil;
        if (ready) {
            error = nil;
            analysis = [RAEAnalyzer analyzeIPAAtPath:path progress:^(NSString *step) {
                dispatch_async(dispatch_get_main_queue(), ^{ box.message = [step stringByAppendingString:@"\n\n"]; });
            } error:&error];
            facts = analysis ? [RAEAnalyzer factsReportForAnalysis:analysis] : nil;
        }
        if (copyDir) [fm removeItemAtPath:copyDir error:NULL];   // only our own copy is deleted
        if (scoped) [url stopAccessingSecurityScopedResource];

        dispatch_async(dispatch_get_main_queue(), ^{
            [top rae_hideBusy:box completion:^{
                if (!analysis) {
                    [self rae_alert:@"Could not open this file" message:error.localizedDescription ?: @"RAE cannot read this file. Try \"Find IPAs on this iPhone\" or move the IPA to Documents."];
                    return;
                }
                NSMutableDictionary *project = [RAEStore.shared addProjectForAnalysis:analysis facts:facts];
                [self.tableView reloadData];
                [self.navigationController pushViewController:[[RAEProjectController alloc] initWithProject:project] animated:YES];
            }];
        });
    });
}

@end
