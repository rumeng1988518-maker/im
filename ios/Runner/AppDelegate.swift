import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var deviceToken: String?
  private var pendingTokenResult: FlutterResult?
  private var pushChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Request notification permission and register for remote notifications
    UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
      print("[APNs] Initial authorization: granted=\(granted)")
      if granted {
        DispatchQueue.main.async {
          UIApplication.shared.registerForRemoteNotifications()
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    // Scene-based app: window is nil in AppDelegate, so set up MethodChannel
    // via the engine's plugin registry which provides a binary messenger.
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "APNsPushPlugin") else {
      print("[APNs] ERROR: Could not get plugin registrar for MethodChannel")
      return
    }
    let channel = FlutterMethodChannel(name: "im.client/push", binaryMessenger: registrar.messenger())
    self.pushChannel = channel
    print("[APNs] MethodChannel 'im.client/push' set up via plugin registrar")

    channel.setMethodCallHandler { [weak self] (call, result) in
      if call.method == "getDeviceToken" {
        if let token = self?.deviceToken {
          print("[APNs] getDeviceToken: returning cached token \(token.prefix(8))...")
          result(token)
        } else {
          print("[APNs] getDeviceToken: no token yet, requesting authorization...")
          self?.pendingTokenResult = result
          UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, error in
            print("[APNs] Authorization result: granted=\(granted), error=\(String(describing: error))")
            if granted {
              DispatchQueue.main.async {
                UIApplication.shared.registerForRemoteNotifications()
              }
            } else {
              DispatchQueue.main.async {
                self?.pendingTokenResult?(nil)
                self?.pendingTokenResult = nil
              }
            }
          }
          // Timeout after 10 seconds
          DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
            if let pending = self?.pendingTokenResult {
              print("[APNs] getDeviceToken: 10s timeout, token=\(self?.deviceToken?.prefix(8) ?? "nil")")
              pending(self?.deviceToken)
              self?.pendingTokenResult = nil
            }
          }
        }
      } else {
        result(FlutterMethodNotImplemented)
      }
    }

    // If token arrived before engine was ready, push it now
    if let token = deviceToken {
      print("[APNs] Engine ready, pushing cached token to Flutter: \(token.prefix(8))...")
      channel.invokeMethod("onTokenReceived", arguments: token)
    }
  }

  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    self.deviceToken = token
    print("[APNs] Device token received: \(token.prefix(16))...")
    // Resolve pending Flutter result
    if let pending = pendingTokenResult {
      pending(token)
      pendingTokenResult = nil
    }
    // Proactively notify Flutter when token arrives
    pushChannel?.invokeMethod("onTokenReceived", arguments: token)
  }

  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("[APNs] Registration FAILED: \(error.localizedDescription)")
    if let pending = pendingTokenResult {
      pending(nil)
      pendingTokenResult = nil
    }
  }

  // Handle remote notification in background — required for content-available
  override func application(_ application: UIApplication,
                            didReceiveRemoteNotification userInfo: [AnyHashable : Any],
                            fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
    print("[APNs] Received remote notification: \(userInfo)")
    completionHandler(.newData)
  }

  // Badge clearing is now controlled by Flutter (ChatProvider._updateAppBadge)
  // Do NOT clear badge/notifications here — user may not have read them yet
}
