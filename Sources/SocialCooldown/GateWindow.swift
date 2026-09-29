import AppKit
import SwiftUI

struct GateView: View {
    @ObservedObject var session: GateSession
    let model: AppModel
    @State private var now = Date()

    private var elapsedMinutesText: String {
        let minutes = max(0, Int(now.timeIntervalSince(session.lastQuit) / 60))
        return minutes == 1 ? "1 minute ago" : "\(minutes) minutes ago"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Cooldown active").font(.title2.bold())
            Text("\(session.app.displayName) was last quit")
                .foregroundStyle(.secondary)
            Text(elapsedMinutesText)
                .font(.system(size: 36, weight: .bold, design: .rounded))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .leading)
            if session.challengeRevealed {
                Text("Type this challenge exactly to continue:")
                Text(session.challenge)
                    .font(.system(.title3, design: .monospaced).bold())
                    .textSelection(.enabled)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                TextField("10-character challenge", text: $session.input)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.submit(session) }
            } else {
                Text("When you are ready, continue to reveal the challenge.")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text(statusText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { model.dismissGate() }
                if session.challengeRevealed {
                    Button("Open \(session.app.displayName)") { model.submit(session) }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!session.canContinue)
                } else {
                    Button("Continue") { session.revealChallenge() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(!session.canRevealChallenge)
                }
            }
        }
        .padding(24)
        .frame(width: 460)
        .onAppear {
            Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { timer in
                if session.waitComplete { timer.invalidate() }
                now = Date()
            }
        }
    }

    private var statusText: String {
        if !session.waitComplete { return "Continue unlocks in 5 seconds…" }
        if !session.challengeRevealed { return "The challenge is hidden until you continue." }
        return "You may open the app when the text matches."
    }
}

@MainActor
final class GateWindowController: NSObject, NSWindowDelegate {
    static let shared = GateWindowController()
    private var gateWindow: NSWindow?

    private override init() { super.init() }

    func show(session: GateSession, model: AppModel) {
        DiagnosticLog.write("show gate window app=\(session.app.rawValue) challengeSession=\(session.id)")
        let view = GateView(session: session, model: model)
        let hostingController = NSHostingController(rootView: view)
        let visibleWindow: NSWindow
        if let existingWindow = gateWindow {
            existingWindow.contentViewController = hostingController
            visibleWindow = existingWindow
            DiagnosticLog.write("updated gate window number=\(existingWindow.windowNumber) app=\(session.app.rawValue)")
        } else {
            // Remove any visible gate that AppKit may have detached from a
            // previous controller reference before creating the sole window.
            for staleWindow in NSApp.windows where staleWindow.title == "Social Cooldown" {
                staleWindow.delegate = nil
                staleWindow.close()
                DiagnosticLog.write("closed orphan gate window number=\(staleWindow.windowNumber)")
            }
            let newWindow = NSWindow(contentViewController: hostingController)
            newWindow.title = "Social Cooldown"
            newWindow.styleMask = [.titled, .closable]
            newWindow.isReleasedWhenClosed = false
            newWindow.delegate = self
            gateWindow = newWindow
            visibleWindow = newWindow
            DiagnosticLog.write("created gate window number=\(newWindow.windowNumber) app=\(session.app.rawValue)")
        }
        NSApp.activate(ignoringOtherApps: true)
        visibleWindow.center()
        visibleWindow.makeKeyAndOrderFront(nil)
    }

    func close() {
        gateWindow?.close()
    }

    func windowWillClose(_ notification: Notification) {
        guard let closingWindow = notification.object as? NSWindow else { return }
        DiagnosticLog.write("gate window closing number=\(closingWindow.windowNumber) tracked=\(closingWindow === gateWindow)")
        if closingWindow === gateWindow {
            gateWindow = nil
        }
    }
}
