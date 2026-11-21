import AppKit
import Quartz

/// Vibrant, borderless floating NSPanel that smoothly morphs between Seek's
/// compact frosted search bar and its expanded two-pane preview palette.
public final class SeekPanel: NSPanel {
    public var onEscape: (() -> Void)?
    public var onResignKey: (() -> Void)?
    public weak var primaryTextField: NSTextField?
    public weak var quickLookDataSource: QLPreviewPanelDataSource?
    public weak var quickLookDelegate: QLPreviewPanelDelegate?

    override public var canBecomeKey: Bool { true }
    override public var canBecomeMain: Bool { true }

    override public func resignKey() {
        super.resignKey()
        onResignKey?()
    }

    override public func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        return quickLookDataSource != nil
    }

    override public func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = quickLookDataSource
        panel.delegate = quickLookDelegate
    }

    override public func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = nil
        panel.delegate = nil
    }

    public func focusPrimaryTextField(selectAll: Bool = false) {
        guard let tf = primaryTextField else { return }
        self.makeFirstResponder(tf)
        if let editor = tf.currentEditor() {
            if selectAll {
                editor.selectAll(nil)
            } else {
                editor.selectedRange = NSRange(location: tf.stringValue.count, length: 0)
            }
        }
    }

    override public func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown {
            if event.keyCode == 53 { // Escape
                onEscape?()
                return
            }

            if let tf = primaryTextField,
               self.firstResponder !== tf && self.firstResponder !== tf.currentEditor(),
               !event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.control) {
                self.makeFirstResponder(tf)
            }

            // Strip lingering Option modifier right after pressing ⌥F so macOS doesn't emit dead-keys (ƒ, ´, π)
            if event.modifierFlags.contains(.option),
               !event.modifierFlags.contains(.command),
               !event.modifierFlags.contains(.control),
               let clean = event.charactersIgnoringModifiers,
               let first = clean.first,
               (first.isLetter || first.isNumber || first == " ") {
                let cleanFlags = event.modifierFlags.subtracting(.option)
                if let cleanEvent = NSEvent.keyEvent(
                    with: .keyDown,
                    location: event.locationInWindow,
                    modifierFlags: cleanFlags,
                    timestamp: event.timestamp,
                    windowNumber: event.windowNumber,
                    context: nil,
                    characters: clean,
                    charactersIgnoringModifiers: clean,
                    isARepeat: event.isARepeat,
                    keyCode: event.keyCode
                ) {
                    super.sendEvent(cleanEvent)
                    return
                }
            }
        }
        super.sendEvent(event)
    }

    override public func cancelOperation(_ sender: Any?) {
        onEscape?()
    }
}
