#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Over the air updates. Info.plist holds what the build was made with
 * (scripts/generateUpdates.js): RNShellUpdatesURL, RNShellUpdatesKey (the
 * publisher's P-256 public key, SPKI in base64) and RNShellRuntimeVersion.
 *
 * Updates live in Application Support/rn-shell-updates, one directory each
 * (the bundle and its assets), with state.json saying which one runs.
 */
@interface RNShellUpdatesLauncher : NSObject

/**
 * The bundle to start: a development build's Metro bundle (RNShellSource),
 * else the downloaded update for this build, or nil for the embedded one.
 * The update is chosen once per process: a new one is tried once, and if the
 * app doesn't call `ready` on it, the next launch goes back to the one before.
 */
+ (nullable NSURL *)bundleURL;

/** The next bundleURL chooses the update again (another release server was chosen: RNShellSource). */
+ (void)relaunch;

@end

NS_ASSUME_NONNULL_END
