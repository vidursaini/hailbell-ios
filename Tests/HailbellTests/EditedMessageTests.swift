import XCTest
@testable import Hailbell

/// A reply the team edited or deleted arrives with `edited` or `deleted`. Older servers and cached
/// copies carry neither.
final class EditedMessageTests: XCTestCase {
    private func decode(_ json: String) throws -> Message {
        try JSONDecoder().decode(Message.self, from: Data(json.utf8))
    }

    func testEditedAndDeletedDecodeAndSurviveTheCache() throws {
        let edited = try decode(#"{"id":"m1","author":"agent","body":"Refund sent today","createdAt":1,"edited":true}"#)
        XCTAssertTrue(edited.isEdited)
        XCTAssertFalse(edited.isDeleted)
        let deleted = try decode(#"{"id":"m2","author":"agent","body":"This message was deleted.","attachments":[],"card":null,"createdAt":2,"deleted":true,"edited":true}"#)
        XCTAssertTrue(deleted.isDeleted)
        XCTAssertFalse(deleted.isEdited, "a deleted message shows only the marker")
        // The offline copy is the same JSON, written and read back.
        let again = try JSONDecoder().decode(Message.self, from: JSONEncoder().encode(deleted))
        XCTAssertEqual(again, deleted)
    }

    func testOlderPayloadsStillLoad() throws {
        let plain = try decode(#"{"id":"m0","author":"agent","body":"hi","attachments":[],"createdAt":0}"#)
        XCTAssertFalse(plain.isEdited)
        XCTAssertFalse(plain.isDeleted)
        // A flag the SDK can't read leaves the message itself intact.
        XCTAssertEqual(try decode(#"{"id":"m3","author":"agent","body":"hi","createdAt":3,"edited":"yes"}"#).body, "hi")
    }

    func testBothWordsExistInEveryLanguage() {
        for lang in ["en", "es", "fr", "de", "it", "pt", "nl", "ja", "ko", "zh", "hi", "tr", "ru", "id"] {
            for key in ["edited", "deleted"] { XCTAssertNotEqual(L10n.text(key, lang: lang), key, "\(lang) \(key)") }
        }
        XCTAssertEqual(L10n.text("edited", lang: "en"), "Edited")
    }
}
