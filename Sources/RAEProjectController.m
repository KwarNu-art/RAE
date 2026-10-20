#import "RAEProjectController.h"
#import "RAETextController.h"
#import "RAEStore.h"
#import "RAEClaude.h"
#import "RAEGenerator.h"
#import "RAEGitHub.h"
#import "RAEUI.h"

typedef NS_ENUM(NSInteger, RAESection) { RAESectionApp, RAESectionReports, RAESectionProfile, RAESectionBuild, RAESectionCount };

@implementation RAEProjectController {
    NSMutableDictionary *_project;
    NSString *_status;       // current line shown in the build section
    BOOL _building;
}

- (instancetype)initWithProject:(NSMutableDictionary *)project {
    if ((self = [super initWithStyle:UITableViewStyleInsetGrouped])) {
        _project = project;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = _project[@"name"];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
}

- (NSDictionary *)analysis { return _project[@"analysis"]; }
- (NSMutableDictionary *)profile { return _project[@"profile"]; }
- (BOOL)hasDeb { NSString *p = _project[@"debPath"]; return p.length && [NSFileManager.defaultManager fileExistsAtPath:p]; }
- (BOOL)hasReport { return [_project[@"aiReport"] length] > 0; }

#pragma mark - Rows

- (NSArray<NSString *> *)rowsInSection:(NSInteger)section {
    switch (section) {
        case RAESectionApp: return @[@"app", @"bundle", @"engine"];
        case RAESectionReports: return self.hasReport ? @[@"facts", @"ai", @"regen"] : @[@"facts", @"ai"];
        case RAESectionProfile: return @[@"fps", @"memory", @"timer", @"background", @"thermal"];
        default: {
            NSMutableArray *rows = [@[@"name", @"build"] mutableCopy];
            if (_status.length) [rows addObject:@"status"];
            if (self.hasDeb) [rows addObject:@"share"];
            [rows addObject:@"source"];
            if ([_project[@"runURL"] length]) [rows addObject:@"log"];
            return rows;
        }
    }
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return RAESectionCount; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return [self rowsInSection:section].count; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return @[@"This app", @"Reports", @"Boost profile", @"Online build"][section];
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == RAESectionReports) return @"The analysis is made on your phone. The AI report sends the analysis text (not the IPA) to Claude with your own API key.";
    if (section == RAESectionProfile) return @"These are the only things the generated tweak can do. It never touches the app's files, game logic, purchases, network traffic or protections. Results depend on the app and the phone.";
    if (section == RAESectionBuild) return @"RAE pushes the source to your GitHub builds repository, GitHub compiles the .deb, and RAE downloads it. Then share it to Sileo, Zebra or Filza to install, and respring.";
    return nil;
}

- (NSString *)fpsText {
    NSArray *t = @[@"Leave as the app wants", @"Smooth", @"Cool (60 fps max)"];
    return t[MAX(0, MIN(2, [self.profile[@"frameMode"] integerValue]))];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString *row = [self rowsInSection:indexPath.section][indexPath.row];
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
    NSDictionary *a = self.analysis;

    if ([row isEqualToString:@"app"]) {
        cell.textLabel.text = a[@"appName"]; cell.detailTextLabel.text = [NSString stringWithFormat:@"v%@", a[@"version"]];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([row isEqualToString:@"bundle"]) {
        cell.textLabel.text = @"Bundle id"; cell.detailTextLabel.text = a[@"bundleId"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([row isEqualToString:@"engine"]) {
        cell.textLabel.text = @"Engine"; cell.detailTextLabel.text = a[@"engine"];
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([row isEqualToString:@"facts"]) {
        cell.textLabel.text = @"Analysis details"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([row isEqualToString:@"ai"]) {
        cell.textLabel.text = @"AI report (Claude)";
        cell.detailTextLabel.text = self.hasReport ? @"Ready" : @"Create";
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([row isEqualToString:@"regen"]) {
        cell.textLabel.text = @"Make the AI report again"; cell.textLabel.textColor = RAEAccent();
    } else if ([row isEqualToString:@"fps"]) {
        cell.textLabel.text = @"Frame rate"; cell.detailTextLabel.text = self.fpsText;
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([@[@"memory", @"timer", @"background", @"thermal"] containsObject:row]) {
        NSDictionary *info = @{@"memory": @[@"Memory trim", @"memoryTrim"], @"timer": @[@"Timer saving", @"timerSaving"],
                               @"background": @[@"Background quiet", @"backgroundQuiet"], @"thermal": @[@"Thermal guard", @"thermalGuard"]};
        NSArray *pair = info[row];
        cell.textLabel.text = pair[0];
        UISwitch *sw = [[UISwitch alloc] init];
        sw.on = [self.profile[pair[1]] boolValue];
        sw.onTintColor = RAEAccent();
        sw.accessibilityIdentifier = pair[1];
        [sw addTarget:self action:@selector(profileSwitched:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = sw;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([row isEqualToString:@"name"]) {
        cell.textLabel.text = @"Project name"; cell.detailTextLabel.text = _project[@"name"];
    } else if ([row isEqualToString:@"build"]) {
        cell.textLabel.text = _building ? @"Building…" : @"Build the .deb online";
        cell.textLabel.textColor = _building ? UIColor.secondaryLabelColor : RAEAccent();
        cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    } else if ([row isEqualToString:@"status"]) {
        cell.textLabel.text = _status; cell.textLabel.numberOfLines = 0;
        cell.textLabel.font = [UIFont systemFontOfSize:14]; cell.textLabel.textColor = UIColor.secondaryLabelColor;
        cell.selectionStyle = UITableViewCellSelectionStyleNone;
    } else if ([row isEqualToString:@"share"]) {
        cell.textLabel.text = @"Install / share the .deb"; cell.textLabel.textColor = RAEAccent();
        cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
        cell.detailTextLabel.text = [_project[@"debPath"] lastPathComponent];
    } else if ([row isEqualToString:@"source"]) {
        cell.textLabel.text = @"View the generated source"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    } else if ([row isEqualToString:@"log"]) {
        cell.textLabel.text = @"Open the build log"; cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    }
    return cell;
}

#pragma mark - Actions

- (void)profileSwitched:(UISwitch *)sw {
    self.profile[sw.accessibilityIdentifier] = @(sw.on);
    [RAEStore.shared save];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    NSString *row = [self rowsInSection:indexPath.section][indexPath.row];
    UIView *source = [tableView cellForRowAtIndexPath:indexPath];

    if ([row isEqualToString:@"facts"]) {
        [self.navigationController pushViewController:[[RAETextController alloc] initWithTitle:@"Analysis" text:_project[@"facts"] monospaced:YES] animated:YES];
    } else if ([row isEqualToString:@"ai"]) {
        if (self.hasReport) [self showReport]; else [self makeReport];
    } else if ([row isEqualToString:@"regen"]) {
        [self makeReport];
    } else if ([row isEqualToString:@"fps"]) {
        self.profile[@"frameMode"] = @(([self.profile[@"frameMode"] integerValue] + 1) % 3);
        [RAEStore.shared save];
        [tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
        [self rae_alert:self.fpsText message:@[@"The tweak leaves the app's own frame rate alone and only steps in if the phone gets very hot.",
                                               @"If the app asks for less than your screen can show (for example 30 fps on a 60 Hz screen), it is raised to the screen's full rate: 60 on an iPhone 7 Plus, 120 on a ProMotion iPhone.",
                                               @"The app never runs above 60 fps, even on a 120 Hz screen. Cooler and lighter on the battery."][[self.profile[@"frameMode"] integerValue]]];
    } else if ([row isEqualToString:@"name"]) {
        [self rename];
    } else if ([row isEqualToString:@"build"]) {
        [self build];
    } else if ([row isEqualToString:@"share"]) {
        [self rae_shareItems:@[[NSURL fileURLWithPath:_project[@"debPath"]]] from:source];
    } else if ([row isEqualToString:@"source"]) {
        [self.navigationController pushViewController:[[RAETextController alloc] initWithTitle:@"Generated source" text:[RAEGenerator tweakSourcePreviewForProject:_project] monospaced:YES] animated:YES];
    } else if ([row isEqualToString:@"log"]) {
        NSURL *url = [NSURL URLWithString:_project[@"runURL"]];
        if (url) [UIApplication.sharedApplication openURL:url options:@{} completionHandler:nil];
    }
}

- (void)showReport {
    [self.navigationController pushViewController:[[RAETextController alloc] initWithTitle:@"AI report" text:_project[@"aiReport"] monospaced:NO] animated:YES];
}

- (void)makeReport {
    RAEStore *store = RAEStore.shared;
    if (!store.anthropicKey.length) {
        [self rae_alert:@"API key needed" message:@"Add your Anthropic API key in Settings (the gear on the first screen), then try again."];
        return;
    }
    UIAlertController *box = [self rae_showBusy:@"Claude is reading the analysis. This takes up to a minute."];
    NSDictionary *snapshot = [_project copy];
    NSString *key = store.anthropicKey, *model = store.model;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSDictionary *suggested = nil;
        NSError *error = nil;
        NSString *report = [RAEClaude reportForProject:snapshot apiKey:key model:model suggestedProfile:&suggested error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self rae_hideBusy:box completion:^{
                if (!report) { [self rae_alert:@"No report" message:error.localizedDescription ?: @"Unknown problem."]; return; }
                self->_project[@"aiReport"] = report;
                if (suggested.count) {
                    [self.profile addEntriesFromDictionary:suggested];
                    // Never throttle an app that must keep running in the background (audio, calls, location).
                    for (NSString *mode in self.analysis[@"backgroundModes"]) {
                        if ([@[@"audio", @"voip", @"location", @"bluetooth-central", @"bluetooth-peripheral", @"external-accessory"] containsObject:mode]) {
                            self.profile[@"backgroundQuiet"] = @NO;
                        }
                    }
                }
                [RAEStore.shared save];
                [self.tableView reloadData];
                [self showReport];
            }];
        });
    });
}

- (void)rename {
    UIAlertController *a = [UIAlertController alertControllerWithTitle:@"Project name" message:@"This becomes the package name in Sileo and Zebra." preferredStyle:UIAlertControllerStyleAlert];
    [a addTextFieldWithConfigurationHandler:^(UITextField *f) { f.text = self->_project[@"name"]; f.clearButtonMode = UITextFieldViewModeWhileEditing; }];
    [a addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    [a addAction:[UIAlertAction actionWithTitle:@"Save" style:UIAlertActionStyleDefault handler:^(UIAlertAction *x) {
        NSString *name = [a.textFields.firstObject.text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (name.length) {
            self->_project[@"name"] = name;
            self.title = name;
            [RAEStore.shared save];
            [self.tableView reloadData];
        }
    }]];
    [self presentViewController:a animated:YES completion:nil];
}

- (void)setStatus:(NSString *)status {
    _status = [status copy];
    [self.tableView reloadSections:[NSIndexSet indexSetWithIndex:RAESectionBuild] withRowAnimation:UITableViewRowAnimationNone];
}

- (void)build {
    if (_building) return;
    RAEStore *store = RAEStore.shared;
    if (!store.githubToken.length) {
        [self rae_alert:@"GitHub token needed" message:@"Add your GitHub token in Settings (the gear on the first screen). RAE uses it to build the .deb in your own repository."];
        return;
    }
    _building = YES;
    [self setStatus:@"Starting…"];
    UIApplication.sharedApplication.idleTimerDisabled = YES;   // keep the screen awake while waiting for the build
    NSString *token = store.githubToken, *repo = store.buildsRepo;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
        NSError *error = nil;
        NSString *deb = [RAEGitHub buildProject:self->_project token:token repoSetting:repo progress:^(NSString *line) {
            dispatch_async(dispatch_get_main_queue(), ^{ [self setStatus:line]; });
        } error:&error];
        dispatch_async(dispatch_get_main_queue(), ^{
            self->_building = NO;
            UIApplication.sharedApplication.idleTimerDisabled = NO;
            if (deb) {
                self->_project[@"debPath"] = deb;
                [RAEStore.shared save];
                [self setStatus:[NSString stringWithFormat:@"Done: %@", deb.lastPathComponent]];
                [self rae_shareItems:@[[NSURL fileURLWithPath:deb]] from:nil];
            } else {
                [RAEStore.shared save];
                [self setStatus:@"The build did not finish."];
                [self rae_alert:@"Build problem" message:error.localizedDescription ?: @"Unknown problem."];
            }
        });
    });
}

@end
