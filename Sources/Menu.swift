import AppKit
import Foundation

/// Builds the status menu. Kept separate from the app delegate so `--menu` can
/// render the exact same menu as text for inspection.
final class MenuBuilder {
    private let snapshot: Snapshot
    private weak var target: AnyObject?
    private let loginOn: Bool

    init(snapshot: Snapshot, target: AnyObject?, loginOn: Bool) {
        self.snapshot = snapshot
        self.target = target
        self.loginOn = loginOn
    }

    func build() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        let s = snapshot

        let header = NSMenuItem(title: "ADB Dock", action: nil, keyEquivalent: "")
        header.attributedTitle = NSAttributedString(string: "ADB Dock", attributes: [
            .font: NSFont.boldSystemFont(ofSize: NSFont.systemFontSize),
            .foregroundColor: NSColor.labelColor,
        ])
        header.isEnabled = false
        menu.addItem(header)

        if s.rows.isEmpty {
            menu.addItem(disabled(s.adbVersion == "adb not found"
                ? "adb not found — install android-platform-tools"
                : "No approved devices yet — use Pair new device…"))
        }
        for row in s.rows { menu.addItem(deviceItem(row)) }

        if !s.discovered.isEmpty {
            menu.addItem(.separator())
            menu.addItem(disabled("Discovered — not in list"))
            for d in s.discovered { menu.addItem(discoveredItem(d)) }
        }

        menu.addItem(.separator())
        menu.addItem(actionItem("Pair new device…", #selector(AppDelegate.pairNewDevice), "p"))
        menu.addItem(actionItem("Refresh now", #selector(AppDelegate.refreshNow), "r"))
        menu.addItem(actionItem("Restart adb server", #selector(AppDelegate.restartAdbServer), ""))
        menu.addItem(.separator())

        let login = actionItem("Start at login", #selector(AppDelegate.toggleLogin), "")
        login.state = loginOn ? .on : .off
        menu.addItem(login)
        menu.addItem(actionItem("Reveal devices.json", #selector(AppDelegate.revealStore), ""))
        menu.addItem(.separator())
        menu.addItem(disabled("adb \(s.adbShort) · mDNS: \(s.mdnsSummary)"))
        menu.addItem(actionItem("Quit ADB Dock", #selector(AppDelegate.quit), "q"))
        return menu
    }

    private func disabled(_ title: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        i.isEnabled = false
        return i
    }

    private func actionItem(_ title: String, _ sel: Selector, _ key: String) -> NSMenuItem {
        let i = NSMenuItem(title: title, action: sel, keyEquivalent: key)
        i.target = target
        i.isEnabled = true
        return i
    }

    private func rowTitle(_ row: Row) -> NSAttributedString {
        let color: NSColor
        let glyph: String
        switch row.status {
        case .connected: color = .systemGreen; glyph = "●"
        case .advertising: color = .systemYellow; glyph = "●"
        case .offline: color = .systemOrange; glyph = "●"
        case .absent: color = .tertiaryLabelColor; glyph = "○"
        }
        let detail: String
        switch row.status {
        case .connected: detail = row.address ?? "connected"
        case .advertising: detail = row.lastError != nil ? "connect failed — pair it?" : "connecting…"
        case .offline: detail = row.state ?? "offline"
        case .absent: detail = "not on network"
        }
        let out = NSMutableAttributedString(string: glyph + "  ", attributes: [.foregroundColor: color])
        out.append(NSAttributedString(string: row.label, attributes: [.foregroundColor: NSColor.labelColor]))
        out.append(NSAttributedString(string: "   " + detail, attributes: [.foregroundColor: NSColor.secondaryLabelColor]))
        return out
    }

    private func deviceItem(_ row: Row) -> NSMenuItem {
        let item = NSMenuItem(title: row.label, action: nil, keyEquivalent: "")
        item.attributedTitle = rowTitle(row)

        let sub = NSMenu()
        sub.autoenablesItems = false
        sub.addItem(disabled("Serial: \(row.serial)"))
        if let m = row.model { sub.addItem(disabled("Model: \(m)")) }
        if let a = row.address { sub.addItem(disabled("Address: \(a)")) }
        if let st = row.state { sub.addItem(disabled("Transport state: \(st)")) }
        if let l = row.lastSeen {
            let f = DateFormatter()
            f.dateStyle = .short
            f.timeStyle = .short
            sub.addItem(disabled("Last seen: \(f.string(from: l))"))
        }
        sub.addItem(.separator())

        let connect = NSMenuItem(title: "Connect now", action: #selector(AppDelegate.connectNow(_:)), keyEquivalent: "")
        connect.target = target
        connect.representedObject = row.serial
        connect.isEnabled = row.status != .connected
        sub.addItem(connect)

        let disconnect = NSMenuItem(title: "Disconnect", action: #selector(AppDelegate.disconnectNow(_:)), keyEquivalent: "")
        disconnect.target = target
        disconnect.representedObject = row.serial
        disconnect.isEnabled = row.status == .connected || row.status == .offline
        sub.addItem(disconnect)

        sub.addItem(.separator())
        let rename = NSMenuItem(title: "Rename…", action: #selector(AppDelegate.renameDevice(_:)), keyEquivalent: "")
        rename.target = target
        rename.representedObject = row.serial
        sub.addItem(rename)

        let forget = NSMenuItem(title: "Remove from list", action: #selector(AppDelegate.forgetDevice(_:)), keyEquivalent: "")
        forget.target = target
        forget.representedObject = row.serial
        sub.addItem(forget)

        item.submenu = sub
        item.isEnabled = true
        return item
    }

    private func discoveredItem(_ d: Discovered) -> NSMenuItem {
        let item = NSMenuItem(title: "+ Add \"\(d.label)\"", action: #selector(AppDelegate.addDiscovered(_:)), keyEquivalent: "")
        item.target = target
        item.representedObject = d.serial
        item.isEnabled = true
        item.toolTip = d.connected ? "connected · \(d.serial)" : (d.address.map { "\($0) · \(d.serial)" } ?? d.serial)
        return item
    }

    // MARK: text rendering (--menu)

    static func describe(_ menu: NSMenu, indent: String = "") -> String {
        var lines: [String] = []
        for item in menu.items {
            if item.isSeparatorItem {
                lines.append("\(indent)────")
                continue
            }
            let title = item.attributedTitle?.string ?? item.title
            var flags: [String] = []
            if !item.isEnabled { flags.append("disabled") }
            if item.state == .on { flags.append("on") }
            if !item.keyEquivalent.isEmpty { flags.append("⌘\(item.keyEquivalent)") }
            var line = "\(indent)\(title)" + (flags.isEmpty ? "" : "   [\(flags.joined(separator: ", "))]")
            if let sub = item.submenu {
                line += "\n" + describe(sub, indent: indent + "    ")
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }
}
