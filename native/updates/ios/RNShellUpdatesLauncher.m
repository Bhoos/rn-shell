#import "RNShellUpdatesLauncher.h"
#import "RNShellUpdatesStore.h"

@implementation RNShellUpdatesLauncher

// Once per process: React Native may ask again (a reload), and a second
// launch would take the update as one that didn't start
+ (NSURL *)bundleURL {
  static NSURL *url;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ url = [[RNShellUpdatesStore shared] launch]; });
  return url;
}

@end
