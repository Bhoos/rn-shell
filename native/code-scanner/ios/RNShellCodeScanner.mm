#import "RNShellCodeScanner.h"
#import <AVFoundation/AVFoundation.h>
#import <React/RCTUtils.h>
#import <UIKit/UIKit.h>

/** The camera, its preview and a Cancel button; `done` gets the code's text, or nil when cancelled. */
@interface RNShellScannerController : UIViewController <AVCaptureMetadataOutputObjectsDelegate>
@property(nonatomic, copy) void (^done)(NSString *_Nullable text);
@end

@implementation RNShellScannerController {
  AVCaptureSession *_session;
  AVCaptureVideoPreviewLayer *_preview;
  BOOL _finished;
}

- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = UIColor.blackColor;

  _session = [AVCaptureSession new];
  AVCaptureDevice *camera = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
  NSError *error = nil;
  AVCaptureDeviceInput *input = camera ? [AVCaptureDeviceInput deviceInputWithDevice:camera error:&error] : nil;
  if (input && [_session canAddInput:input]) [_session addInput:input];
  AVCaptureMetadataOutput *output = [AVCaptureMetadataOutput new];
  if ([_session canAddOutput:output]) {
    [_session addOutput:output];
    [output setMetadataObjectsDelegate:self queue:dispatch_get_main_queue()];
    if ([output.availableMetadataObjectTypes containsObject:AVMetadataObjectTypeQRCode]) {
      output.metadataObjectTypes = @[ AVMetadataObjectTypeQRCode ];
    }
  }
  _preview = [AVCaptureVideoPreviewLayer layerWithSession:_session];
  _preview.videoGravity = AVLayerVideoGravityResizeAspectFill;
  [self.view.layer addSublayer:_preview];

  UILabel *hint = [UILabel new];
  hint.text = @"Point the camera at the QR code";
  hint.textColor = UIColor.whiteColor;
  hint.textAlignment = NSTextAlignmentCenter;
  hint.translatesAutoresizingMaskIntoConstraints = NO;
  [self.view addSubview:hint];

  UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
  [cancel setTitle:@"Cancel" forState:UIControlStateNormal];
  [cancel setTitleColor:UIColor.whiteColor forState:UIControlStateNormal];
  cancel.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
  cancel.translatesAutoresizingMaskIntoConstraints = NO;
  [cancel addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:cancel];

  UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
  [NSLayoutConstraint activateConstraints:@[
    [hint.topAnchor constraintEqualToAnchor:safe.topAnchor constant:24],
    [hint.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
    [cancel.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-24],
    [cancel.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
  ]];
}

- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  _preview.frame = self.view.bounds;
}

- (void)viewDidAppear:(BOOL)animated {
  [super viewDidAppear:animated];
  AVCaptureSession *session = _session;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [session startRunning];
  });
}

- (void)finish:(NSString *)text {
  if (_finished) return;
  _finished = YES;
  AVCaptureSession *session = _session;
  dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
    [session stopRunning];
  });
  void (^done)(NSString *) = self.done;
  [self dismissViewControllerAnimated:YES completion:^{
    done(text);
  }];
}

- (void)cancel {
  [self finish:nil];
}

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)objects
              fromConnection:(AVCaptureConnection *)connection {
  for (AVMetadataObject *object in objects) {
    if ([object isKindOfClass:AVMetadataMachineReadableCodeObject.class]) {
      NSString *text = ((AVMetadataMachineReadableCodeObject *)object).stringValue;
      if (text.length) {
        [self finish:text];
        return;
      }
    }
  }
}
@end

@implementation RNShellCodeScanner

RCT_EXPORT_MODULE(RNShellCodeScanner)

+ (BOOL)requiresMainQueueSetup {
  return NO;
}

- (void)isAvailable:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  resolve(@([AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] != nil));
}

- (void)scan:(RCTPromiseResolveBlock)resolve reject:(RCTPromiseRejectBlock)reject {
  if (![AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo]) {
    reject(@"no_camera", @"This device has no camera", nil);
    return;
  }
  void (^present)(void) = ^{
    dispatch_async(dispatch_get_main_queue(), ^{
      RNShellScannerController *controller = [RNShellScannerController new];
      controller.modalPresentationStyle = UIModalPresentationFullScreen;
      controller.done = ^(NSString *text) {
        resolve(text ?: (id)[NSNull null]);
      };
      UIViewController *top = RCTPresentedViewController();
      if (!top) {
        reject(@"no_view", @"Nothing to show the scanner over", nil);
        return;
      }
      [top presentViewController:controller animated:YES completion:nil];
    });
  };
  AVAuthorizationStatus status = [AVCaptureDevice authorizationStatusForMediaType:AVMediaTypeVideo];
  if (status == AVAuthorizationStatusAuthorized) {
    present();
  } else if (status == AVAuthorizationStatusNotDetermined) {
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo
                             completionHandler:^(BOOL granted) {
                               if (granted) present();
                               else reject(@"denied", @"The camera isn't allowed: allow it in Settings", nil);
                             }];
  } else {
    reject(@"denied", @"The camera isn't allowed: allow it in Settings", nil);
  }
}

- (std::shared_ptr<facebook::react::TurboModule>)getTurboModule:(const facebook::react::ObjCTurboModule::InitParams &)params {
  return std::make_shared<facebook::react::NativeCodeScannerSpecJSI>(params);
}

@end
