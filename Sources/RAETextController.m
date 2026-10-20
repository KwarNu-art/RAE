#import "RAETextController.h"
#import "RAEUI.h"

@implementation RAETextController {
    NSString *_text;
    BOOL _mono;
    UITextView *_view;
}

- (instancetype)initWithTitle:(NSString *)title text:(NSString *)text monospaced:(BOOL)monospaced {
    if ((self = [super init])) {
        self.title = title;
        _text = [text copy];
        _mono = monospaced;
    }
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.largeTitleDisplayMode = UINavigationItemLargeTitleDisplayModeNever;
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAction target:self action:@selector(share)];
    _view = [[UITextView alloc] initWithFrame:self.view.bounds];
    _view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _view.editable = NO;
    _view.alwaysBounceVertical = YES;
    _view.textContainerInset = UIEdgeInsetsMake(14, 12, 24, 12);
    _view.font = _mono ? [UIFont monospacedSystemFontOfSize:12 weight:UIFontWeightRegular] : [UIFont systemFontOfSize:15];
    _view.textColor = UIColor.labelColor;
    _view.text = _text;
    [self.view addSubview:_view];
}

- (void)share {
    [self rae_shareItems:@[_text ?: @""] from:nil];
}

@end
