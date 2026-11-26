#import <Foundation/Foundation.h>
#import "RNShellUpdatesSpec.h"
#import <ReactCommon/RCTTurboModuleWithJSIBindings.h>

/**
 * Over the air updates for JavaScript: what's running, checking for a newer
 * one, keeping a new one; and plugins (their index, their bundles, and
 * global.__rnShellLoadPlugin, from ../cpp).
 */
@interface RNShellUpdates : NSObject <NativeUpdatesSpec, RCTTurboModuleWithJSIBindings>
@end
