import AppKit
import SwiftUI

@MainActor
struct IdentifierSettingsView: View {
    let model: AppModel
    @State private var discordIdentifier: String
    @State private var qqIdentifier: String

    init(model: AppModel) {
        self.model = model
        _discordIdentifier = State(initialValue: model.bundleIdentifier(for: .discord))
        _qqIdentifier = State(initialValue: model.bundleIdentifier(for: .qq))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Application identifiers").font(.title3.bold())
            Text("Use these when your installed Discord or QQ build has a different bundle identifier.")
                .font(.caption)
                .foregroundStyle(.secondary)
            LabeledContent("Discord") {
                TextField("com.hnc.Discord", text: $discordIdentifier)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("QQ") {
                TextField("com.tencent.qq", text: $qqIdentifier)
                    .textFieldStyle(.roundedBorder)
            }
            HStack {
                Spacer()
                Button("Save") {
                    model.setBundleIdentifier(discordIdentifier, for: .discord)
                    model.setBundleIdentifier(qqIdentifier, for: .qq)
                    SettingsWindowController.shared.close()
                }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 500)
    }
}

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private init() { super.init(window: nil) }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    func show(model: AppModel) {
        if window == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: IdentifierSettingsView(model: model)))
            window.title = "Social Cooldown Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.center()
        window?.makeKeyAndOrderFront(nil)
    }

    override func close() { window?.close() }
}
