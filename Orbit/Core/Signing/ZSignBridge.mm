#import "ZSignBridge.h"
#include "P12Normalizer.h"

#if __has_include("bundle.h") && __has_include(<openssl/pem.h>)
#define ORBIT_HAS_ZSIGN 1
#include "common.h"
#include "bundle.h"
#include "openssl.h"
#include "log.h"
#else
#define ORBIT_HAS_ZSIGN 0
#endif

static NSString *const ZSignErrorDomain = @"ZSignBridge";

@implementation ZSignBridge

+ (BOOL)isAvailable { return ORBIT_HAS_ZSIGN; }

+ (BOOL)signAppAtPath:(NSString *)appPath
              p12Path:(NSString *)p12Path
             password:(NSString *)password
          profilePath:(NSString *)profilePath
             bundleID:(NSString *)bundleID
          displayName:(NSString *)displayName
                error:(NSError **)error
{
#if ORBIT_HAS_ZSIGN
    // zsign keeps global state — never run two signings at once.
    static NSLock *lock = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = [NSLock new]; });
    [lock lock];

    ZLog::SetLogLever(ZLog::E_ERROR);

    ZSignAsset asset;
    // A .p12 is accepted as the "private key" file; the certificate is read from it.
    bool ok = asset.Init("", p12Path.UTF8String, profilePath.UTF8String, "",
                         password.UTF8String, false, false, false);
    if (!ok) {
        [lock unlock];
        if (error) *error = [NSError errorWithDomain:ZSignErrorDomain code:1
                                            userInfo:@{NSLocalizedDescriptionKey: @"Certificate or profile could not be loaded"}];
        return NO;
    }

    ZBundle bundle;
    std::vector<std::string> noDylibs;
    std::vector<std::string> noRemovals;
    ok = bundle.SignFolder(&asset,
                           appPath.UTF8String,
                           bundleID ? bundleID.UTF8String : "",
                           "",                                   // keep version
                           displayName ? displayName.UTF8String : "",
                           noDylibs, noRemovals,
                           true,    // force re-sign everything
                           false,   // weak inject
                           false);  // no cache: we always sign a fresh copy
    [lock unlock];

    if (!ok && error) {
        *error = [NSError errorWithDomain:ZSignErrorDomain code:2
                                 userInfo:@{NSLocalizedDescriptionKey: @"Signing the bundle failed"}];
    }
    return ok;
#else
    if (error) *error = [NSError errorWithDomain:ZSignErrorDomain code:-1
                                        userInfo:@{NSLocalizedDescriptionKey: @"zsign is not compiled into this build"}];
    return NO;
#endif
}

+ (NSData *)normalizedP12:(NSData *)data password:(NSString *)password error:(NSError **)error
{
    uint8_t *out = NULL;
    size_t length = 0;
    OrbitP12Status status = orbit_p12_normalize((const uint8_t *)data.bytes, data.length,
                                                password.UTF8String, &out, &length);
    if (status == ORBIT_P12_OK) {
        return [NSData dataWithBytesNoCopy:out length:length freeWhenDone:YES];
    }
    if (error) {
        NSString *message = status == ORBIT_P12_WRONG_PASSWORD ? @"Wrong .p12 password"
                          : status == ORBIT_P12_UNAVAILABLE ? @"OpenSSL is not compiled into this build"
                          : @"Not a readable PKCS#12 file";
        *error = [NSError errorWithDomain:ZSignErrorDomain code:status
                                 userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    return nil;
}

@end
