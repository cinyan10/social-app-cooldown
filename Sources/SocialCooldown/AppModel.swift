import AppKit
import Combine
import Foundation

@MainActor
final class AppModel: ObservableObject {
    let store: CooldownStore
    private(set) var monitor: ProcessMonitor!
    private var enabled: [SocialApp: Bool] = Dictionary(uniqueKeysWithValues: SocialApp.allCases.map { ($0, true) })
    private var bundleIdentifiers: [SocialApp: String]

    @Published var gate: GateSession?
    @Published var quitConfirmationPresented = false

    init(store: CooldownStore = CooldownStore()) {
        self.store = store
        let saved = UserDefaults.standard.dictionary(forKey: "bundleIdentifiers") as? [String: String] ?? [:]
        bundleIdentifiers = Dictionary(uniqueKeysWithValues: SocialApp.allCases.map { ($0, saved[$0.rawValue] ?? $0.defaultBundleIdentifier) })
        monitor = ProcessMonitor(store: store, model: self)
        monitor.start()
    }

    func isMonitored(_ app: SocialApp) -> Bool { enabled[app] ?? true }

    func bundleIdentifier(for app: SocialApp) -> String { bundleIdentifiers[app] ?? app.defaultBundleIdentifier }

    func setBundleIdentifier(_ identifier: String, for app: SocialApp) {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        bundleIdentifiers[app] = trimmed
        UserDefaults.standard.set(bundleIdentifiers.reduce(into: [String: String]()) { result, item in
            result[item.key.rawValue] = item.value
        }, forKey: "bundleIdentifiers")
        objectWillChange.send()
    }

    func setMonitored(_ value: Bool, for app: SocialApp) {
        enabled[app] = value
        objectWillChange.send()
    }

    func lastQuit(for app: SocialApp) -> Date? { store.date(for: app) }

    func reset(_ app: SocialApp) {
        store.reset(for: app)
        objectWillChange.send()
    }

    func resetAll() {
        store.resetAll()
        objectWillChange.send()
    }

    func presentGate(for app: SocialApp, lastQuit: Date) {
        // Every blocked launch gets a fresh session. The challenge therefore
        // remains hidden until the user explicitly presses Continue again.
        let session = GateSession(app: app, lastQuit: lastQuit)
        gate = session
        session.beginWait()
        GateWindowController.shared.show(session: session, model: self)
    }

    func submit(_ session: GateSession) {
        guard session.canContinue else { return }
        monitor.allowNextLaunch(of: session.app)
        gate = nil
        GateWindowController.shared.close()
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier(for: session.app)) else { return }
        NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    func dismissGate() {
        gate = nil
        GateWindowController.shared.close()
    }
}
