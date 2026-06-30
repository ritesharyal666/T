//
//  AppDelegate.m
//  TheosAuthDemo
//
//  Owns the window and decides the initial screen based on whether a valid
//  session token is stored. Also provides root-swap helpers used by the
//  login/logout flows so screens never have to manage each other's lifecycle.
//

#import "AppDelegate.h"
#import "AuthManager.h"
#import "LoginViewController.h"
#import "HomeViewController.h"

@implementation AppDelegate

+ (instancetype)current {
    return (AppDelegate *)UIApplication.sharedApplication.delegate;
}

- (BOOL)application:(UIApplication *)application
    didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {

    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];

    // Start on Home if we already hold a token, otherwise Login.
    if (AuthManager.shared.isLoggedIn) {
        [self setRoot:[HomeViewController new]];
    } else {
        [self setRoot:[LoginViewController new]];
    }
    [self.window makeKeyAndVisible];

    // Validate any stored token in the background; bounce to Login if stale.
    if (AuthManager.shared.isLoggedIn) {
        [AuthManager.shared verifyWithCompletion:^(BOOL valid, NSString *username, NSString *error) {
            if (!valid) {
                [AuthManager.shared clearSession];
                [self switchToLogin];
            }
        }];
    }

    return YES;
}

#pragma mark - Root swapping

- (void)setRoot:(UIViewController *)vc {
    UINavigationController *nav =
        [[UINavigationController alloc] initWithRootViewController:vc];
    self.window.rootViewController = nav;
}

- (void)switchToHome {
    [self transitionToRoot:[HomeViewController new]];
}

- (void)switchToLogin {
    [self transitionToRoot:[LoginViewController new]];
}

- (void)transitionToRoot:(UIViewController *)vc {
    UINavigationController *nav =
        [[UINavigationController alloc] initWithRootViewController:vc];

    [UIView transitionWithView:self.window
                      duration:0.3
                       options:UIViewAnimationOptionTransitionCrossDissolve
                    animations:^{
                        self.window.rootViewController = nav;
                    }
                    completion:nil];
}

@end
