import AppKit
import Carbon.HIToolbox

/// A session-wide event tap that owns the ⌥Tab and ⌥` chords.
///
/// A Carbon hot key would be simpler, but it cannot observe the *release* of a
/// modifier — and "hold ⌥, tab through, release to commit" is the whole interaction.
/// An active tap also lets us swallow the keystrokes so no app underneath sees them.
final class HotKeyTap {

    /// Advance the selection. `backwards` is ⇧ being held; `scope` says which
    /// windows the chord is about, and is only consulted when it opens a session.
    var onCycle: ((SwitchScope, Bool) -> Void)?
    /// ⌥ was released — commit the current selection.
    var onCommit: (() -> Void)?
    /// Escape was pressed — abandon the switch.
    var onCancel: (() -> Void)?
    /// Whether a switching session is currently open.
    var isSessionActive: () -> Bool = { false }

    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    @discardableResult
    func start() -> Bool {
        let mask = (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.keyUp.rawValue)
            | (1 << CGEventType.flagsChanged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let tap = Unmanaged<HotKeyTap>.fromOpaque(refcon).takeUnretainedValue()
            return tap.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }

        self.tap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    // MARK: - Event handling

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        let pass = Unmanaged.passUnretained(event)

        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // The system disables taps that block for too long. Just turn it back on.
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return pass

        case .keyDown:
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            let flags = event.flags

            if let scope = scope(for: code, flags: flags) {
                onCycle?(scope, flags.contains(.maskShift))
                return nil
            }
            if isSessionActive(), code == kVK_Escape {
                onCancel?()
                return nil
            }
            return pass

        case .keyUp:
            let code = Int(event.getIntegerValueField(.keyboardEventKeycode))
            // Swallow the matching key-up so the focused app never sees a stray Tab.
            if isSessionActive(), code == kVK_Tab || code == kVK_Escape || code == kVK_ANSI_Grave {
                return nil
            }
            return pass

        case .flagsChanged:
            if isSessionActive(), !event.flags.contains(.maskAlternate) {
                onCommit?()
            }
            return pass

        default:
            return pass
        }
    }

    /// The scope the chord opens a session over, or nil if this is not one of ours.
    ///
    /// ⌥Tab spans every window; ⌥` stays inside the front app, mirroring the ⌘`
    /// macOS users already know. ⌘ or ⌃ being held means the user meant some other
    /// shortcut entirely.
    private func scope(for code: Int, flags: CGEventFlags) -> SwitchScope? {
        guard flags.contains(.maskAlternate),
              !flags.contains(.maskCommand),
              !flags.contains(.maskControl) else { return nil }
        switch code {
        case kVK_Tab: return .allWindows
        case kVK_ANSI_Grave: return .frontmostApp
        default: return nil
        }
    }
}
