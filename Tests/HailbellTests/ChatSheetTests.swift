import UIKit
import XCTest
@testable import Hailbell

/// The chat is open, the person goes to the home screen, a reply arrives and they tap it.
/// The tap must bring back the chat they had open, not present a second chat on top of it.
@MainActor
final class ChatSheetTests: XCTestCase {
    private var presented: [UIViewController] = []
    private var saved: (present: (UIViewController, UIViewController) -> Void, top: () -> UIViewController?)?

    override func setUp() async throws {
        let hailbell = Hailbell.shared
        saved = (hailbell.present, hailbell.topViewController)
        let root = UIViewController()
        hailbell.topViewController = { root }
        hailbell.present = { [weak self] sheet, _ in self?.presented.append(sheet) }
    }

    override func tearDown() async throws {
        Hailbell.shared.chat.disappeared()
        if let saved { Hailbell.shared.present = saved.present; Hailbell.shared.topViewController = saved.top }
        presented = []
    }

    func testTappingAReplyWithTheChatOpenDoesNotStackASecondChat() {
        Hailbell.shared.open()
        XCTAssertEqual(presented.count, 1)
        Hailbell.shared.chat.appeared()  // the sheet's ChatView is on screen

        // The app went to the background with the chat open, then the reply was tapped.
        NotificationCenter.default.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        NotificationCenter.default.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        XCTAssertTrue(Hailbell.handleNotification(["hailbell": ["conversationId": "c1"]]))
        XCTAssertEqual(presented.count, 1, "a reply tap stacked a second chat")
    }

    func testTappingAReplyAfterClosingTheChatOpensIt() {
        Hailbell.shared.open()
        Hailbell.shared.chat.appeared()
        Hailbell.shared.chat.disappeared()  // closed the sheet
        XCTAssertTrue(Hailbell.handleNotification(["hailbell": ["conversationId": "c1"]]))
        XCTAssertEqual(presented.count, 2)
    }
}
