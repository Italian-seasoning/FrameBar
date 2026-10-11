import Carbon
import AppKit

/// An OS hotkey avoids an accessibility permission or a per-keystroke event tap.
@MainActor final class OverlayShortcut {
    private var hotKey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    var action: (() -> Void)?
    var registered: Bool { hotKey != nil }
    static func matches(_ event: NSEvent) -> Bool {
        event.keyCode == UInt16(kVK_ANSI_O)
            && event.modifierFlags.intersection([.command, .option, .control, .shift]) == [.command, .option, .control]
    }

    init() {
        var type = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            guard let context else { return OSStatus(eventNotHandledErr) }
            let shortcut = Unmanaged<OverlayShortcut>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated { shortcut.action?() }
            return noErr
        }, 1, &type, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func setEnabled(_ enabled: Bool) {
        if let hotKey { UnregisterEventHotKey(hotKey); self.hotKey = nil }
        guard enabled else { return }
        let id = EventHotKeyID(signature: 0x46424152, id: 1)
        RegisterEventHotKey(UInt32(kVK_ANSI_O), UInt32(cmdKey | optionKey | controlKey), id,
                            GetApplicationEventTarget(), 0, &hotKey)
    }

    deinit {
        if let hotKey { UnregisterEventHotKey(hotKey) }
        if let handler { RemoveEventHandler(handler) }
    }
}
