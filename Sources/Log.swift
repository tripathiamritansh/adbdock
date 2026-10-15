import Foundation

/// Append-only log at ~/Library/Application Support/ADBWireless/app.log,
/// truncated on each launch. A background app with no window has nowhere else
/// to explain itself.
enum AppLog {
    static var url: URL { Store.dir.appendingPathComponent("app.log") }

    private static let fmt: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    private static let queue = DispatchQueue(label: "app.log")

    static func reset() {
        try? FileManager.default.createDirectory(at: Store.dir, withIntermediateDirectories: true)
        try? Data().write(to: url)
    }

    static func write(_ message: String) {
        queue.sync {
            try? FileManager.default.createDirectory(at: Store.dir, withIntermediateDirectories: true)
            let line = "\(fmt.string(from: Date())) \(message)\n"
            if let handle = try? FileHandle(forWritingTo: url) {
                handle.seekToEndOfFile()
                handle.write(Data(line.utf8))
                try? handle.close()
            } else {
                try? Data(line.utf8).write(to: url)
            }
        }
    }
}
