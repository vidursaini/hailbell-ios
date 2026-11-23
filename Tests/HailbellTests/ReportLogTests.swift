import XCTest
@testable import Hailbell

/// The log lines and failed requests a bug report carries: what is kept, how much, and the secrets
/// removed before anything is kept. The cases match test/bug-report-logs.test.js on the server.
final class ReportLogTests: XCTestCase {
    override func setUp() { ReportLog.shared.reset() }
    override func tearDown() { ReportLog.shared.reset() }

    func testURLsLoseQueryStringsLoginsAndSecretLookingParts() {
        let cases: [(String, String)] = [
            ("https://user:pw@API.Example.com/v1/receipts?token=abc&user=bob#top", "https://api.example.com/v1/receipts"),
            ("https://api.example.com/v1/items/12345", "https://api.example.com/v1/items/12345"),
            ("https://api.example.com/users/bob@example.com/profile", "https://api.example.com/users/:redacted/profile"),
            ("https://api.example.com/users/bob%40example.com", "https://api.example.com/users/:redacted"),
            ("https://api.example.com/u/550e8400-e29b-41d4-a716-446655440000/orders", "https://api.example.com/u/:redacted/orders"),
            ("https://api.example.com/verify/eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln", "https://api.example.com/verify/:redacted"),
            ("https://api.example.com/files/9f86d081884c7d659a2feaa0c55ad015a3bf4f1b2b0b822cd15d6c15b0f00a08", "https://api.example.com/files/:redacted"),
            ("https://api.example.com/reset/Zx81kdh2", "https://api.example.com/reset/:redacted"),
            ("https://api.example.com/keys/sk_live_abcdefghijklmnop1234", "https://api.example.com/keys/:redacted"),
            ("https://api.example.com/password/forgot", "https://api.example.com/password/forgot"),
            ("https://api.example.com/call/+1 (415) 555-0100-2000", "https://api.example.com/call/:redacted"),
            ("https://api.example.com/v1/receipt;jsessionid=ABC123", "https://api.example.com/v1/receipt"),
            ("/v1/restore?receipt=MIIT", "/v1/restore"),
            ("https://api.example.com", "https://api.example.com"),
        ]
        for (raw, want) in cases { XCTAssertEqual(Redact.url(raw), want, raw) }
        XCTAssertNil(Redact.url("  "))
        XCTAssertNil(Redact.url("https://@/x"))
        XCTAssertFalse(Redact.secretSegment("pro_yearly_2026"))
    }

    func testLogLinesHideSecretsAndKeepTheRest() {
        let cases: [(String, String)] = [
            ("restore failed: 422 for sku pro_yearly", "restore failed: 422 for sku pro_yearly"),
            ("POST https://api.example.com/v1/receipt?key=abc failed", "POST https://api.example.com/v1/receipt failed"),
            ("Authorization: Bearer abc.def.ghi", "Authorization: [redacted]"),
            ("sent with Bearer abcdef123456", "sent with Bearer [redacted]"),
            ("login password=hunter2 user=bob", "login password=[redacted] user=bob"),
            (#"{"apiKey":"abc123", "n":1}"#, #"{"apiKey":[redacted], "n":1}"#),
            ("x-api-key: zzz", "x-api-key: [redacted]"),
            ("refresh_token=abc&next=1", "refresh_token=[redacted]&next=1"),
            ("pin=1234", "pin=[redacted]"),
            ("jwt eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.c2ln here", "jwt [redacted] here"),
            ("key a1b2c3d4e5f6a1b2c3d4e5f6a1b2c3d4e5f6 used", "key [redacted] used"),
            ("shipping: 3 items", "shipping: 3 items"),
            ("monkey=3", "monkey=3"),
            ("  two\n lines\t here ", "two lines here"),
        ]
        for (raw, want) in cases { XCTAssertEqual(Redact.line(raw), want, raw) }
        XCTAssertNil(Redact.line(" \n "))
        XCTAssertEqual(Redact.line(String(repeating: "x", count: 1000))?.count, 300)
    }

    func testKeepsTheLast50LinesAndTheLast10FailedRequests() {
        for i in 0..<60 { Hailbell.log("line \(i)") }
        for i in 0..<14 { Hailbell.logRequest(method: "post", url: "https://api.example.com/r/\(i)?secret=1", status: 500) }
        Hailbell.logRequest(method: "GET", url: "https://api.example.com/ok", status: 200)
        Hailbell.logRequest(method: "GET", url: URL(string: "https://api.example.com/offline"), status: 0)
        let (logs, requests) = ReportLog.shared.snapshot()
        XCTAssertEqual(logs.count, 50)
        XCTAssertEqual(logs.first?["m"] as? String, "line 10")
        XCTAssertEqual(requests.count, 10)
        XCTAssertEqual(requests.last?["url"] as? String, "https://api.example.com/offline")
        XCTAssertEqual(requests.last?["status"] as? Int, 0)
        XCTAssertEqual(requests.first?["method"] as? String, "POST")
        XCTAssertEqual(requests.first?["url"] as? String, "https://api.example.com/r/5")
        XCTAssertFalse(requests.contains { ($0["url"] as? String)?.hasSuffix("/ok") == true }, "a request that worked was kept")
    }

    func testURLSessionRequestsCountOnlyWhenTheyFail() throws {
        var request = URLRequest(url: try XCTUnwrap(URL(string: "https://api.example.com/v1/receipt?sig=x")))
        request.httpMethod = "POST"
        let failed = HTTPURLResponse(url: request.url!, statusCode: 422, httpVersion: nil, headerFields: nil)
        let worked = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)
        Hailbell.logRequest(request, response: worked, error: nil)
        Hailbell.logRequest(request, response: nil, error: URLError(.cancelled))
        Hailbell.logRequest(request, response: failed, error: nil)
        Hailbell.logRequest(request, response: nil, error: URLError(.notConnectedToInternet))
        let requests = ReportLog.shared.snapshot().requests
        XCTAssertEqual(requests.map { $0["status"] as? Int }, [422, 0])
        XCTAssertEqual(requests.first?["url"] as? String, "https://api.example.com/v1/receipt")
        XCTAssertEqual(Set(requests[0].keys), ["t", "method", "url", "status"], "never bodies or headers")
    }

    func testReportDetailsCarryTheLogOnlyWhenThereIsOne() {
        let empty = Hailbell.reportDetails(info: [:], device: "iPhone17,2", systemVersion: "27.2", locale: "en_US", screens: [])
        XCTAssertNil(empty["logs"])
        XCTAssertNil(empty["requests"])
        Hailbell.log("Restore tapped")
        Hailbell.logRequest(method: "POST", url: "https://api.example.com/v1/receipt", status: 422)
        let report = Hailbell.reportDetails(info: [:], device: "iPhone17,2", systemVersion: "27.2", locale: "en_US", screens: [],
                                            log: ReportLog.shared.snapshot())
        XCTAssertEqual((report["logs"] as? [[String: Any]])?.first?["m"] as? String, "Restore tapped")
        XCTAssertEqual((report["requests"] as? [[String: Any]])?.first?["status"] as? Int, 422)
        XCTAssertTrue(JSONSerialization.isValidJSONObject(report))
    }

    func testABugReportRequestCardIsShownWithoutALink() throws {
        let card = try JSONDecoder().decode(Card.self, from: Data(#"{"type":"report","button":"Send a bug report","state":"sent"}"#.utf8))
        XCTAssertTrue(card.isShown)
        let unknown = try JSONDecoder().decode(Card.self, from: Data(#"{"type":"poll","button":"Vote","state":"sent"}"#.utf8))
        XCTAssertFalse(unknown.isShown)
    }
}
