import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var deviceToken: String?
  private var pendingTokenResult: FlutterResult?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Register push method channel
    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(name: "im.client/push", binaryMessenger: controller.binaryMessenger)
      channel.setMethodCallHandler { [weak self] (call, result) in
        if call.method == "getDeviceToken" {
          if let token = self?.deviceToken {
            result(token)
          } else {
            self?.pendingTokenResult = result
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
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
    // Resolve pending Flutter result
    if let pending = pendingTokenResult {
      pending(token)
      pendingTokenResult = nil
    }
  }

  override func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
    print("[APNs] Registration failed: \(error.localizedDescription)")
    if let pending = pendingTokenResult {
      pending(nil)
      pendingTokenResult = nil
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
