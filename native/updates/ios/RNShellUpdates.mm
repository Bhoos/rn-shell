#import "RNShellUpdates.h"
#import "RNShellUpdatesStore.h"

@implementation RNShellUpdates

RCT_EXPORT_MODULE(RNShellUpdates)

- (void)info:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  resolve([[RNShellUpdatesStore shared] info]);
}

- (void)check:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    NSError *error = nil;
    NSDictionary *result = [[RNShellUpdatesStore shared] check:&error];
    if (result) {
      resolve(result);
    } else {
      resolve(@{@"status" : @"failed", @"error" : error.localizedDescription ?: @"The update check failed"});
    }
  });
}

- (void)ready {
  [[RNShellUpdatesStore shared] ready];
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params {
  return std::make_shared<facebook::react::NativeUpdatesSpecJSI>(params);
}

@end
