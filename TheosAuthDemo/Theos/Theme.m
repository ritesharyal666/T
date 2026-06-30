//
//  Theme.m
//  TheosAuthDemo
//

#import "Theme.h"

UITextField *TADMakeTextField(NSString *placeholder, BOOL secure) {
    UITextField *tf = [UITextField new];
    tf.placeholder = placeholder;
    tf.secureTextEntry = secure;
    tf.borderStyle = UITextBorderStyleRoundedRect;
    tf.autocapitalizationType = UITextAutocapitalizationTypeNone;
    tf.autocorrectionType = UITextAutocorrectionTypeNo;
    tf.clearButtonMode = UITextFieldViewModeWhileEditing;
    tf.font = [UIFont systemFontOfSize:16.0];
    tf.translatesAutoresizingMaskIntoConstraints = NO;
    [tf.heightAnchor constraintEqualToConstant:48.0].active = YES;
    return tf;
}

UIButton *TADMakeButton(NSString *title, BOOL primary) {
    UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
    [btn setTitle:title forState:UIControlStateNormal];
    btn.titleLabel.font = [UIFont systemFontOfSize:17.0
                                            weight:primary ? UIFontWeightSemibold
                                                           : UIFontWeightRegular];
    btn.translatesAutoresizingMaskIntoConstraints = NO;
    [btn.heightAnchor constraintEqualToConstant:50.0].active = YES;

    if (primary) {
        btn.backgroundColor = UIColor.systemBlueColor;
        [btn setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
        btn.layer.cornerRadius = 10.0;
        btn.layer.masksToBounds = YES;
    } else {
        [btn setTitleColor:UIColor.systemBlueColor forState:UIControlStateNormal];
    }
    return btn;
}

void TADShowAlert(UIViewController *vc, NSString *title, NSString *message) {
    UIAlertController *alert =
        [UIAlertController alertControllerWithTitle:title
                                            message:message
                                     preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                              style:UIAlertActionStyleDefault
                                            handler:nil]];
    [vc presentViewController:alert animated:YES completion:nil];
}
