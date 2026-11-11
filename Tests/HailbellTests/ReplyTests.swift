import XCTest
@testable import Hailbell

/// Replies quote another message: the server sends a snapshot of it as `replyTo`, and the customer
/// sees who wrote it named from their side of the chat.
final class ReplyTests: XCTestCase {
    private func decode(_ json: String) throws -> Message {
        try JSONDecoder().decode(Message.self, from: Data(json.utf8))
    }

    func testRepliesDecodeTheirQuoteAndOlderPayloadsStillLoad() throws {
        let reply = try decode(#"{"id":"m2","author":"agent","authorName":"Ana","body":"Sure","createdAt":2,"replyTo":{"id":"m1","author":"user","authorName":null,"body":"Can I get a refund?"}}"#)
        XCTAssertEqual(reply.replyTo?.id, "m1")
        XCTAssertEqual(reply.replyTo?.author, "user")
        XCTAssertNil(reply.replyTo?.authorName)
        XCTAssertEqual(reply.replyTo?.snippet, "Can I get a refund?")
        XCTAssertNil(reply.replyTo?.image)

        // A message from a server that predates replies, or from the offline copy of an older version.
        XCTAssertNil(try decode(#"{"id":"m0","author":"agent","body":"hi","attachments":[],"createdAt":0}"#).replyTo)
        // A quote the SDK can't read leaves the message itself intact.
        let odd = try decode(#"{"id":"m3","author":"agent","body":"hi","createdAt":3,"replyTo":"m1"}"#)
        XCTAssertNil(odd.replyTo)
        XCTAssertEqual(odd.body, "hi")

        // The offline copy keeps the quote.
        let again = try JSONDecoder().decode(Message.self, from: JSONEncoder().encode(reply))
        XCTAssertEqual(again.replyTo, reply.replyTo)
    }

    func testAQuoteOfAnImageOnlyMessageSaysPhoto() throws {
        let reply = try decode(#"{"id":"m2","author":"user","body":"this one","createdAt":2,"replyTo":{"id":"m1","author":"agent","authorName":"Ana","body":"","image":true}}"#)
        XCTAssertNil(reply.replyTo?.snippet)
        XCTAssertTrue(reply.replyTo?.isPhoto == true)
        // Text and an image: the text is the snippet.
        let both = ReplyTo(id: "m1", author: "agent", authorName: nil, body: "Look\nhere ", image: true)
        XCTAssertEqual(both.snippet, "Look here")
        XCTAssertFalse(both.isPhoto)
    }

    func testTheQuoteBuiltOnTheDeviceMatchesWhatTheServerSends() throws {
        let original = try decode(#"{"id":"m1","author":"agent","authorName":"Ana","body":"\#(String(repeating: "a", count: 300))","attachments":[{"id":"a1","url":"/v1/files/a1/k"}],"createdAt":1}"#)
        let quote = ReplyTo(original)
        XCTAssertEqual(quote.id, "m1")
        XCTAssertEqual(quote.authorName, "Ana")
        XCTAssertEqual(quote.body.count, 200)
        XCTAssertEqual(quote.image, true)
    }

    func testNamesFromTheCustomersSide() {
        let you = L10n.text("you")
        XCTAssertEqual(ChatModel.replyName(author: "user", authorName: "Sam", chatTitle: "Acme Support"), you)
        XCTAssertEqual(ChatModel.replyName(author: "agent", authorName: "Ana", chatTitle: "Acme Support"), "Ana")
        XCTAssertEqual(ChatModel.replyName(author: "agent", authorName: nil, chatTitle: "Acme Support"), "Acme Support")
        XCTAssertEqual(ChatModel.replyName(author: "agent", authorName: " ", chatTitle: "Acme Support"), "Acme Support")
        XCTAssertEqual(ChatModel.replyName(author: "bot", authorName: "Bell", chatTitle: "Acme Support"), "Bell · \(L10n.text("ai"))")
        XCTAssertEqual(ChatModel.replyName(author: "system", authorName: nil, chatTitle: "Acme Support"), "Acme Support")
    }

    func testEveryLanguageHasTheReplyStrings() {
        for key in ["reply", "replyingTo", "you", "photo", "cancelReply"] {
            XCTAssertNotEqual(L10n.text(key), key, key)
        }
        XCTAssertEqual(L10n.text("replyingTo", ["name": "Ana"]).contains("Ana"), true)
    }

    func testSwipeResistance() {
        XCTAssertEqual(SwipeToReply.resist(-20), 0)
        XCTAssertLessThan(SwipeToReply.resist(40), 40)
        XCTAssertLessThan(SwipeToReply.resist(60), SwipeToReply.threshold, "a 60pt drag alone isn't quite enough")
        XCTAssertGreaterThanOrEqual(SwipeToReply.resist(75), SwipeToReply.threshold)
        XCTAssertLessThan(SwipeToReply.resist(1000), 110, "it never runs off with the finger")
    }
}
