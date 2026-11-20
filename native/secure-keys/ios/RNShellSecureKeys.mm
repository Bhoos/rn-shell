#import "RNShellSecureKeys.h"
#import <DeviceCheck/DeviceCheck.h>
#import <Security/Security.h>

/** The keychain tag of key `alias`. */
static NSData *TagOf(NSString *alias) {
  return [[@"plus.num.securekeys." stringByAppendingString:alias] dataUsingEncoding:NSUTF8StringEncoding];
}

static NSDictionary *KeyQuery(NSString *alias) {
  return @{
    (id)kSecClass : (id)kSecClassKey,
    (id)kSecAttrApplicationTag : TagOf(alias),
    (id)kSecAttrKeyType : (id)kSecAttrKeyTypeECSECPrimeRandom,
  };
}

/** Key `alias`'s private key (to release), or NULL. */
static SecKeyRef CopyPrivateKey(NSString *alias) {
  NSMutableDictionary *query = [KeyQuery(alias) mutableCopy];
  query[(id)kSecAttrKeyClass] = (id)kSecAttrKeyClassPrivate;
  query[(id)kSecReturnRef] = @YES;
  SecKeyRef key = NULL;
  OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, (CFTypeRef *)&key);
  return status == errSecSuccess ? key : NULL;
}

static NSString *Base64(NSData *data) {
  return [data base64EncodedStringWithOptions:0];
}

static NSString *ErrorText(CFErrorRef error) {
  if (!error) return @"unknown error";
  NSString *text = [(__bridge NSError *)error localizedDescription];
  CFRelease(error);
  return text;
}

/** The raw public key (0x04 ‖ X ‖ Y) of a private key. */
static NSData *RawPublicKey(SecKeyRef privateKey) {
  SecKeyRef publicKey = SecKeyCopyPublicKey(privateKey);
  if (!publicKey) return nil;
  NSData *raw = (__bridge_transfer NSData *)SecKeyCopyExternalRepresentation(publicKey, NULL);
  CFRelease(publicKey);
  return raw;
}

/** Make a P-256 private key tagged `alias`: in the Secure Enclave if `enclave`. NULL (and `error`) if it can't. */
static SecKeyRef MakeKey(NSString *alias, BOOL enclave, CFErrorRef *error) {
  SecAccessControlCreateFlags flags = enclave ? kSecAccessControlPrivateKeyUsage : 0;
  SecAccessControlRef access =
      SecAccessControlCreateWithFlags(kCFAllocatorDefault, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, flags, error);
  if (!access) return NULL;
  NSMutableDictionary *attributes = [@{
    (id)kSecAttrKeyType : (id)kSecAttrKeyTypeECSECPrimeRandom,
    (id)kSecAttrKeySizeInBits : @256,
    (id)kSecPrivateKeyAttrs : @{
      (id)kSecAttrIsPermanent : @YES,
      (id)kSecAttrApplicationTag : TagOf(alias),
      (id)kSecAttrAccessControl : (__bridge id)access,
    },
  } mutableCopy];
  if (enclave) attributes[(id)kSecAttrTokenID] = (id)kSecAttrTokenIDSecureEnclave;
  SecKeyRef key = SecKeyCreateRandomKey((__bridge CFDictionaryRef)attributes, error);
  CFRelease(access);
  return key;
}

@implementation RNShellSecureKeys

RCT_EXPORT_MODULE(RNShellSecureKeys)

+ (BOOL)requiresMainQueueSetup {
  return NO;
}

- (void)generateKey:(NSString *)alias
              usage:(NSString *)usage
           hardware:(BOOL)hardware
            resolve:(RCTPromiseResolveBlock)resolve
             reject:(RCTPromiseRejectBlock)reject {
  SecItemDelete((__bridge CFDictionaryRef)KeyQuery(alias));
  CFErrorRef error = NULL;
  BOOL inEnclave = NO;
  SecKeyRef key = NULL;
  // The Secure Enclave where there is one; the keychain otherwise (the simulator has none)
#if !TARGET_OS_SIMULATOR
  if (hardware) {
    key = MakeKey(alias, YES, &error);
    inEnclave = key != NULL;
    if (!key && error) {
      CFRelease(error);
      error = NULL;
    }
  }
#endif
  if (!key) key = MakeKey(alias, NO, &error);
  if (!key) {
    reject(@"generate", [NSString stringWithFormat:@"Couldn't make key %@: %@", alias, ErrorText(error)], nil);
    return;
  }
  NSData *raw = RawPublicKey(key);
  CFRelease(key);
  resolve(@{@"publicKey" : Base64(raw), @"hardware" : @(inEnclave)});
}

- (void)publicKey:(NSString *)alias resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  SecKeyRef key = CopyPrivateKey(alias);
  if (!key) {
    resolve([NSNull null]);
    return;
  }
  NSData *raw = RawPublicKey(key);
  CFRelease(key);
  resolve(Base64(raw));
}

- (void)sign:(NSString *)alias data:(NSString *)data resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  SecKeyRef key = CopyPrivateKey(alias);
  if (!key) {
    reject(@"sign", [NSString stringWithFormat:@"No key %@", alias], nil);
    return;
  }
  NSData *message = [[NSData alloc] initWithBase64EncodedString:data options:0];
  CFErrorRef error = NULL;
  NSData *signature = (__bridge_transfer NSData *)SecKeyCreateSignature(
      key, kSecKeyAlgorithmECDSASignatureMessageX962SHA256, (__bridge CFDataRef)message, &error);
  CFRelease(key);
  if (!signature) {
    reject(@"sign", [NSString stringWithFormat:@"Couldn't sign with %@: %@", alias, ErrorText(error)], nil);
    return;
  }
  resolve(Base64(signature));
}

- (void)agree:(NSString *)alias peer:(NSString *)peer resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  SecKeyRef key = CopyPrivateKey(alias);
  if (!key) {
    reject(@"agree", [NSString stringWithFormat:@"No key %@", alias], nil);
    return;
  }
  NSData *raw = [[NSData alloc] initWithBase64EncodedString:peer options:0];
  NSDictionary *attributes = @{
    (id)kSecAttrKeyType : (id)kSecAttrKeyTypeECSECPrimeRandom,
    (id)kSecAttrKeyClass : (id)kSecAttrKeyClassPublic,
    (id)kSecAttrKeySizeInBits : @256,
  };
  CFErrorRef error = NULL;
  SecKeyRef peerKey = SecKeyCreateWithData((__bridge CFDataRef)raw, (__bridge CFDictionaryRef)attributes, &error);
  if (!peerKey) {
    CFRelease(key);
    reject(@"agree", [NSString stringWithFormat:@"Not a public key: %@", ErrorText(error)], nil);
    return;
  }
  // The standard ECDH: the shared point's X, 32 bytes (as Web Crypto's deriveBits)
  NSData *secret = (__bridge_transfer NSData *)SecKeyCopyKeyExchangeResult(
      key, kSecKeyAlgorithmECDHKeyExchangeStandard, peerKey, (__bridge CFDictionaryRef) @{}, &error);
  CFRelease(key);
  CFRelease(peerKey);
  if (!secret) {
    reject(@"agree", [NSString stringWithFormat:@"Couldn't agree with %@: %@", alias, ErrorText(error)], nil);
    return;
  }
  resolve(Base64(secret));
}

- (void)deleteKey:(NSString *)alias resolve:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  OSStatus status = SecItemDelete((__bridge CFDictionaryRef)KeyQuery(alias));
  resolve(@(status == errSecSuccess));
}

- (void)attestationSupported:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  resolve(@([DCAppAttestService sharedService].isSupported));
}

- (void)attest:(NSString *)challenge
       options:(NSDictionary *)options
       resolve:(RCTPromiseResolveBlock)resolve
        reject:(RCTPromiseRejectBlock)reject {
  DCAppAttestService *service = [DCAppAttestService sharedService];
  if (!service.isSupported) {
    reject(@"attest", @"App Attest isn't supported on this device (the simulator has none)", nil);
    return;
  }
  NSData *clientDataHash = [[NSData alloc] initWithBase64EncodedString:challenge options:0];
  [service generateKeyWithCompletionHandler:^(NSString *keyId, NSError *error) {
    if (!keyId) {
      reject(@"attest", [NSString stringWithFormat:@"Couldn't make the App Attest key: %@", error.localizedDescription], error);
      return;
    }
    [service attestKey:keyId
        clientDataHash:clientDataHash
     completionHandler:^(NSData *attestation, NSError *attestError) {
       if (!attestation) {
         reject(@"attest", [NSString stringWithFormat:@"Couldn't attest: %@", attestError.localizedDescription], attestError);
         return;
       }
       resolve(@{@"kind" : @"apple", @"keyId" : keyId, @"attestation" : Base64(attestation)});
     }];
  }];
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params {
  return std::make_shared<facebook::react::NativeSecureKeysSpecJSI>(params);
}

@end
