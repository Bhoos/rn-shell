#import "RNShellSource.h"

static NSString *const kSource = @"RNShellSource";              // { kind, metroURL, releaseURL }
static NSString *const kMetroLoading = @"RNShellSourceMetroLoading"; // a Metro bundle loaded, not yet rendered

static NSString *sFallback;
static BOOL sRunningMetro;

@implementation RNShellSource

+ (BOOL)enabled {
#if DEBUG
  return NO;
#else
  return [NSBundle.mainBundle.infoDictionary[@"RNShellSources"] boolValue];
#endif
}

+ (NSDictionary *)saved {
  NSDictionary *saved = [NSUserDefaults.standardUserDefaults dictionaryForKey:kSource];
  return saved ?: @{};
}

+ (NSString *)kind {
  return [[self saved][@"kind"] isEqual:@"metro"] ? @"metro" : @"release";
}

static NSString *NonEmpty(id value) {
  return [value isKindOfClass:NSString.class] && [value length] > 0 ? value : nil;
}

+ (NSString *)metroURL {
  return NonEmpty([self saved][@"metroURL"]);
}

+ (NSString *)releaseURL {
  return NonEmpty([self saved][@"releaseURL"]);
}

+ (void)setKind:(NSString *)kind url:(NSString *)url {
  NSMutableDictionary *saved = [[self saved] mutableCopy];
  if ([kind isEqual:@"metro"]) {
    saved[@"kind"] = @"metro";
    if (url.length) saved[@"metroURL"] = url;
  } else {
    saved[@"kind"] = @"release";
    saved[@"releaseURL"] = url ?: @"";
  }
  NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
  [defaults setObject:saved forKey:kSource];
  // A new choice is tried again, even if Metro's last bundle didn't render
  [defaults removeObjectForKey:kMetroLoading];
}

+ (NSString *)fallback {
  @synchronized(self) {
    return sFallback;
  }
}

+ (BOOL)runningMetro {
  @synchronized(self) {
    return sRunningMetro;
  }
}

/** Metro's status page answers "packager-status:running". */
static BOOL MetroRunning(NSURL *base) {
  NSURL *url = [base URLByAppendingPathComponent:@"status"];
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  request.timeoutInterval = 2;
  request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
  __block BOOL running = NO;
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  NSURLSessionConfiguration *configuration = NSURLSessionConfiguration.ephemeralSessionConfiguration;
  configuration.timeoutIntervalForResource = 2;
  NSURLSession *session = [NSURLSession sessionWithConfiguration:configuration];
  [[session dataTaskWithRequest:request
              completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
                if (data && !error) {
                  NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                  running = [text containsString:@"packager-status:running"];
                }
                dispatch_semaphore_signal(done);
              }] resume];
  dispatch_semaphore_wait(done, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(3 * NSEC_PER_SEC)));
  [session invalidateAndCancel];
  return running;
}

+ (NSURL *)metroBundleURL {
  @synchronized(self) {
    sFallback = nil;
    sRunningMetro = NO;
    if (!self.enabled || ![self.kind isEqual:@"metro"]) return nil;
    NSString *metro = self.metroURL;
    NSURL *base = metro ? [NSURL URLWithString:metro] : nil;
    if (!base) {
      sFallback = @"No Metro server was given";
      return nil;
    }
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    if ([defaults boolForKey:kMetroLoading]) {
      // Its last bundle never rendered (it failed, or the app was killed): not again now,
      // so the app can start and another source be chosen; the next launch tries again
      [defaults removeObjectForKey:kMetroLoading];
      sFallback = @"Metro's last bundle didn't start";
      return nil;
    }
    if (!MetroRunning(base)) {
      sFallback = [NSString stringWithFormat:@"Metro isn't running at %@", metro];
      return nil;
    }
    // The bundle a release build runs (no development tools), from the shell's index.js
    NSURLComponents *components = [NSURLComponents componentsWithURL:[base URLByAppendingPathComponent:@"index.bundle"]
                                             resolvingAgainstBaseURL:NO];
    components.queryItems = @[
      [NSURLQueryItem queryItemWithName:@"platform" value:@"ios"],
      [NSURLQueryItem queryItemWithName:@"dev" value:@"false"],
      [NSURLQueryItem queryItemWithName:@"minify" value:@"false"],
      [NSURLQueryItem queryItemWithName:@"app" value:NSBundle.mainBundle.bundleIdentifier],
    ];
    [defaults setBool:YES forKey:kMetroLoading];
    sRunningMetro = YES;
    return components.URL;
  }
}

+ (void)ready {
  @synchronized(self) {
    if (sRunningMetro) [NSUserDefaults.standardUserDefaults removeObjectForKey:kMetroLoading];
  }
}

@end
