#import <Foundation/Foundation.h>
#import "RNShellCodeScannerSpec.h"

/** Scanning a QR code: a full-screen camera view, closed on the first code or on Cancel. */
@interface RNShellCodeScanner : NSObject <NativeCodeScannerSpec>
@end
