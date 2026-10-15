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
}

final class Store {
    static var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("AdbDock", isDirectory: true)
    }

    var devicesURL: URL { Store.dir.appendingPathComponent("devices.json") }
    var stateURL: URL { Store.dir.appendingPathComponent("state.json") }

    private(set) var devices: [Device] = []

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

    func load() {
        guard let data = try? Data(contentsOf: devicesURL),
              let list = try? Store.decoder.decode([Device].self, from: data) else {
            devices = []
            return
        }
        devices = list
    }

    func save() {
        try? FileManager.default.createDirectory(at: Store.dir, withIntermediateDirectories: true)
        guard let data = try? Store.encoder.encode(devices) else { return }
        try? data.write(to: devicesURL, options: .atomic)
    }

    func contains(serial: String) -> Bool { devices.contains { $0.serial == serial } }

    func add(serial: String, label: String, model: String?) {
        guard !contains(serial: serial) else { return }
        devices.append(Device(serial: serial, label: label, model: model, addedAt: Date(), lastSeen: nil, lastAddress: nil))
        save()
    }

    func remove(serial: String) {
        devices.removeAll { $0.serial == serial }
        save()
    }

    func rename(serial: String, label: String) {
        guard let i = devices.firstIndex(where: { $0.serial == serial }) else { return }
        devices[i].label = label
        save()
    }

    func touch(serial: String, address: String?) {
        guard let i = devices.firstIndex(where: { $0.serial == serial }) else { return }
        devices[i].lastSeen = Date()
        if let a = address { devices[i].lastAddress = a }
    }
}
