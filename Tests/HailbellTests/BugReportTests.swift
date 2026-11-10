import UIKit
import XCTest
@testable import Hailbell

/// Shake to report: the screens a report carries, the details it sends, the sheet it opens and the
/// screenshot it uploads.
@MainActor
final class BugReportTests: XCTestCase {
    private var presented: [UIViewController] = []
    private var saved: (present: (UIViewController, UIViewController) -> Void, top: () -> UIViewController?, capture: () -> UIImage?)?

    override func setUp() async throws {
        let hailbell = Hailbell.shared
        saved = (hailbell.present, hailbell.topViewController, hailbell.captureScreen)
        let root = UIViewController()
        hailbell.topViewController = { root }
        hailbell.present = { [weak self] sheet, _ in self?.presented.append(sheet) }
        hailbell.captureScreen = { Self.image(points: CGSize(width: 40, height: 80), scale: 2) }
        hailbell.screens.reset()
    }

    override func tearDown() async throws {
        let hailbell = Hailbell.shared
        if let saved { hailbell.present = saved.present; hailbell.topViewController = saved.top; hailbell.captureScreen = saved.capture }
        hailbell.reportSheet = nil
        hailbell.screens.reset()
        Hailbell.shakeToReport = false
        presented = []
    }

    // MARK: screens

    func testTrackScreenKeepsTheLastTen() {
        for i in 1...12 { Hailbell.trackScreen("Screen \(i)") }
        XCTAssertEqual(Hailbell.shared.screens.names, (3...12).map { "Screen \($0)" })
    }

    func testTrackScreenSkipsEmptyNamesAndRepeatsInARow() {
        Hailbell.trackScreen("Home")
        Hailbell.trackScreen("  Home ")
        Hailbell.trackScreen("")
        Hailbell.trackScreen("   ")
        Hailbell.trackScreen("Settings")
        Hailbell.trackScreen("Home")
        XCTAssertEqual(Hailbell.shared.screens.names, ["Home", "Settings", "Home"])
    }

    // MARK: details

    func testReportDetailsHasEveryField() {
        let report = Hailbell.reportDetails(info: ["CFBundleShortVersionString": "2.3", "CFBundleVersion": "45"],
                                            device: "iPhone17,2", systemVersion: "27.2", locale: "en_US",
                                            screens: ["Home", "Paywall"])
        XCTAssertEqual(Set(report.keys), ["appVersion", "build", "device", "os", "locale", "screens"])
        XCTAssertEqual(report["appVersion"] as? String, "2.3")
        XCTAssertEqual(report["build"] as? String, "45")
        XCTAssertEqual(report["device"] as? String, "iPhone17,2")
        XCTAssertEqual(report["os"] as? String, "iOS 27.2")
        XCTAssertEqual(report["locale"] as? String, "en_US")
        XCTAssertEqual(report["screens"] as? [String], ["Home", "Paywall"])
        XCTAssertTrue(JSONSerialization.isValidJSONObject(report))
    }

    func testReportDetailsCarriesTrackedScreens() {
        Hailbell.trackScreen("Settings")
        XCTAssertEqual(Hailbell.shared.reportDetails()["screens"] as? [String], ["Settings"])
    }

    // MARK: messages

    func testMessageDecodesWithAndWithoutReport() throws {
        let plain = try JSONDecoder().decode(Message.self, from: Data(#"{"id":"m1","author":"user","body":"Hi","createdAt":1}"#.utf8))
        XCTAssertNil(plain.report)

        let json = #"{"id":"m2","author":"user","body":"","createdAt":2,"report":{"appVersion":"2.3","build":"45","device":"iPhone17,2","deviceName":"iPhone 16 Pro Max","os":"iOS 27.2","locale":"en_US","screens":["Home","Settings"]}}"#
        let report = try XCTUnwrap(try JSONDecoder().decode(Message.self, from: Data(json.utf8)).report)
        XCTAssertEqual(report.appVersion, "2.3")
        XCTAssertEqual(report.build, "45")
        XCTAssertEqual(report.device, "iPhone17,2")
        XCTAssertEqual(report.deviceName, "iPhone 16 Pro Max")
        XCTAssertEqual(report.os, "iOS 27.2")
        XCTAssertEqual(report.locale, "en_US")
        XCTAssertEqual(report.screens, ["Home", "Settings"])

        // A partial report still decodes, and survives the offline copy.
        let partial = try JSONDecoder().decode(Message.self, from: Data(#"{"id":"m3","author":"user","createdAt":3,"report":{"os":"iOS 27.2"}}"#.utf8))
        let again = try JSONDecoder().decode(Message.self, from: JSONEncoder().encode(partial))
        XCTAssertEqual(again.report?.os, "iOS 27.2")
        XCTAssertNil(again.report?.appVersion)
    }

    // MARK: sheet

    func testReportBugPresentsOneSheetWithTheScreenshot() throws {
        Hailbell.reportBug()
        XCTAssertEqual(presented.count, 1)
        let host = try XCTUnwrap(presented.first as? ReportHostingController)
        XCTAssertNotNil(host.rootView.screenshot)

        // A second shake while it is up doesn't stack another.
        Hailbell.reportBug()
        XCTAssertEqual(presented.count, 1, "a second report screen was stacked")
    }

    func testShakingTheWindowOpensTheReportOnlyWhenTurnedOn() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 100, height: 100))
        Hailbell.shakeToReport = true
        XCTAssertTrue(ShakeDetector.installed)
        window.motionEnded(.motionShake, with: nil)
        XCTAssertEqual(presented.count, 1)

        Hailbell.shared.reportSheet = nil
        window.motionEnded(.remoteControlPlay, with: nil)
        XCTAssertEqual(presented.count, 1, "a motion that isn't a shake opened the report")

        Hailbell.shakeToReport = false
        window.motionEnded(.motionShake, with: nil)
        XCTAssertEqual(presented.count, 1, "a shake opened the report while it was off")

        // Other responders still have UIResponder's own method.
        UIView().motionEnded(.motionShake, with: nil)
        XCTAssertEqual(presented.count, 1)
    }

    // MARK: screenshot

    func testScreenshotJPEGKeepsTheLongSideWithinTheLimit() throws {
        // A 3x screenshot: 1206 x 2622 pixels.
        let shot = Self.image(points: CGSize(width: 402, height: 874), scale: 3)
        let jpeg = try XCTUnwrap(shot.chatJPEG())
        XCTAssertLessThanOrEqual(max(jpeg.width, jpeg.height), 1600)
        XCTAssertEqual(jpeg.height, 1600)
        XCTAssertLessThan(jpeg.data.count, 1_500_000)

        // A small image keeps its pixel size.
        let small = try XCTUnwrap(Self.image(points: CGSize(width: 100, height: 50), scale: 2).chatJPEG())
        XCTAssertEqual(small.width, 200)
        XCTAssertEqual(small.height, 100)
    }

    func testMarkupDrawsIntoTheScreenshotAtItsSize() {
        let shot = Self.image(points: CGSize(width: 40, height: 80), scale: 2)
        XCTAssertTrue(MarkupStroke.flatten(shot, []) === shot)
        let marked = MarkupStroke.flatten(shot, [MarkupStroke(points: [CGPoint(x: 5, y: 5), CGPoint(x: 30, y: 60)], width: 4)])
        XCTAssertEqual(marked.size, shot.size)
        XCTAssertEqual(marked.scale, shot.scale)
        XCTAssertNotEqual(marked.pngData(), shot.pngData())
    }

    func testFitCentresThePicture() {
        let rect = MarkupView.fit(CGSize(width: 100, height: 200), in: CGSize(width: 300, height: 300))
        XCTAssertEqual(rect, CGRect(x: 75, y: 0, width: 150, height: 300))
    }

    private static func image(points: CGSize, scale: CGFloat) -> UIImage {
        let format = UIGraphicsImageRendererFormat.default()
        format.scale = scale
        return UIGraphicsImageRenderer(size: points, format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: points))
        }
    }
}
