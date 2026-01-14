[![NPM Version](https://img.shields.io/npm/v/@choochmeque%2Ftauri-plugin-notifications-api)](https://www.npmjs.com/package/@choochmeque/tauri-plugin-notifications-api)
[![Crates.io Version](https://img.shields.io/crates/v/tauri-plugin-notifications)](https://crates.io/crates/tauri-plugin-notifications)
[![Tests](https://github.com/Choochmeque/tauri-plugin-notifications/actions/workflows/tests.yml/badge.svg)](https://github.com/Choochmeque/tauri-plugin-notifications/actions/workflows/tests.yml)
[![codecov](https://codecov.io/gh/Choochmeque/tauri-plugin-notifications/branch/main/graph/badge.svg)](https://codecov.io/gh/Choochmeque/tauri-plugin-notifications)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

# Tauri Plugin Notifications

A Tauri v2 plugin for sending notifications on desktop and mobile platforms. Send toast notifications (brief auto-expiring OS window elements) with support for rich content, scheduling, actions, channels, and push delivery via FCM and APNs.

## Features

- Send simple and rich notifications
- Schedule notifications for specific dates or recurring intervals
- Interactive notifications with custom actions
- Notification channels (Android) for organized notifications
- Manage pending and active notifications
- Support for attachments, icons, and custom sounds
- Inbox and large text notification styles
- Group notifications with summary support
- Permission management
- Real-time notification events

## Platform Support

- **macOS**: Native notification center integration
- **Windows**: Windows notification system
- **Linux**: notify-rust with desktop notification support
- **iOS**: User Notifications framework
- **Android**: Android notification system with channels

## Installation

Install the JavaScript package:

```bash
npm install @choochmeque/tauri-plugin-notifications-api
# or
yarn add @choochmeque/tauri-plugin-notifications-api
# or
pnpm add @choochmeque/tauri-plugin-notifications-api
```

Add the plugin to your Tauri project's `Cargo.toml`:

```toml
[dependencies]
tauri-plugin-notifications = "0.3"
```

### Push Notifications Feature

The `push-notifications` feature is **disabled by default**. To enable push notifications support:

```toml
[dependencies]
tauri-plugin-notifications = { version = "0.3", features = ["push-notifications"] }
```

This enables:

- Firebase Cloud Messaging (FCM) support on iOS/macOS and Android
- Push notification registration and token management
- Topic subscription for group messaging

**Important Changes:**

- **iOS/macOS now use FCM** instead of direct APNS integration
- FCM uses APNS as the transport layer but provides unified API
- Requires `GoogleService-Info.plist` configuration (see Platform Setup)
- FCM tokens replace APNS device tokens

**Note:** Push notifications require proper Firebase setup on mobile platforms. See Platform Setup section for detailed configuration instructions.

Without this feature enabled:

- Firebase dependencies are not included in builds
- Push notification registration code is disabled
- The `registerForPushNotifications()` function will return an error if called

Configure the plugin permissions in your `capabilities/default.json`:

```json
{
  "permissions": ["notifications:default"]
}
```

Register the plugin in your Tauri app:

```rust
fn main() {
    tauri::Builder::default()
        .plugin(tauri_plugin_notifications::init())
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
```

## Example App

An example app is available in [`examples/notifications-demo`](examples/notifications-demo) demonstrating all plugin features:

- Permission management and push notifications (mobile)
- Basic, scheduled, and styled notifications
- Interactive notifications with action buttons
- Notification channels (Android)
- Pending and active notification management
- Event listeners with logging

**Run it:**

```bash
cd examples/notifications-demo
pnpm install
pnpm tauri dev
```

## Usage

### JavaScript/TypeScript

#### Basic Notifications

```typescript
import {
  isPermissionGranted,
  requestPermission,
  sendNotification,
} from "@choochmeque/tauri-plugin-notifications-api";

// Check and request permission
let permissionGranted = await isPermissionGranted();
if (!permissionGranted) {
  const permission = await requestPermission();
  permissionGranted = permission === "granted";
}

// Send simple notification
if (permissionGranted) {
  sendNotification("Hello from Tauri!");

  // Or with more details
  sendNotification({
    title: "TAURI",
    body: "Tauri is awesome!",
  });
}
```

#### Rich Notifications

```typescript
import { sendNotification } from "@choochmeque/tauri-plugin-notifications-api";

// Notification with icon and sound
await sendNotification({
  id: 1,
  title: "New Message",
  body: "You have a new message from John",
  icon: "message_icon",
  sound: "notification_sound",
  autoCancel: true,
});

// Large text notification
await sendNotification({
  id: 2,
  title: "Article",
  body: "New article available",
  largeBody:
    "This is a much longer text that will be displayed when the user expands the notification...",
  summary: "Read more",
});

// Inbox style notification
await sendNotification({
  id: 3,
  title: "Email",
  body: "3 new emails",
  inboxLines: [
    "Alice: Meeting at 3pm",
    "Bob: Project update",
    "Charlie: Lunch tomorrow?",
  ],
});
```

#### Scheduled Notifications

```typescript
import {
  sendNotification,
  Schedule,
} from "@choochmeque/tauri-plugin-notifications-api";

// Schedule notification for specific date
await sendNotification({
  title: "Reminder",
  body: "Time for your meeting!",
  schedule: Schedule.at(new Date(2024, 0, 15, 14, 30)),
});

// Repeating notification
await sendNotification({
  title: "Daily Reminder",
  body: "Don't forget to exercise!",
  schedule: Schedule.at(new Date(2024, 0, 15, 9, 0), true),
});

// Schedule with interval
await sendNotification({
  title: "Break Time",
  body: "Time to take a break!",
  schedule: Schedule.interval({
    hour: 1,
  }),
});

// Schedule every X units
import { ScheduleEvery } from "@choochmeque/tauri-plugin-notifications-api";

await sendNotification({
  title: "Hourly Update",
  body: "Checking in every hour",
  schedule: Schedule.every(ScheduleEvery.Hour, 1),
});
```

#### Interactive Notifications with Actions

```typescript
import {
  sendNotification,
  registerActionTypes,
  onAction,
} from "@choochmeque/tauri-plugin-notifications-api";

// Register action types
await registerActionTypes([
  {
    id: "message-actions",
    actions: [
      {
        id: "reply",
        title: "Reply",
        input: true,
        inputPlaceholder: "Type your reply...",
        inputButtonTitle: "Send",
      },
      {
        id: "mark-read",
        title: "Mark as Read",
      },
      {
        id: "delete",
        title: "Delete",
        destructive: true,
      },
    ],
  },
]);

// Send notification with actions
await sendNotification({
  title: "New Message",
  body: "You have a new message",
  actionTypeId: "message-actions",
});

// Listen for action events
const unlisten = await onAction((notification) => {
  console.log("Action performed on notification:", notification);
});

// Stop listening
unlisten();
```

#### Notification Channels (Android)

```typescript
import {
  createChannel,
  channels,
  removeChannel,
  Importance,
  Visibility,
} from "@choochmeque/tauri-plugin-notifications-api";

// Create a notification channel
await createChannel({
  id: "messages",
  name: "Messages",
  description: "Notifications for new messages",
  importance: Importance.High,
  visibility: Visibility.Private,
  sound: "message_sound",
  vibration: true,
  lights: true,
  lightColor: "#FF0000",
});

// Send notification to specific channel
await sendNotification({
  channelId: "messages",
  title: "New Message",
  body: "You have a new message",
});

// List all channels
const channelList = await channels();

// Remove a channel
await removeChannel("messages");
```

#### Managing Notifications

```typescript
import {
  pending,
  active,
  cancel,
  cancelAll,
  removeActive,
  removeAllActive,
} from "@choochmeque/tauri-plugin-notifications-api";

// Get pending notifications
const pendingNotifications = await pending();

// Cancel specific pending notifications
await cancel([1, 2, 3]);

// Cancel all pending notifications
await cancelAll();

// Get active notifications
const activeNotifications = await active();

// Remove specific active notifications
await removeActive([{ id: 1 }, { id: 2, tag: "message" }]);

// Remove all active notifications
await removeAllActive();
```

#### Notification Events

```typescript
import { onNotificationReceived } from "@choochmeque/tauri-plugin-notifications-api";

// Listen for notifications received
const unlisten = await onNotificationReceived((notification) => {
  console.log("Notification received:", notification);
});

// Stop listening
unlisten();
```

#### Push Notifications (Mobile)

```typescript
import { registerForPushNotifications } from "@choochmeque/tauri-plugin-notifications-api";

// Register for push notifications and get device token
try {
  const token = await registerForPushNotifications();
  console.log("Push token:", token);
  // Send this token to your server to send push notifications
} catch (error) {
  console.error("Failed to register for push notifications:", error);
}
```

### Rust

```rust
use tauri_plugin_notifications::{NotificationsExt, Schedule, ScheduleEvery};

// Send simple notification
app.notifications()
    .builder()
    .title("Hello")
    .body("This is a notification from Rust!")
    .show()?;

// Send rich notification
app.notifications()
    .builder()
    .id(1)
    .title("New Message")
    .body("You have a new message")
    .icon("message_icon")
    .sound("notification_sound")
    .auto_cancel()
    .show()?;

// Scheduled notification
app.notifications()
    .builder()
    .title("Reminder")
    .body("Time for your meeting!")
    .schedule(Schedule::at(date_time, false, false))
    .show()?;

// Notification with attachments
use tauri_plugin_notifications::Attachment;

app.notifications()
    .builder()
    .title("Photo Shared")
    .body("Check out this image!")
    .attachment(Attachment {
        id: "image1".to_string(),
        url: "file:///path/to/image.jpg".to_string(),
    })
    .show()?;
```

## API Reference

### `isPermissionGranted()`

Checks if the permission to send notifications is granted.

**Returns:** `Promise<boolean>`

### `requestPermission()`

Requests the permission to send notifications.

**Returns:** `Promise<'granted' | 'denied' | 'default'>`

### `registerForPushNotifications()`

Registers the app for push notifications using Firebase Cloud Messaging (FCM). This method:

- On iOS/macOS: Requests notification permissions and retrieves FCM token
- On Android: Retrieves the FCM device token

The FCM token should be sent to your backend server for sending targeted push notifications.

**Note:** Requires the `push-notifications` feature and proper Firebase configuration (see Platform Setup).

**Returns:** `Promise<string>` - The FCM device token

**Example:**

```typescript
try {
  const fcmToken = await registerForPushNotifications();
  console.log("FCM Token:", fcmToken);
  // Send token to your backend
  await fetch("https://your-api.com/register-device", {
    method: "POST",
    body: JSON.stringify({ token: fcmToken }),
  });
} catch (error) {
  console.error("Failed to register:", error);
}
```

### `sendNotification(options: Options | string)`

Sends a notification to the user. Can be called with a simple string for the title or with a detailed options object.

**Parameters:**

- `options`: Notification options or title string
  - `id`: Notification identifier (32-bit integer)
  - `channelId`: Channel identifier (Android)
  - `title`: Notification title
  - `body`: Notification body
  - `schedule`: Schedule for delayed or recurring notifications
  - `largeBody`: Multiline text content
  - `summary`: Detail text for large notifications
  - `actionTypeId`: Action type identifier
  - `group`: Group identifier
  - `groupSummary`: Mark as group summary (Android)
  - `sound`: Sound resource name
  - `inboxLines`: Array of lines for inbox style (max 5)
  - `icon`: Notification icon
  - `largeIcon`: Large icon (Android)
  - `iconColor`: Icon color (Android)
  - `attachments`: Array of attachments
  - `extra`: Extra payload data
  - `ongoing`: Non-dismissible notification (Android)
  - `autoCancel`: Auto-cancel on click
  - `silent`: Silent notification (iOS)
  - `visibility`: Notification visibility
  - `number`: Number of items (Android)

### `registerActionTypes(types: ActionType[])`

Register actions that are performed when the user clicks on the notification.

**Parameters:**

- `types`: Array of action type objects with:
  - `id`: Action type identifier
  - `actions`: Array of action objects
    - `id`: Action identifier
    - `title`: Action title
    - `requiresAuthentication`: Requires device unlock
    - `foreground`: Opens app in foreground
    - `destructive`: Destructive action style
    - `input`: Enable text input
    - `inputButtonTitle`: Input button label
    - `inputPlaceholder`: Input placeholder text

### `pending()`

Retrieves the list of pending notifications.

**Returns:** `Promise<PendingNotification[]>`

### `cancel(notifications: number[])`

Cancels the pending notifications with the given list of identifiers.

### `cancelAll()`

Cancels all pending notifications.

### `active()`

Retrieves the list of active notifications.

**Returns:** `Promise<ActiveNotification[]>`

### `removeActive(notifications: Array<{ id: number; tag?: string }>)`

Removes the active notifications with the given list of identifiers.

### `removeAllActive()`

Removes all active notifications.

### `createChannel(channel: Channel)`

Creates a notification channel (Android).

**Parameters:**

- `channel`: Channel configuration
  - `id`: Channel identifier
  - `name`: Channel name
  - `description`: Channel description
  - `sound`: Sound resource name
  - `lights`: Enable notification light
  - `lightColor`: Light color
  - `vibration`: Enable vibration
  - `importance`: Importance level (None, Min, Low, Default, High)
  - `visibility`: Visibility level (Secret, Private, Public)

### `removeChannel(id: string)`

Removes the channel with the given identifier.

### `channels()`

Retrieves the list of notification channels.

**Returns:** `Promise<Channel[]>`

### `onNotificationReceived(callback: (notification: Options) => void)`

Listens for notification received events.

**Returns:** `Promise<PluginListener>` with `unlisten()` method

### `onAction(callback: (notification: Options) => void)`

Listens for notification action performed events.

**Returns:** `Promise<PluginListener>` with `unlisten()` method

## Platform Differences

### Desktop (macOS, Windows, Linux)

- Uses native notification systems
- Actions support varies by platform
- Limited scheduling capabilities on some platforms
- Channels not applicable (Android-specific)

### iOS

- Requires permission request
- Rich notifications with attachments
- Action support with input options
- Silent notifications available
- Group notifications (thread identifiers)

### Android

- Notification channels required for Android 8.0+
- Full scheduling support
- Rich notification styles (inbox, large text)
- Ongoing notifications for background tasks
- Detailed importance and visibility controls
- Custom sounds, vibration, and lights

## Platform Setup

### iOS Setup

1. The plugin automatically configures notification capabilities
2. Add notification sounds to your Xcode project if needed:
   - Add sound files to your iOS project
   - Place in app bundle
   - Reference by filename (without extension)

#### Firebase Cloud Messaging Setup for iOS/macOS

This plugin now uses **Firebase Cloud Messaging (FCM)** instead of APNS directly for push notifications on iOS and macOS. Follow these steps to configure FCM:

##### 1. Create Firebase Project

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Create a new project or select an existing one
3. Add an iOS app to your project
   - Bundle ID must match your Tauri app's bundle identifier (found in `src-tauri/tauri.conf.json` under `identifier`)
4. Download the `GoogleService-Info.plist` file

##### 2. Add GoogleService-Info.plist to Your Project

Place the `GoogleService-Info.plist` file in your iOS project:

```bash
# Copy to iOS project root
cp GoogleService-Info.plist gen/apple/
```

Or add it through Xcode:

1. Open your project in Xcode (`gen/apple/YourApp.xcodeproj`)
2. Drag `GoogleService-Info.plist` into the project navigator
3. Ensure "Copy items if needed" and your app target are selected

**Note:** Firebase automatically handles APNS token registration via method swizzling. No additional AppDelegate configuration is required.

##### 3. Add Required Linker Flag

**IMPORTANT:** Add `-ObjC` linker flag to your Xcode project:

1. Open your project in Xcode (`gen/apple/YourApp.xcodeproj`)
2. Select your app target
3. Go to **Build Settings** → Search for "Other Linker Flags"
4. Add `-ObjC` to **Other Linker Flags**

This flag is required for Firebase to load Objective-C categories. Without it, you'll see crashes like:

```
+[NSError messagingErrorWithCode:failureReason:]: unrecognized selector sent to class
```

##### 4. Configure APNS with Firebase

- Enable "Apple Push Notifications service (APNs)"
- Download the `.p8` file (keep it safe!)
- Note the Key ID

2. **Upload to Firebase Console**:
   - In Firebase Console, go to Project Settings → Cloud Messaging
   - Under "Apple app configuration", click "Upload"
   - Upload your `.p8` file
   - Enter your Key ID and Team ID (from Apple Developer)

##### 5. Enable Push Notifications Feature

Ensure you have the `push-notifications` feature enabled in your `Cargo.toml`:

```toml
[dependencies]
tauri-plugin-notifications = { version = "0.3", features = ["push-notifications"] }
```

##### 6. Request Push Notification Permissions

```typescript
import {
  registerForPushNotifications,
  subscribeToTopic,
  onNotificationReceived,
} from "@choochmeque/tauri-plugin-notifications-api";

// Register for push notifications and get FCM token
try {
  const fcmToken = await registerForPushNotifications();
  console.log("FCM Token:", fcmToken);

  // Send this token to your backend server
  await sendTokenToServer(fcmToken);

  // Optional: Subscribe to topics for targeted messaging
  await subscribeToTopic("news-updates");
  await subscribeToTopic("promotions");
} catch (error) {
  console.error("Failed to register for push notifications:", error);
}

// Listen for incoming notifications
const unlisten = await onNotificationReceived((notification) => {
  console.log("Received notification:", notification);
});
```

##### 7. Sending Test Notifications

You can send test notifications from Firebase Console:

1. Go to Cloud Messaging → Send your first message
2. Enter notification title and text
3. Select your iOS app
4. Click "Send test message" or "Review" → "Publish"

##### macOS Support

The same Firebase setup applies to macOS, but note:

- macOS FCM support is less mature than iOS
- The app must run from a signed `.app` bundle (not during `tauri dev`)
- For development, consider using APNS sandbox certificates

##### Migration from APNS

If you previously used direct APNS integration:

- **FCM tokens** replace APNS device tokens
- The `registerForPushNotifications()` API remains the same but now returns FCM tokens
- Update your backend to send notifications via Firebase API instead of APNS directly
- Events (`push-token`, `push-message`, `notificationClicked`) remain compatible

##### Troubleshooting

**"GoogleService-Info.plist not found" error:**

- Ensure the file is in your iOS project root or properly added in Xcode
- Rebuild the project after adding the file

**"Failed to register for push notifications" error:**

- Verify APNS auth key is uploaded to Firebase Console
- Check that bundle ID matches between Firebase Console and app
- Ensure push notification capability is enabled in Xcode

**Notifications not arriving:**

- Verify FCM token is sent to your backend
- Check Firebase Console for delivery status
- Ensure APNS certificates/keys are valid
- Test with Firebase Console test messages first

### Android Setup

1. The plugin automatically includes required permissions
2. For custom sounds:
   - Place sound files in `res/raw/` folder
   - Reference by filename (without extension)
3. For custom icons:
   - Place icons in `res/drawable/` folder
   - Reference by filename (without extension)
4. **For push notifications (FCM)** - These steps must be done in your Tauri app project:
   - Create a Firebase project at [Firebase Console](https://console.firebase.google.com/)
   - Download the `google-services.json` file from Firebase Console
   - Place `google-services.json` in your Tauri app's `gen/android/app/` directory
   - Add the Google Services classpath to your app's `gen/android/build.gradle.kts`:
     ```kotlin
     buildscript {
         repositories {
             google()
             mavenCentral()
         }
         dependencies {
             classpath("com.google.gms:google-services:4.4.2")
         }
     }
     ```
   - Apply the plugin at the bottom of `gen/android/app/build.gradle.kts`:
     ```kotlin
     apply(plugin = "com.google.gms.google-services")
     ```
   - The notification plugin already includes the Firebase Cloud Messaging dependency when the `push-notifications` feature is enabled

## Testing

### Desktop

- Notifications appear in the system notification center
- Test different notification types and interactions
- Verify notification persistence and dismissal

### iOS

- Test on physical devices (simulator support is limited)
- Request permissions before sending notifications
- Test scheduled notifications with different intervals
- Verify action handling and notification grouping

### Android

- Create and test notification channels
- Test different importance levels and visibility settings
- Verify scheduled notifications work with device sleep
- Test ongoing notifications for background tasks
- Verify notification styles (inbox, large text, etc.)

## Troubleshooting

### Notifications not appearing

- Verify permissions are granted
- On Android, ensure notification channel exists
- Check system notification settings
- Verify notification ID is unique

### Scheduled notifications not firing

- Check device power settings (battery optimization)
- On Android, use `allowWhileIdle` for critical notifications
- Verify schedule time is in the future

### Actions not working

- Ensure action types are registered before sending notification
- Verify action IDs match between registration and handling
- Check platform-specific action support

## License

[MIT](LICENSE)
