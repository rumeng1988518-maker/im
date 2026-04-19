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
    // Register push method channel
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "im.client/push", binaryMessenger: controller.binaryMessenger)
      self.pushChannel = channel
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
    }

    // Request notification permission and register
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

  override func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    let token = deviceToken.map { String(format: "%02.2hhx", $0) }.joined()
    self.deviceToken = token
    print("[APNs] Device token: \(token)")
    // Resolve pending Flutter result
    if let pending = pendingTokenResult {
      pending(token)
      pendingTokenResult = nil
    }
    // Proactively notify Flutter when token arrives (even if no pending request)
    pushChannel?.invokeMethod("onTokenReceived", arguments: token)
  }

  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("[APNs] Registration failed: \(error.localizedDescription)")
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

  // Clear badge when app becomes active
  override func applicationDidBecomeActive(_ application: UIApplication) {
    application.applicationIconBadgeNumber = 0
    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
