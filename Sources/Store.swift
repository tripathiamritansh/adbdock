import Foundation

/// A device the user has put on the approved list. Identity is the device
/// serial, not the mdns instance name (whose random suffix changes per adbd
/// start) and not the address (whose port changes per wireless-debugging
/// toggle).
struct Device: Codable {
    var serial: String
    var label: String
    var model: String?
    var addedAt: Date
    var lastSeen: Date?
    var lastAddress: String?
    /// Paused means "hands off": the app stops managing this device (no
    /// auto-attach, no reconnect after a drop, and it will not trigger an adb
    /// server restart) while leaving the adb transport exactly as it is.
    var paused: Bool = false
}

extension Device {
    /// Tolerant decoding: `paused` was added after the first release, and a
    /// missing key must not wipe someone's approved list.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        serial = try c.decode(String.self, forKey: .serial)
        label = try c.decode(String.self, forKey: .label)
        model = try c.decodeIfPresent(String.self, forKey: .model)
        addedAt = try c.decode(Date.self, forKey: .addedAt)
        lastSeen = try c.decodeIfPresent(Date.self, forKey: .lastSeen)
        lastAddress = try c.decodeIfPresent(String.self, forKey: .lastAddress)
        paused = try c.decodeIfPresent(Bool.self, forKey: .paused) ?? false
    }
}

final class Store {
    static var dir: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support", isDirectory: true)
        return base.appendingPathComponent("AdbDock", isDirectory: true)
    }

    var devicesURL: URL { Store.dir.appendingPathComponent("devices.json") }
    var stateURL: URL { Store.dir.appendingPathComponent("state.json") }

    private var stored: [Device] = []
    private let lock = NSLock()

    /// Serialised copy: the engine reads this from a background queue while menu
    /// actions mutate on the main thread. Concurrent array access would be
    /// undefined behaviour (a click during an in-flight refresh).
    var devices: [Device] {
        lock.lock()
        defer { lock.unlock() }
        return stored
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys]
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    /// 0700 — the state holds device serials, LAN addresses and labels, which are
    /// nobody else's business on a shared or managed Mac.
    static func ensureDirectory() {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true,
                                attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: dir.path)
    }

    static func restrict(_ url: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }

    func load() {
        Store.ensureDirectory()
        guard let data = try? Data(contentsOf: devicesURL),
              let list = try? Store.decoder.decode([Device].self, from: data) else {
            lock.lock(); stored = []; lock.unlock()
            return
        }
        lock.lock(); stored = list; lock.unlock()
    }

    func save() {
        Store.ensureDirectory()
        lock.lock()
        let list = stored
        lock.unlock()
        guard let data = try? Store.encoder.encode(list) else { return }
        try? data.write(to: devicesURL, options: .atomic)
        Store.restrict(devicesURL)
    }

    func contains(serial: String) -> Bool { devices.contains { $0.serial == serial } }

    func add(serial: String, label: String, model: String?) {
        lock.lock()
        let exists = stored.contains { $0.serial == serial }
        if !exists {
            stored.append(Device(serial: serial, label: label, model: model,
                                 addedAt: Date(), lastSeen: nil, lastAddress: nil))
        }
        lock.unlock()
        if !exists { save() }
    }

    func remove(serial: String) {
        lock.lock()
        stored.removeAll { $0.serial == serial }
        lock.unlock()
        save()
    }

    func rename(serial: String, label: String) {
        lock.lock()
        if let i = stored.firstIndex(where: { $0.serial == serial }) { stored[i].label = label }
        lock.unlock()
        save()
    }

    func setPaused(serial: String, _ paused: Bool) {
        lock.lock()
        if let i = stored.firstIndex(where: { $0.serial == serial }) { stored[i].paused = paused }
        lock.unlock()
        save()
    }

    func touch(serial: String, address: String?) {
        lock.lock()
        if let i = stored.firstIndex(where: { $0.serial == serial }) {
            stored[i].lastSeen = Date()
            if let a = address { stored[i].lastAddress = a }
        }
        lock.unlock()
    }
}
