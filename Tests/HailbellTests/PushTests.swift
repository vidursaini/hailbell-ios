import UserNotifications
import XCTest
@testable import Hailbell

@MainActor
final class PushTests: XCTestCase {
    override func setUp() {
        UserDefaults.standard.removeObject(forKey: "hailbell.push.marketing")
    }

    func testMarketingChoiceSurvivesARelaunch() {
        XCTAssertNil(Hailbell.push.marketing)
        Hailbell.push.setMarketing(true)
        XCTAssertEqual(UserDefaults.standard.object(forKey: "hailbell.push.marketing") as? Bool, true)
        Hailbell.push.setMarketing(false)
        XCTAssertEqual(Hailbell.push.marketing, false)
    }

    func testCampaignPayloadParses() throws {
        let note = try XCTUnwrap(HailbellNotification(userInfo: ["hb": [
            "n": "ntf_1", "u": "myapp://offer", "s": "sub_1", "v": "a",
            "b": [["id": "b1", "text": "Open", "url": "https://example.com"]],
        ]]))
        XCTAssertEqual(note.id, "ntf_1")
        XCTAssertEqual(note.url?.absoluteString, "myapp://offer")
        XCTAssertEqual(note.buttons.first?.url?.host, "example.com")
        XCTAssertEqual(note.ping as? [String: String], ["n": "ntf_1", "s": "sub_1", "v": "a"])
    }

    func testChatRepliesAndOtherPushesAreNotCampaigns() {
        XCTAssertNil(HailbellNotification(userInfo: ["hailbell": ["conversationId": "c1"]]))
        XCTAssertNil(HailbellNotification(userInfo: ["aps": ["alert": "Daily verse"]]))
        XCTAssertNil(HailbellNotification(userInfo: ["hb": ["u": "https://example.com"]]))
    }

    func testHandlingAPayloadIgnoresOtherPushes() {
        XCTAssertFalse(Hailbell.push.handle(userInfo: ["hailbell": ["conversationId": "c1"]]))
        XCTAssertFalse(Hailbell.push.handle(userInfo: ["aps": ["alert": "Daily verse"]], actionIdentifier: "b1"))
    }
}
