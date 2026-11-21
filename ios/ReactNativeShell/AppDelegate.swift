import UIKit
import React
import React_RCTAppDelegate
import ReactAppDependencyProvider

// Splash screen library (react-native-bootsplash)
import RNBootSplash

// Over the air updates (native/updates)
import RNShellUpdates

@main
class AppDelegate: UIResponder, UIApplicationDelegate {
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
    return true
  }

  // The window and React Native start in the scene (SceneDelegate): iOS 27 requires the scene lifecycle
  func application(
    _ application: UIApplication,
    configurationForConnecting connectingSceneSession: UISceneSession,
    options: UIScene.ConnectionOptions
  ) -> UISceneConfiguration {
    let configuration = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
    configuration.delegateClass = SceneDelegate.self
    return configuration
  }

  func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    return RCTLinkingManager.application(app, open: url, options: options)
  }
}

/// The app's one scene: its window runs React Native. Deep and universal
/// links reach React Native's Linking from here (the app delegate's link
/// callbacks aren't called with scenes).
class SceneDelegate: UIResponder, UIWindowSceneDelegate {
  var window: UIWindow?

  func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    guard let windowScene = scene as? UIWindowScene,
          let factory = (UIApplication.shared.delegate as? AppDelegate)?.reactNativeFactory else { return }
    let window = UIWindow(windowScene: windowScene)
    self.window = window

    // A link that opened the app: Linking.getInitialURL reads it from the launch options
    var launchOptions: [UIApplication.LaunchOptionsKey: Any] = [:]
    if let url = connectionOptions.urlContexts.first?.url {
      launchOptions[.url] = url
    } else if let activity = connectionOptions.userActivities.first(where: { $0.activityType == NSUserActivityTypeBrowsingWeb }),
              let url = activity.webpageURL {
      launchOptions[.url] = url
    }

    factory.startReactNative(withModuleName: "ReactNativeShell", in: window, launchOptions: launchOptions)
  }

  // The idle timer may be re-enabled by the system while in background
  func sceneDidBecomeActive(_ scene: UIScene) {
    if Kiosk.keepAwake {
      UIApplication.shared.isIdleTimerDisabled = true
    }
  }

  // A deep link while running
  func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    for context in URLContexts {
      RCTLinkingManager.application(UIApplication.shared, open: context.url, options: [:])
    }
  }

  // A universal link while running
  func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
    _ = RCTLinkingManager.application(UIApplication.shared, continue: userActivity) { _ in }
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
    // A downloaded update for this build, else the one it was built with
    RNShellUpdatesLauncher.bundleURL() ?? Bundle.main.url(forResource: "main", withExtension: "jsbundle")
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
