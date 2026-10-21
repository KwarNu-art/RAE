#import "RAESettingsController.h"
#import "RAEStore.h"
#import "RAEUI.h"

@interface RAESettingsController () <UITextFieldDelegate>
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, UITextField *> *fields;
@end

@implementation RAESettingsController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    self.fields = [NSMutableDictionary dictionary];
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self saveAll];
}

#pragma mark - Saving

- (void)saveAll {
    RAEStore *s = RAEStore.shared;
    for (NSNumber *tag in self.fields) {
        NSString *text = self.fields[tag].text ?: @"";
        switch (tag.integerValue) {
            case 0: s.anthropicKey = text; break;
            case 1: s.model = text; break;
            case 2: s.baseURL = text; break;
            case 10: s.githubToken = text; break;
            case 11: s.buildsRepo = text; break;
        }
    }
}

- (void)fieldChanged:(UITextField *)field { [self saveAll]; }   // saved on every keystroke and paste

- (void)paste:(UIButton *)button {
    UITextField *field = self.fields[@(button.tag)];
    NSString *text = UIPasteboard.generalPasteboard.string;
    if (!field) return;
    if (!text.length) {
        [self rae_alert:@"Paste is not available"
                message:@"Either nothing is copied, or this phone does not let RAE read the clipboard.\n\nNo-paste way: open Notes, type\nrae://save?claude=YOUR_KEY&github=YOUR_TOKEN\n(put your real key and token in), then tap that link. RAE opens and saves them."];
        return;
    }
    field.text = [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    [self saveAll];
}

static NSString *Status(NSString *value, BOOL showEnd) {
    if (!value.length) return @"not set";
    if (showEnd && value.length > 8) return [NSString stringWithFormat:@"saved (ends …%@)", [value substringFromIndex:value.length - 4]];
    return @"saved";
}

- (void)saveTapped {
    [self.view endEditing:YES];
    [self saveAll];
    RAEStore *s = RAEStore.shared;
    NSString *message = [NSString stringWithFormat:@"AI (%@) key: %@\nGitHub token: %@\nModel: %@\nRepository: %@\n\nThey stay saved when you close and reopen RAE.",
                         s.providerInfo[@"name"], Status(s.anthropicKey, YES), Status(s.githubToken, YES), s.model,
                         s.buildsRepo.length ? s.buildsRepo : @"automatic (RAE-Builds)"];
    [self rae_alert:@"Saved ✓" message:message];
}

#pragma mark - Table

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 3; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 2 ? 1 : section == 0 ? 4 : 2; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"AI report" : section == 1 ? @"Online build (GitHub)" : nil;
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Pick an AI and add its key. Free keys: Google Gemini (aistudio.google.com/apikey), Groq (console.groq.com/keys), OpenRouter (openrouter.ai/keys, use models ending in :free). Free plans have limits, and model names change, so you can type any model name. Each AI keeps its own key. Claude (paid) needs a paid Anthropic key. RAE sends the analysis text of the IPA, never the IPA itself. If paste does not work: in Notes type rae://save?claude=YOUR_KEY and tap the link.";
    if (section == 1) return @"A GitHub token with the \"repo\" and \"workflow\" permissions (github.com > Settings > Developer settings > Tokens). RAE creates a public repository for your builds if it does not exist; leave the name empty to use <you>/RAE-Builds.";
    return @"Everything is also saved automatically as you type. It is stored in this app's own folder on your phone only.";
}

- (void)chooseProvider {
    [self saveAll];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:@"Choose an AI" message:nil preferredStyle:UIAlertControllerStyleActionSheet];
    for (NSDictionary *d in RAEStore.providers) {
        [sheet addAction:[UIAlertAction actionWithTitle:d[@"name"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *a) {
            RAEStore.shared.provider = d[@"id"];
            [self.fields removeAllObjects];
            [self.tableView reloadData];
        }]];
    }
    [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
    sheet.popoverPresentationController.sourceView = self.view;
    sheet.popoverPresentationController.sourceRect = CGRectMake(self.view.bounds.size.width / 2, 120, 1, 1);
    [self presentViewController:sheet animated:YES completion:nil];
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    if (indexPath.section == 2) {
        cell.textLabel.text = @"Save";
        cell.textLabel.textAlignment = NSTextAlignmentCenter;
        cell.textLabel.textColor = RAEAccent();
        cell.textLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightBold];
        return cell;
    }
    if (indexPath.section == 0 && indexPath.row == 0) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleValue1 reuseIdentifier:nil];
        cell.textLabel.text = @"AI";
        cell.detailTextLabel.text = RAEStore.shared.providerInfo[@"name"];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        return cell;
    }
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSInteger tag = indexPath.section == 0 ? indexPath.row - 1 : 10 + indexPath.row;
    NSDictionary *titleFor = @{@0: @"API key", @1: @"Model", @2: @"Base URL", @10: @"Token", @11: @"Repository"};
    NSDictionary *placeholderFor = @{@0: @"paste the AI key", @1: RAEStore.shared.providerInfo[@"model"] ?: @"model name",
                                     @2: RAEStore.shared.providerInfo[@"url"] ?: @"https://…/v1",
                                     @10: @"ghp_… or github_pat_…", @11: @"owner/RAE-Builds (optional)"};

    UILabel *label = [[UILabel alloc] init];
    label.text = titleFor[@(tag)];
    label.font = [UIFont systemFontOfSize:16];
    label.translatesAutoresizingMaskIntoConstraints = NO;

    UITextField *field = [[UITextField alloc] init];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.placeholder = placeholderFor[@(tag)];
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.spellCheckingType = UITextSpellCheckingTypeNo;
    field.smartQuotesType = UITextSmartQuotesTypeNo;
    field.smartDashesType = UITextSmartDashesTypeNo;
    field.delegate = self;
    field.returnKeyType = UIReturnKeyDone;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.font = [UIFont systemFontOfSize:15];
    field.tag = tag;
    [field addTarget:self action:@selector(fieldChanged:) forControlEvents:UIControlEventEditingChanged];
    RAEStore *s = RAEStore.shared;
    switch (tag) {
        case 0: field.text = s.anthropicKey; break;      // shown in plain text so you can see that it is there
        case 1: field.text = s.model; break;
        case 2: field.text = s.baseURL; break;
        case 10: field.text = s.githubToken; break;
        case 11: field.text = s.buildsRepo; break;
    }
    self.fields[@(tag)] = field;

    [cell.contentView addSubview:label];
    [cell.contentView addSubview:field];
    NSMutableArray *constraints = [NSMutableArray arrayWithArray:@[
        [label.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [label.widthAnchor constraintEqualToConstant:84],
        [field.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:8],
        [field.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
        [field.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
        [cell.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:48],
    ]];
    if (tag == 0 || tag == 10) {
        UIButton *paste = [UIButton buttonWithType:UIButtonTypeSystem];
        paste.translatesAutoresizingMaskIntoConstraints = NO;
        [paste setTitle:@"Paste" forState:UIControlStateNormal];
        paste.titleLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightSemibold];
        paste.tag = tag;
        [paste addTarget:self action:@selector(paste:) forControlEvents:UIControlEventTouchUpInside];
        [cell.contentView addSubview:paste];
        [constraints addObjectsFromArray:@[
            [paste.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
            [paste.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
            [paste.widthAnchor constraintEqualToConstant:52],
            [field.trailingAnchor constraintEqualToAnchor:paste.leadingAnchor constant:-4],
        ]];
    } else {
        [constraints addObject:[field.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor]];
    }
    [NSLayoutConstraint activateConstraints:constraints];
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
    if (indexPath.section == 2) [self saveTapped];
    else if (indexPath.section == 0 && indexPath.row == 0) [self chooseProvider];
}

- (void)textFieldDidEndEditing:(UITextField *)field { [self saveAll]; }
- (BOOL)textFieldShouldReturn:(UITextField *)field { [field resignFirstResponder]; return YES; }

@end
