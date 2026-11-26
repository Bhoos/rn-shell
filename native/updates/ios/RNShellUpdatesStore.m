#import "RNShellUpdatesStore.h"
#import "RNShellSource.h"
#import <CommonCrypto/CommonDigest.h>
#import <Security/Security.h>

static NSString *const kPlatform = @"ios";
static NSString *const kBundleName = @"main.jsbundle";
static NSString *const kErrorDomain = @"RNShellUpdates";

/*
 * state.json:
 *   binary, runtimeVersion  the build the updates below were downloaded for
 *   url       the server they came from (another one, chosen with RNShellSource, starts over)
 *   current   { id, message, status: new | launching | ok }: the update that runs
 *   previous  { id, message }: the last one that rendered, kept until current does
 *   pending   { id, message, embedded }: downloaded, started on the next launch
 *   lastId    the newest id taken (an older one is never taken again), at first
 *             the build's (RNShellEmbeddedId: when it was made)
 *   failed    ids that didn't render
 * Each update's files are in a directory named by its id.
 */
@implementation RNShellUpdatesStore {
  NSString *_root;
  NSURL *_baseURL;
  NSString *_buildURL;
  BOOL _launched;
  NSData *_publicKey;
  NSString *_runtimeVersion;
  NSString *_binary;
  NSNumber *_embeddedId;
  NSMutableDictionary *_state;
  dispatch_queue_t _checks;
}

+ (instancetype)shared {
  static RNShellUpdatesStore *store;
  static dispatch_once_t once;
  dispatch_once(&once, ^{ store = [RNShellUpdatesStore new]; });
  return store;
}

- (instancetype)init {
  if ((self = [super init])) {
    NSDictionary *plist = NSBundle.mainBundle.infoDictionary;
    NSString *url = plist[@"RNShellUpdatesURL"];
    NSString *key = plist[@"RNShellUpdatesKey"];
    _runtimeVersion = plist[@"RNShellRuntimeVersion"] ?: @"";
    // When the build was made: updates published before it are older than its own bundle
    _embeddedId = @([plist[@"RNShellEmbeddedId"] longLongValue]);
    _binary = [NSString stringWithFormat:@"%@ (%@) %@", plist[@"CFBundleShortVersionString"], plist[@"CFBundleVersion"], _embeddedId];
    _buildURL = url ?: @"";
    // A development build's release server, chosen in the app (RNShellSource), else the build's
    [self setBase:(RNShellSource.enabled ? RNShellSource.releaseURL : nil) ?: url];
    if (key.length > 0) _publicKey = [[NSData alloc] initWithBase64EncodedString:key options:0];
    NSString *support = NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES).firstObject;
    _root = [support stringByAppendingPathComponent:@"rn-shell-updates"];
    _checks = dispatch_queue_create("rn-shell-updates.check", DISPATCH_QUEUE_SERIAL);
  }
  return self;
}

- (void)setBase:(NSString *)url {
  _baseURL = url.length > 0 ? [NSURL URLWithString:[url hasSuffix:@"/"] ? url : [url stringByAppendingString:@"/"]] : nil;
}

- (NSString *)buildURL {
  return _buildURL;
}

- (NSString *)url {
  @synchronized(self) {
    return _baseURL.absoluteString ?: @"";
  }
}

- (void)useURL:(NSString *)url {
  @synchronized(self) {
    [self setBase:url.length > 0 ? url : _buildURL];
    // Loaded again: a different server's updates start over
    _state = nil;
    _launched = NO;
  }
}

- (BOOL)enabled {
#if DEBUG
  return NO;
#else
  return _baseURL != nil && _publicKey != nil && _runtimeVersion.length > 0;
#endif
}

#pragma mark - State

- (NSString *)pathOf:(id)update {
  return [_root stringByAppendingPathComponent:[update[@"id"] stringValue]];
}

- (void)remove:(nullable NSDictionary *)update {
  if (update && ![update[@"embedded"] boolValue]) {
    [NSFileManager.defaultManager removeItemAtPath:[self pathOf:update] error:nil];
  }
}

/** The state, loaded once; a different build starts over (its updates were for another one). */
- (NSMutableDictionary *)state {
  if (_state) return _state;
  NSData *data = [NSData dataWithContentsOfFile:[_root stringByAppendingPathComponent:@"state.json"]];
  NSDictionary *saved = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
  NSString *url = _baseURL.absoluteString ?: @"";
  if ([saved isKindOfClass:NSDictionary.class] && [saved[@"binary"] isEqual:_binary] &&
      [saved[@"runtimeVersion"] isEqual:_runtimeVersion] && [(saved[@"url"] ?: url) isEqual:url]) {
    _state = [saved mutableCopy];
  } else {
    [NSFileManager.defaultManager removeItemAtPath:_root error:nil];
    _state = [@{@"binary" : _binary, @"runtimeVersion" : _runtimeVersion, @"url" : url, @"lastId" : _embeddedId, @"failed" : @[]} mutableCopy];
  }
  _state[@"url"] = url;
  return _state;
}

- (void)save {
  [NSFileManager.defaultManager createDirectoryAtPath:_root withIntermediateDirectories:YES attributes:nil error:nil];
  NSData *data = [NSJSONSerialization dataWithJSONObject:_state options:0 error:nil];
  NSString *path = [_root stringByAppendingPathComponent:@"state.json"];
  [data writeToFile:path options:NSDataWritingAtomic error:nil];
  // Kept out of backups: a restored phone downloads them again
  [[NSURL fileURLWithPath:_root] setResourceValue:@YES forKey:NSURLIsExcludedFromBackupKey error:nil];
}

#pragma mark - Launch

- (NSURL *)launch {
  if (!self.enabled) return nil;
  @synchronized(self) {
    _launched = YES;
    NSMutableDictionary *state = self.state;
    NSDictionary *pending = state[@"pending"];
    if (pending) {
      [state removeObjectForKey:@"pending"];
      if ([pending[@"embedded"] boolValue]) {
        [self remove:state[@"current"]];
        [self remove:state[@"previous"]];
        [state removeObjectForKey:@"current"];
        [state removeObjectForKey:@"previous"];
      } else {
        NSDictionary *current = state[@"current"];
        if ([current[@"status"] isEqual:@"ok"]) {
          [self remove:state[@"previous"]];
          state[@"previous"] = @{@"id" : current[@"id"], @"message" : current[@"message"] ?: NSNull.null};
        } else {
          [self remove:current];
        }
        state[@"current"] = [@{@"id" : pending[@"id"], @"message" : pending[@"message"] ?: NSNull.null, @"status" : @"new"} mutableCopy];
      }
    }

    NSMutableDictionary *current = [state[@"current"] mutableCopy];
    if ([current[@"status"] isEqual:@"launching"]) {
      // The last launch didn't render it: back to the one before
      NSLog(@"[RNShellUpdates] update %@ didn't start, rolled back", current[@"id"]);
      state[@"failed"] = [state[@"failed"] arrayByAddingObject:current[@"id"]];
      [self remove:current];
      NSDictionary *previous = state[@"previous"];
      [state removeObjectForKey:@"previous"];
      current = previous ? [@{@"id" : previous[@"id"], @"message" : previous[@"message"], @"status" : @"ok"} mutableCopy] : nil;
    }
    if (current && ![NSFileManager.defaultManager fileExistsAtPath:[[self pathOf:current] stringByAppendingPathComponent:kBundleName]]) {
      current = nil;
    }
    if ([current[@"status"] isEqual:@"new"]) current[@"status"] = @"launching";
    if (current) {
      state[@"current"] = current;
    } else {
      [state removeObjectForKey:@"current"];
    }
    [self save];
    return current ? [NSURL fileURLWithPath:[[self pathOf:current] stringByAppendingPathComponent:kBundleName]] : nil;
  }
}

- (void)ready {
  if (!self.enabled) return;
  @synchronized(self) {
    // Only an update this process started (not while a Metro bundle runs: RNShellSource)
    if (!_launched) return;
    NSMutableDictionary *state = self.state;
    NSMutableDictionary *current = [state[@"current"] mutableCopy];
    if (![current[@"status"] isEqual:@"launching"]) return;
    current[@"status"] = @"ok";
    state[@"current"] = current;
    [self remove:state[@"previous"]];
    [state removeObjectForKey:@"previous"];
    [self save];
  }
}

- (NSDictionary *)info {
  @synchronized(self) {
    BOOL enabled = self.enabled;
    NSDictionary *current = enabled ? self.state[@"current"] : nil;
    NSDictionary *pending = enabled ? self.state[@"pending"] : nil;
    return @{
      @"enabled" : @(enabled),
      @"runtimeVersion" : _runtimeVersion,
      @"updateId" : current[@"id"] ?: NSNull.null,
      @"message" : current[@"message"] ?: NSNull.null,
      @"pending" : pending ? @{@"id" : pending[@"id"], @"embedded" : @([pending[@"embedded"] boolValue])} : NSNull.null,
    };
  }
}

#pragma mark - Check

- (NSDictionary *)check:(NSError **)error {
  if (!self.enabled) return @{@"status" : @"disabled"};
  __block NSDictionary *result;
  __block NSError *failure;
  dispatch_sync(_checks, ^{
    NSError *err = nil;
    result = [self checkOnce:&err];
    failure = err;
  });
  if (error) *error = failure;
  return result;
}

static NSError *Failure(NSString *message) {
  return [NSError errorWithDomain:kErrorDomain code:1 userInfo:@{NSLocalizedDescriptionKey : message}];
}

- (NSDictionary *)checkOnce:(NSError **)error {
  NSString *latest = [NSString stringWithFormat:@"%@/%@/latest.json", kPlatform, _runtimeVersion];
  NSInteger status = 0;
  NSData *data = [self get:[NSURL URLWithString:latest relativeToURL:_baseURL] status:&status error:error];
  if (status == 404) return @{@"status" : @"none"};
  if (!data) return nil;

  // { manifest: "<json>", signature: "<base64, DER>" }, signed by the publisher's key
  NSDictionary *signed_ = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  NSString *text = [signed_ isKindOfClass:NSDictionary.class] ? signed_[@"manifest"] : nil;
  NSString *signature = [signed_ isKindOfClass:NSDictionary.class] ? signed_[@"signature"] : nil;
  if (![text isKindOfClass:NSString.class] || ![signature isKindOfClass:NSString.class]) {
    if (error) *error = Failure(@"The update's manifest isn't readable");
    return nil;
  }
  NSData *manifestData = [text dataUsingEncoding:NSUTF8StringEncoding];
  NSData *signatureData = [[NSData alloc] initWithBase64EncodedString:signature options:0];
  if (!signatureData || ![self verify:manifestData signature:signatureData]) {
    if (error) *error = Failure(@"The update's signature doesn't match the app's key");
    return nil;
  }
  NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:nil];
  if (![manifest isKindOfClass:NSDictionary.class] || ![manifest[@"platform"] isEqual:kPlatform] ||
      ![manifest[@"runtimeVersion"] isEqual:_runtimeVersion] || ![manifest[@"id"] isKindOfClass:NSNumber.class]) {
    if (error) *error = Failure(@"The update isn't for this build");
    return nil;
  }

  NSNumber *updateId = manifest[@"id"];
  BOOL embedded = [manifest[@"embedded"] boolValue];
  id message = [manifest[@"message"] isKindOfClass:NSString.class] ? manifest[@"message"] : NSNull.null;
  @synchronized(self) {
    // An older update (replayed, or rolled back from) is never taken again
    if (updateId.longLongValue <= [self.state[@"lastId"] longLongValue] || [self.state[@"failed"] containsObject:updateId]) {
      return @{@"status" : @"upToDate"};
    }
  }

  if (!embedded) {
    NSString *dir = [_root stringByAppendingPathComponent:[updateId stringValue]];
    NSString *tmp = [dir stringByAppendingString:@".download"];
    NSFileManager *fm = NSFileManager.defaultManager;
    [fm removeItemAtPath:tmp error:nil];
    NSMutableArray *files = [NSMutableArray arrayWithObject:@{@"path" : kBundleName, @"hash" : manifest[@"bundle"] ?: @""}];
    if ([manifest[@"assets"] isKindOfClass:NSArray.class]) [files addObjectsFromArray:manifest[@"assets"]];
    for (NSDictionary *file in files) {
      NSString *path = [file isKindOfClass:NSDictionary.class] ? file[@"path"] : nil;
      NSString *hash = [file isKindOfClass:NSDictionary.class] ? file[@"hash"] : nil;
      if (![path isKindOfClass:NSString.class] || ![hash isKindOfClass:NSString.class] || !SafePath(path) || hash.length != 64) {
        if (error) *error = Failure(@"The update names a file it can't have");
        [fm removeItemAtPath:tmp error:nil];
        return nil;
      }
      NSData *content = [self get:[NSURL URLWithString:[@"files/" stringByAppendingString:hash] relativeToURL:_baseURL] status:&status error:error];
      if (!content || status != 200 || ![Sha256(content) isEqualToString:hash.lowercaseString]) {
        if (error && !*error) *error = Failure([NSString stringWithFormat:@"The update's %@ didn't download", path]);
        [fm removeItemAtPath:tmp error:nil];
        return nil;
      }
      NSString *target = [tmp stringByAppendingPathComponent:path];
      [fm createDirectoryAtPath:target.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
      if (![content writeToFile:target options:NSDataWritingAtomic error:error]) {
        [fm removeItemAtPath:tmp error:nil];
        return nil;
      }
    }
    [fm removeItemAtPath:dir error:nil];
    if (![fm moveItemAtPath:tmp toPath:dir error:error]) return nil;
  }

  @synchronized(self) {
    NSMutableDictionary *state = self.state;
    NSDictionary *previous = state[@"pending"];
    if (previous) [self remove:previous];
    state[@"pending"] = @{@"id" : updateId, @"message" : message, @"embedded" : @(embedded)};
    state[@"lastId"] = updateId;
    [self save];
  }
  return @{@"status" : @"downloaded", @"id" : updateId, @"embedded" : @(embedded), @"message" : message};
}

#pragma mark - Plugins

- (NSString *)pluginsDir {
  return [_root stringByAppendingPathComponent:@"plugins"];
}

/** A signed index's manifest (text), if it's the publisher's and for this build. */
- (nullable NSString *)pluginManifest:(NSData *)data identifier:(long long *)identifier {
  NSDictionary *outer = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
  NSString *text = [outer isKindOfClass:NSDictionary.class] ? outer[@"manifest"] : nil;
  NSString *signature = [outer isKindOfClass:NSDictionary.class] ? outer[@"signature"] : nil;
  if (![text isKindOfClass:NSString.class] || ![signature isKindOfClass:NSString.class]) return nil;
  NSData *signatureData = [[NSData alloc] initWithBase64EncodedString:signature options:0];
  NSData *manifestData = [text dataUsingEncoding:NSUTF8StringEncoding];
  if (!signatureData || ![self verify:manifestData signature:signatureData]) return nil;
  NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:nil];
  if (![manifest isKindOfClass:NSDictionary.class] || ![manifest[@"platform"] isEqual:kPlatform] ||
      ![manifest[@"runtimeVersion"] isEqual:_runtimeVersion]) {
    return nil;
  }
  if (identifier) *identifier = [manifest[@"id"] longLongValue];
  return text;
}

- (NSString *)pluginIndex:(NSError **)error {
  if (!self.enabled) return nil;
  @synchronized(self) { (void)self.state; }
  NSString *savedPath = [_root stringByAppendingPathComponent:@"plugins.json"];
  long long savedId = -1, fetchedId = -1;
  NSString *saved = [self pluginManifest:[NSData dataWithContentsOfFile:savedPath] identifier:&savedId];
  NSInteger status = 0;
  NSError *offline = nil;
  NSString *url = [NSString stringWithFormat:@"%@/%@/plugins.json", kPlatform, _runtimeVersion];
  NSData *fetched = [self get:[NSURL URLWithString:url relativeToURL:_baseURL] status:&status error:&offline];
  if (fetched) {
    NSString *manifest = [self pluginManifest:fetched identifier:&fetchedId];
    if (!manifest) {
      if (error) *error = Failure(@"The plugin index's signature doesn't match the app's key");
      return nil;
    }
    if (fetchedId > savedId) {
      [NSFileManager.defaultManager createDirectoryAtPath:_root withIntermediateDirectories:YES attributes:nil error:nil];
      [fetched writeToFile:savedPath options:NSDataWritingAtomic error:nil];
      return manifest;
    }
  }
  // Offline, or nothing newer: the saved one
  return saved;
}

- (BOOL)fetchPlugin:(NSString *)hash error:(NSError **)error {
  if (!self.enabled) {
    if (error) *error = Failure(@"Plugins load from the development server in debug builds");
    return NO;
  }
  if (hash.length != 64 || [hash rangeOfCharacterFromSet:[[NSCharacterSet characterSetWithCharactersInString:@"0123456789abcdef"] invertedSet]].location != NSNotFound) {
    if (error) *error = Failure([@"Not a plugin's hash: " stringByAppendingString:hash]);
    return NO;
  }
  @synchronized(self) { (void)self.state; }
  NSFileManager *fm = NSFileManager.defaultManager;
  NSString *file = [self.pluginsDir stringByAppendingPathComponent:hash];
  if ([fm fileExistsAtPath:file]) return YES;
  NSInteger status = 0;
  NSData *content = [self get:[NSURL URLWithString:[@"files/" stringByAppendingString:hash] relativeToURL:_baseURL] status:&status error:error];
  if (!content || ![Sha256(content) isEqualToString:hash]) {
    if (error && !*error) *error = Failure([NSString stringWithFormat:@"The plugin %@ didn't download", hash]);
    return NO;
  }
  [fm createDirectoryAtPath:self.pluginsDir withIntermediateDirectories:YES attributes:nil error:nil];
  return [content writeToFile:file options:NSDataWritingAtomic error:error];
}

/** A path inside the update's directory: relative, without "..". */
static BOOL SafePath(NSString *path) {
  if (path.length == 0 || [path hasPrefix:@"/"] || [path containsString:@"\\"]) return NO;
  for (NSString *part in [path componentsSeparatedByString:@"/"]) {
    if (part.length == 0 || [part isEqual:@"."] || [part isEqual:@".."]) return NO;
  }
  return YES;
}

static NSString *Sha256(NSData *data) {
  unsigned char digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
  NSMutableString *hex = [NSMutableString stringWithCapacity:64];
  for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
  return hex;
}

/** ECDSA P-256 with SHA-256, the signature in DER; the key is SPKI (its last 65 bytes, the point). */
- (BOOL)verify:(NSData *)message signature:(NSData *)signature {
  if (_publicKey.length != 91) return NO;
  NSData *point = [_publicKey subdataWithRange:NSMakeRange(26, 65)];
  NSDictionary *attributes = @{
    (id)kSecAttrKeyType : (id)kSecAttrKeyTypeECSECPrimeRandom,
    (id)kSecAttrKeyClass : (id)kSecAttrKeyClassPublic,
    (id)kSecAttrKeySizeInBits : @256,
  };
  SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)point, (__bridge CFDictionaryRef)attributes, NULL);
  if (!key) return NO;
  BOOL valid = SecKeyVerifySignature(key, kSecKeyAlgorithmECDSASignatureMessageX962SHA256, (__bridge CFDataRef)message,
                                     (__bridge CFDataRef)signature, NULL);
  CFRelease(key);
  return valid;
}

- (NSData *)get:(NSURL *)url status:(NSInteger *)status error:(NSError **)error {
  NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
  request.cachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
  request.timeoutInterval = 60;
  dispatch_semaphore_t done = dispatch_semaphore_create(0);
  __block NSData *body;
  __block NSError *failure;
  __block NSInteger code = 0;
  [[NSURLSession.sharedSession dataTaskWithRequest:request
                                 completionHandler:^(NSData *data, NSURLResponse *response, NSError *err) {
                                   body = data;
                                   failure = err;
                                   code = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse *)response).statusCode : 0;
                                   dispatch_semaphore_signal(done);
                                 }] resume];
  dispatch_semaphore_wait(done, DISPATCH_TIME_FOREVER);
  *status = code;
  if (failure) {
    if (error) *error = failure;
    return nil;
  }
  if (code != 200 && code != 404) {
    if (error) *error = Failure([NSString stringWithFormat:@"%@: HTTP %ld", url.absoluteString, (long)code]);
    return nil;
  }
  return code == 200 ? body : nil;
}

@end
