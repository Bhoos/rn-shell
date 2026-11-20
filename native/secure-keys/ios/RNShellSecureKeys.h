#import <Foundation/Foundation.h>
#import "RNShellSecureKeysSpec.h"

/** Keys the platform holds (the Secure Enclave, else the keychain), and App Attest. */
@interface RNShellSecureKeys : NSObject <NativeSecureKeysSpec>
@end
