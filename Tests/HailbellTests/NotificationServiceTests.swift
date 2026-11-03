import UserNotifications
import XCTest
import HailbellNotificationService

final class NotificationServiceTests: XCTestCase {
    /// An app's own pushes (no "hb" key) reach the user exactly as sent, with no network call.
    func testOtherPushesPassThroughUnchanged() {
        let content = UNMutableNotificationContent()
        content.title = "Your daily verse"
        content.userInfo = ["type": "daily_verse", "hailbell": ["conversationId": "c1"]]
        let request = UNNotificationRequest(identifier: "own", content: content, trigger: nil)
        var delivered: UNNotificationContent?
        HailbellNotificationService().didReceive(request) { delivered = $0 }
        XCTAssertTrue(delivered === request.content)
    }
}
