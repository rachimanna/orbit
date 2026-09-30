#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Thin Objective-C++ wrapper around zsign (github.com/zhlynn/zsign, MIT).
@interface ZSignBridge : NSObject

/// NO if the zsign sources were not compiled into this build.
+ (BOOL)isAvailable;

/// Re-signs an unpacked .app folder in place.
/// @param bundleID  nil keeps the original bundle identifier.
+ (BOOL)signAppAtPath:(NSString *)appPath
              p12Path:(NSString *)p12Path
             password:(NSString *)password
          profilePath:(NSString *)profilePath
             bundleID:(nullable NSString *)bundleID
          displayName:(nullable NSString *)displayName
                error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
