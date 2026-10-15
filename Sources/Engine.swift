import Foundation

enum DeviceStatus: String {
    case connected
    case offline       // transport exists but is not usable (offline/unauthorized)
    case advertising   // on the network and advertising, not attached yet
    case absent
}

struct Row {
    let serial: String
    let label: String
    let model: String?
    let status: DeviceStatus
    let address: String?
    let transport: String?
    let state: String?
    let lastSeen: Date?
    let lastError: String?
    let paused: Bool
}

struct Discovered {
    let serial: String
    let label: String
    let transport: String?
    let address: String?
    let connected: Bool
}

struct Snapshot {
    var rows: [Row] = []
    var discovered: [Discovered] = []
    var mdns: String = ""
    var mdnsSummary: String = ""
    var adbPath: String = ""
    var adbVersion: String = ""
    var adbShort: String = ""
    var connectLog: [String] = []
    var updatedAt = Date()
}

/// All adb interaction lives here so the UI and `--dump` share one code path.
final class Engine {
    private let adb = Adb.shared
    let store: Store
    private var lastAttempt: [String: Date] = [:]
    private var failures: [String: Int] = [:]
    private var lastError: [String: String] = [:]
    private var lastSave = Date.distantPast
    private var cachedMdnsCheck = ""
    private var cachedMdnsCheckAt = Date.distantPast
    private var mdnsCheckTTL: TimeInterval = 60
    private var bonjourInstances: [String] = []
    private var bonjourAt = Date.distantPast
    private var lastServerRestart = Date.distantPast
    private var emptyServiceTicks = 0
    private let busyLock = NSLock()
    private var _busy = false

    /// True while a user-initiated adb action (pairing, connecting) is in flight.
    /// The wedge-recovery heuristic must never restart the shared adb server under
    /// an interactive operation.
    var busy: Bool {
        get { busyLock.lock(); defer { busyLock.unlock() }; return _busy }
        set { busyLock.lock(); _busy = newValue; busyLock.unlock() }
    }

    /// Test hook: pretend adb's mDNS client is blind, to exercise the recovery path.
    private static let faultNoMdns = ProcessInfo.processInfo.environment["ADBDOCK_FAULT_NO_MDNS"] == "1"

    init(store: Store) { self.store = store }

    func snapshot(autoConnect: Bool) -> Snapshot {
        var snap = Snapshot()
        snap.adbPath = adb.path ?? "not found"
        snap.adbVersion = adb.version ?? "adb not found"
        snap.adbShort = Engine.shortVersion(snap.adbVersion)

        // Any adb call starts the server when it is down; ask for services first
        // so the mdns check below talks to a live server.
        var services = adb.mdnsServices()
        var transports = adb.devices()
        if Engine.faultNoMdns { services = [] }

        if Date().timeIntervalSince(cachedMdnsCheckAt) > mdnsCheckTTL {
            cachedMdnsCheck = adb.mdnsCheck()
            cachedMdnsCheckAt = Date()
            let lower = cachedMdnsCheck.lowercased()
            mdnsCheckTTL = (cachedMdnsCheck.isEmpty || lower.contains("error")) ? 10 : 60
        }
        snap.mdns = cachedMdnsCheck
        snap.mdnsSummary = Engine.mdnsSummary(cachedMdnsCheck)

        // adb's own mDNS client can wedge; the system resolver does not. When adb
        // sees nothing, ask Bonjour — and if an approved device is advertising
        // there while nothing at all is attached, the app's adb server is the
        // broken part, so restart it. (2026-10-14: a server started while the
        // phone was off the network never re-discovered it; a restart fixed it.)
        if services.isEmpty {
            emptyServiceTicks += 1
            if Date().timeIntervalSince(bonjourAt) > 15 {
                bonjourInstances = Bonjour.connectInstances()
                bonjourAt = Date()
            }
        } else {
            emptyServiceTicks = 0
            bonjourInstances = []
            bonjourAt = Date()
        }
        // Three consecutive blind ticks (~15s) before touching the shared server,
        // and never while the user is pairing or connecting.
        if autoConnect, !busy, emptyServiceTicks >= 3, !bonjourInstances.isEmpty,
           !transports.contains(where: { $0.state == "device" }),
           Date().timeIntervalSince(lastServerRestart) > 300 {
            let stranded = store.devices.filter { d in
                !d.paused && bonjourInstances.contains { SerialId.fromMdns($0) == d.serial }
            }
            if !stranded.isEmpty {
                lastServerRestart = Date()
                let result = adb.restartServer()
                snap.connectLog.append("adb mDNS blind (Bonjour sees \(stranded.map { $0.serial }.joined(separator: ", "))) — restarted adb server: \(result)")
                services = adb.mdnsServices()
                transports = adb.devices()
                if Engine.faultNoMdns { services = [] }
            }
        }

        let connectServices = { services.filter { !$0.isPairing } }

        if autoConnect {
            var attempted = false
            for d in store.devices where !d.paused {
                let t = transports.first { $0.deviceSerial == d.serial }
                let usable = t?.state == "device"
                let needsUserAction = t?.state == "unauthorized"
                guard !usable, !needsUserAction,
                      let svc = connectServices().first(where: { $0.serial == d.serial }) else { continue }
                let last = lastAttempt[d.serial] ?? .distantPast
                // A device that is advertising but not paired can never connect;
                // don't hammer it every 20s forever.
                let throttle: TimeInterval = (failures[d.serial] ?? 0) >= 3 ? 300 : 20
                guard Date().timeIntervalSince(last) > throttle else { continue }
                lastAttempt[d.serial] = Date()
                attempted = true
                let r = adb.connect(svc.transportName)
                snap.connectLog.append("\(d.serial): \(r.message)")
                if r.ok {
                    failures[d.serial] = 0
                    lastError[d.serial] = nil
                } else {
                    failures[d.serial] = (failures[d.serial] ?? 0) + 1
                    lastError[d.serial] = r.message
                }
            }
            if attempted {
                transports = adb.devices()
                services = adb.mdnsServices()
            }
        }

        var sawSomething = false
        for d in store.devices {
            let t = transports.first { $0.deviceSerial == d.serial }
            let svc = services.first { !$0.isPairing && $0.serial == d.serial }
            if t != nil || svc != nil {
                sawSomething = true
                store.touch(serial: d.serial, address: svc?.address)
            }
        }

        for d in store.devices {
            let t = transports.first { $0.deviceSerial == d.serial }
            let svc = services.first { !$0.isPairing && $0.serial == d.serial }
            var status: DeviceStatus
            var address = svc?.address
            if let t = t {
                status = t.state == "device" ? .connected : .offline
                if address == nil && !t.isMdns { address = "USB" }
            } else if svc != nil {
                status = .advertising
            } else {
                status = .absent
            }
            if status == .connected && address == nil { address = "wireless" }
            snap.rows.append(Row(
                serial: d.serial,
                label: d.label,
                model: d.model ?? t?.model,
                status: status,
                address: address,
                transport: t?.serial ?? svc?.transportName,
                state: t?.state,
                lastSeen: d.lastSeen,
                lastError: status == .advertising ? lastError[d.serial] : nil,
                paused: d.paused
            ))
        }

        var known = Set(store.devices.map { $0.serial })
        var discovered: [Discovered] = []
        for t in transports where !known.contains(t.deviceSerial) {
            known.insert(t.deviceSerial)
            discovered.append(Discovered(
                serial: t.deviceSerial,
                label: t.model ?? t.deviceSerial,
                transport: t.serial,
                address: nil,
                connected: t.state == "device"
            ))
        }
        for s in connectServices() where !known.contains(s.serial) {
            known.insert(s.serial)
            discovered.append(Discovered(
                serial: s.serial,
                label: "Unlisted device",
                transport: s.transportName,
                address: s.address,
                connected: false
            ))
        }
        snap.discovered = discovered

        if sawSomething && Date().timeIntervalSince(lastSave) > 300 {
            store.save()
            lastSave = Date()
        }
        snap.updatedAt = Date()
        return snap
    }

    static func shortVersion(_ v: String) -> String {
        // "Android Debug Bridge version 1.0.41" -> "1.0.41"
        if let r = v.range(of: "version ") { return String(v[r.upperBound...]) }
        return v
    }

    static func mdnsSummary(_ raw: String) -> String {
        let s = raw.lowercased()
        if raw.isEmpty { return "no response" }
        if s.contains("error") || s.contains("unavailable") || s.contains("cannot") { return "unavailable" }
        if s.contains("openscreen") { return "ok (openscreen)" }
        if s.contains("version [") { return "ok (bonjour)" }   // "mdns daemon version [2881160004]"
        if s.contains("discovery") { return "ok (adb)" }       // "adb discovery 0.0.0" — adb's default backend
        return raw.count > 40 ? String(raw.prefix(40)) + "…" : raw
    }

    func json(_ s: Snapshot) -> [String: Any] {
        let iso = ISO8601DateFormatter()
        var out: [String: Any] = [
            "updatedAt": iso.string(from: s.updatedAt),
            "adbPath": s.adbPath,
            "adbVersion": s.adbVersion,
            "mdns": s.mdns,
            "mdnsSummary": s.mdnsSummary,
            "connectLog": s.connectLog,
        ]
        out["devices"] = s.rows.map { r -> [String: Any] in
            var d: [String: Any] = ["serial": r.serial, "label": r.label, "status": r.status.rawValue]
            if let m = r.model { d["model"] = m }
            if let a = r.address { d["address"] = a }
            if let t = r.transport { d["transport"] = t }
            if let st = r.state { d["state"] = st }
            if let l = r.lastSeen { d["lastSeen"] = iso.string(from: l) }
            if let e = r.lastError { d["lastError"] = e }
            if r.paused { d["paused"] = true }
            return d
        }
        out["discovered"] = s.discovered.map { x -> [String: Any] in
            var d: [String: Any] = ["serial": x.serial, "label": x.label, "connected": x.connected]
            if let t = x.transport { d["transport"] = t }
            if let a = x.address { d["address"] = a }
            return d
        }
        return out
    }
}
