import AppKit
import Foundation

@MainActor
final class ProcessMonitor {
    private let workspace = NSWorkspace.shared
    private let store: CooldownStore
    private weak var model: AppModel?
    private var observers: [NSObjectProtocol] = []
    private var activePIDs: [SocialApp: Set<pid_t>] = [:]
    private var appByPID: [pid_t: SocialApp] = [:]
    private var blockedPIDs: Set<pid_t> = []
    private var oneTimeAllowances: Set<SocialApp> = []

    init(store: CooldownStore, model: AppModel) {
        self.store = store
        self.model = model
    }

    func start() {
        guard observers.isEmpty else { return }
        let center = workspace.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { [weak self] in self?.didLaunch(app) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { [weak self] in self?.didTerminate(app) }
        })

        for app in SocialApp.allCases {
            let running = workspace.runningApplications.filter { $0.bundleIdentifier == model?.bundleIdentifier(for: app) }
            activePIDs[app] = Set(running.map(\.processIdentifier))
            for process in running {
                appByPID[process.processIdentifier] = app
            }
        }
    }

    func allowNextLaunch(of app: SocialApp) {
        oneTimeAllowances.insert(app)
    }

    func stop() {
        observers.forEach(workspace.notificationCenter.removeObserver)
        observers.removeAll()
    }

    private func didLaunch(_ process: NSRunningApplication) {
        guard let model,
              let app = SocialApp.allCases.first(where: { model.bundleIdentifier(for: $0) == process.bundleIdentifier }),
              model.isMonitored(app) else { return }
        let pid = process.processIdentifier
        guard !(activePIDs[app, default: []].contains(pid)) else { return }

        if oneTimeAllowances.remove(app) != nil || CooldownPolicy.canLaunch(lastQuit: store.date(for: app)) {
            activePIDs[app, default: []].insert(pid)
            appByPID[pid] = app
            return
        }

        blockedPIDs.insert(pid)
        appByPID[pid] = app
        process.terminate()
        if let lastQuit = store.date(for: app) {
            model.presentGate(for: app, lastQuit: lastQuit)
        }
    }

    private func didTerminate(_ process: NSRunningApplication) {
        let pid = process.processIdentifier
        if blockedPIDs.remove(pid) != nil {
            appByPID.removeValue(forKey: pid)
            return
        }
        guard let model, let app = appByPID.removeValue(forKey: pid)
                ?? SocialApp.allCases.first(where: { model.bundleIdentifier(for: $0) == process.bundleIdentifier }) else { return }
        guard activePIDs[app, default: []].remove(pid) != nil else { return }
        store.save(date: .now, for: app)
        model.objectWillChange.send()
    }
}
