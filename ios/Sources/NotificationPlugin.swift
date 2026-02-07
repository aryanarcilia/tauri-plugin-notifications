// Copyright 2019-2023 Tauri Programme within The Commons Conservancy
// SPDX-License-Identifier: Apache-2.0
// SPDX-License-Identifier: MIT

import SwiftRs
import Tauri
import UIKit
import UserNotifications
import WebKit

#if ENABLE_PUSH_NOTIFICATIONS
  import FirebaseCore
  import FirebaseMessaging
#endif

enum ShowNotificationError: LocalizedError {
  case make(Error)
  case create(Error)

  var errorDescription: String? {
    switch self {
    case .make(let error):
      return "Unable to make notification: \(error)"
    case .create(let error):
      return "Unable to create notification: \(error)"
    }
  }
}

enum ScheduleEveryKind: String, Codable {
  case year
  case month
  case twoWeeks
  case week
  case day
  case hour
  case minute
  case second
}

struct ScheduleInterval: Codable {
  var year: Int?
  var month: Int?
  var day: Int?
  var weekday: Int?
  var hour: Int?
  var minute: Int?
  var second: Int?
}

enum NotificationSchedule: Codable {
  case at(date: String, repeating: Bool)
  case interval(interval: ScheduleInterval)
  case every(interval: ScheduleEveryKind, count: Int)
}

struct NotificationAttachmentOptions: Codable {
  let iosUNNotificationAttachmentOptionsTypeHintKey: String?
  let iosUNNotificationAttachmentOptionsThumbnailHiddenKey: String?
  let iosUNNotificationAttachmentOptionsThumbnailClippingRectKey: String?
  let iosUNNotificationAttachmentOptionsThumbnailTimeKey: String?
}

struct NotificationAttachment: Codable {
  let id: String
  let url: String
  let options: NotificationAttachmentOptions?
}

struct Notification: Decodable {
  let id: Int
  var title: String
  var body: String?
  var extra: [String: String]?
  var schedule: NotificationSchedule?
  var attachments: [NotificationAttachment]?
  var sound: String?
  var group: String?
  var actionTypeId: String?
  var summary: String?
  var silent: Bool?
}

struct RemoveActiveNotification: Decodable {
  let id: Int
}

struct RemoveActiveArgs: Decodable {
  let notifications: [RemoveActiveNotification]
}

func showNotification(invoke: Invoke, notification: Notification)
  throws -> UNNotificationRequest
{
  var content: UNNotificationContent
  do {
    content = try makeNotificationContent(notification)
  } catch {
    throw ShowNotificationError.make(error)
  }

  var trigger: UNNotificationTrigger?

  do {
    if let schedule = notification.schedule {
      try trigger = handleScheduledNotification(schedule)
    }
  } catch {
    throw ShowNotificationError.create(error)
  }

  // Schedule the request.
  let request = UNNotificationRequest(
    identifier: "\(notification.id)", content: content, trigger: trigger
  )

  let center = UNUserNotificationCenter.current()
  center.add(request) { (error: Error?) in
    if let theError = error {
      invoke.reject(theError.localizedDescription)
    }
  }

  return request
}

struct CancelArgs: Decodable {
  let notifications: [Int]
}

struct Action: Decodable {
  let id: String
  let title: String
  var requiresAuthentication: Bool?
  var foreground: Bool?
  var destructive: Bool?
  var input: Bool?
  var inputButtonTitle: String?
  var inputPlaceholder: String?
}

struct ActionType: Decodable {
  let id: String
  let actions: [Action]
  var hiddenPreviewsBodyPlaceholder: String?
  var customDismissAction: Bool?
  var allowInCarPlay: Bool?
  var hiddenPreviewsShowTitle: Bool?
  var hiddenPreviewsShowSubtitle: Bool?
  var hiddenBodyPlaceholder: String?
}

struct RegisterActionTypesArgs: Decodable {
  let types: [ActionType]
}

struct BatchArgs: Decodable {
  let notifications: [Notification]
}

struct SetClickListenerActiveArgs: Decodable {
  let active: Bool
}

#if ENABLE_PUSH_NOTIFICATIONS
enum FirebaseState {
  case notConfigured
  case configuring
  case configured
  case ready
}
#endif

class NotificationPlugin: Plugin {
  let notificationHandler = NotificationHandler()
  let notificationManager = NotificationManager()

  #if ENABLE_PUSH_NOTIFICATIONS
    // Completion handler for push token registration
    private var pushTokenCompletion: ((Result<String, Error>) -> Void)?
    private let pushTokenTimeout: TimeInterval = 30.0
    private var pushTokenTimer: Timer?
    private var firebaseState: FirebaseState = .notConfigured
    
    private var pendingPushRegistrationInvoke: Invoke?
    
    // Cache for FCM token received early (before registration)
    private var cachedFCMToken: String?
    
    // Helper to detect if running on simulator
    private var isRunningOnSimulator: Bool {
      #if targetEnvironment(simulator)
        return true
      #else
        return false
      #endif
    }
  #endif

  override init() {
    super.init()
    notificationManager.notificationHandler = notificationHandler
    notificationHandler.plugin = self
  }

  public override func load(webview: WKWebView) {
    super.load(webview: webview)
    #if ENABLE_PUSH_NOTIFICATIONS
      // Store reference to this plugin for event triggering
      print("Setup Swizzler plugin reference")
      AppDelegateSwizzler.plugin = self

      // swizzle UIApplicationDelegate push methods
      AppDelegateSwizzler.swizzlePushCallbacks()
      // Firebase will be configured lazily when registerForPushNotifications() is called
      // This prevents auto-init from generating tokens before we're ready
      print("✅ NotificationPlugin loaded, Firebase will initialize on demand")
    #endif
  }

  @objc public func show(_ invoke: Invoke) throws {
    let notification = try invoke.parseArgs(Notification.self)

    let request = try showNotification(invoke: invoke, notification: notification)
    notificationHandler.saveNotification(request.identifier, notification)
    invoke.resolve(Int(request.identifier) ?? -1)
  }

  @objc public func batch(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(BatchArgs.self)
    var ids = [Int]()

    for notification in args.notifications {
      let request = try showNotification(invoke: invoke, notification: notification)
      notificationHandler.saveNotification(request.identifier, notification)
      ids.append(Int(request.identifier) ?? -1)
    }

    invoke.resolve(ids)
  }

  @objc public override func requestPermissions(_ invoke: Invoke) {
    notificationHandler.requestPermissions { granted, error in
      guard error == nil else {
        invoke.reject(error!.localizedDescription)
        return
      }

      let permissionState = granted ? "granted" : "denied"
      invoke.resolve(["permissionState": permissionState])
    }
  }

   @objc public func registerForPushNotifications(_ invoke: Invoke) {
    #if ENABLE_PUSH_NOTIFICATIONS
      // Check if we already have a cached token
      // First request notification permissions
      notificationHandler.requestPermissions { [weak self] granted, error in
        guard error == nil else {
          invoke.reject(error!.localizedDescription)
          return
        }
        print("✅ registerForPushNotifications")
        self?.registerForPushNotifications { result in
          switch result {
          case .success(let token):
            print("✅ registerForPushNotifications success")
            invoke.resolve(["deviceToken": token])
            // self?.trigger("push-token", data: ["token": token])
          case .failure(let error):
            print("✅ registerForPushNotifications err")
            invoke.reject(error.localizedDescription)
          }
        }
      }
    #else
      invoke.reject("Push notifications are disabled in this build")
    #endif
  }


  @objc public func unregisterForPushNotifications(_ invoke: Invoke) {
    #if ENABLE_PUSH_NOTIFICATIONS
      // Clear any pending registration (timer and completion)
      pushTokenTimer?.invalidate()
      pushTokenTimer = nil
      if let completion = pushTokenCompletion {
        pushTokenCompletion = nil
        let error = NSError(
          domain: "NotificationPlugin",
          code: -1,
          userInfo: [NSLocalizedDescriptionKey: "Registration cancelled by unregister"]
        )
        completion(.failure(error))
      }

      // Delete FCM token via Firebase completion API (same pattern as rest of plugin)
      Messaging.messaging().deleteToken { [weak self] error in
        DispatchQueue.main.async {
          if let error = error {
            invoke.reject("Failed to delete FCM token: \(error.localizedDescription)")
            return
          }
          self?.cachedFCMToken = nil
          UIApplication.shared.unregisterForRemoteNotifications()
          invoke.resolve()
        }
      }
    #else
      invoke.reject("Push notifications are disabled in this build")
    #endif
  }

  #if ENABLE_PUSH_NOTIFICATIONS
    private func ensureFirebaseReady(completion: @escaping (Bool) -> Void) {
      // Check current state
      switch firebaseState {
      case .ready:
        completion(true)
        return
      case .configuring:
        // Already configuring, wait and retry
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
          self?.ensureFirebaseReady(completion: completion)
        }
        return
      case .configured:
        // Already configured, just verify Messaging is accessible
        firebaseState = .ready
        completion(true)
        return
      case .notConfigured:
        // Need to configure
        firebaseState = .configuring
        
        DispatchQueue.main.async { [weak self] in
          guard let self = self else {
            completion(false)
            return
          }
          
          // Configure Firebase if needed
          if FirebaseApp.app() == nil {
            print("🔧 Configuring Firebase...")
            FirebaseApp.configure()
          }
          
          // Verify Firebase is configured
          guard FirebaseApp.app() != nil else {
            print("❌ Firebase configuration failed")
            self.firebaseState = .notConfigured
            completion(false)
            return
          }
          
          // Set delegate to receive FCM token updates
          Messaging.messaging().delegate = self
          
          // Give Firebase time to fully initialize
          DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self = self else {
              completion(false)
              return
            }
            
            self.firebaseState = .ready
            print("✅ Firebase ready")
            completion(true)
          }
        }
      }
    }
    
    private func registerForPushNotifications(completion: @escaping (Result<String, Error>) -> Void)
    {
      // Ensure Firebase is configured and ready before proceeding
      ensureFirebaseReady { [weak self] isReady in
        guard let self = self else {
          completion(.failure(NSError(
            domain: "NotificationPlugin",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Plugin deallocated"]
          )))
          return
        }
        
        guard isReady else {
          let error = NSError(
            domain: "NotificationPlugin",
            code: -1,
            userInfo: [NSLocalizedDescriptionKey: "Firebase failed to initialize"]
          )
          completion(.failure(error))
          return
        }
        
        print("✅ Firebase ready, proceeding with push registration")
        
        // Store completion for later (will be called when FCM token is received)
        self.pushTokenCompletion = completion
        
        // Set up timeout on main thread
        DispatchQueue.main.async { [weak self] in
          guard let self = self else { return }
          self.pushTokenTimer?.invalidate()
          self.pushTokenTimer = Timer.scheduledTimer(withTimeInterval: self.pushTokenTimeout, repeats: false)
          { [weak self] _ in
            print("⏱️ Token timeout triggered")
            self?.handlePushTokenTimeout()
          }
          
          // Register for remote notifications (will trigger APNs token callback)
          print("✅ Calling registerForRemoteNotifications")
          UIApplication.shared.registerForRemoteNotifications()
        }
      }
    }

    private func handlePushTokenTimeout() {
      print("⚠️ handlePushTokenTimeout called")
      pushTokenTimer?.invalidate()
      pushTokenTimer = nil

      if let completion = pushTokenCompletion {
        pushTokenCompletion = nil
        let error = NSError(
          domain: "NotificationPlugin",
          code: -1,
          userInfo: [NSLocalizedDescriptionKey: "Timeout waiting for device token"]
        )
        print("❌ Timeout error: \(error.localizedDescription)")
        completion(.failure(error))
      } else {
        print("⚠️ No completion handler to call")
      }
    }

    func handlePushTokenReceived(_ deviceToken: Data) {
      let token = deviceToken.map { String(format: "%02x", $0) }.joined()
      print("✅ handlePushTokenReceived (APNs) called with token: \(token)")
      print("✅ handlePushTokenReceived (APNs) called with deviceToken: \(deviceToken)")
      
      // Only set APNs token on physical device, not simulator
      #if !targetEnvironment(simulator)
        setAPNsToken(deviceToken, retryCount: 0)
      #else
        print("⚠️ Skipping APNs token assignment on simulator")
        // On simulator, we won't get FCM token, so return the APNs token hex
        handleFCMPushTokenReceived(token)
      #endif
    }
    
    private func setAPNsToken(_ deviceToken: Data, retryCount: Int) {
      // First ensure Firebase is ready
      ensureFirebaseReady { [weak self] isReady in
        guard let self = self else { return }
        
        guard isReady else {
          print("❌ Firebase not ready, cannot set APNs token")
          if retryCount < 3 {
            print("⚠️ Retrying Firebase initialization in 1s...")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
              self?.setAPNsToken(deviceToken, retryCount: retryCount + 1)
            }
          }
          return
        }
        
        // Verify Firebase app still exists
        guard FirebaseApp.app() != nil else {
          print("❌ Firebase app not configured")
          return
        }
        
        // Set APNs token with defensive checks
        DispatchQueue.main.async { [weak self] in
          guard let self = self else { return }
          
          // Defensive: verify Messaging instance is accessible
          let messaging = Messaging.messaging()
          
          // Try to set APNs token
          messaging.apnsToken = deviceToken
          print("✅ APNs token set to Firebase Messaging")
          
          // Request FCM token explicitly after APNs token is set
          messaging.token { token, error in
            if let error = error {
              print("❌ Error getting FCM token: \(error.localizedDescription)")
              self.handlePushTokenError(error)
            } else if let token = token {
              print("✅ FCM token retrieved after APNs token set: \(token)")
              self.handleFCMPushTokenReceived(token)
            } else {
              print("⚠️ No FCM token available yet")
            }
          }
        }
      }
    }

    func handleFCMPushTokenReceived(_ token: String) {
      print("✅ handleFCMPushTokenReceived called with token: \(token)")
      
      // Cache the token for later use
      cachedFCMToken = token
      print("✅ FCM token cached")
      
      pushTokenTimer?.invalidate()
      pushTokenTimer = nil

      if let completion = pushTokenCompletion {
        pushTokenCompletion = nil
        print("✅ Calling completion with token")
        completion(.success(token))
      } else {
        print("⚠️ No completion handler to call (token cached for later)")
      }
    }

    func handlePushTokenError(_ error: Error) {
      print("❌ handlePushTokenError called: \(error.localizedDescription)")
      pushTokenTimer?.invalidate()
      pushTokenTimer = nil

      if let completion = pushTokenCompletion {
        pushTokenCompletion = nil
        print("❌ Calling completion with error")
        completion(.failure(error))
      } else {
        print("⚠️ No completion handler to call")
      }
    }
  #endif


  @objc public override func checkPermissions(_ invoke: Invoke) {
    notificationHandler.checkPermissions { status in
      let permission: String

      switch status {
      case .authorized, .ephemeral, .provisional:
        permission = "granted"
      case .denied:
        permission = "denied"
      case .notDetermined:
        permission = "prompt"
      @unknown default:
        permission = "prompt"
      }

      invoke.resolve(["permissionState": permission])
    }
  }

  @objc func cancel(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(CancelArgs.self)

    UNUserNotificationCenter.current().removePendingNotificationRequests(
      withIdentifiers: args.notifications.map { String($0) }
    )
    invoke.resolve()
  }

  @objc func cancelAll(_ invoke: Invoke) {
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
    invoke.resolve()
  }

  @objc func getPending(_ invoke: Invoke) {
    UNUserNotificationCenter.current().getPendingNotificationRequests(completionHandler: {
      (notifications) in
      let ret = notifications.compactMap({ [weak self] (notification) -> PendingNotification? in
        return self?.notificationHandler.toPendingNotification(notification)
      })

      invoke.resolve(ret)
    })
  }

  @objc func registerActionTypes(_ invoke: Invoke) throws {
    let args = try invoke.parseArgs(RegisterActionTypesArgs.self)
    makeCategories(args.types)
    invoke.resolve()
  }

  @objc func removeActive(_ invoke: Invoke) {
    do {
      let args = try invoke.parseArgs(RemoveActiveArgs.self)
      UNUserNotificationCenter.current().removeDeliveredNotifications(
        withIdentifiers: args.notifications.map { String($0.id) })
      invoke.resolve()
    } catch {
      UNUserNotificationCenter.current().removeAllDeliveredNotifications()
      DispatchQueue.main.async(execute: {
        UIApplication.shared.applicationIconBadgeNumber = 0
      })
      invoke.resolve()
    }
  }

  @objc func getActive(_ invoke: Invoke) {
    UNUserNotificationCenter.current().getDeliveredNotifications(completionHandler: {
      (notifications) in
      let ret = notifications.compactMap({ (notification) -> ActiveNotification? in
        return self.notificationHandler.toActiveNotification(
          notification.request)
      })
      invoke.resolve(ret)
    })
  }

  @objc func setClickListenerActive(_ invoke: Invoke) {
    do {
      let args = try invoke.parseArgs(SetClickListenerActiveArgs.self)
      notificationHandler.setClickListenerActive(args.active)
      invoke.resolve()
    } catch {
      invoke.reject(error.localizedDescription)
    }
  }
}

#if ENABLE_PUSH_NOTIFICATIONS
extension NotificationPlugin: MessagingDelegate {
  // Called when FCM token is received or refreshed
  func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
    guard let token = fcmToken else {
      print("⚠️ Received nil FCM token")
      return
    }
    
    // Only process token if Firebase is in the correct state
    guard firebaseState == .ready else {
      print("⚠️ FCM token received but Firebase not ready (state: \(firebaseState)), ignoring")
      return
    }
    
    print("✅ FCM Token received: \(token)")
    handleFCMPushTokenReceived(token)
  }
}
#endif

@_cdecl("init_plugin_notification")
func initPlugin() -> Plugin {
  return NotificationPlugin()
}