#import "RNShellUpdates.h"
#import "RNShellUpdatesStore.h"
#import "RNShellPlugins.h"
#import "RNShellSource.h"
#import "RNShellUpdatesLauncher.h"
#import <React/RCTReloadCommand.h>

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
  [RNShellSource ready];
}

static NSDictionary *SourceInfo(void) {
  RNShellUpdatesStore *store = [RNShellUpdatesStore shared];
  NSString *running = RNShellSource.runningMetro ? @"metro" : [store.info[@"updateId"] isKindOfClass:NSNumber.class] ? @"update" : @"embedded";
  return @{
    @"kind" : RNShellSource.kind,
    @"metroUrl" : RNShellSource.metroURL ?: @"",
    @"releaseUrl" : store.url,
    @"buildReleaseUrl" : store.buildURL,
    @"running" : running,
    @"fallback" : RNShellSource.fallback ?: (id)NSNull.null,
  };
}

- (void)source:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  resolve(RNShellSource.enabled ? SourceInfo() : (id)NSNull.null);
}

- (void)setSource:(NSString *)kind url:(NSString *)url resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  if (!RNShellSource.enabled) {
    reject(@"source", @"This build loads its own bundle (no \"sources\")", nil);
    return;
  }
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [RNShellSource setKind:kind url:url];
    if (![kind isEqual:@"metro"]) {
      // The release server's latest, started by the reload below
      RNShellUpdatesStore *store = [RNShellUpdatesStore shared];
      [store useURL:url];
      [store check:nil];
      [RNShellUpdatesLauncher relaunch];
    }
    resolve(nil);
    dispatch_async(dispatch_get_main_queue(), ^{
      RCTTriggerReloadCommandListeners(@"rn-shell: the bundle's source changed");
    });
  });
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
