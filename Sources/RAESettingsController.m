#import "RAESettingsController.h"
#import "RAEStore.h"
#import "RAEUI.h"

@interface RAESettingsController () <UITextFieldDelegate>
@end

@implementation RAESettingsController

- (instancetype)init { return [super initWithStyle:UITableViewStyleInsetGrouped]; }

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Settings";
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView { return 2; }
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section { return section == 0 ? 2 : 2; }

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    return section == 0 ? @"AI report (Claude)" : @"Online build (GitHub)";
}

- (NSString *)tableView:(UITableView *)tableView titleForFooterInSection:(NSInteger)section {
    if (section == 0) return @"Your own Anthropic API key (console.anthropic.com). It is only sent to api.anthropic.com. RAE sends the analysis text of the IPA, never the IPA itself.";
    return @"A GitHub token with the \"repo\" and \"workflow\" permissions (github.com > Settings > Developer settings > Tokens). RAE creates a public repository for your builds if it does not exist; leave the name empty to use <you>/RAE-Builds. Keys and tokens are stored in this app's storage on your phone only.";
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    UITableViewCell *cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:nil];
    cell.selectionStyle = UITableViewCellSelectionStyleNone;
    NSArray *titles = @[@[@"API key", @"Model"], @[@"Token", @"Repository"]];
    NSArray *placeholders = @[@[@"sk-ant-…", @"claude-sonnet-5-5"], @[@"ghp_… or github_pat_…", @"owner/RAE-Builds (optional)"]];
    UILabel *label = [[UILabel alloc] init];
    label.text = titles[indexPath.section][indexPath.row];
    label.font = [UIFont systemFontOfSize:16];
    label.translatesAutoresizingMaskIntoConstraints = NO;
    UITextField *field = [[UITextField alloc] init];
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.placeholder = placeholders[indexPath.section][indexPath.row];
    field.autocapitalizationType = UITextAutocapitalizationTypeNone;
    field.autocorrectionType = UITextAutocorrectionTypeNo;
    field.delegate = self;
    field.returnKeyType = UIReturnKeyDone;
    field.clearButtonMode = UITextFieldViewModeWhileEditing;
    field.tag = indexPath.section * 10 + indexPath.row;
    RAEStore *s = RAEStore.shared;
    switch (field.tag) {
        case 0: field.text = s.anthropicKey; field.secureTextEntry = YES; break;
        case 1: field.text = s.model; break;
        case 10: field.text = s.githubToken; field.secureTextEntry = YES; break;
        case 11: field.text = s.buildsRepo; break;
    }
    [cell.contentView addSubview:label];
    [cell.contentView addSubview:field];
    [NSLayoutConstraint activateConstraints:@[
        [label.leadingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.leadingAnchor],
        [label.centerYAnchor constraintEqualToAnchor:cell.contentView.centerYAnchor],
        [label.widthAnchor constraintEqualToConstant:92],
        [field.leadingAnchor constraintEqualToAnchor:label.trailingAnchor constant:8],
        [field.trailingAnchor constraintEqualToAnchor:cell.contentView.layoutMarginsGuide.trailingAnchor],
        [field.topAnchor constraintEqualToAnchor:cell.contentView.topAnchor],
        [field.bottomAnchor constraintEqualToAnchor:cell.contentView.bottomAnchor],
        [cell.contentView.heightAnchor constraintGreaterThanOrEqualToConstant:46],
    ]];
    return cell;
}

- (void)textFieldDidEndEditing:(UITextField *)field {
    RAEStore *s = RAEStore.shared;
    switch (field.tag) {
        case 0: s.anthropicKey = field.text ?: @""; break;
        case 1: s.model = field.text ?: @""; break;
        case 10: s.githubToken = field.text ?: @""; break;
        case 11: s.buildsRepo = field.text ?: @""; break;
    }
    [NSUserDefaults.standardUserDefaults synchronize];
}

- (BOOL)textFieldShouldReturn:(UITextField *)field { [field resignFirstResponder]; return YES; }

@end
