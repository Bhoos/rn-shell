#import "RNShellUpdatesLauncher.h"
#import "RNShellSource.h"
#import "RNShellUpdatesStore.h"

static BOOL sLaunched;
static NSURL *sUpdate;

@implementation RNShellUpdatesLauncher

+ (NSURL *)bundleURL {
  // A development build's Metro server, each load (RNShellSource)
  NSURL *metro = [RNShellSource metroBundleURL];
  if (metro) return metro;
  // Once per process: React Native asks again on a reload, and a second launch
  // would take the update as one that didn't start
  @synchronized(self) {
    if (!sLaunched) {
      sUpdate = [[RNShellUpdatesStore shared] launch];
      sLaunched = YES;
    }
    return sUpdate;
  }
}

+ (void)relaunch {
  @synchronized(self) {
    sLaunched = NO;
    sUpdate = nil;
  }
}

@end
