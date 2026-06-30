//
//  CryptoManager.h
//  TheosAuthDemo
//
//  Symmetric payload encryption using only CommonCrypto (no third-party libs).
//
//  Scheme: AES-256-CBC with Encrypt-then-MAC (HMAC-SHA256).
//
//  AES-256-GCM is the preferred AEAD mode, but Apple's *public* CommonCrypto
//  API does not expose a stable one-shot GCM interface to Objective-C (the GCM
//  helpers are private SPI). To stay buildable with public APIs only while
//  still authenticating every message, we use AES-256-CBC + HMAC-SHA256, which
//  provides equivalent confidentiality + integrity. The PHP backend
//  (crypto.php) implements the identical scheme.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CryptoManager : NSObject

+ (instancetype)sharedManager;

/// Encrypt arbitrary data into a transport envelope:
/// @{ @"v": @1, @"iv": b64, @"ct": b64, @"mac": b64 }. Returns nil on failure.
- (nullable NSDictionary<NSString *, id> *)encryptData:(NSData *)plaintext;

/// Verify + decrypt an envelope produced by encryptData: (or the backend).
/// Returns nil if the MAC check or decryption fails.
- (nullable NSData *)decryptData:(NSDictionary<NSString *, id> *)envelope;

// --- Primitives (exposed for completeness / testing) ----------------------

/// 16 secure-random bytes (AES-CBC block-size IV).
- (NSData *)generateRandomIV;

/// 12 secure-random bytes (AEAD-style nonce; provided per spec).
- (NSData *)generateNonce;

- (NSString *)base64Encode:(NSData *)data;
- (nullable NSData *)base64Decode:(NSString *)string;

@end

NS_ASSUME_NONNULL_END
