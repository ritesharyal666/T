//
//  LoginViewController.m
//  TheosAuthDemo
//
//  Username + password fields, Login button, Register button.
//

#import "LoginViewController.h"
#import "RegisterViewController.h"
#import "AppDelegate.h"
#import "AuthManager.h"
#import "Theme.h"

@interface LoginViewController ()
@property (nonatomic, strong) UITextField *usernameField;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UIButton *loginButton;
@property (nonatomic, strong) UIButton *registerButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation LoginViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Sign In";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    self.navigationItem.hidesBackButton = YES;
    [self buildUI];
}

- (void)buildUI {
    self.usernameField  = TADMakeTextField(@"Username", NO);
    self.passwordField  = TADMakeTextField(@"Password", YES);
    self.loginButton    = TADMakeButton(@"Login", YES);
    self.registerButton = TADMakeButton(@"Create an account", NO);

    [self.loginButton addTarget:self
                         action:@selector(didTapLogin)
               forControlEvents:UIControlEventTouchUpInside];
    [self.registerButton addTarget:self
                            action:@selector(didTapRegister)
                  forControlEvents:UIControlEventTouchUpInside];

    self.spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.usernameField, self.passwordField, self.loginButton, self.registerButton
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16.0;
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

#pragma mark - Actions

- (void)didTapLogin {
    NSString *username = [self.usernameField.text
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSString *password = self.passwordField.text ?: @"";

    if (username.length == 0 || password.length == 0) {
        TADShowAlert(self, @"Missing details",
                     @"Please enter both a username and password.");
        return;
    }

    [self setLoading:YES];
    [AuthManager.shared loginWithUsername:username
                                password:password
                              completion:^(BOOL success, NSString *error) {
        [self setLoading:NO];
        if (success) {
            [[AppDelegate current] switchToHome];
        } else {
            TADShowAlert(self, @"Login failed",
                         error ?: @"Please check your credentials.");
        }
    }];
}

- (void)didTapRegister {
    [self.navigationController pushViewController:[RegisterViewController new]
                                        animated:YES];
}

#pragma mark - Loading state

- (void)setLoading:(BOOL)loading {
    if (loading) { [self.spinner startAnimating]; }
    else         { [self.spinner stopAnimating]; }

    self.loginButton.enabled    = !loading;
    self.registerButton.enabled = !loading;
    self.usernameField.enabled  = !loading;
    self.passwordField.enabled  = !loading;
    self.loginButton.alpha      = loading ? 0.5 : 1.0;
}

@end
