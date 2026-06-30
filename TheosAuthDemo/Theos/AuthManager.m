//
//  AuthManager.m
//  TheosAuthDemo
//

#import "AuthManager.h"
#import "NetworkManager.h"
#import <Security/Security.h>

static NSString *const kKeychainService = @"com.tweak.theosauthdemo";
static NSString *const kKeychainAccount = @"jwt";
static NSString *const kKeychainDeviceAccount = @"device_id";
static NSString *const kUsernameDefault = @"com.tweak.theosauthdemo.username";

@implementation AuthManager

+ (AuthManager *)shared {
    static AuthManager *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[AuthManager alloc] init]; });
    return instance;
}

#pragma mark - State

- (BOOL)isLoggedIn {
    return self.currentToken.length > 0;
}

- (NSString *)currentToken {
    return [self keychainReadToken];
}

- (NSString *)currentUsername {
    return [[NSUserDefaults standardUserDefaults] stringForKey:kUsernameDefault];
}

- (NSString *)deviceID {
    NSString *existing = [self keychainReadStringForAccount:kKeychainDeviceAccount];
    if (existing.length > 0) {
        return existing;
    }
    NSString *fresh = [[NSUUID UUID] UUIDString];
    [self keychainWriteString:fresh forAccount:kKeychainDeviceAccount];
    return fresh;
}

#pragma mark - Register

- (void)registerWithUsername:(NSString *)username
                    password:(NSString *)password
                  completion:(TADAuthCompletion)completion {

    NSDictionary *payload = @{ @"username": username, @"password": password };

    [[NetworkManager sharedManager] postEndpoint:@"register.php"
                                         payload:payload
                                           token:nil
                                      completion:^(NSDictionary *json, NSError *error) {
        [self handleSimpleResult:json error:error completion:completion];
    }];
}

#pragma mark - Login

- (void)loginWithUsername:(NSString *)username
                 password:(NSString *)password
               completion:(TADAuthCompletion)completion {

    NSDictionary *payload = @{ @"username": username,
                               @"password": password,
                               @"device_id": self.deviceID };

    [[NetworkManager sharedManager] postEndpoint:@"login.php"
                                         payload:payload
                                           token:nil
                                      completion:^(NSDictionary *json, NSError *error) {
        if (error) {
            completion(NO, error.localizedDescription);
            return;
        }
        if ([json[@"success"] boolValue]) {
            NSString *token = json[@"token"];
            NSString *name  = json[@"username"] ?: username;
            if (token.length == 0) {
                completion(NO, @"Server did not return a token.");
                return;
            }
            [self persistToken:token username:name];
            completion(YES, nil);
        } else {
            completion(NO, [self errorMessageFromJSON:json]);
        }
    }];
}

#pragma mark - Verify

- (void)verifyWithCompletion:(TADVerifyCompletion)completion {
    NSString *token = self.currentToken;
    if (token.length == 0) {
        completion(NO, nil, @"Not logged in.");
        return;
    }

    [[NetworkManager sharedManager] getEndpoint:@"verify.php"
                                          token:token
                                     completion:^(NSDictionary *json, NSError *error) {
        if (error) {
            completion(NO, nil, error.localizedDescription);
            return;
        }
        if ([json[@"success"] boolValue]) {
            NSString *name = json[@"user"][@"username"];
            if (name.length > 0) {
                [[NSUserDefaults standardUserDefaults] setObject:name
                                                          forKey:kUsernameDefault];
            }
            completion(YES, name, nil);
        } else {
            completion(NO, nil, [self errorMessageFromJSON:json]);
        }
    }];
}

#pragma mark - Logout

- (void)logoutWithCompletion:(TADAuthCompletion)completion {
    NSString *token = self.currentToken;
    if (token.length == 0) {
        [self clearSession];
        completion(YES, nil);
        return;
    }

    [[NetworkManager sharedManager] postEndpoint:@"logout.php"
                                         payload:@{}
                                           token:token
                                      completion:^(NSDictionary *json, NSError *error) {
        // Clear locally regardless of the server outcome — the user wants out.
        [self clearSession];
        completion(YES, nil);
    }];
}

- (void)clearSession {
    [self keychainDeleteToken];
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kUsernameDefault];
}

#pragma mark - Result helpers

- (void)handleSimpleResult:(NSDictionary *)json
                     error:(NSError *)error
                completion:(TADAuthCompletion)completion {
    if (error) {
        completion(NO, error.localizedDescription);
    } else if ([json[@"success"] boolValue]) {
        completion(YES, nil);
    } else {
        completion(NO, [self errorMessageFromJSON:json]);
    }
}

- (NSString *)errorMessageFromJSON:(NSDictionary *)json {
    NSString *msg = json[@"error"];
    return msg.length > 0 ? msg : @"Request failed. Please try again.";
}

- (void)persistToken:(NSString *)token username:(NSString *)username {
    [self keychainWriteToken:token];
    [[NSUserDefaults standardUserDefaults] setObject:username forKey:kUsernameDefault];
}

#pragma mark - Keychain (secure storage)

- (NSMutableDictionary *)keychainBaseQueryForAccount:(NSString *)account {
    NSMutableDictionary *q = [NSMutableDictionary dictionary];
    q[(__bridge id)kSecClass]       = (__bridge id)kSecClassGenericPassword;
    q[(__bridge id)kSecAttrService] = kKeychainService;
    q[(__bridge id)kSecAttrAccount] = account;
    return q;
}

- (void)keychainWriteString:(NSString *)value forAccount:(NSString *)account {
    [self keychainDeleteAccount:account]; // overwrite semantics

    NSMutableDictionary *q = [self keychainBaseQueryForAccount:account];
    q[(__bridge id)kSecValueData] = [value dataUsingEncoding:NSUTF8StringEncoding];
    q[(__bridge id)kSecAttrAccessible] =
        (__bridge id)kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly;

    SecItemAdd((__bridge CFDictionaryRef)q, NULL);
}

- (NSString *)keychainReadStringForAccount:(NSString *)account {
    NSMutableDictionary *q = [self keychainBaseQueryForAccount:account];
    q[(__bridge id)kSecReturnData]  = (__bridge id)kCFBooleanTrue;
    q[(__bridge id)kSecMatchLimit]  = (__bridge id)kSecMatchLimitOne;

    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)q, &result);
    if (status != errSecSuccess || result == NULL) {
        return nil;
    }

    NSData *data = (__bridge_transfer NSData *)result;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (void)keychainDeleteAccount:(NSString *)account {
    SecItemDelete((__bridge CFDictionaryRef)[self keychainBaseQueryForAccount:account]);
}

// Token-specific wrappers (the device id uses the same helpers, see -deviceID).
- (void)keychainWriteToken:(NSString *)token {
    [self keychainWriteString:token forAccount:kKeychainAccount];
}

- (NSString *)keychainReadToken {
    return [self keychainReadStringForAccount:kKeychainAccount];
}

- (void)keychainDeleteToken {
    [self keychainDeleteAccount:kKeychainAccount];
}

@end
