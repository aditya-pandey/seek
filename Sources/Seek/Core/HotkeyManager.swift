import AppKit
import Carbon

public enum SeekHotkeyPreset: String, CaseIterable {
    case optionF         = "option_f"
    case optionSpace     = "option_space"
    case commandShiftSpace = "cmd_shift_space"

    public var displayLabel: String {
        switch self {
        case .optionF:           return "⌥ F (Default — works alongside WeaponWheel)"
        case .optionSpace:       return "⌥ Space"
        case .commandShiftSpace: return "⌘ ⇧ Space"
        }
    }

    public var shortLabel: String {
        switch self {
        case .optionF:           return "⌥ F"
        case .optionSpace:       return "⌥ Space"
        case .commandShiftSpace: return "⌘⇧Space"
        }
    }

    public var keyCode: UInt32 {
        switch self {
        case .optionF:           return UInt32(kVK_ANSI_F)
        case .optionSpace:       return UInt32(kVK_Space)
        case .commandShiftSpace: return UInt32(kVK_Space)
        }
    }

    public var carbonModifiers: UInt32 {
        switch self {
        case .optionF:           return UInt32(optionKey)
        case .optionSpace:       return UInt32(optionKey)
        case .commandShiftSpace: return UInt32(cmdKey | shiftKey)
        }
    }
}

public final class HotkeyManager {
    private static let defaultsKey = "SeekHotkeyPreset"
    public var onToggleSeek: (() -> Void)?

    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?

    public var currentPreset: SeekHotkeyPreset {
        get {
            if let raw = UserDefaults.standard.string(forKey: Self.defaultsKey),
               let preset = SeekHotkeyPreset(rawValue: raw) {
                return preset
            }
            return .optionF
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: Self.defaultsKey)
            register(preset: newValue)
        }
    }

    public init() {}

    deinit {
        unregister()
    }

    public func registerCurrentPreset() {
        register(preset: currentPreset)
    }

    public func register(preset: SeekHotkeyPreset) {
        unregister()

        var eventType = EventTypeSpec(
            eventClass: OSType(kEventClassKeyboard),
            eventKind: UInt32(kEventHotKeyPressed)
        )

        let selfPtr = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        InstallEventHandler(
            GetApplicationEventTarget(),
            { (_, _, userData) -> OSStatus in
                guard let userData = userData else { return noErr }
                let mgr = Unmanaged<HotkeyManager>.fromOpaque(userData).takeUnretainedValue()
                DispatchQueue.main.async {
                    mgr.onToggleSeek?()
                }
                return noErr
            },
            1,
            &eventType,
            selfPtr,
            &eventHandler
        )

        let hotKeyID = EventHotKeyID(signature: OSType(0x5345454B), id: 1) // 'SEEK'
        RegisterEventHotKey(
            preset.keyCode,
            preset.carbonModifiers,
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
        print("[Seek] Global hotkey registered: \(preset.shortLabel)")
    }

    public func unregister() {
        if let hk = hotKeyRef {
            UnregisterEventHotKey(hk)
            hotKeyRef = nil
        }
        if let handler = eventHandler {
            RemoveEventHandler(handler)
            eventHandler = nil
        }
    }
}
