#import "RNShellUpdates.h"
#import "RNShellUpdatesStore.h"
#import "RNShellPlugins.h"

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

- (void)pluginIndex:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    NSError *error = nil;
    NSString *manifest = [[RNShellUpdatesStore shared] pluginIndex:&error];
    if (error) {
      reject(@"plugins", error.localizedDescription, error);
    } else {
      resolve(manifest ?: (id)NSNull.null);
    }
  });
}

- (void)fetchPlugin:(NSString *)hash resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
    NSError *error = nil;
    if ([[RNShellUpdatesStore shared] fetchPlugin:hash error:&error]) {
      resolve(nil);
    } else {
      reject(@"plugins", error.localizedDescription ?: @"The plugin didn't download", error);
    }
  });
}

- (void)installJSIBindingsWithRuntime:(facebook::jsi::Runtime &)runtime
                          callInvoker:(const std::shared_ptr<facebook::react::CallInvoker> &)callInvoker {
  rnshell::installPluginLoader(runtime, std::string([RNShellUpdatesStore shared].pluginsDir.UTF8String));
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params {
  return std::make_shared<facebook::react::NativeUpdatesSpecJSI>(params);
}

@end
