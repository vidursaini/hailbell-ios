import Foundation

/// The app's last log lines (`Hailbell.log`) and failed network requests (`Hailbell.logRequest`),
/// kept in memory on the phone and sent only with a bug report the user chooses to send. Secret-looking
/// parts are removed as each one is recorded, so they never reach the report at all.
final class ReportLog: @unchecked Sendable {
    static let shared = ReportLog()
    static let maxLines = 50
    static let maxRequests = 10

    struct Line: Equatable {
        let t: Int64
        let m: String
    }

    struct Request: Equatable {
        let t: Int64
        let method: String
        let url: String
        let status: Int
    }

    private let lock = NSLock()
    private var lines: [Line] = []
    private var requests: [Request] = []

    static func now() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }

    func log(_ message: String, at t: Int64 = ReportLog.now()) {
        guard let m = Redact.line(message) else { return }
        lock.lock(); defer { lock.unlock() }
        lines.append(Line(t: t, m: m))
        if lines.count > Self.maxLines { lines.removeFirst(lines.count - Self.maxLines) }
    }

    /// Keeps the request only when it failed: no answer (status 0) or a status of 400 or more.
    func request(method: String, url: String, status: Int, at t: Int64 = ReportLog.now()) {
        guard status == 0 || status >= 400, let clean = Redact.url(url) else { return }
        let verb = method.trimmingCharacters(in: .whitespaces).uppercased()
        let known = ["GET", "POST", "PUT", "PATCH", "DELETE", "HEAD", "OPTIONS"].contains(verb)
        lock.lock(); defer { lock.unlock() }
        requests.append(Request(t: t, method: known ? verb : "GET", url: clean, status: min(max(status, 0), 999)))
        if requests.count > Self.maxRequests { requests.removeFirst(requests.count - Self.maxRequests) }
    }

    /// The report's `logs` and `requests`, oldest first.
    func snapshot() -> (logs: [[String: Any]], requests: [[String: Any]]) {
        lock.lock(); defer { lock.unlock() }
        return (lines.map { ["t": $0.t, "m": $0.m] },
                requests.map { ["t": $0.t, "method": $0.method, "url": $0.url, "status": $0.status] })
    }

    func reset() {
        lock.lock(); defer { lock.unlock() }
        lines = []
        requests = []
    }
}

/// Removes secrets before anything is kept. The server (worker/src/bug-report.js) and the Android SDK
/// (Redact.kt) carry the same rules; change all three together.
enum Redact {
    static let maxLength = 300
    private static let hidden = "[redacted]"
    private static let redactedSegment = ":redacted"

    /// A path segment after one of these words is the secret itself: /reset/<token>, /keys/<key>.
    private static let secretWords = regex(#"^(token|tokens|key|keys|apikey|api[-_]key|secret|secrets|password|passwords|signature|session|sessions|reset|invite|invites|otp|magic|confirm|verify|unsubscribe)$"#, ignoreCase: true)
    /// A plain route word, which even after one of those words isn't a secret: /password/forgot.
    private static let routeWord = regex(#"^[a-z-]{1,12}$"#)
    private static let jwt = regex(#"^eyJ[\w-]{4,}\.[\w-]{4,}"#)
    private static let phoneLike = regex(#"^[\d\s()+.-]+$"#)
    private static let longToken = regex(#"^[\w.~+=-]+$"#)
    private static let address = regex(#"\b[a-z][a-z0-9+.-]*://[^\s"'<>]+"#, ignoreCase: true)
    private static let urlParts = regex(#"^([a-z][a-z0-9+.-]*)://([^/]*)(.*)$"#, ignoreCase: true)
    /// A key (bare or quoted) that names a secret, then : or =, then its value.
    private static let secretPair = regex(#"((?<![\w-])["']?(?:[\w-]*(?:password|passwd|secret|token|api[-_]?key|authorization|cookie|session[-_]?id|signature|card[-_]?number)[\w-]*|pass|pwd|pin|cvv|cvc|otp|auth|sig|sid|key)["']?\s*[:=]\s*)((?:bearer|basic) +\S+|"[^"]*"|'[^']*'|[^\s,;&}]+)"#, ignoreCase: true)
    private static let bearer = regex(#"\b(bearer|basic) +(?!\[redacted\])[\w.~+/=-]+"#, ignoreCase: true)
    private static let jwtAnywhere = regex(#"\beyJ[\w-]{4,}\.[\w-]{4,}(\.[\w-]*)?"#)
    private static let longKey = regex(#"\b(?=[\w-]*\d)(?=[\w-]*[a-z])[\w-]{32,}\b"#, ignoreCase: true)

    /// Whether one path segment looks like a secret or personal data: an email, a JWT, a long run of
    /// letters and digits (API keys, hashes, UUIDs, signed ids) or a long number (a phone or card).
    static func secretSegment(_ segment: String) -> Bool {
        let s = segment.removingPercentEncoding ?? segment
        if s.contains("@") { return true }
        if matches(jwt, s) { return true }
        if s.filter(\.isASCIIDigit).count >= 10 && matches(phoneLike, s) { return true }
        if s.count >= 32 && matches(longToken, s) { return true }
        return s.count >= 20 && s.contains(where: \.isASCIIDigit) && s.contains(where: \.isASCIILetter)
    }

    /// A request's address without its query string, fragment, login or secret-looking path segments:
    /// "https://api.example.com/v1/receipts/:redacted". Nil when there is nothing usable.
    static func url(_ raw: String) -> String? {
        var s = replace(raw.trimmingCharacters(in: .whitespacesAndNewlines), regex(#"\s+"#), with: "")
        guard !s.isEmpty else { return nil }
        if let cut = s.firstIndex(where: { $0 == "?" || $0 == "#" }) { s = String(s[..<cut]) }
        var origin = "", path = s
        if let m = urlParts.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
           let scheme = group(m, 1, s), let hostPart = group(m, 2, s), let rest = group(m, 3, s) {
            let host = replace(hostPart, regex(#"^.*@"#), with: "").lowercased()
            guard !host.isEmpty else { return nil }
            origin = "\(scheme.lowercased())://\(host)"
            path = rest
        }
        let segments = path.components(separatedBy: "/")
        let cleaned = segments.enumerated().map { i, raw -> String in
            let plain = raw.components(separatedBy: ";")[0]
            if plain.isEmpty { return plain }
            if secretSegment(plain) { return redactedSegment }
            if i > 0 {
                let previous = segments[i - 1].components(separatedBy: ";")[0]
                if !previous.isEmpty && matches(secretWords, previous) && !matches(routeWord, plain) { return redactedSegment }
            }
            return plain
        }
        let out = String((origin + cleaned.joined(separator: "/")).prefix(maxLength))
        return out.isEmpty ? nil : out
    }

    /// A log line on one line, with secret-looking parts hidden: addresses lose their query strings,
    /// "Bearer <token>", JWTs and long keys become [redacted], and so does the value after a word like
    /// password, token or api_key.
    static func line(_ raw: String) -> String? {
        var s = replace(raw, regex(#"\s+"#), with: " ").trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        s = replaceEach(s, address) { url($0) ?? hidden }
        s = replace(s, secretPair, with: "$1\(hidden)")
        s = replace(s, bearer, with: "$1 \(hidden)")
        s = replace(s, jwtAnywhere, with: hidden)
        s = replace(s, longKey, with: hidden)
        return String(s.prefix(maxLength))
    }

    // MARK: helpers

    private static func regex(_ pattern: String, ignoreCase: Bool = false) -> NSRegularExpression {
        // The patterns are fixed and tested, so a failure here is a programming error.
        try! NSRegularExpression(pattern: pattern, options: ignoreCase ? [.caseInsensitive] : [])
    }

    private static func matches(_ re: NSRegularExpression, _ s: String) -> Bool {
        re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    private static func replace(_ s: String, _ re: NSRegularExpression, with template: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
    }

    private static func replaceEach(_ s: String, _ re: NSRegularExpression, _ transform: (String) -> String) -> String {
        var out = s
        for m in re.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
            guard let r = Range(m.range, in: out) else { continue }
            out.replaceSubrange(r, with: transform(String(out[r])))
        }
        return out
    }

    private static func group(_ m: NSTextCheckingResult, _ i: Int, _ s: String) -> String? {
        guard let r = Range(m.range(at: i), in: s) else { return m.range(at: i).location == NSNotFound ? nil : "" }
        return String(s[r])
    }
}

private extension Character {
    var isASCIIDigit: Bool { isASCII && isNumber }
    var isASCIILetter: Bool { isASCII && isLetter }
}
