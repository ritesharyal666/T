//
//  HomeViewController.m
//  TheosAuthDemo
//
//  Authenticated screen: "Welcome, <username>" + Logout button.
//

#import "HomeViewController.h"
#import "AppDelegate.h"
#import "AuthManager.h"
#import "Theme.h"

@interface HomeViewController ()
@property (nonatomic, strong) UILabel *welcomeLabel;
@property (nonatomic, strong) UIButton *logoutButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation HomeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Home";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.hidesBackButton = YES;
    [self buildUI];
    [self refreshWelcome];
}

- (void)buildUI {
    self.welcomeLabel = [UILabel new];
    self.welcomeLabel.font = [UIFont systemFontOfSize:24.0 weight:UIFontWeightSemibold];
    self.welcomeLabel.textAlignment = NSTextAlignmentCenter;
    self.welcomeLabel.numberOfLines = 0;
    self.welcomeLabel.translatesAutoresizingMaskIntoConstraints = NO;

    self.logoutButton = TADMakeButton(@"Logout", YES);
    self.logoutButton.backgroundColor = UIColor.systemRedColor;
    [self.logoutButton addTarget:self
                          action:@selector(didTapLogout)
                forControlEvents:UIControlEventTouchUpInside];

    self.spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.welcomeLabel, self.logoutButton
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 32.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:stack];
    [self.view addSubview:self.spinner];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.centerYAnchor constraintEqualToAnchor:g.centerYAnchor],
        [stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:24.0],
        [stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-24.0],

        [self.spinner.centerXAnchor constraintEqualToAnchor:stack.centerXAnchor],
        [self.spinner.topAnchor constraintEqualToAnchor:stack.bottomAnchor constant:24.0],
    ]];
}

- (void)refreshWelcome {
    NSString *name = AuthManager.shared.currentUsername ?: @"there";
    self.welcomeLabel.text = [NSString stringWithFormat:@"Welcome, %@ 👋", name];
}

#pragma mark - Actions

- (void)didTapLogout {
    [self setLoading:YES];
    [AuthManager.shared logoutWithCompletion:^(BOOL success, NSString *error) {
        [self setLoading:NO];
        [[AppDelegate current] switchToLogin];
    }];
}

- (void)setLoading:(BOOL)loading {
    if (loading) { [self.spinner startAnimating]; }
    else         { [self.spinner stopAnimating]; }
    self.logoutButton.enabled = !loading;
    self.logoutButton.alpha   = loading ? 0.5 : 1.0;
}

@end
