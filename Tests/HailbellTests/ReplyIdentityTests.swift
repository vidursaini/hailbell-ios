import XCTest
@testable import Hailbell

/// The dashboard decides who customers see. A photo bundled in the app (`Hailbell.teamPhoto`) only
/// fills in while the chat hasn't heard otherwise, and each reply shows its own teammate's photo.
final class ReplyIdentityTests: XCTestCase {
    private func team(_ avatar: String? = nil, photo: Bool? = nil, profile: Bool? = nil) -> [TeamMember] {
        [TeamMember(name: "Vidur", avatarUrl: avatar, photo: photo, profilePhoto: profile)]
    }

    func testBundledPhotoShowsOnlyWhenTheServerHasNoOtherAnswer() {
        // Each teammate signs, photos on, no photo of its own: the bundled one may fill in.
        XCTAssertTrue(ChatModel.allowsBundledPhoto(appearance: Appearance(), team: team()))
        XCTAssertTrue(ChatModel.allowsBundledPhoto(appearance: Appearance(), team: []))
        // Signed as the team, photos off, "no photo" for this app, or a dashboard photo: never.
        var asTeam = Appearance(); asTeam.agentIdentity = "team"
        XCTAssertFalse(ChatModel.allowsBundledPhoto(appearance: asTeam, team: team(photo: false)))
        XCTAssertFalse(ChatModel.allowsBundledPhoto(appearance: asTeam, team: team()), "an older server without the photo flag")
        var photosOff = Appearance(); photosOff.teamPhotos = false
        XCTAssertFalse(ChatModel.allowsBundledPhoto(appearance: photosOff, team: team()))
        XCTAssertFalse(ChatModel.allowsBundledPhoto(appearance: Appearance(), team: team(photo: false)))
        XCTAssertFalse(ChatModel.allowsBundledPhoto(appearance: Appearance(), team: team("/v1/files/att_1/k")))
        XCTAssertFalse(ChatModel.allowsBundledPhoto(appearance: Appearance(), team: team("/v1/files/att_1/k", photo: true, profile: false)))
        // An app that bundles the owner's photo, with the same Profile photo in the dashboard: it stays.
        XCTAssertTrue(ChatModel.allowsBundledPhoto(appearance: Appearance(), team: team("/v1/files/att_1/k", photo: true, profile: true)))
    }

    func testRepliesDecodeTheirTeammatesPhotoAndOldCachesStillLoad() throws {
        let fresh = try JSONDecoder().decode(Message.self, from: Data(#"{"id":"m1","author":"agent","authorName":"Seva","authorAvatarUrl":"/v1/files/att_2/k","body":"hi","createdAt":1}"#.utf8))
        XCTAssertEqual(fresh.authorAvatarUrl, "/v1/files/att_2/k")
        let cached = try JSONDecoder().decode(Message.self, from: Data(#"{"id":"m0","author":"agent","body":"hi","attachments":[],"createdAt":0}"#.utf8))
        XCTAssertNil(cached.authorAvatarUrl)
        // A snapshot written by an older version has no photo flag.
        let member = try JSONDecoder().decode(TeamMember.self, from: Data(#"{"name":"Vidur","avatarUrl":null}"#.utf8))
        XCTAssertNil(member.photo)
        // Round trip through the offline copy keeps the photo.
        let again = try JSONDecoder().decode(Message.self, from: JSONEncoder().encode(fresh))
        XCTAssertEqual(again.authorAvatarUrl, fresh.authorAvatarUrl)
    }
}
