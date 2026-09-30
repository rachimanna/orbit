#import "ZSignBridge.h"

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

@end
