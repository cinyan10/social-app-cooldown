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
                TextField("20-character challenge", text: $session.input)
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
final class GateWindowController: NSWindowController, NSWindowDelegate {
    static let shared = GateWindowController()

    private init() { super.init(window: nil) }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    func show(session: GateSession, model: AppModel) {
        // Replace any previous gate window so a repeated blocked launch cannot
        // leave an old challenge screen visible underneath the new session.
        if let previousWindow = window {
            previousWindow.delegate = nil
            previousWindow.close()
            window = nil
        }
        let view = GateView(session: session, model: model)
        let window = NSWindow(contentViewController: NSHostingController(rootView: view))
        window.title = "Social Cooldown"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.delegate = self
        self.window = window
        NSApp.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    static func close() { shared.window?.close() }
    func windowWillClose(_ notification: Notification) { window = nil }
}
