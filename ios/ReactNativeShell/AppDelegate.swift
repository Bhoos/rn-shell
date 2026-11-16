import UIKit
import React
import React_RCTAppDelegate
import ReactAppDependencyProvider

// Splash screen library (react-native-bootsplash)
import RNBootSplash

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
  var window: UIWindow?

  var reactNativeDelegate: ReactNativeDelegate?
  var reactNativeFactory: RCTReactNativeFactory?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    let delegate = ReactNativeDelegate()
    let factory = RCTReactNativeFactory(delegate: delegate)
    delegate.dependencyProvider = RCTAppDependencyProvider()

    reactNativeDelegate = delegate
    reactNativeFactory = factory

    window = UIWindow(frame: UIScreen.main.bounds)

    factory.startReactNative(
      withModuleName: "ReactNativeShell",
      in: window,
      launchOptions: launchOptions
    )

    applyKioskMode(application)

    return true
  }

  // The idle timer may be re-enabled by the system while in background
  func applicationDidBecomeActive(_ application: UIApplication) {
    applyKioskMode(application)
  }

  private func applyKioskMode(_ application: UIApplication) {
    if Kiosk.keepAwake {
      application.isIdleTimerDisabled = true
    }
  }

  
  func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    return RCTLinkingManager.application(app, open: url, options: options)
  }

  func application(
    _ app: UIApplication,
    continue userActivity: NSUserActivity,
    restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void
  ) -> Bool {
    return RCTLinkingManager.application(
      app,
      continue: userActivity,
      restorationHandler: restorationHandler
    )
  }
}

class ReactNativeDelegate: RCTDefaultReactNativeFactoryDelegate {
  override func sourceURL(for bridge: RCTBridge) -> URL? {
    self.bundleURL()
  }

  override func bundleURL() -> URL? {
#if DEBUG
    RCTBundleURLProvider.sharedSettings().jsBundleURL(forBundleRoot: "index")
#else
    Bundle.main.url(forResource: "main", withExtension: "jsbundle")
#endif
  }

  // Splash screen library react-native-bootsplash
  override func customize(_ rootView: RCTRootView) {
    super.customize(rootView)
    RNBootSplash.initWithStoryboard("BootSplash", rootView: rootView)
  }

  override func createRootViewController() -> UIViewController {
    Kiosk.fullScreen ? KioskViewController() : super.createRootViewController()
  }
}

/// Kiosk mode flags, written into Info.plist by scripts/generateKiosk.js
enum Kiosk {
  static let fullScreen = Bundle.main.object(forInfoDictionaryKey: "RNShellFullScreen") as? Bool ?? false
  static let keepAwake = Bundle.main.object(forInfoDictionaryKey: "RNShellKeepAwake") as? Bool ?? false
}

/// Root view controller for full screen kiosk mode: hides the status bar and home
/// indicator, and makes edge swipes require a second swipe to open system UI.
class KioskViewController: UIViewController {
  override var prefersStatusBarHidden: Bool { true }
  override var prefersHomeIndicatorAutoHidden: Bool { true }
  override var preferredScreenEdgesDeferringSystemGestures: UIRectEdge { .all }
}
