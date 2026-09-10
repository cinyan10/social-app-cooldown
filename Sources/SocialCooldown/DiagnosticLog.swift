import Foundation

@MainActor
enum DiagnosticLog {
    static let fileURL = URL(fileURLWithPath: "/tmp/social-cooldown-debug.log")

    static func reset() {
        try? "".write(to: fileURL, atomically: true, encoding: .utf8)
        write("diagnostic log started")
    }

    static func write(_ message: String) {
        let timestamp = ISO8601DateFormatter().string(from: .now)
        let line = "\(timestamp) \(message)\n"
        let data = Data(line.utf8)

        if !FileManager.default.fileExists(atPath: fileURL.path) {
            FileManager.default.createFile(atPath: fileURL.path, contents: nil)
        }
        guard let handle = try? FileHandle(forWritingTo: fileURL) else { return }
        defer { try? handle.close() }
        do {
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } catch {
            // Diagnostics must never interfere with enforcement.
        }
    }
}
