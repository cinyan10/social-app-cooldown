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
    private var activationExemptPIDs: Set<pid_t> = []
    private var suppressActivationsUntil = Date.distantPast
    private var reconciliationTimer: Timer?

    init(store: CooldownStore, model: AppModel) {
        self.store = store
        self.model = model
    }

    func start() {
        guard observers.isEmpty else { return }
        DiagnosticLog.write("process monitor start")
        let center = workspace.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { [weak self] in self?.didLaunch(app) }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { [weak self] in self?.didTerminate(app) }
        })
        // QQ and Discord can emit activation before their launch notification.
        // Observe both events, while treating processes already known to be
        // running as legitimate activations rather than new launches.
        observers.append(center.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            guard let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
            MainActor.assumeIsolated { [weak self] in self?.didActivate(app) }
        })

        for app in SocialApp.allCases {
            let running = workspace.runningApplications.filter { $0.bundleIdentifier == model?.bundleIdentifier(for: app) }
            DiagnosticLog.write("initial running app=\(app.rawValue) pids=\(running.map(\.processIdentifier))")
            activePIDs[app] = Set(running.map(\.processIdentifier))
            for process in running {
                appByPID[process.processIdentifier] = app
            }
        }

        reconciliationTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { [weak self] in self?.reconcileRunningProcesses() }
        }
    }

    func allowNextLaunch(of app: SocialApp) {
        DiagnosticLog.write("allow next launch app=\(app.rawValue)")
        oneTimeAllowances.insert(app)
    }

    func stop() {
        observers.forEach(workspace.notificationCenter.removeObserver)
        observers.removeAll()
        reconciliationTimer?.invalidate()
        reconciliationTimer = nil
    }

    private func didLaunch(_ process: NSRunningApplication) {
        let resolved = model.flatMap { monitoredApp(for: process, model: $0) }
        DiagnosticLog.write("event=launch \(description(of: process)) resolved=\(resolved?.rawValue ?? "none")")
        guard let model,
              let app = resolved,
              model.isMonitored(app) else { return }
        let pid = process.processIdentifier
        guard !blockedPIDs.contains(pid) else {
            DiagnosticLog.write("launch ignored app=\(app.rawValue) pid=\(pid) reason=already-blocked")
            return
        }
        guard !(activePIDs[app, default: []].contains(pid)) else {
            DiagnosticLog.write("launch ignored app=\(app.rawValue) pid=\(pid) reason=already-active")
            return
        }

        let challengeWasCompleted = oneTimeAllowances.remove(app) != nil
        let lastQuit = store.date(for: app)
        let cooldownComplete = CooldownPolicy.canLaunch(lastQuit: lastQuit)
        DiagnosticLog.write("launch decision app=\(app.rawValue) pid=\(pid) challengeAllowed=\(challengeWasCompleted) cooldownComplete=\(cooldownComplete) lastQuit=\(lastQuit?.timeIntervalSince1970.description ?? "nil")")
        if challengeWasCompleted || cooldownComplete {
            activePIDs[app, default: []].insert(pid)
            appByPID[pid] = app
            if challengeWasCompleted {
                // didActivate normally follows didLaunch. Do not immediately
                // block the launch that the user just authorized.
                activationExemptPIDs.insert(pid)
            }
            return
        }

        block(process, as: app, model: model)
    }

    private func didTerminate(_ process: NSRunningApplication) {
        let pid = process.processIdentifier
        let mapped = appByPID[pid]
        let resolved = model.flatMap { monitoredApp(for: process, model: $0) }
        DiagnosticLog.write("event=terminate \(description(of: process)) mapped=\(mapped?.rawValue ?? "none") resolved=\(resolved?.rawValue ?? "none") blocked=\(blockedPIDs.contains(pid))")
        activationExemptPIDs.remove(pid)
        if blockedPIDs.remove(pid) != nil {
            appByPID.removeValue(forKey: pid)
            return
        }
        guard let model, let app = appByPID.removeValue(forKey: pid)
                ?? monitoredApp(for: process, model: model) else { return }
        guard activePIDs[app, default: []].remove(pid) != nil else { return }
        store.save(date: .now, for: app)
        model.objectWillChange.send()
    }

    private func didActivate(_ process: NSRunningApplication) {
        let resolved = model.flatMap { monitoredApp(for: process, model: $0) }
        let pid = process.processIdentifier
        let alreadyActive = resolved.map { activePIDs[$0, default: []].contains(pid) } ?? false
        DiagnosticLog.write("event=activate \(description(of: process)) resolved=\(resolved?.rawValue ?? "none") suppressed=\(Date.now < suppressActivationsUntil) exempt=\(activationExemptPIDs.contains(pid)) alreadyActive=\(alreadyActive)")
        // Terminating a blocked app can make macOS briefly activate whichever
        // app was previously frontmost. Ignore that synthetic fallback event
        // so it cannot replace the gate with another app's name.
        guard Date.now >= suppressActivationsUntil else { return }

        guard !activationExemptPIDs.contains(pid) else { return }
        guard let model,
              let app = resolved,
              model.isMonitored(app) else { return }

        // An activation of a process that was already running is not a reopen.
        // This is especially important after another app is terminated, when
        // macOS activates the previous foreground app as a fallback.
        guard !activePIDs[app, default: []].contains(pid) else {
            DiagnosticLog.write("activation ignored app=\(app.rawValue) pid=\(pid) reason=already-active")
            return
        }

        // Some apps activate before didLaunch arrives. Consume the allowance
        // here so a challenge-authorized launch is not blocked by event order.
        if oneTimeAllowances.remove(app) != nil {
            activePIDs[app, default: []].insert(pid)
            appByPID[pid] = app
            activationExemptPIDs.insert(pid)
            DiagnosticLog.write("activation allowed app=\(app.rawValue) pid=\(pid) reason=challenge-completed")
            return
        }

        guard !CooldownPolicy.canLaunch(lastQuit: store.date(for: app)) else { return }

        guard !blockedPIDs.contains(pid) else { return }
        block(process, as: app, model: model)
    }

    private func block(_ process: NSRunningApplication, as app: SocialApp, model: AppModel) {
        let pid = process.processIdentifier
        DiagnosticLog.write("block app=\(app.rawValue) pid=\(pid) bundle=\(process.bundleIdentifier ?? "nil") existingGate=\(model.gate?.app.rawValue ?? "none")")
        blockedPIDs.insert(pid)
        appByPID[pid] = app
        activePIDs[app, default: []].remove(pid)
        suppressActivationsUntil = Date.now.addingTimeInterval(1)
        process.terminate()
        if let lastQuit = store.date(for: app) {
            model.presentGate(for: app, lastQuit: lastQuit)
        }
    }

    private func monitoredApp(for process: NSRunningApplication, model: AppModel) -> SocialApp? {
        if let identifier = process.bundleIdentifier {
            if let match = SocialApp.allCases.first(where: { model.bundleIdentifier(for: $0) == identifier }) {
                return match
            }
        }

        // Some launch/termination notifications arrive without a bundle ID.
        // Resolve those by the app bundle's final path component.
        guard let bundleName = process.bundleURL?.deletingPathExtension().lastPathComponent.lowercased() else { return nil }
        return SocialApp.allCases.first { $0.displayName.lowercased() == bundleName }
    }

    private func description(of process: NSRunningApplication) -> String {
        "pid=\(process.processIdentifier) bundle=\(process.bundleIdentifier ?? "nil") name=\(process.localizedName ?? "nil") url=\(process.bundleURL?.path ?? "nil") active=\(process.isActive) terminated=\(process.isTerminated)"
    }

    private func reconcileRunningProcesses() {
        guard let model else { return }
        for app in SocialApp.allCases {
            let currentProcesses = workspace.runningApplications.filter { process in
                guard !blockedPIDs.contains(process.processIdentifier) else { return false }
                return monitoredApp(for: process, model: model) == app
            }
            let current = Set(currentProcesses.map(\.processIdentifier))
            let previous = activePIDs[app, default: []]
            for pid in previous.subtracting(current) {
                appByPID.removeValue(forKey: pid)
                activationExemptPIDs.remove(pid)
                store.save(date: .now, for: app)
            }
            activePIDs[app, default: []].subtract(previous.subtracting(current))

            // A process first discovered by reconciliation still represents a
            // launch. Run the normal decision path instead of silently adding
            // it to activePIDs and bypassing the cooldown.
            for process in currentProcesses where !previous.contains(process.processIdentifier) {
                DiagnosticLog.write("reconcile discovered new app=\(app.rawValue) pid=\(process.processIdentifier)")
                didLaunch(process)
            }
        }
        model.objectWillChange.send()
    }
}
