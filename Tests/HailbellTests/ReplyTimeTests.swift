import XCTest
import UserNotifications
@testable import Hailbell

/// The reply time card: a "system" message whose `expect` says when the team will reply. The words
/// are worked out on the device from its own clock, zone and 12/24-hour setting.
final class ReplyTimeTests: XCTestCase {
    private func decode(_ json: String) throws -> Message {
        try JSONDecoder().decode(Message.self, from: Data(json.utf8))
    }

    // MARK: decoding

    func testACardDecodesItsDetailsAndKeepsThemOffline() throws {
        let m = try decode(#"{"id":"m1","author":"system","body":"Bello is offline right now. Usually back by…","createdAt":1,"expect":{"kind":"back","name":"Bello","backAt":1764100000000,"notify":true,"ownerZone":"Asia/Kolkata","ownerCountry":"IN"}}"#)
        let e = try XCTUnwrap(m.expectCard)
        XCTAssertEqual(e.kind, "back")
        XCTAssertEqual(e.name, "Bello")
        XCTAssertEqual(e.backAt, 1764100000000)
        XCTAssertTrue(e.notify)
        XCTAssertEqual(e.ownerZone, "Asia/Kolkata")
        XCTAssertEqual(e.ownerCountry, "IN")
        // The offline copy keeps it.
        let again = try JSONDecoder().decode(Message.self, from: JSONEncoder().encode(m))
        XCTAssertEqual(again.expect, m.expect)

        let typical = try decode(#"{"id":"m2","author":"system","body":"x","createdAt":1,"expect":{"kind":"typical","name":"Bello","hours":3,"notify":false}}"#)
        XCTAssertEqual(typical.expectCard?.hours, 3)
        XCTAssertEqual(typical.expectCard?.notify, false)
    }

    func testMessagesWithoutAReadableCardStayPlainBubbles() throws {
        // No expect at all: an ordinary system message, such as the away message.
        let plain = try decode(#"{"id":"m1","author":"system","body":"We're away","createdAt":1}"#)
        XCTAssertNil(plain.expect)
        XCTAssertNil(plain.expectCard)
        // Malformed: the message still loads with its text.
        for odd in [#""soon""#, #"{"kind":3}"#, #"{"kind":"soon"}"#, #"[]"#, "null"] {
            let m = try decode(#"{"id":"m2","author":"system","body":"Bello will reply","createdAt":1,"expect":\#(odd)}"#)
            XCTAssertNil(m.expectCard, odd)
            XCTAssertEqual(m.body, "Bello will reply")
        }
        // A kind this SDK doesn't know, or one missing what it needs.
        XCTAssertNil(try decode(#"{"id":"m3","author":"system","body":"x","createdAt":1,"expect":{"kind":"later","name":"Bello","notify":true}}"#).expectCard)
        XCTAssertNil(try decode(#"{"id":"m4","author":"system","body":"x","createdAt":1,"expect":{"kind":"back","name":"Bello","notify":true}}"#).expectCard)
        XCTAssertNil(try decode(#"{"id":"m5","author":"system","body":"x","createdAt":1,"expect":{"kind":"typical","name":"Bello"}}"#).expectCard)
        // Only system messages become cards.
        XCTAssertNil(try decode(#"{"id":"m6","author":"agent","body":"x","createdAt":1,"expect":{"kind":"soon","name":"Bello","notify":true}}"#).expectCard)
        // A field of the wrong type is dropped, not fatal.
        let loose = try decode(#"{"id":"m7","author":"system","body":"x","createdAt":1,"expect":{"kind":"soon","name":"Bello","notify":"yes","ownerZone":5}}"#)
        XCTAssertEqual(loose.expectCard?.notify, false)
        XCTAssertNil(loose.expectCard?.ownerZone)
    }

    // MARK: words

    private let london = TimeZone(identifier: "Europe/London")!
    private let gb = Locale(identifier: "en_GB")   // 24-hour clock
    private let us = Locale(identifier: "en_US")   // 12-hour clock

    /// 2026-11-26 15:00 in London (a Thursday).
    private var now: Date {
        var c = DateComponents(year: 2026, month: 11, day: 26, hour: 15, minute: 0)
        c.timeZone = london
        return Calendar(identifier: .gregorian).date(from: c)!
    }

    private func back(in hours: Double, notify: Bool = true) -> Expect {
        Expect(kind: "back", name: "Bello", backAt: (now.timeIntervalSince1970 + hours * 3600) * 1000, notify: notify)
    }

    private func words(_ e: Expect, lang: String = "en", locale: Locale? = nil, at: Date? = nil) -> ReplyTime.Words {
        ReplyTime.words(e, now: at ?? now, lang: lang, locale: locale ?? gb, zone: london)
    }

    func testTheDayPhrase() {
        // Later today, before 6 PM.
        XCTAssertEqual(words(back(in: 2)).bold, "17:00 today")
        // Today, from 6 PM: tonight.
        XCTAssertEqual(words(back(in: 3)).bold, "18:00 tonight")
        XCTAssertEqual(words(back(in: 8.5)).bold, "23:30 tonight")
        // The next calendar day.
        XCTAssertEqual(words(back(in: 10)).bold, "01:00 tomorrow")
        XCTAssertEqual(words(back(in: 32)).bold, "23:00 tomorrow")
        // Further out: the weekday.
        XCTAssertEqual(words(back(in: 42)).bold, "09:00 on Saturday")
        // In the reader's language and the device's 12-hour clock.
        XCTAssertEqual(words(back(in: 42), lang: "de").bold, "Samstag um 09:00")
        let twelve = words(back(in: 8.5), locale: us).bold ?? ""
        XCTAssertTrue(twelve.hasPrefix("11:30") && twelve.hasSuffix("PM tonight"), twelve)
    }

    func testTheWordsAreRecomputedFromTheClock() {
        let e = back(in: 42)   // Saturday 09:00
        XCTAssertEqual(words(e).bold, "09:00 on Saturday")
        // The same card read a day later.
        XCTAssertEqual(words(e, at: now.addingTimeInterval(24 * 3600)).bold, "09:00 tomorrow")
        XCTAssertEqual(words(e, at: now.addingTimeInterval(24 * 3600)).line?.hasSuffix("That’s in about 18 hours."), true)
        // And on Saturday morning, before the team is back.
        XCTAssertEqual(words(e, at: now.addingTimeInterval(41 * 3600)).bold, "09:00 today")
        // Once it has passed: title only.
        XCTAssertNil(words(e, at: now.addingTimeInterval(43 * 3600)).line)
    }

    func testTheHourCount() {
        XCTAssertEqual(words(back(in: 1)).line, "Usually back by 16:00 today, your time. That’s in about an hour.")
        XCTAssertEqual(words(back(in: 1.4)).line?.hasSuffix("That’s in about an hour."), true)
        XCTAssertEqual(words(back(in: 1.6)).line?.hasSuffix("That’s in about 2 hours."), true)
        XCTAssertEqual(words(back(in: 8.5)).line, "Usually back by 23:30 tonight, your time. That’s in about 9 hours.")
        XCTAssertEqual(words(back(in: 23.4)).line?.hasSuffix("That’s in about 23 hours."), true)
        // A day or more away: no count.
        XCTAssertEqual(words(back(in: 24)).line, "Usually back by 15:00 tomorrow, your time.")
        XCTAssertEqual(words(back(in: 42)).line, "Usually back by 09:00 on Saturday, your time.")
    }

    func testTitlesAndThePastTime() {
        XCTAssertEqual(words(back(in: 3)).title, "Bello is offline right now")
        // Back already: the title alone.
        let past = words(back(in: -1))
        XCTAssertEqual(past.title, "Bello is offline right now")
        XCTAssertNil(past.line)
        XCTAssertNil(past.bold)

        XCTAssertEqual(words(Expect(kind: "typical", name: "Bello", hours: 3)),
                       ReplyTime.Words(title: "Bello will reply here", line: "At this time of day Bello usually replies within 3 hours."))
        XCTAssertEqual(words(Expect(kind: "typical", name: "Bello", hours: 1)).line,
                       "At this time of day Bello usually replies within an hour.")
        XCTAssertEqual(words(Expect(kind: "soon", name: "Bello")),
                       ReplyTime.Words(title: "Bello will reply here", line: "Bello will reply as soon as possible."))
        // Japanese runs its sentences together.
        let ja = words(back(in: 3), lang: "ja").line ?? ""
        XCTAssertFalse(ja.contains("。 "), ja)
    }

    func testTheOwnersTime() {
        let e = Expect(kind: "soon", name: "Bello", ownerZone: "Asia/Kolkata", ownerCountry: "IN")
        // 15:00 in London is 20:30 in India.
        XCTAssertEqual(words(e).ownerTime, "It’s 20:30 for Bello in India.")
        XCTAssertEqual(words(e, lang: "de").ownerTime, "Bei Bello (Indien) ist es 20:30.")
        // English adds "the" where the country's name needs it.
        let us = Expect(kind: "soon", name: "Bello", ownerZone: "Asia/Kolkata", ownerCountry: "US")
        XCTAssertEqual(words(us).ownerTime, "It’s 20:30 for Bello in the United States.")
        XCTAssertEqual(words(Expect(kind: "soon", name: "Bello", ownerZone: "Asia/Kolkata", ownerCountry: "NL")).ownerTime, "It’s 20:30 for Bello in the Netherlands.")
        XCTAssertEqual(words(us, lang: "es").ownerTime, "Son las 20:30 para Bello en Estados Unidos.")
        // Both parts or none.
        XCTAssertNil(words(Expect(kind: "soon", name: "Bello", ownerZone: "Asia/Kolkata")).ownerTime)
        XCTAssertNil(words(Expect(kind: "soon", name: "Bello", ownerZone: "Mars/Base", ownerCountry: "IN")).ownerTime)
    }

    func testEveryLanguageHasEveryKey() {
        let keys = Set(L10n.replyTimeTable["en"]!.keys)
        XCTAssertEqual(keys.count, 19)
        XCTAssertEqual(L10n.replyTimeTable.count, 14)
        for (lang, table) in L10n.replyTimeTable { XCTAssertEqual(Set(table.keys), keys, lang) }
        // The owner-approved English.
        XCTAssertEqual(L10n.text("expectNotify", ["name": "Bello"], lang: "en"), "Notify me when Bello replies")
    }

    // MARK: notify part

    func testTheNotifyPart() {
        XCTAssertEqual(ReplyTime.notify(offered: true, teamReplied: false, permission: .notDetermined), .ask)
        XCTAssertEqual(ReplyTime.notify(offered: true, teamReplied: false, permission: .denied), .settings)
        XCTAssertEqual(ReplyTime.notify(offered: true, teamReplied: false, permission: .authorized), .done)
        XCTAssertEqual(ReplyTime.notify(offered: true, teamReplied: false, permission: .provisional), .done)
        // Not offered, already answered, or not known yet: nothing.
        XCTAssertEqual(ReplyTime.notify(offered: false, teamReplied: false, permission: .notDetermined), .none)
        XCTAssertEqual(ReplyTime.notify(offered: true, teamReplied: true, permission: .notDetermined), .none)
        XCTAssertEqual(ReplyTime.notify(offered: true, teamReplied: true, permission: .authorized), .none)
        XCTAssertEqual(ReplyTime.notify(offered: true, teamReplied: false, permission: nil), .none)
    }

    func testTheBoldPartIsTheDayPhrase() {
        let s = ReplyTime.styled("Usually back by 23:30 tonight, your time.", bold: "23:30 tonight")
        let bold = s.runs.filter { $0.inlinePresentationIntent == .stronglyEmphasized }.map { String(s[$0.range].characters) }
        XCTAssertEqual(bold, ["23:30 tonight"])
    }
}
