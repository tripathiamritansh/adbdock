import AppKit
import Carbon.HIToolbox
import Darwin
import Foundation

enum LoginItem {
    /// Derived from the app's bundle identifier so there is a single source of
    /// truth: set `BUNDLE_ID` in build.sh (or an untracked local.env) and both
    /// the app and its LaunchAgent use it.
    static let label = Bundle.main.bundleIdentifier ?? "com.example.adbdock"
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(label).plist")
    }
    static var isEnabled: Bool { FileManager.default.fileExists(atPath: plistURL.path) }
}

// MARK: - CLI modes

let args = CommandLine.arguments

if args.contains("--dump") || args.contains("--menu") {
    _ = NSApplication.shared
    let store = Store()
    store.load()
    let engine = Engine(store: store)
    let snap = engine.snapshot(autoConnect: false)
    if args.contains("--dump") {
        if let data = try? JSONSerialization.data(withJSONObject: engine.json(snap), options: [.prettyPrinted, .sortedKeys]) {
            FileHandle.standardOutput.write(data)
            print("")
        }
    } else {
        let menu = MenuBuilder(snapshot: snap, target: nil, loginOn: LoginItem.isEnabled).build()
        print(MenuBuilder.describe(menu))
    }
    exit(0)
}

// MARK: - Menu bar app

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let store = Store()
    private lazy var engine = Engine(store: store)
    private let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
    private var snapshot = Snapshot()
    private var refreshing = false
    private var hotKey: HotKey?
    private var lastStateWrite = Date.distantPast
    private var lastStateJSON = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.reset()
        store.load()
        NSApp.setActivationPolicy(.accessory)
        AppLog.write("launch bundle=\(Bundle.main.bundlePath) devices=\(store.devices.count)")
        AppLog.write("adb path=\(Adb.shared.path ?? "not found") version=\(Adb.shared.version ?? "unknown")")
        AppLog.write("screens " + NSScreen.screens.map { "\($0.frame)" }.joined(separator: " "))
        // An accessory app has no menu bar; an empty one makes the status item
        // reachable from System Events (accessibility tooling, tests).
        NSApp.mainMenu = NSMenu()

        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "antenna.radiowaves.left.and.right",
                                   accessibilityDescription: "ADB Dock")
            button.image?.isTemplate = true
            button.toolTip = "ADB Dock"
        }
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.logStatusItemGeometry(attempt: 1)
        }

        hotKey = HotKey(keyCode: UInt32(kVK_ANSI_A),
                        modifiers: UInt32(controlKey | optionKey | cmdKey)) { [weak self] in
            self?.openMenu()
        }

        refresh()
        let timer = Timer(timeInterval: 5, repeats: true) { [weak self] _ in self?.refresh() }
        RunLoop.main.add(timer, forMode: .common)
    }

    /// Records where the status item landed and warns when macOS parked it behind
    /// the notch. Retries because the item's window has no screen attached for the
    /// first moments after launch (its frame is not yet placed either).
    private func logStatusItemGeometry(attempt: Int) {
        guard let button = statusItem.button else { return }
        let frame = button.window?.frame ?? .zero
        let screen = button.window?.screen
        if screen == nil && attempt < 5 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
                self?.logStatusItemGeometry(attempt: attempt + 1)
            }
            return
        }
        AppLog.write("statusItem visible=\(statusItem.isVisible) frame=\(frame) screen=\(screen?.frame.debugDescription ?? "unknown")")
        // Notch geometry is in global coordinates, same as the item frame, so the
        // x axis is directly comparable.
        if let screen = screen,
           let left = screen.auxiliaryTopLeftArea,
           let right = screen.auxiliaryTopRightArea {
            AppLog.write("screen notch gap x \(left.maxX)…\(right.minX)")
            if frame.minX >= left.maxX, frame.maxX <= right.minX {
                AppLog.write("WARNING: status item is behind the notch — press ⌃⌥⌘A to open the menu, or free menu bar space")
            }
        }
    }

    // MARK: refresh loop

    private func refresh() {
        guard !refreshing else { return }
        refreshing = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            guard let self = self else { return }
            let snap = self.engine.snapshot(autoConnect: true)
            DispatchQueue.main.async {
                self.snapshot = snap
                self.refreshing = false
                self.updateStatusButton()
                self.writeState(snap)
                for line in snap.connectLog { AppLog.write("autoconnect \(line)") }
            }
        }
    }

    private func updateStatusButton() {
        let connected = snapshot.rows.filter { $0.status == .connected }.count
        statusItem.button?.toolTip = "ADB Dock — \(connected)/\(snapshot.rows.count) approved devices connected"
    }

    private func writeState(_ s: Snapshot) {
        guard let data = try? JSONSerialization.data(withJSONObject: engine.json(s), options: [.prettyPrinted, .sortedKeys]) else { return }
        let str = String(decoding: data, as: UTF8.self)
        let changed = str != lastStateJSON
        guard changed || Date().timeIntervalSince(lastStateWrite) > 60 else { return }
        lastStateJSON = str
        lastStateWrite = Date()
        try? FileManager.default.createDirectory(at: Store.dir, withIntermediateDirectories: true)
        try? data.write(to: store.stateURL, options: .atomic)
    }

    // MARK: menu

    func menuNeedsUpdate(_ menu: NSMenu) {
        let built = MenuBuilder(snapshot: snapshot, target: self, loginOn: LoginItem.isEnabled).build()
        menu.removeAllItems()
        while let item = built.items.first {
            built.removeItem(item)
            menu.addItem(item)
        }
        AppLog.write("menu opened items=\(menu.items.count) rows=\(snapshot.rows.count) discovered=\(snapshot.discovered.count)")
    }

    // MARK: actions

    /// Opens the status menu. Works even when the item is parked behind the notch.
    private func openMenu() {
        AppLog.write("hotkey ⌃⌥⌘A: opening menu")
        refresh()
        statusItem.button?.performClick(nil)
    }

    @objc func refreshNow() { refresh() }

    @objc func restartAdbServer() {
        let result = Adb.shared.restartServer()
        AppLog.write("restart adb server (manual): \(result)")
        refresh()
    }

    @objc func quit() {
        AppLog.write("quit")
        NSApp.terminate(nil)
    }

    @objc func revealStore() {
        try? FileManager.default.createDirectory(at: Store.dir, withIntermediateDirectories: true)
        NSWorkspace.shared.activateFileViewerSelecting([store.devicesURL])
    }

    @objc func connectNow(_ sender: NSMenuItem) {
        guard let serial = sender.representedObject as? String else { return }
        guard let svc = Adb.shared.mdnsServices().first(where: { !$0.isPairing && $0.serial == serial }) else {
            AppLog.write("connectNow \(serial): not advertising")
            alert("Connect now", "\(serial) is not advertising on this network.\n\nCheck that Wireless debugging is on for the device and that it is on the same Wi-Fi network as this Mac.")
            return
        }
        let r = Adb.shared.connect(svc.transportName)
        AppLog.write("connectNow \(serial): \(r.message)")
        if !r.ok { alert("Connect failed", r.message) }
        refresh()
    }

    @objc func disconnectNow(_ sender: NSMenuItem) {
        guard let serial = sender.representedObject as? String else { return }
        guard let t = Adb.shared.devices().first(where: { $0.deviceSerial == serial }) else { return }
        let message = Adb.shared.disconnect(t.serial)
        AppLog.write("disconnect \(serial): \(message)")
        if !message.contains("disconnected") { alert("Disconnect", message) }
        refresh()
    }

    @objc func renameDevice(_ sender: NSMenuItem) {
        guard let serial = sender.representedObject as? String,
              let d = store.devices.first(where: { $0.serial == serial }) else { return }
        let a = NSAlert()
        a.messageText = "Rename device"
        a.informativeText = "Serial \(serial)"
        a.addButton(withTitle: "Save")
        a.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.stringValue = d.label
        a.accessoryView = field
        a.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if !name.isEmpty {
                store.rename(serial: serial, label: name)
                AppLog.write("rename \(serial) -> \(name)")
            }
        }
        refresh()
    }

    @objc func forgetDevice(_ sender: NSMenuItem) {
        guard let serial = sender.representedObject as? String else { return }
        let a = NSAlert()
        a.messageText = "Remove \(serial) from the list?"
        a.informativeText = "The adb pairing key is kept, so it can be added again without re-pairing."
        a.addButton(withTitle: "Remove")
        a.addButton(withTitle: "Cancel")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            store.remove(serial: serial)
            AppLog.write("remove \(serial) from list")
            refresh()
        }
    }

    @objc func addDiscovered(_ sender: NSMenuItem) {
        guard let serial = sender.representedObject as? String else { return }
        let transports = Adb.shared.devices()
        let services = Adb.shared.mdnsServices()
        let t = transports.first { $0.deviceSerial == serial }
        let svc = services.first { !$0.isPairing && $0.serial == serial }
        var model = t?.model
        var label = model ?? serial
        var connectFailure: String?
        if let transport = t?.serial ?? svc?.transportName {
            let r = Adb.shared.connect(transport)
            AppLog.write("add \(serial): connect -> \(r.message)")
            if !r.ok && t?.state != "device" { connectFailure = r.message }
            if model == nil, let m = Adb.shared.prop(transport, "ro.product.model") {
                model = m
                label = m
            }
        }
        store.add(serial: serial, label: label, model: model)
        AppLog.write("add \(serial) label=\(label)")
        if let failure = connectFailure {
            alert("Added, but could not connect", "\(label) is advertising on the network but adb could not attach it:\n\n\(failure)\n\nIf this device has never been paired with this Mac, use “Pair new device…” instead — on the phone: Settings → Developer options → Wireless debugging → Pair device with pairing code.\n\nIt stays in the list and connects automatically once it is paired.")
        }
        refresh()
    }

    @objc func pairNewDevice() {
        guard let pairing = Adb.shared.mdnsServices().first(where: { $0.isPairing }) else {
            AppLog.write("pair: no device in pairing mode")
            alert("Pair new device", "No device is in pairing mode.\n\nOn the phone: Settings → Developer options → Wireless debugging → Pair device with pairing code. Then choose this menu item again.")
            return
        }
        let a = NSAlert()
        a.messageText = "Pair \(pairing.address)"
        a.informativeText = "Enter the 6-digit pairing code shown on the device."
        a.addButton(withTitle: "Pair")
        a.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 220, height: 24))
        field.placeholderString = "6-digit code"
        a.accessoryView = field
        a.window.initialFirstResponder = field
        NSApp.activate(ignoringOtherApps: true)
        guard a.runModal() == .alertFirstButtonReturn else { return }
        let code = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { return }

        let r = Adb.shared.pair(address: pairing.address, code: code)
        AppLog.write("pair \(pairing.address): \(r.message)")
        guard r.ok else {
            alert("Pairing failed", r.message)
            return
        }

        // The connect service appears shortly after pairing.
        var connectService: MdnsService?
        for _ in 0..<20 {
            connectService = Adb.shared.mdnsServices().first { !$0.isPairing && $0.serial == pairing.serial }
            if connectService != nil { break }
            Thread.sleep(forTimeInterval: 0.5)
        }

        var model: String?
        if let transport = connectService?.transportName {
            let c = Adb.shared.connect(transport)
            AppLog.write("pair \(pairing.serial): connect -> \(c.message)")
            if !c.ok { alert("Paired, but connect failed", c.message) }
            model = Adb.shared.prop(transport, "ro.product.model")
        }
        let label = model ?? "Device \(pairing.serial)"
        store.add(serial: pairing.serial, label: label, model: model)
        AppLog.write("paired \(pairing.serial) label=\(label) connected=\(connectService != nil)")
        alert("Paired", "\(label) added to the approved list." + (connectService == nil
            ? "\n\nIt is not advertising on this network yet; it will connect automatically once it is."
            : ""))
        refresh()
    }

    // MARK: start at login

    @objc func toggleLogin() {
        if LoginItem.isEnabled {
            try? FileManager.default.removeItem(at: LoginItem.plistURL)
            if getppid() != 1 {   // don't bootout the job that launched this very process
                let r = runLaunchctl(["bootout", "gui/\(getuid())/\(LoginItem.label)"])
                AppLog.write("login off: bootout status=\(r.code) \(r.out)")
            } else {
                AppLog.write("login off: plist removed (running from launchd; job stops at logout)")
            }
            return
        }
        let bundlePath = Bundle.main.bundlePath
        guard bundlePath.hasSuffix(".app") else {
            alert("Start at login", "Run the app from AdbDock.app (the build output), not from the raw binary.")
            return
        }
        let exe = xmlEscape(bundlePath + "/Contents/MacOS/AdbDock")
        let plist = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>\(LoginItem.label)</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(exe)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>ProcessType</key>
            <string>Interactive</string>
        </dict>
        </plist>
        """
        do {
            try FileManager.default.createDirectory(at: LoginItem.plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try plist.write(to: LoginItem.plistURL, atomically: true, encoding: .utf8)
        } catch {
            AppLog.write("login on failed: \(error)")
            alert("Start at login", "Could not write \(LoginItem.plistURL.path):\n\(error)")
            return
        }
        let r = runLaunchctl(["bootstrap", "gui/\(getuid())", LoginItem.plistURL.path])
        AppLog.write("login on: bootstrap status=\(r.code) \(r.out)")
        if r.code != 0 && !r.out.contains("already") {
            alert("Start at login", "launchctl bootstrap failed:\n\(r.out)")
        }
    }

    private func runLaunchctl(_ args: [String]) -> (code: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/launchctl")
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe
        guard (try? p.run()) != nil else { return (-1, "launchctl failed to run") }
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    @discardableResult
    private func alert(_ title: String, _ body: String) -> NSApplication.ModalResponse {
        AppLog.write("alert: \(title) — \(body.replacingOccurrences(of: "\n", with: " "))")
        let a = NSAlert()
        a.messageText = title
        a.informativeText = body
        a.addButton(withTitle: "OK")
        NSApp.activate(ignoringOtherApps: true)
        return a.runModal()
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
