#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * Where a release build with "sources" (Info.plist RNShellSources: a
 * development build, `rn-shell --variant`) loads its JavaScript from, chosen
 * in the app and kept in the user defaults:
 *
 *   metro    a Metro server (`rn-shell start`), its URL: the bundle it serves
 *            as a release build would run it (dev=false), each launch and
 *            reload; when Metro isn't reachable, or the last bundle it served
 *            never rendered, the release source's bundle instead
 *   release  over the air updates from a release server, its URL (the
 *            build's RNShellUpdatesURL unless another was chosen), else the
 *            bundle the app was built with
 */
@interface RNShellSource : NSObject

/** This build chooses its source (RNShellSources), and isn't a debug build (those always use Metro). */
@property(class, nonatomic, readonly) BOOL enabled;

/** "metro" or "release". */
@property(class, nonatomic, readonly) NSString *kind;
/** The Metro server's URL (http://host:port), or nil. */
@property(class, nonatomic, readonly, nullable) NSString *metroURL;
/** The release server's URL chosen, or nil for the build's. */
@property(class, nonatomic, readonly, nullable) NSString *releaseURL;

/** Keeps the source (a URL of nil or "" for the release source: the build's). */
+ (void)setKind:(NSString *)kind url:(nullable NSString *)url;

/**
 * The Metro bundle to load now, or nil when the source isn't Metro, Metro
 * doesn't answer, or its last bundle didn't render (`fallback` says why).
 * Blocks for up to 2 seconds while it asks Metro.
 */
+ (nullable NSURL *)metroBundleURL;

/** Why the last load didn't use Metro although it was chosen, or nil. */
@property(class, nonatomic, readonly, nullable) NSString *fallback;
/** The running bundle came from Metro. */
@property(class, nonatomic, readonly) BOOL runningMetro;

/** The running bundle rendered (a Metro bundle that didn't is skipped on the next launch). */
+ (void)ready;

@end

NS_ASSUME_NONNULL_END
