#import "RAEHomeController.h"
#import "RAEProjectController.h"
#import "RAESettingsController.h"
#import "RAEAnalyzer.h"
#import "RAEStore.h"
#import "RAEUI.h"

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
    return section == 0 ? 1 : MAX((NSInteger)RAEStore.shared.projects.count, 1);
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
        cell.textLabel.text = @"Choose a decrypted IPA…";
        cell.textLabel.textColor = RAEAccent();
        cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        cell.imageView.image = [UIImage systemImageNamed:@"doc.badge.plus"];
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
    if (indexPath.section == 0) { [self pickIPA]; return; }
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
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:@[@"public.data"] inMode:UIDocumentPickerModeImport];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    UIAlertController *box = [self rae_showBusy:@"Reading the IPA…"];
    // The picker already copied the file into this app's temp folder.
    NSString *path = url.path;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSDictionary *analysis = [RAEAnalyzer analyzeIPAAtPath:path progress:^(NSString *step) {
            dispatch_async(dispatch_get_main_queue(), ^{ box.message = [step stringByAppendingString:@"\n\n"]; });
        } error:&error];
        NSString *facts = analysis ? [RAEAnalyzer factsReportForAnalysis:analysis] : nil;
        [NSFileManager.defaultManager removeItemAtPath:path error:NULL];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self rae_hideBusy:box completion:^{
                if (!analysis) {
                    [self rae_alert:@"Could not analyse this file" message:error.localizedDescription ?: @"Unknown problem."];
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
