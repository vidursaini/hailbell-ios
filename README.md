# Hailbell for iOS

In-app support chat and push notifications for iOS 16 and later. Customers write from a native chat screen inside your app; you answer from the [Hailbell](https://hailbell.com) dashboard, Discord or Telegram, and your reply reaches them live or as a push notification.

This package has two libraries:

- **Hailbell**: the chat screen, identity, signals and push. Add it to the app.
- **HailbellNotificationService**: images, buttons, badge increments and delivery receipts for Hailbell's push campaigns. Add it to a Notification Service Extension, never to the app.

## Install

In Xcode, choose **File > Add Package Dependencies...**, enter

```
https://github.com/vidursaini/hailbell-ios
```

and pick **Up to Next Major Version** from `1.0.0`. Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/vidursaini/hailbell-ios", from: "1.0.0"),
],
targets: [
    .target(name: "MyApp", dependencies: [.product(name: "Hailbell", package: "hailbell-ios")]),
]
```

The repository is public, so Xcode Cloud and other CI fetch it with no extra access.

## Quick start

1. Create an app at [app.hailbell.com](https://app.hailbell.com) with platform iOS and your bundle ID. Copy its **App ID** (`app_...`). The App ID is public and belongs in your code.
2. Configure once at launch, then open the chat from a button:

```swift
import Hailbell

// application(_:didFinishLaunchingWithOptions:)
Hailbell.configure(appId: "app_XXXXXXXX")
Hailbell.setMetadata(["plan": "free"])     // shown beside the chat in the dashboard

// A "Chat with us" button
Hailbell.shared.open()                     // or place HailbellChatView() yourself
```

3. For replies as push notifications, add the Push Notifications capability and pass the token:

```swift
func application(_ app: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken token: Data) {
    Hailbell.setPushToken(token)           // sandbox or production is read from the build
}

@MainActor func userNotificationCenter(_ c: UNUserNotificationCenter, didReceive r: UNNotificationResponse) async {
    if Hailbell.push.handle(r) { return }                                     // campaign pushes
    Hailbell.handleNotification(r.notification.request.content.userInfo)     // chat replies
}
```

4. On sign-out call `Hailbell.reset()`. When a user deletes their account, call `try await Hailbell.deleteData()`.

The full guide, with entry points, signed-in users, offers, App Store privacy answers and a checklist, is at [hailbell.com/docs](https://hailbell.com/docs). AI coding agents can install the Hailbell skill from `https://hailbell.com/skills/hailbell/SKILL.md`.

## Hailbell

| API | Use |
| --- | --- |
| `Hailbell.configure(appId:baseURL:)` | Call once at launch, before anything else. |
| `Hailbell.shared.open()` | Presents the chat as a full-height sheet over the top-most view controller. |
| `HailbellChatView()` | The chat as a SwiftUI view, to place it yourself. |
| `Hailbell.shared.unreadCount` | `@Published` replies not yet read; use it for a badge. |
| `Hailbell.teamPhoto: UIImage?` | A photo bundled in the app for the chat header. Without it, the dashboard photo loads. |
| `Hailbell.identify(userId:name:email:identityToken:)` | Who the user is. Only `identityToken`, an HS256 JWT signed with the app's identity secret, links the chat across devices. |
| `Hailbell.identify(name:email:firebaseIdToken:)` | For apps on Firebase Auth: pass `{ try await Auth.auth().currentUser?.getIDToken() }`. Hailbell verifies the token, uses the Firebase uid as the user id, and links the chat across devices without a backend of your own. Set the Firebase project in the dashboard's push settings. |
| `Hailbell.asksForNotifications` | Default true. After the first message, the chat offers to turn on notifications if they're off. Set false if your app asks itself. |
| `Hailbell.darkMode` | Default nil, which follows the phone. Set true for an always-dark app so the chat matches it. |
| `Hailbell.setMetadata(_:)` | Context shown beside the chat, merged with what you sent before. `appVersion`, `os` and `locale` are sent automatically. Set `superwallUserId` or `revenueCatUserId` to match purchases. |
| `Hailbell.track(_:properties:)` | A signal shown beside the chat, such as `paywall_decline` or `chat_opened`. |
| `Hailbell.setPaywallPlacements(_:)` | The placements an offer can open. |
| `Hailbell.onPaywall` | `(placement, purchased) -> Void`: open the paywall, and call `purchased()` if they buy. |
| `Hailbell.setPushToken(_:sandbox:)` | The APNs token. The environment is read from the build's provisioning profile. |
| `Hailbell.handleNotification(_:) -> Bool` | Opens the chat for a tapped reply push (`userInfo["hailbell"]`). |
| `Hailbell.reset()` | On sign-out: clears the identity and the cached chat. |
| `Hailbell.deleteData() async throws` | Deletes the user's chat, images and details from Hailbell. |

`Message`, `Attachment` and `Card` are public, for apps that read the conversation.

## Hailbell.push

Hailbell's own push notifications, sent from the dashboard, the REST API or an AI agent over MCP:

| API | Use |
| --- | --- |
| `requestPermission(provisional:) async -> Bool` | Asks, then registers with APNs. |
| `permission` | The current `UNAuthorizationStatus`. |
| `setTags(_:)` | Key/value data for segments and `{{tag.x}}`; `nil` removes a tag. |
| `setMarketing(_:)` / `optOut()` | Promotional opt-in, or stop all pushes to this device. The marketing choice is saved and sent with every subscribe, so a new token keeps it. New devices start opted out. |
| `handle(_ response:) -> Bool` | Opens a tapped Hailbell push's link, or hands it to `onOpen`. |
| `handle(userInfo:actionIdentifier:) -> Bool` | The same, from the payload, for push libraries that pass on `userInfo` rather than the response (React Native, Flutter). |
| `onOpen: ((HailbellNotification) -> Bool)?` | Route deep links yourself, and return true when handled. |
| `clearBadge(appGroup:)` | Resets the badge kept by the service extension. |

## HailbellNotificationService

Add a Notification Service Extension target in Xcode, link **HailbellNotificationService** to it, and make its class:

```swift
import HailbellNotificationService
final class NotificationService: HailbellNotificationService {
    override var appGroup: String? { "group.com.example.app" }   // only for badge increments
}
```

It adds images and buttons, handles badge increments and sends delivery receipts. Other pushes pass through untouched. Set `HailbellAPI` in the extension's Info.plist to point at another server.

## Requirements

- iOS 16 or later, Swift 5.9 or later.
- On iOS 26 the composer and buttons use Liquid Glass; below that they use flat fills in the theme's colours.
- No third-party dependencies.
- Each library carries its own `PrivacyInfo.xcprivacy`, which Xcode merges into the app's privacy report.

## Files

| File | What it holds |
| --- | --- |
| `Hailbell.swift` | Public entry point, session and retry, sheet presentation |
| `Client.swift` | HTTP and WebSocket client, install id in the Keychain, public models |
| `ChatModel.swift` | Chat state: cache, paging, sending, uploads, ticks, typing, presence, cards |
| `ChatView.swift`, `MessageRow.swift`, `Composer.swift` | The chat UI: header, bubbles and cards, composer |
| `ChatTheme.swift`, `Glass.swift` | Colours from the dashboard's Chat design, Liquid Glass on iOS 26 with fallbacks |
| `L10n.swift` | The chat's own words in 14 languages |
| `Push.swift` | `Hailbell.push` |
| `PrivacyInfo.xcprivacy` | The privacy manifest Xcode merges into the app's report |

## Support and license

Questions: hello@hailbell.com, or the chat on [hailbell.com](https://hailbell.com).

MIT. See [LICENSE](LICENSE).
