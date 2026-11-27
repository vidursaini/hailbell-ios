# Hailbell for iOS

In-app support chat and push notifications for iOS 16 and later. Customers write from a native chat screen inside your app; you answer from the [Hailbell](https://hailbell.com) dashboard, Discord or Telegram, and your reply reaches them live or as a push notification.

When the support AI hands a chat to your team while nobody is around, the chat shows a reply time card saying when to expect a reply, in the customer's own time, with a button to turn on notifications. The card arrived in 1.3.0; earlier versions show the same words as a normal message.

This package has two libraries:

- **Hailbell**: the chat screen, identity, signals and push. Add it to the app.
- **HailbellNotificationService**: images, buttons, badge increments and delivery receipts for Hailbell's push campaigns. Add it to a Notification Service Extension, never to the app.

## Install

In Xcode, choose **File > Add Package Dependencies...**, enter

```
https://github.com/vidursaini/hailbell-ios
```

and pick **Up to Next Major Version** from `1.2.0`. Or in `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/vidursaini/hailbell-ios", from: "1.2.0"),
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

When the AI hands a chat to you while nobody is around, the chat shows a reply time card instead of a plain message: "Vidur is offline right now. Usually back by **11:30 PM tonight**, your time.", worked out on the phone in the customer's own time zone and clock format, with a "Notify me when Vidur replies" button that turns on notifications. Turn it on or off in the dashboard's AI replies settings. Older SDK versions show the same words as a normal message.

The full guide, with entry points, signed-in users, offers, App Store privacy answers and a checklist, is at [hailbell.com/docs](https://hailbell.com/docs). AI coding agents can install the Hailbell skill from `https://hailbell.com/skills/hailbell/SKILL.md`.

## Hailbell

| API | Use |
| --- | --- |
| `Hailbell.configure(appId:baseURL:)` | Call once at launch, before anything else. |
| `Hailbell.shared.open()` | Presents the chat as a full-height sheet over the top-most view controller. |
| `HailbellChatView()` | The chat as a SwiftUI view, to place it yourself. |
| `Hailbell.shared.unreadCount` | `@Published` replies not yet read; use it for a badge. |
| `Hailbell.teamPhoto: UIImage?` | Deprecated: set the photo in the dashboard. A bundled photo shows only until the chat hears from Hailbell, and never once the dashboard signs replies as the team, turns photos off or sets a photo for this app. |
| `Hailbell.identify(userId:name:email:identityToken:)` | Who the user is. Only `identityToken`, an HS256 JWT signed with the app's identity secret, links the chat across devices. |
| `Hailbell.identify(name:email:firebaseIdToken:)` | For apps on Firebase Auth: pass `{ try await Auth.auth().currentUser?.getIDToken() }`. Hailbell verifies the token, uses the Firebase uid as the user id, and links the chat across devices without a backend of your own. Set the Firebase project in the dashboard's push settings. |
| `Hailbell.asksForNotifications` | Default true. After the first message, the chat offers to turn on notifications if they're off. Set false if your app asks itself. The reply time card's "Notify me" button shows either way, since the customer taps it. |
| `Hailbell.darkMode` | Default nil, which follows the phone. Set true for an always-dark app so the chat matches it. |
| `Hailbell.setMetadata(_:)` | Context shown beside the chat, merged with what you sent before. `appVersion`, `os` and `locale` are sent automatically. Set `superwallUserId` or `revenueCatUserId` to match purchases. |
| `Hailbell.track(_:properties:)` | A signal shown beside the chat, such as `paywall_decline` or `chat_opened`. |
| `Hailbell.setPaywallPlacements(_:)` | The placements an offer can open. |
| `Hailbell.onPaywall` | `(placement, purchased) -> Void`: open the paywall, and call `purchased()` if they buy. |
| `Hailbell.setPushToken(_:sandbox:)` | The APNs token. The environment is read from the build's provisioning profile. |
| `Hailbell.handleNotification(_:) -> Bool` | Opens the chat for a tapped reply push (`userInfo["hailbell"]`). |
| `Hailbell.reset()` | On sign-out: clears the identity and the cached chat. |
| `Hailbell.deleteData() async throws` | Deletes the user's chat, images and details from Hailbell. |
| `Hailbell.shakeToReport` | Default false. When true, shaking the phone opens the report screen. |
| `Hailbell.trackScreen(_:)` | Notes the screen the user is on. A bug report carries the last 10. |
| `Hailbell.reportBug()` | Opens the report screen, for a "Report a problem" button. |
| `Hailbell.log(_:)` | 1.2.0. Keeps a line for the next bug report. The last 50 stay in memory on the phone. |
| `Hailbell.logRequest(_:response:error:)` | 1.2.0. Call after a URLSession call; records it only if it failed (status 400 or more, or no answer). A bug report carries the last 10. |
| `Hailbell.logRequest(method:url:status:)` | 1.2.0. Records a failed request by hand. |

`Message`, `Attachment`, `Card` and `ReportDetails` are public, for apps that read the conversation.

## Bug reports

```swift
Hailbell.shakeToReport = true          // shake the phone to report a problem
Hailbell.trackScreen("Settings")       // call as screens appear
Hailbell.reportBug()                   // or open it from a "Report a problem" button
```

The report screen opens with a screenshot of what was on screen. The user can mark it up with a red pen, remove it, and say what went wrong. Send posts it with the app version and build, the device model, the iOS version, the locale and the last 10 screens from `trackScreen`.

It lands in the normal chat inbox as a message from that user, tagged as a bug report, and the dashboard's Bugs filter lists only reports. Replies go back to the chat like any other. There is no session replay: nothing is captured or sent until the user taps Send, and the screen names stay in memory until then.

### The app's log and failed requests (1.2.0)

```swift
Hailbell.log("Restore tapped")                                   // a line you want in the next report

do {
    let (data, response) = try await URLSession.shared.data(for: request)
    Hailbell.logRequest(request, response: response, error: nil) // kept only if it failed
} catch {
    Hailbell.logRequest(request, response: nil, error: error)    // no answer: offline, timed out
    throw error
}

Hailbell.logRequest(method: "POST", url: url, status: 422)       // or by hand
```

Both are opt-in. The SDK doesn't read the console or watch the network by itself. It keeps the last 50 log lines and the last 10 failed requests in memory, and sends them only with a bug report the user chooses to send. A failed request is one with status 400 or more, or no answer, and it keeps the method, address, status code and time, never bodies or headers. Before anything leaves the phone, addresses lose their query strings and secret-looking parts (emails, tokens, keys, long ids, JWTs, phone numbers) become `:redacted`, and passwords, tokens, API keys and Bearer values in log lines become `[redacted]`. Hailbell's server applies the same rules again.

The dashboard shows them under the report, next to the customer's plan and purchases. The customer's own chat doesn't show them.

### Asking for a report

A teammate can ask for a report from the dashboard (**Ask for bug report**), with `!bugreport` in Discord or Telegram, or with the **Ask for a bug report** button in Slack. The AI can add the same request to its reply when a customer describes a bug. In SDK 1.2.0 and later the message has a **Send a bug report** button that opens the report screen, where the user can also add a screenshot from their photos. Older SDKs show the message as text.

## Edited and deleted replies

Your team can edit or delete a reply after sending it (dashboard). The chat shows the new wording, with "Edited" under it when the customer had already read the old one, and "This message was deleted" in place of a deleted reply, in the customer's language. Both arrived in 1.4.0; earlier versions show the new wording without the label, and a deleted reply as that line in English. `Message.edited` and `Message.deleted` carry the two flags. Nothing to set up.

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
| `BugReport.swift` | Shake to report, the report screen and the screenshot markup |
| `ChatTheme.swift`, `Glass.swift` | Colours from the dashboard's Chat design, Liquid Glass on iOS 26 with fallbacks |
| `L10n.swift` | The chat's own words in 14 languages |
| `Push.swift` | `Hailbell.push` |
| `PrivacyInfo.xcprivacy` | The privacy manifest Xcode merges into the app's report |

## Support and license

Questions: hello@hailbell.com, or the chat on [hailbell.com](https://hailbell.com).

MIT. See [LICENSE](LICENSE).
