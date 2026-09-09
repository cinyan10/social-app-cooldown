import AppKit
import ServiceManagement

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var terminationApproved = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        try? SMAppService.mainApp.register()
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // This also catches the standard application menu's ⌘Q action. The only
        // intentional exit path is the menu-bar confirmation in requestQuit().
        terminationApproved ? .terminateNow : .terminateCancel
    }

    func requestQuit() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.messageText = "Quit Social Cooldown?"
        alert.informativeText = "Monitoring will stop until you launch it again."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Quit")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            terminationApproved = true
            NSApp.terminate(nil)
        }
    }
}
