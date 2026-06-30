//
//  NetworkManager.h
//  TheosAuthDemo
//
//  Reusable NSURLSession networking layer.
//
//  Pipeline for every call:
//      JSON -> encrypt -> HTTPS POST/GET -> receive -> decrypt -> JSON
//
//  All requests/responses are AES-encrypted envelopes (see CryptoManager).
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Completion delivers the decrypted JSON dictionary, or an NSError.
/// Always invoked on the main thread.
typedef void (^TADNetworkCompletion)(NSDictionary *_Nullable json,
                                      NSError *_Nullable error);

extern NSString *const TADNetworkErrorDomain;

@interface NetworkManager : NSObject

+ (instancetype)sharedManager;

/// Encrypted POST. `payload` is plaintext JSON; it is encrypted before send.
- (void)postEndpoint:(NSString *)endpoint
             payload:(NSDictionary *)payload
               token:(nullable NSString *)token
          completion:(TADNetworkCompletion)completion;

/// Encrypted GET (no body). Response is still a decrypted JSON dictionary.
- (void)getEndpoint:(NSString *)endpoint
              token:(nullable NSString *)token
         completion:(TADNetworkCompletion)completion;

@end

NS_ASSUME_NONNULL_END
