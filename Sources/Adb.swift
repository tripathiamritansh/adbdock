import Foundation

/// One entry from `adb mdns services`.
struct MdnsService {
    let instance: String   // e.g. "adb-0123456789ABCDEF-abcdef"
    let type: String       // "_adb-tls-connect._tcp" | "_adb-tls-pairing._tcp"
    let address: String    // "192.168.1.42:5555"

    var isPairing: Bool { type.contains("pairing") }
    /// Just the address part, for matching a pairing advertisement to a device's
    /// last known address (the pairing instance name does not always carry the serial).
    var ip: String { address.split(separator: ":").first.map(String.init) ?? address }
    /// Device serial recovered from the mdns instance name.
    var serial: String { SerialId.fromMdns(instance) }
    /// Transport name exactly as `adb devices` reports it.
    var transportName: String { "\(instance).\(type)" }
}

/// One entry from `adb devices -l`.
struct Transport {
    let serial: String     // raw serial: USB serial or "adb-…._adb-tls-connect._tcp"
    let state: String      // device | offline | unauthorized
    let model: String?
    let product: String?
    let isMdns: Bool
    let mdnsInstance: String?

    /// Serial with any mdns decoration stripped, so USB and wireless rows for the
    /// same phone collapse onto one identity.
    var deviceSerial: String { isMdns ? SerialId.fromMdns(serial) : serial }
}

enum SerialId {
    /// mdns advertises `adb-<serial>-<randomSuffix>`; the suffix is regenerated
    /// whenever adbd restarts, so the serial — not the instance name — is the
    /// stable identity.
    static func fromMdns(_ raw: String) -> String {
        var s = raw
        for suffix in ["._adb-tls-connect._tcp", "._adb-tls-pairing._tcp"] {
            if let r = s.range(of: suffix) { s = String(s[..<r.lowerBound]) }
        }
        if s.hasPrefix("adb-") { s = String(s.dropFirst(4)) }
        if let i = s.lastIndex(of: "-") { s = String(s[..<i]) }
        return s
    }
}

final class Adb {
    static let shared = Adb()

    private(set) var path: String?
    private(set) var version: String?

    private init() {
        path = Adb.resolve()
        if let p = path {
            let r = Adb.exec(p, ["version"], timeout: 10)
            version = r.out.split(separator: "\n").first.map { String($0).trimmingCharacters(in: .whitespaces) }
        }
    }

    /// GUI apps launched by launchd inherit a minimal PATH, so never rely on
    /// `which adb` alone.
    static func resolve() -> String? {
        let candidates = [
            "/opt/homebrew/bin/adb",
            "/usr/local/bin/adb",
            NSHomeDirectory() + "/Library/Android/sdk/platform-tools/adb",
        ]
        for c in candidates where FileManager.default.isExecutableFile(atPath: c) { return c }
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v adb"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let out = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return out.isEmpty ? nil : out
    }

    static func exec(_ path: String, _ args: [String], timeout: TimeInterval) -> (code: Int32, out: String, err: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["HOME"] = NSHomeDirectory()   // adb keys live in ~/.android
        // macOS: use the system Bonjour stack (mDNSResponder). adb's openscreen
        // client has been observed to stop discovering devices entirely.
        env["ADB_MDNS_OPENSCREEN"] = "0"
        p.environment = env
        let outPipe = Pipe()
        let errPipe = Pipe()
        p.standardOutput = outPipe
        p.standardError = errPipe
        do { try p.run() } catch { return (-1, "", "\(error)") }
        let killer = DispatchWorkItem { if p.isRunning { p.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: killer)
        let outData = outPipe.fileHandleForReading.readDataToEndOfFile()
        let errData = errPipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        killer.cancel()
        return (p.terminationStatus, String(decoding: outData, as: UTF8.self), String(decoding: errData, as: UTF8.self))
    }

    @discardableResult
    func run(_ args: [String], timeout: TimeInterval = 15) -> (code: Int32, out: String, err: String) {
        guard let p = path else { return (-1, "", "adb not found") }
        return Adb.exec(p, args, timeout: timeout)
    }

    func mdnsServices() -> [MdnsService] {
        let r = run(["mdns", "services"], timeout: 10)
        var out: [MdnsService] = []
        for line in r.out.split(separator: "\n") {
            let f = line.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            guard f.count >= 3, f[1].hasPrefix("_adb-tls-") else { continue }
            out.append(MdnsService(instance: f[0], type: f[1], address: f[2]))
        }
        return out
    }

    func mdnsCheck() -> String {
        let r = run(["mdns", "check"], timeout: 10)
        return (r.out + r.err).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func devices() -> [Transport] {
        let r = run(["devices", "-l"], timeout: 10)
        var out: [Transport] = []
        for line in r.out.split(separator: "\n") {
            let s = line.trimmingCharacters(in: .whitespaces)
            if s.isEmpty || s.hasPrefix("List of devices") { continue }
            let f = s.split(whereSeparator: { $0 == "\t" || $0 == " " }).map(String.init)
            guard f.count >= 2 else { continue }
            var kv: [String: String] = [:]
            for part in f.dropFirst(2) {
                if let i = part.firstIndex(of: ":") {
                    kv[String(part[..<i])] = String(part[part.index(after: i)...])
                }
            }
            let serial = f[0]
            let isMdns = serial.contains("._adb-tls-connect._tcp")
            out.append(Transport(
                serial: serial,
                state: f[1],
                model: kv["model"],
                product: kv["product"],
                isMdns: isMdns,
                mdnsInstance: isMdns ? serial.replacingOccurrences(of: "._adb-tls-connect._tcp", with: "") : nil
            ))
        }
        return out
    }

    func connect(_ transportName: String) -> (ok: Bool, message: String) {
        let r = run(["connect", transportName], timeout: 20)
        let msg = (r.out + r.err).trimmingCharacters(in: .whitespacesAndNewlines)
        return (r.out.contains("connected to"), msg)
    }

    /// The recovery lever: a wedged mDNS client is fixed by a fresh server.
    func restartServer() -> String {
        let killed = run(["kill-server"], timeout: 15)
        let started = run(["start-server"], timeout: 25)
        return ((killed.out + killed.err) + (started.out + started.err))
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\n", with: " ")
    }

    func disconnect(_ transportName: String) -> String {
        let r = run(["disconnect", transportName], timeout: 10)
        return (r.out + r.err).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func pair(address: String, code: String) -> (ok: Bool, message: String) {
        let r = run(["pair", address, code], timeout: 45)
        let msg = (r.out + r.err).trimmingCharacters(in: .whitespacesAndNewlines)
        return (r.out.contains("Successfully paired"), msg)
    }

    func prop(_ transport: String, _ name: String) -> String? {
        let r = run(["-s", transport, "shell", "getprop", name], timeout: 10)
        let v = r.out.trimmingCharacters(in: .whitespacesAndNewlines)
        return v.isEmpty ? nil : v
    }
}
