import UIKit
import Tauri
import ObjectiveC.runtime

#if ENABLE_PUSH_NOTIFICATIONS

enum AppDelegateSwizzler {
  static weak var plugin: NotificationPlugin?
  
  // Track which methods were actually swizzled vs added
  private static var swizzledSelectors: Set<Selector> = []

  static func swizzlePushCallbacks() {
    guard let app = UIApplication.shared as UIApplication?,
          let delegate = app.delegate else { return }
    
    let delegateClass = type(of: delegate)

    // didRegisterForRemoteNotificationsWithDeviceToken
    swizzle(
      delegateClass,
      #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)),
      #selector(PushForwarder.ta_application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
    )

    // didFailToRegisterForRemoteNotificationsWithError
    swizzle(
      delegateClass,
      #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:)),
      #selector(PushForwarder.ta_application(_:didFailToRegisterForRemoteNotificationsWithError:))
    )

    // didReceiveRemoteNotification (silent/background)
    swizzle(
      delegateClass,
      #selector(UIApplicationDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:)),
      #selector(PushForwarder.ta_application(_:didReceiveRemoteNotification:fetchCompletionHandler:))
    )
  }

  private static func swizzle(_ cls: AnyClass, _ original: Selector, _ replacement: Selector) {
    guard
      let swizzledMethod = class_getInstanceMethod(PushForwarder.self, replacement)
    else { return }

    if let originalMethod = class_getInstanceMethod(cls, original) {
      // Original method exists - exchange implementations
      method_exchangeImplementations(originalMethod, swizzledMethod)
      swizzledSelectors.insert(original)
    } else {
      // Original method doesn't exist - add our method
      class_addMethod(
        cls,
        original,
        method_getImplementation(swizzledMethod),
        method_getTypeEncoding(swizzledMethod)
      )
    }
  }
  
  static func wasSwizzled(_ selector: Selector) -> Bool {
    return swizzledSelectors.contains(selector)
  }
}

/// A helper that hosts the swizzled implementations.
/// NOTE: These method names must exactly match the selectors we swizzle.
final class PushForwarder: NSObject, UIApplicationDelegate {
  // Token success
  @objc func ta_application(_ application: UIApplication,
                            didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
    // Notify plugin about token
    AppDelegateSwizzler.plugin?.handlePushTokenReceived(deviceToken)

    // Call original implementation if it was swizzled (implementations were exchanged)
    let selector = #selector(UIApplicationDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:))
    if AppDelegateSwizzler.wasSwizzled(selector) {
      // This will now call the original implementation since methods were swapped
      self.ta_application(application, didRegisterForRemoteNotificationsWithDeviceToken: deviceToken)
    }
  }

  // Token failure
  @objc func ta_application(_ application: UIApplication,
                            didFailToRegisterForRemoteNotificationsWithError error: Error) {
    // Notify plugin about error
    AppDelegateSwizzler.plugin?.handlePushTokenError(error)

    // Emit event for JS/Rust listeners
    try? AppDelegateSwizzler.plugin?.trigger("push-error", data: ["message": error.localizedDescription])

    // Call original implementation if it was swizzled
    let selector = #selector(UIApplicationDelegate.application(_:didFailToRegisterForRemoteNotificationsWithError:))
    if AppDelegateSwizzler.wasSwizzled(selector) {
      self.ta_application(application, didFailToRegisterForRemoteNotificationsWithError: error)
    }
  }

  // Background/remote (silent) payloads
  @objc func ta_application(_ application: UIApplication,
                            didReceiveRemoteNotification userInfo: [AnyHashable : Any],
                            fetchCompletionHandler completion: @escaping (UIBackgroundFetchResult) -> Void) {
    // Emit event for push message
    if let jsData = JSTypes.coerceDictionaryToJSObject(userInfo) {
      try? AppDelegateSwizzler.plugin?.trigger("push-message", data: jsData)
    }

    // Call original implementation if it was swizzled
    let selector = #selector(UIApplicationDelegate.application(_:didReceiveRemoteNotification:fetchCompletionHandler:))
    if AppDelegateSwizzler.wasSwizzled(selector) {
      self.ta_application(application, didReceiveRemoteNotification: userInfo, fetchCompletionHandler: completion)
    } else {
      // If no original implementation existed, call completion with noData
      completion(.noData)
    }
  }
}

#endif
