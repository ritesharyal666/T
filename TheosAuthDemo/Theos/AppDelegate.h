//
//  AppDelegate.h
//  TheosAuthDemo
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@interface AppDelegate : UIResponder <UIApplicationDelegate>

@property (nonatomic, strong, nullable) UIWindow *window;

/// Convenience accessor for the live delegate.
+ (instancetype)current;

/// Swap the root view controller (used after login / logout).
- (void)switchToHome;
- (void)switchToLogin;

@end

NS_ASSUME_NONNULL_END
