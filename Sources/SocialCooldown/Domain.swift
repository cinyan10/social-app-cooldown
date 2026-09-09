import Foundation

enum SocialApp: String, CaseIterable, Identifiable, Codable {
    case discord
    case qq

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .discord: "Discord"
        case .qq: "QQ"
        }
    }

    // These can be changed in Settings if a regional build uses another identifier.
    var defaultBundleIdentifier: String {
        switch self {
        case .discord: "com.hnc.Discord"
        case .qq: "com.tencent.qq"
        }
    }
}

struct CooldownStore {
    private let defaults: UserDefaults
    private let key = "lastQuitDates"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func date(for app: SocialApp) -> Date? {
        dates[app.rawValue]
    }

    func save(date: Date, for app: SocialApp) {
        var updated = dates
        updated[app.rawValue] = date
        defaults.set(updated.mapValues { $0.timeIntervalSince1970 }, forKey: key)
    }

    func reset(for app: SocialApp) {
        var updated = dates
        updated.removeValue(forKey: app.rawValue)
        defaults.set(updated.mapValues { $0.timeIntervalSince1970 }, forKey: key)
    }

    func resetAll() {
        defaults.removeObject(forKey: key)
    }

    private var dates: [String: Date] {
        guard let raw = defaults.dictionary(forKey: key) as? [String: Double] else { return [:] }
        return raw.reduce(into: [:]) { result, item in
            result[item.key] = Date(timeIntervalSince1970: item.value)
        }
    }
}

enum CooldownPolicy {
    static let interval: TimeInterval = 60 * 60

    static func canLaunch(lastQuit: Date?, now: Date = .now) -> Bool {
        guard let lastQuit else { return true }
        return now.timeIntervalSince(lastQuit) >= interval
    }

    static func elapsed(lastQuit: Date?, now: Date = .now) -> TimeInterval? {
        guard let lastQuit else { return nil }
        return max(0, now.timeIntervalSince(lastQuit))
    }
}

struct ChallengeGenerator {
    static let alphabet = Array("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")

    static func make(length: Int = 20) -> String {
        var generator = SystemRandomNumberGenerator()
        return make(length: length, using: &generator)
    }

    static func make(length: Int = 20, using generator: inout SystemRandomNumberGenerator) -> String {
        String((0..<length).map { _ in alphabet.randomElement(using: &generator)! })
    }
}

@MainActor
final class GateSession: ObservableObject, Identifiable {
    let id = UUID()
    let app: SocialApp
    let challenge: String
    let lastQuit: Date
    let createdAt = Date()

    @Published var input = ""
    @Published private(set) var waitComplete = false
    @Published private(set) var challengeRevealed = false
    private var timerTask: Task<Void, Never>?

    init(app: SocialApp, lastQuit: Date, challenge: String = ChallengeGenerator.make()) {
        self.app = app
        self.lastQuit = lastQuit
        self.challenge = challenge
    }

    var canRevealChallenge: Bool { waitComplete && !challengeRevealed }
    var canContinue: Bool { waitComplete && challengeRevealed && input == challenge }

    func revealChallenge() {
        guard canRevealChallenge else { return }
        challengeRevealed = true
    }

    func beginWait() {
        timerTask?.cancel()
        timerTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            self?.waitComplete = true
        }
    }

    deinit { timerTask?.cancel() }
}
