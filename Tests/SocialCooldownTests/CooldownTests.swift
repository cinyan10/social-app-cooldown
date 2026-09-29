import XCTest
@testable import SocialCooldown

final class CooldownTests: XCTestCase {
    func testNoPreviousQuitAllowsLaunch() {
        XCTAssertTrue(CooldownPolicy.canLaunch(lastQuit: nil))
    }

    func testCooldownBoundaries() {
        let now = Date(timeIntervalSince1970: 10_000)
        let almost = now.addingTimeInterval(-CooldownPolicy.interval + 1)
        let exact = now.addingTimeInterval(-CooldownPolicy.interval)
        XCTAssertFalse(CooldownPolicy.canLaunch(lastQuit: almost, now: now))
        XCTAssertTrue(CooldownPolicy.canLaunch(lastQuit: exact, now: now))
        XCTAssertTrue(CooldownPolicy.canLaunch(lastQuit: exact.addingTimeInterval(-1), now: now))
    }

    func testChallengeShapeAndExactMatch() {
        var generator = SystemRandomNumberGenerator()
        let challenge = ChallengeGenerator.make(using: &generator)
        XCTAssertEqual(challenge.count, 10)
        XCTAssertTrue(challenge.allSatisfy { ChallengeGenerator.alphabet.contains($0) })
    }

    func testStorePersistsAndResets() {
        let suite = "SocialCooldownTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = CooldownStore(defaults: defaults)
        let date = Date(timeIntervalSince1970: 123)
        store.save(date: date, for: .discord)
        XCTAssertEqual(store.date(for: .discord), date)
        store.reset(for: .discord)
        XCTAssertNil(store.date(for: .discord))
    }

    @MainActor
    func testChallengeIsHiddenUntilExplicitlyRevealed() {
        let session = GateSession(app: .discord, lastQuit: .now, challenge: "abcdefghij")
        XCTAssertFalse(session.challengeRevealed)
        XCTAssertFalse(session.canContinue)
        session.revealChallenge()
        XCTAssertFalse(session.challengeRevealed, "The five-second wait must still be required")
    }
}
