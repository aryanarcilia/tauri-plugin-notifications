# iOS Push Notifications Integration Guide

## Required: Add to Your App's AppDelegate

To enable push notifications, you **must** add the following code to your Tauri app's `AppDelegate.swift` file.

### Location

In your Tauri iOS app, find or create: `src-tauri/gen/apple/YourAppName_iOS/YourAppName_iOS/AppDelegate.swift`

### Required Code

Add these imports at the top:

```swift
import UIKit
#if ENABLE_PUSH_NOTIFICATIONS
  import FirebaseMessaging
#endif
```

Add these methods to your `AppDelegate` class:

```swift
#if ENABLE_PUSH_NOTIFICATIONS
  // MARK: - Remote Notifications (APNS)

  /// Called when APNS registration succeeds
  func application(
    _ application: UIApplication,
    didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
  ) {
    // Pass token to Firebase
    Messaging.messaging().apnsToken = deviceToken

    // Notify plugin via NotificationCenter
    NotificationCenter.default.post(
      name: NSNotification.Name("APNSTokenReceived"),
      object: nil,
      userInfo: ["deviceToken": deviceToken]
    )
  }

  /// Called when APNS registration fails
  func application(
    _ application: UIApplication,
    didFailToRegisterForRemoteNotificationsWithError error: Error
  ) {
    // Notify plugin about error
    NotificationCenter.default.post(
      name: NSNotification.Name("APNSTokenError"),
      object: nil,
      userInfo: ["error": error]
    )
  }
#endif
```

### Complete Example

Here's a complete example of what your `AppDelegate.swift` should look like:

```swift
import UIKit
import Tauri
#if ENABLE_PUSH_NOTIFICATIONS
  import FirebaseMessaging
#endif

class AppDelegate: UIResponder, UIApplicationDelegate {

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return true
  }

  #if ENABLE_PUSH_NOTIFICATIONS
    // MARK: - Remote Notifications (APNS)

    func application(
      _ application: UIApplication,
      didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
      // Pass token to Firebase
      Messaging.messaging().apnsToken = deviceToken

      // Notify plugin via NotificationCenter
      NotificationCenter.default.post(
        name: NSNotification.Name("APNSTokenReceived"),
        object: nil,
        userInfo: ["deviceToken": deviceToken]
      )
    }

    func application(
      _ application: UIApplication,
      didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
      // Notify plugin about error
      NotificationCenter.default.post(
        name: NSNotification.Name("APNSTokenError"),
        object: nil,
        userInfo: ["error": error]
      )
    }
  #endif
}
```

## How It Works

1. Your JavaScript calls `registerForPushNotifications()`
2. Plugin requests permissions and calls `UIApplication.shared.registerForRemoteNotifications()`
3. iOS contacts APNS and returns token to **AppDelegate** (not Plugin)
4. AppDelegate posts `NSNotification` with token
5. Plugin receives notification and continues FCM token flow
6. FCM token is returned to JavaScript

## Troubleshooting

If you don't add this code to AppDelegate:

- ❌ APNS token will never reach the plugin
- ❌ FCM token request will timeout after 10 seconds
- ❌ `registerForPushNotifications()` will reject with error

## Testing

After adding the code, test with:

```typescript
import { registerForPushNotifications } from "@choochmeque/tauri-plugin-notifications-api";

try {
  const token = await registerForPushNotifications();
  console.log("✅ FCM Token:", token);
} catch (error) {
  console.error("❌ Registration failed:", error);
}
```

Expected console output:

```
✅ APNS Device Token received: <hex_string>
✅ APNS Token set to Firebase Messaging
🔥 FCM Token registered: <fcm_token>
```
