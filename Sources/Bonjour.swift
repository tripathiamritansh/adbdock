import Foundation

/// The system's Bonjour view of the network, independent of adb's own mDNS client.
///
/// adb's mDNS client can wedge: an adb server started while the phone was
/// off-network never re-discovered it (observed 2026-10-14, openscreen backend),
/// while `dns-sd` — which goes through mDNSResponder — saw the device immediately.
/// This is the ground truth the app uses to decide that *it* is the broken part.
enum Bonjour {
    static func connectInstances(timeout: TimeInterval = 2.0) -> [String] {
        browse("_adb-tls-connect._tcp", timeout: timeout)
    }

    /// `dns-sd -B` keeps running; it is killed at `timeout` and whatever it printed is parsed.
    private static func browse(_ type: String, timeout: TimeInterval) -> [String] {
        var names: [String] = []
        for line in run(["-B", type], timeout: timeout).split(separator: "\n") {
            // "17:27:18.748  Add  2  14 local.  _adb-tls-connect._tcp.  adb-0123456789ABCDEF-abcdef"
            let f = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
            guard f.count >= 7, f[1] == "Add" else { continue }
            let name = f.dropFirst(6).joined(separator: " ")
            if !name.isEmpty && !names.contains(name) { names.append(name) }
        }
        return names
    }

    private static func run(_ args: [String], timeout: TimeInterval) -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/dns-sd")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return "" }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return String(decoding: data, as: UTF8.self)
    }
}
