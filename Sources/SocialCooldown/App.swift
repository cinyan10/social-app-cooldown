import SwiftUI

@main
struct SocialCooldownApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var model = AppModel()

    var body: some Scene {
        MenuBarExtra("Social Cooldown", systemImage: "hourglass") {
            Text("Social Cooldown").font(.headline)
            Divider()
            ForEach(SocialApp.allCases) { app in
                let lastQuit = model.lastQuit(for: app)
                Toggle(isOn: Binding(
                    get: { model.isMonitored(app) },
                    set: { model.setMonitored($0, for: app) }
                )) {
                    VStack(alignment: .leading) {
                        Text(app.displayName)
                        Text(lastQuit.map { RelativeDateTimeFormatter().localizedString(for: $0, relativeTo: .now) } ?? "No quit recorded")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            Divider()
            Button("Application identifiers…") { SettingsWindowController.shared.show(model: model) }
            Button("Quit Social Cooldown") { appDelegate.requestQuit() }
        }
        .menuBarExtraStyle(.menu)
    }
}
