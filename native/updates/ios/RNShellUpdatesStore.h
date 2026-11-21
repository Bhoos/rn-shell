#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/** The updates on this device (RNShellUpdatesLauncher's, and the module's). */
@interface RNShellUpdatesStore : NSObject

+ (instancetype)shared;

/** Updates are configured (an URL and a key) and this isn't a debug build. */
@property(nonatomic, readonly) BOOL enabled;

/** The bundle to start (see RNShellUpdatesLauncher). */
- (nullable NSURL *)launch;
/** The running bundle rendered. */
- (void)ready;
/** What's running and what's pending. */
- (NSDictionary *)info;
/** Looks for an update and downloads it (blocking: call it off the main thread). */
- (NSDictionary *)check:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
