import Cocoa
import Carbon.HIToolbox

/// Puts text at the caret of whatever app was frontmost when dictation started.
///
/// Paste rather than synthesized keystrokes: it is one event instead of N, it
/// is instant regardless of length, and it handles unicode and emoji that
/// per-character injection drops in some Electron apps.
enum Injector {

    static func inject(_ text: String, into target: NSRunningApplication?, mode: OutputMode) {
        guard !text.isEmpty else { return }

        switch mode {
        case .paste: paste(text, into: target)
        case .copy:  copyOnly(text)
        case .type:  restoreFocus(target) { typeOut(text) }
        }
    }

    /// Leaves the focused app alone entirely.
    private static func copyOnly(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Per-character synthesis. Slower and can drop characters in some Electron
    /// apps, but works where paste is intercepted or blocked.
    private static func typeOut(_ text: String) {
        let src = CGEventSource(stateID: .combinedSessionState)
        for chunk in Array(text.utf16).chunked(into: 16) {
            guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                  let up   = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            else { continue }
            var buf = chunk
            down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: &buf)
            up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: &buf)
            down.post(tap: .cgAnnotatedSessionEventTap)
            up.post(tap: .cgAnnotatedSessionEventTap)
            usleep(1500)
        }
    }

    private static func paste(_ text: String, into target: NSRunningApplication?) {
        let pb = NSPasteboard.general
        // ponytail: string-only clipboard save/restore. Deep-copy every
        // NSPasteboardItem if this ever eats someone's copied image.
        let saved = pb.string(forType: .string)

        pb.clearContents()
        pb.setString(text, forType: .string)
        let stamp = pb.changeCount

        restoreFocus(target) {
            postCommandV()
            // Give the target app time to read the pasteboard before we put
            // the old contents back.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard pb.changeCount == stamp else { return } // user copied since; leave it
                pb.clearContents()
                if let saved { pb.setString(saved, forType: .string) }
            }
        }
    }

    /// Our HUD is non-activating, but a stray click or app switch during
    /// dictation can still move focus. Put it back before pasting.
    private static func restoreFocus(_ target: NSRunningApplication?, then: @escaping () -> Void) {
        guard let target, !target.isTerminated,
              target.processIdentifier != NSWorkspace.shared.frontmostApplication?.processIdentifier
        else { return then() }

        target.activate()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: then)
    }

    private static func postCommandV() {
        let src = CGEventSource(stateID: .combinedSessionState)
        src?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        let v = CGKeyCode(kVK_ANSI_V)
        guard let down = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: true),
              let up   = CGEvent(keyboardEventSource: src, virtualKey: v, keyDown: false)
        else { return }

        // Set flags explicitly: the hotkey modifier may still be settling and
        // would otherwise ride along as option-command-V.
        down.flags = .maskCommand
        up.flags   = .maskCommand
        down.post(tap: .cgAnnotatedSessionEventTap)
        up.post(tap: .cgAnnotatedSessionEventTap)
    }
}

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0..<Swift.min($0 + size, count)]) }
    }
}
