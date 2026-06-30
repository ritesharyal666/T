//
//  AuthManager.h
//  TheosAuthDemo
//
//  High-level authentication facade. Wraps NetworkManager calls to the
//  backend and persists the JWT securely in the Keychain.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// success + (on failure) a human-readable error string. Main-thread callback.
typedef void (^TADAuthCompletion)(BOOL success, NSString *_Nullable error);

/// valid + username (when valid) + error. Main-thread callback.
typedef void (^TADVerifyCompletion)(BOOL valid,
                                     NSString *_Nullable username,
                                     NSString *_Nullable error);

@interface AuthManager : NSObject

@property (class, nonatomic, readonly) AuthManager *shared;

/// YES if a token is currently stored (not necessarily still valid server-side).
@property (nonatomic, readonly) BOOL isLoggedIn;

/// The currently stored JWT, or nil.
@property (nonatomic, readonly, nullable) NSString *currentToken;

/// The last known username (for display on the Home screen).
@property (nonatomic, readonly, nullable) NSString *currentUsername;

/// A stable per-device identifier (UUID), generated once and kept in the
/// Keychain. Sent with login so the backend can enforce one login per device.
@property (nonatomic, readonly) NSString *deviceID;

- (void)registerWithUsername:(NSString *)username
                    password:(NSString *)password
                  completion:(TADAuthCompletion)completion;

- (void)loginWithUsername:(NSString *)username
                 password:(NSString *)password
               completion:(TADAuthCompletion)completion;

/// Validate the stored token against the backend (GET /verify.php).
- (void)verifyWithCompletion:(TADVerifyCompletion)completion;

/// Calls the backend to revoke the token, then clears local session.
- (void)logoutWithCompletion:(TADAuthCompletion)completion;

/// Clear local credentials without a network round-trip.
- (void)clearSession;

@end

NS_ASSUME_NONNULL_END
