//
//  NetworkManager.m
//  TheosAuthDemo
//

#import "NetworkManager.h"
#import "CryptoManager.h"

// Base URL of the backend. MUST be HTTPS (App Transport Security enforces it
// and refuses cleartext). Keep the trailing slash.
//
// Set this to your backend before building (see README "2. Configure the app"):
//   - a deployed PHP server, e.g.  @"https://api.yourdomain.com/"
//   - or the public URL printed by Backend/tools/serve_public.sh
//     (a Cloudflare quick-tunnel URL is random and changes on every restart —
//      update this line and rebuild when it does).
static NSString *const kTADBaseURL = @"https://YOUR-BACKEND-URL/";

static NSTimeInterval const kTADTimeout = 30.0;

NSString *const TADNetworkErrorDomain = @"TADNetworkErrorDomain";

typedef NS_ENUM(NSInteger, TADNetworkErrorCode) {
    TADNetworkErrorBadURL        = 1,
    TADNetworkErrorEncryption    = 2,
    TADNetworkErrorTransport     = 3,
    TADNetworkErrorEmptyResponse = 4,
    TADNetworkErrorDecryption    = 5,
    TADNetworkErrorBadJSON       = 6,
};

@implementation NetworkManager {
    NSURLSession *_session;
}

+ (instancetype)sharedManager {
    static NetworkManager *instance;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ instance = [[NetworkManager alloc] init]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        NSURLSessionConfiguration *cfg =
            [NSURLSessionConfiguration defaultSessionConfiguration];
        cfg.timeoutIntervalForRequest  = kTADTimeout;
        cfg.timeoutIntervalForResource = kTADTimeout;
        cfg.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
        // Default session => standard, non-disabled TLS validation.
        _session = [NSURLSession sessionWithConfiguration:cfg];
    }
    return self;
}

#pragma mark - Public API

- (void)postEndpoint:(NSString *)endpoint
             payload:(NSDictionary *)payload
               token:(NSString *)token
          completion:(TADNetworkCompletion)completion {
    [self performRequest:@"POST"
                endpoint:endpoint
                 payload:payload
                   token:token
              completion:completion];
}

- (void)getEndpoint:(NSString *)endpoint
              token:(NSString *)token
         completion:(TADNetworkCompletion)completion {
    [self performRequest:@"GET"
                endpoint:endpoint
                 payload:nil
                   token:token
              completion:completion];
}

#pragma mark - Core

- (void)performRequest:(NSString *)method
              endpoint:(NSString *)endpoint
               payload:(NSDictionary *)payload
                 token:(NSString *)token
            completion:(TADNetworkCompletion)completion {

    NSURL *url = [NSURL URLWithString:endpoint
                       relativeToURL:[NSURL URLWithString:kTADBaseURL]];
    if (url == nil) {
        [self finish:completion json:nil
               error:[self errorWithCode:TADNetworkErrorBadURL
                                 message:@"Invalid endpoint URL."]];
        return;
    }

    NSMutableURLRequest *request =
        [NSMutableURLRequest requestWithURL:url
                                cachePolicy:NSURLRequestReloadIgnoringLocalCacheData
                            timeoutInterval:kTADTimeout];
    request.HTTPMethod = method;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    // Bearer token (Authorization header) when authenticated.
    if (token.length > 0) {
        NSString *bearer = [@"Bearer " stringByAppendingString:token];
        [request setValue:bearer forHTTPHeaderField:@"Authorization"];
    }

    // Encrypt the JSON body for POST requests.
    if ([method isEqualToString:@"POST"]) {
        NSError *encError = nil;
        NSData *body = [self encryptPayload:payload error:&encError];
        if (body == nil) {
            [self finish:completion json:nil error:encError];
            return;
        }
        request.HTTPBody = body;
    }

    __weak typeof(self) weakSelf = self;
    NSURLSessionDataTask *task =
        [_session dataTaskWithRequest:request
                    completionHandler:^(NSData *data,
                                        NSURLResponse *response,
                                        NSError *error) {
        [weakSelf handleResponseData:data
                            response:response
                               error:error
                          completion:completion];
    }];
    [task resume];
}

/// JSON-serialize -> encrypt -> JSON-serialize the envelope into a body.
- (NSData *)encryptPayload:(NSDictionary *)payload error:(NSError **)error {
    NSError *jsonError = nil;
    NSData *plaintext = [NSJSONSerialization dataWithJSONObject:(payload ?: @{})
                                                       options:0
                                                         error:&jsonError];
    if (plaintext == nil) {
        if (error) {
            *error = [self errorWithCode:TADNetworkErrorEncryption
                                 message:@"Failed to serialize request."];
        }
        return nil;
    }

    NSDictionary *envelope = [[CryptoManager sharedManager] encryptData:plaintext];
    if (envelope == nil) {
        if (error) {
            *error = [self errorWithCode:TADNetworkErrorEncryption
                                 message:@"Failed to encrypt request."];
        }
        return nil;
    }

    return [NSJSONSerialization dataWithJSONObject:envelope options:0 error:NULL];
}

- (void)handleResponseData:(NSData *)data
                  response:(NSURLResponse *)response
                     error:(NSError *)error
                completion:(TADNetworkCompletion)completion {

    // 1) Transport-level failure (timeout, no connection, TLS, ...).
    if (error != nil) {
        [self finish:completion json:nil error:error];
        return;
    }

    if (data.length == 0) {
        [self finish:completion json:nil
               error:[self errorWithCode:TADNetworkErrorEmptyResponse
                                 message:@"Empty server response."]];
        return;
    }

    // 2) Parse the outer encrypted envelope.
    NSDictionary *envelope = [NSJSONSerialization JSONObjectWithData:data
                                                            options:0
                                                              error:NULL];
    if (![envelope isKindOfClass:[NSDictionary class]]) {
        [self finish:completion json:nil
               error:[self errorWithCode:TADNetworkErrorBadJSON
                                 message:@"Malformed server response."]];
        return;
    }

    // 3) Decrypt -> plaintext JSON. The server encrypts BOTH success and error
    //    bodies, so we decrypt regardless of the HTTP status code and let the
    //    caller inspect the "success" flag.
    NSData *plaintext = [[CryptoManager sharedManager] decryptData:envelope];
    if (plaintext == nil) {
        [self finish:completion json:nil
               error:[self errorWithCode:TADNetworkErrorDecryption
                                 message:@"Failed to decrypt server response."]];
        return;
    }

    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:plaintext
                                                        options:0
                                                          error:NULL];
    if (![json isKindOfClass:[NSDictionary class]]) {
        [self finish:completion json:nil
               error:[self errorWithCode:TADNetworkErrorBadJSON
                                 message:@"Invalid decrypted JSON."]];
        return;
    }

    [self finish:completion json:json error:nil];
}

#pragma mark - Helpers

- (NSError *)errorWithCode:(TADNetworkErrorCode)code message:(NSString *)message {
    return [NSError errorWithDomain:TADNetworkErrorDomain
                               code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

/// Always hop back to the main thread for UI-friendly callbacks.
- (void)finish:(TADNetworkCompletion)completion
          json:(NSDictionary *)json
         error:(NSError *)error {
    if (completion == nil) { return; }
    dispatch_async(dispatch_get_main_queue(), ^{ completion(json, error); });
}

@end
