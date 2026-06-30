//
//  CryptoManager.m
//  TheosAuthDemo
//

#import "CryptoManager.h"
#import <CommonCrypto/CommonCrypto.h>
#import <Security/Security.h>

// Shared master key (64 hex chars = 32 bytes). MUST match CRYPTO_MASTER_KEY_HEX
// in the PHP backend (config.php). Generated with `openssl rand -hex 32`.
static NSString *const kTADMasterKeyHex =
    @"9af29479de0b00650c20b6009a889a5bf90774ad6b15f6f0cd0132aa5287b108";

@implementation CryptoManager {
    NSData *_encKey; // 32 bytes, AES-256
    NSData *_macKey; // 32 bytes, HMAC-SHA256
}

+ (instancetype)sharedManager {
    static CryptoManager *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[CryptoManager alloc] init]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSData *master = [self dataFromHex:kTADMasterKeyHex];
        // Derive independent keys: SHA256(master || "enc") / SHA256(master || "mac").
        // The PHP side derives these the exact same way.
        _encKey = [self sha256OfData:master suffix:@"enc"];
        _macKey = [self sha256OfData:master suffix:@"mac"];
    }
    return self;
}

#pragma mark - Public API

- (NSDictionary<NSString *, id> *)encryptData:(NSData *)plaintext {
    if (plaintext == nil) { return nil; }

    NSData *iv = [self generateRandomIV];
    NSData *ct = [self aesCBCOperation:kCCEncrypt data:plaintext iv:iv];
    if (ct == nil) { return nil; }

    NSData *mac = [self hmacForIV:iv ciphertext:ct];

    return @{
        @"v":   @1,
        @"iv":  [self base64Encode:iv],
        @"ct":  [self base64Encode:ct],
        @"mac": [self base64Encode:mac],
    };
}

- (NSData *)decryptData:(NSDictionary<NSString *, id> *)envelope {
    NSData *iv  = [self base64Decode:envelope[@"iv"]];
    NSData *ct  = [self base64Decode:envelope[@"ct"]];
    NSData *mac = [self base64Decode:envelope[@"mac"]];

    if (iv.length != kCCBlockSizeAES128 || ct == nil ||
        mac.length != CC_SHA256_DIGEST_LENGTH) {
        return nil;
    }

    // Authenticate BEFORE decrypting (Encrypt-then-MAC), constant-time.
    NSData *expected = [self hmacForIV:iv ciphertext:ct];
    if (![self constantTimeEqual:expected other:mac]) {
        return nil;
    }

    return [self aesCBCOperation:kCCDecrypt data:ct iv:iv];
}

#pragma mark - Primitives

- (NSData *)generateRandomIV { return [self randomBytes:kCCBlockSizeAES128]; } // 16
- (NSData *)generateNonce    { return [self randomBytes:12]; }

- (NSString *)base64Encode:(NSData *)data {
    return [data base64EncodedStringWithOptions:0];
}

- (NSData *)base64Decode:(NSString *)string {
    if (![string isKindOfClass:[NSString class]]) { return nil; }
    return [[NSData alloc] initWithBase64EncodedString:string options:0];
}

#pragma mark - Crypto helpers

/// AES-256-CBC encrypt/decrypt with PKCS7 padding.
- (NSData *)aesCBCOperation:(CCOperation)op data:(NSData *)data iv:(NSData *)iv {
    size_t bufferSize = data.length + kCCBlockSizeAES128;
    NSMutableData *output = [NSMutableData dataWithLength:bufferSize];
    size_t bytesMoved = 0;

    CCCryptorStatus status = CCCrypt(
        op,
        kCCAlgorithmAES,
        kCCOptionPKCS7Padding,
        _encKey.bytes, _encKey.length,   // 32 bytes -> AES-256
        iv.bytes,
        data.bytes, data.length,
        output.mutableBytes, bufferSize,
        &bytesMoved);

    if (status != kCCSuccess) { return nil; }
    output.length = bytesMoved;
    return output;
}

/// HMAC-SHA256 over (iv || ciphertext).
- (NSData *)hmacForIV:(NSData *)iv ciphertext:(NSData *)ct {
    NSMutableData *message = [NSMutableData dataWithData:iv];
    [message appendData:ct];

    NSMutableData *mac = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    CCHmac(kCCHmacAlgSHA256,
           _macKey.bytes, _macKey.length,
           message.bytes, message.length,
           mac.mutableBytes);
    return mac;
}

#pragma mark - Low-level utilities

- (NSData *)randomBytes:(size_t)count {
    NSMutableData *data = [NSMutableData dataWithLength:count];
    int rc = SecRandomCopyBytes(kSecRandomDefault, count, data.mutableBytes);
    NSAssert(rc == errSecSuccess, @"SecRandomCopyBytes failed");
    return data;
}

- (NSData *)dataFromHex:(NSString *)hex {
    NSMutableData *data = [NSMutableData dataWithCapacity:hex.length / 2];
    for (NSUInteger i = 0; i + 1 < hex.length; i += 2) {
        unsigned int byte = 0;
        NSString *pair = [hex substringWithRange:NSMakeRange(i, 2)];
        [[NSScanner scannerWithString:pair] scanHexInt:&byte];
        uint8_t b = (uint8_t)byte;
        [data appendBytes:&b length:1];
    }
    return data;
}

- (NSData *)sha256OfData:(NSData *)data suffix:(NSString *)suffix {
    NSMutableData *message = [NSMutableData dataWithData:data];
    [message appendData:[suffix dataUsingEncoding:NSUTF8StringEncoding]];

    NSMutableData *digest = [NSMutableData dataWithLength:CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(message.bytes, (CC_LONG)message.length, digest.mutableBytes);
    return digest;
}

/// Length-checked, constant-time byte comparison.
- (BOOL)constantTimeEqual:(NSData *)a other:(NSData *)b {
    if (a.length != b.length) { return NO; }
    const uint8_t *pa = a.bytes;
    const uint8_t *pb = b.bytes;
    uint8_t diff = 0;
    for (NSUInteger i = 0; i < a.length; i++) {
        diff |= (uint8_t)(pa[i] ^ pb[i]);
    }
    return diff == 0;
}

@end
