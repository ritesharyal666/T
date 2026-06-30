//
//  RegisterViewController.m
//  TheosAuthDemo
//
//  Username + password + confirm password, Register button.
//  Validates input client-side (the server validates again), creates the
//  account, then logs the user straight in.
//

#import "RegisterViewController.h"
#import "AppDelegate.h"
#import "AuthManager.h"
#import "Theme.h"

@interface RegisterViewController ()
@property (nonatomic, strong) UITextField *usernameField;
@property (nonatomic, strong) UITextField *passwordField;
@property (nonatomic, strong) UITextField *confirmField;
@property (nonatomic, strong) UIButton *registerButton;
@property (nonatomic, strong) UIActivityIndicatorView *spinner;
@end

@implementation RegisterViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.title = @"Create Account";
    self.view.backgroundColor = UIColor.systemBackgroundColor;
    [self buildUI];
}

- (void)buildUI {
    self.usernameField  = TADMakeTextField(@"Username (3-32 chars)", NO);
    self.passwordField  = TADMakeTextField(@"Password (min 8, letters + numbers)", YES);
    self.confirmField   = TADMakeTextField(@"Confirm password", YES);
    self.registerButton = TADMakeButton(@"Register", YES);

    [self.registerButton addTarget:self
                            action:@selector(didTapRegister)
                  forControlEvents:UIControlEventTouchUpInside];

    self.spinner = [[UIActivityIndicatorView alloc]
        initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.spinner.hidesWhenStopped = YES;
    self.spinner.translatesAutoresizingMaskIntoConstraints = NO;

    UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[
        self.usernameField, self.passwordField, self.confirmField, self.registerButton
    ]];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.spacing = 16.0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;

    [self.view addSubview:stack];
    [self.view addSubview:self.spinner];

    UILayoutGuide *g = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [stack.topAnchor constraintEqualToAnchor:g.topAnchor constant:40.0],
        [stack.leadingAnchor constraintEqualToAnchor:g.leadingAnchor constant:24.0],
        [stack.trailingAnchor constraintEqualToAnchor:g.trailingAnchor constant:-24.0],

        [self.spinner.centerXAnchor constraintEqualToAnchor:stack.centerXAnchor],
        [self.spinner.topAnchor constraintEqualToAnchor:stack.bottomAnchor constant:24.0],
    ]];
}

#pragma mark - Actions

- (void)didTapRegister {
    NSString *username = [self.usernameField.text
        stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
    NSString *password = self.passwordField.text ?: @"";
    NSString *confirm  = self.confirmField.text ?: @"";

    NSString *validationError = [self validateUsername:username password:password
                                               confirm:confirm];
    if (validationError) {
        TADShowAlert(self, @"Check your details", validationError);
        return;
    }

    [self setLoading:YES];

    // Register, then chain straight into login for a smooth first-run flow.
    [AuthManager.shared registerWithUsername:username
                                    password:password
                                  completion:^(BOOL success, NSString *error) {
        if (!success) {
            [self setLoading:NO];
            TADShowAlert(self, @"Registration failed",
                         error ?: @"Please try again.");
            return;
        }

        [AuthManager.shared loginWithUsername:username
                                    password:password
                                  completion:^(BOOL loginOK, NSString *loginError) {
            [self setLoading:NO];
            if (loginOK) {
                [[AppDelegate current] switchToHome];
            } else {
                // Account exists; just send them back to sign in manually.
                TADShowAlert(self, @"Account created",
                             @"Your account was created. Please sign in.");
                [self.navigationController popViewControllerAnimated:YES];
            }
        }];
    }];
}

#pragma mark - Validation (mirrors the server rules)

- (NSString *)validateUsername:(NSString *)username
                      password:(NSString *)password
                       confirm:(NSString *)confirm {

    NSPredicate *userRule = [NSPredicate predicateWithFormat:
        @"SELF MATCHES %@", @"^[A-Za-z0-9_]{3,32}$"];
    if (![userRule evaluateWithObject:username]) {
        return @"Username must be 3-32 characters: letters, numbers or underscore.";
    }

    BOOL hasLetter = [password rangeOfCharacterFromSet:
        NSCharacterSet.letterCharacterSet].location != NSNotFound;
    BOOL hasDigit = [password rangeOfCharacterFromSet:
        NSCharacterSet.decimalDigitCharacterSet].location != NSNotFound;

    if (password.length < 8 || !hasLetter || !hasDigit) {
        return @"Password must be at least 8 characters and include a letter and a number.";
    }

    if (![password isEqualToString:confirm]) {
        return @"Passwords do not match.";
    }

    return nil;
}

#pragma mark - Loading state

- (void)setLoading:(BOOL)loading {
    if (loading) { [self.spinner startAnimating]; }
    else         { [self.spinner stopAnimating]; }

    self.registerButton.enabled = !loading;
    self.usernameField.enabled  = !loading;
    self.passwordField.enabled  = !loading;
    self.confirmField.enabled   = !loading;
    self.registerButton.alpha   = loading ? 0.5 : 1.0;
}

@end
