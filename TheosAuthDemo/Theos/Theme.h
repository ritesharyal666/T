//
//  Theme.h
//  TheosAuthDemo
//
//  Small reusable UIKit factory helpers so the view controllers stay free of
//  duplicated styling/boilerplate.
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

/// A rounded text field with sensible auth defaults (no autocorrect/caps).
UITextField *TADMakeTextField(NSString *placeholder, BOOL secure);

/// A filled primary button (call-to-action) or a plain secondary button.
UIButton *TADMakeButton(NSString *title, BOOL primary);

/// Present a simple single-button alert.
void TADShowAlert(UIViewController *vc, NSString *title, NSString *message);

NS_ASSUME_NONNULL_END
