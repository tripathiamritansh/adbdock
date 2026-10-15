import Carbon.HIToolbox
import Foundation

/// A system-wide hotkey via Carbon's RegisterEventHotKey (no Accessibility
/// permission needed, unlike a CGEvent tap).
///
/// Why it exists: on a notched MacBook the menu bar's status-item area can fill
/// up and the system parks extra items *behind the notch*, where they are
/// invisible and unclickable. The hotkey opens the menu anyway.
final class HotKey {
    private var hotKeyRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private let action: () -> Void

    init(keyCode: UInt32, modifiers: UInt32, action: @escaping () -> Void) {
        self.action = action
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard),
                                      eventKind: UInt32(kEventHotKeyPressed))
        let handlerStatus = InstallEventHandler(GetApplicationEventTarget(), { _, _, userData -> OSStatus in
            guard let userData = userData else { return noErr }
            Unmanaged<HotKey>.fromOpaque(userData).takeUnretainedValue().fire()
            return noErr
        }, 1, &eventType, Unmanaged.passUnretained(self).toOpaque(), &handlerRef)

        let hotKeyID = EventHotKeyID(signature: OSType(0x4144_4257), id: 1)   // 'ADBW'
        let registerStatus = RegisterEventHotKey(keyCode, modifiers, hotKeyID, GetApplicationEventTarget(), 0, &hotKeyRef)
        if handlerStatus != noErr || registerStatus != noErr {
            AppLog.write("hotkey: registration failed (handler=\(handlerStatus) hotkey=\(registerStatus)) — another app may already own the combination")
        }
    }

    private func fire() {
        DispatchQueue.main.async { [weak self] in self?.action() }
    }

    deinit {
        if let ref = hotKeyRef { UnregisterEventHotKey(ref) }
        if let ref = handlerRef { RemoveEventHandler(ref) }
    }
}
