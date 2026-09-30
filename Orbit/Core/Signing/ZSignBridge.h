#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin Objective-C++ wrapper around zsign (github.com/zhlynn/zsign, MIT).
@interface ZSignBridge : NSObject

/// NO if the zsign sources were not compiled into this build.
+ (BOOL)isAvailable;

/// Re-signs an unpacked .app folder in place.
/// @param profilePaths  main app profile first; extensions get the profile whose
///                      application-identifier matches their bundle ID, else the first.
/// @param bundleID  nil keeps the original bundle identifier.
+ (BOOL)signAppAtPath:(NSString *)appPath
              p12Path:(NSString *)p12Path
             password:(NSString *)password
         profilePaths:(NSArray<NSString *> *)profilePaths
             bundleID:(nullable NSString *)bundleID
          displayName:(nullable NSString *)displayName
                error:(NSError **)error;

/// Re-packs a .p12 into the classic 3DES/SHA-1 layout that SecPKCS12Import and zsign
/// accept, protected with the same password. Error code 1 = wrong password.
+ (nullable NSData *)normalizedP12:(NSData *)data
                          password:(NSString *)password
                             error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
