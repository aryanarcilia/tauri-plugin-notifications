import AppKit
import UserNotifications

#if ENABLE_PUSH_NOTIFICATIONS
  import FirebaseCore
  import FirebaseMessaging
#endif

extension FFIResult: Error {}

typealias JsonObject = [String: Any]

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

struct SetClickListenerActiveArgs: Decodable {
  let active: Bool
}

struct RemoveActiveNotification: Decodable {
  let id: Int
}

struct RemoveActiveArgs: Decodable {
  let notifications: [RemoveActiveNotification]
}

struct TopicSubscriptionArgs: Decodable {
  let topic: String
}

extension RustString {
  func decode<T: Decodable>(_ type: T.Type) throws(FFIResult) -> T {
    guard let data = self.toString().data(using: .utf8) else {
      throw FFIResult.Err(RustString("Invalid UTF-8 string"))
    }
    do {
      return try JSONDecoder().decode(type, from: data)
    } catch {
      throw FFIResult.Err(RustString("Failed to decode JSON: \(error.localizedDescription)"))
    }
  }
}

extension Encodable {
  func toJSONString() throws(FFIResult) -> String {
    do {
      let jsonData = try JSONEncoder().encode(self)
      guard let jsonString = String(data: jsonData, encoding: .utf8) else {
        throw FFIResult.Err(RustString("Failed to encode to JSON string"))
      }
      return jsonString
    } catch let error as FFIResult {
      throw error
    } catch {
      throw FFIResult.Err(RustString("Failed to encode to JSON: \(error.localizedDescription)"))
    }
  }
}

func showNotification(notification: Notification) async throws(FFIResult) -> UNNotificationRequest {
  var content: UNNotificationContent
  do {
    content = try makeNotificationContent(notification)
  } catch {
    throw FFIResult.Err(RustString(error.localizedDescription))
  }

  var trigger: UNNotificationTrigger?

  do {
    if let schedule = notification.schedule {
      try trigger = handleScheduledNotification(schedule)
    }
  } catch {
    throw FFIResult.Err(RustString(error.localizedDescription))
  }

  // Schedule the request.
  let request = UNNotificationRequest(
    identifier: "\(notification.id)", content: content, trigger: trigger
  )

  let center = UNUserNotificationCenter.current()
  do {
    try await center.add(request)
  } catch {
    throw FFIResult.Err(RustString(error.localizedDescription))
  }

  return request
}

class NotificationPlugin {
  let notificationHandler = NotificationHandler()
  let notificationManager = NotificationManager()

  #if ENABLE_PUSH_NOTIFICATIONS
    // Completion handler for push token registration
    private var pushTokenCompletion: ((Result<String, Error>) -> Void)?
    private let pushTokenTimeout: TimeInterval = 10.0
    private var pushTokenTimer: Timer?
    private var isFirebaseConfigured = false
    
    // Helper to detect if running on simulator (macOS doesn't have simulator, but keeping for consistency)
    private var isRunningOnSimulator: Bool {
      return false // macOS doesn't have simulator
    }
  #endif

  init() {
    notificationHandler.plugin = self
    notificationManager.notificationHandler = notificationHandler
    
    #if ENABLE_PUSH_NOTIFICATIONS
      // Configure Firebase - it will auto-swizzle AppDelegate methods
      if FirebaseApp.app() == nil {
        FirebaseApp.configure()
      }
      
      // Enable auto-init for automatic token handling
      Messaging.messaging().isAutoInitEnabled = true
      
      // Set delegate to receive FCM token updates
      Messaging.messaging().delegate = self
      
      isFirebaseConfigured = true
      
      // Register for remote notifications to enable FCM
      DispatchQueue.main.async {
        NSApplication.shared.registerForRemoteNotifications()
      }
    #endif
  }

  public func show(args: RustString) async throws(FFIResult) -> Int32 {
    let notification = try args.decode(Notification.self)

    let request = try await showNotification(notification: notification)
    notificationHandler.saveNotification(request.identifier, notification)
    return Int32(request.identifier) ?? -1
  }

  public func requestPermissions() async throws(FFIResult) -> String {
    do {
      let granted = try await notificationHandler.requestPermissions()
      let permissionState = granted ? "granted" : "denied"
      return "{\"permissionState\":\"\(permissionState)\"}"
    } catch {
      throw FFIResult.Err(RustString(error.localizedDescription))
    }
  }

  public func registerForPushNotifications() async throws(FFIResult) -> String {
    #if ENABLE_PUSH_NOTIFICATIONS
      // First request notification permissions
      let granted: Bool
      do {
        granted = try await notificationHandler.requestPermissions()
      } catch {
        throw FFIResult.Err(RustString("Failed to request notification permissions: \(error.localizedDescription)"))
      }

      guard granted else {
        throw FFIResult.Err(RustString("Notification permissions not granted"))
      }

      // Register and wait for token
      do {
        let token = try await withCheckedThrowingContinuation { continuation in
          self.registerForPushNotificationsWithCompletion { result in
            continuation.resume(with: result)
          }
        }
        return "{\"deviceToken\":\"\(token)\"}"
      } catch {
        throw FFIResult.Err(RustString(error.localizedDescription))
      }
    #else
      throw FFIResult.Err(RustString("Push notifications are disabled in this build"))
    #endif
  }

  public func unregisterForPushNotifications() throws(FFIResult) {
    #if ENABLE_PUSH_NOTIFICATIONS
      DispatchQueue.main.async {
        NSApplication.shared.unregisterForRemoteNotifications()
      }
    #else
      throw FFIResult.Err(RustString("Push notifications are disabled in this build"))
    #endif
  }

  public func checkPermissions() async throws(FFIResult) -> String {
    let settings = await notificationHandler.checkPermissions()
    let permission: String

    switch settings.authorizationStatus {
    case .authorized, .ephemeral, .provisional:
      permission = "granted"
    case .denied:
      permission = "denied"
    case .notDetermined:
      permission = "prompt"
    @unknown default:
      permission = "prompt"
    }

    return "{\"permissionState\":\"\(permission)\"}"
  }

  public func cancel(args: RustString) throws(FFIResult) {
    let args = try args.decode(CancelArgs.self)

    UNUserNotificationCenter.current().removePendingNotificationRequests(
      withIdentifiers: args.notifications.map { String($0) }
    )
  }

  public func cancelAll() throws(FFIResult) {
    UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
  }

  public func getPending() async throws(FFIResult) -> String {
    let notifications = await UNUserNotificationCenter.current().pendingNotificationRequests()

    let ret = notifications.compactMap({ [weak self] (notification) -> PendingNotification? in
      return self?.notificationHandler.toPendingNotification(notification)
    })

    return try ret.toJSONString()
  }

  public func registerActionTypes(args: RustString) throws(FFIResult) {
    let args = try args.decode(RegisterActionTypesArgs.self)
    makeCategories(args.types)
  }

  public func removeActive(args: RustString) throws(FFIResult) {
    let args = try args.decode(RemoveActiveArgs.self)
    UNUserNotificationCenter.current().removeDeliveredNotifications(
      withIdentifiers: args.notifications.map { String($0.id) })
  }

  public func removeAllActive() throws(FFIResult) {
    UNUserNotificationCenter.current().removeAllDeliveredNotifications()
    DispatchQueue.main.async {
      NSApp.dockTile.badgeLabel = nil
    }
  }

  public func getActive() async throws(FFIResult) -> String {
    let notifications = await UNUserNotificationCenter.current().deliveredNotifications()

    let ret = notifications.compactMap({ (notification) -> ActiveNotification? in
      return self.notificationHandler.toActiveNotification(notification.request)
    })

    return try ret.toJSONString()
  }

  public func setClickListenerActive(args: RustString) throws(FFIResult) {
    let args = try args.decode(SetClickListenerActiveArgs.self)
    notificationHandler.setClickListenerActive(args.active)
  }

  #if ENABLE_PUSH_NOTIFICATIONS
    private func registerForPushNotificationsWithCompletion(_ completion: @escaping (Result<String, Error>) -> Void)
    {
      // Store completion for later
      self.pushTokenCompletion = completion

      // Set up timeout
      self.pushTokenTimer?.invalidate()
      self.pushTokenTimer = Timer.scheduledTimer(withTimeInterval: pushTokenTimeout, repeats: false)
      { [weak self] _ in
        self?.handlePushTokenTimeout()
      }

      // Get FCM token
      Messaging.messaging().token { token, error in
        self.pushTokenTimer?.invalidate()
        self.pushTokenTimer = nil
        
        if let error = error {
          if let completion = self.pushTokenCompletion {
            self.pushTokenCompletion = nil
            completion(.failure(error))
          }
          return
        }
        
        if let token = token {
          if let completion = self.pushTokenCompletion {
            self.pushTokenCompletion = nil
            completion(.success(token))
          }
        }
      }
    }

    private func handlePushTokenTimeout() {
      pushTokenTimer?.invalidate()
      pushTokenTimer = nil

      if let completion = pushTokenCompletion {
        pushTokenCompletion = nil
        let error = NSError(
          domain: "NotificationPlugin",
          code: -1,
          userInfo: [NSLocalizedDescriptionKey: "Timeout waiting for FCM token"]
        )
        completion(.failure(error))
      }
    }
  #endif

  public func trigger<T: Encodable>(_ event: String, data: T) throws {
    let jsonData = try JSONEncoder().encode(data)
    guard let jsonString = String(data: jsonData, encoding: .utf8) else {
      throw NSError(
        domain: "NotificationPlugin", code: -1,
        userInfo: [NSLocalizedDescriptionKey: "Failed to encode data to JSON string"])
    }
    try bridgeTrigger(RustString(event), RustString(jsonString))
  }
}

#if ENABLE_PUSH_NOTIFICATIONS
  extension NotificationPlugin: MessagingDelegate {
    public func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
      // FCM token received - can be used for notifications
      print("FCM token: \(fcmToken ?? "nil")")
      
      // Token is now available for retrieval via Messaging.messaging().token()
    }
  }
#endif

// Initialize the plugin
func initPlugin() -> NotificationPlugin {
  return NotificationPlugin()
}
