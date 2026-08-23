import Cocoa
import Carbon.HIToolbox

/// Puts text at the caret of whatever app was frontmost when dictation started.
///
/// Paste rather than synthesized keystrokes: it is one event instead of N, it
/// is instant regardless of length, and it handles unicode and emoji that
/// per-character injection drops in some Electron apps.
enum Injector {

    /// `leaveOnClipboard` keeps the transcript on the clipboard afterwards. In
    /// paste mode that means skipping the usual restore — otherwise the restore
    /// would immediately overwrite the very thing the user asked us to leave.
    static func inject(_ text: String, into target: NSRunningApplication?,
                       mode: OutputMode, leaveOnClipboard: Bool = false) {
        guard !text.isEmpty else { return }

        switch mode {
        case .paste:
            paste(text, into: target, restoreClipboard: !leaveOnClipboard)
        case .copy:
            copyOnly(text)
        case .type:
            restoreFocus(target) {
                typeOut(text)
                if leaveOnClipboard { copyOnly(text) }
            }
        }
    }

    /// Puts text on the clipboard without touching the focused app.
    static func setClipboard(_ text: String) {
        guard !text.isEmpty else { return }
        copyOnly(text)
    }

    /// Leaves the focused app alone entirely.
    private static func copyOnly(_ text: String) {
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    /// Per-character synthesis. Slower than pasting, but it is the only way to
    /// deliver text incrementally, and terminals that collapse a paste into
    /// "[Pasted text]" show typed characters normally.
    ///
    /// Two things matter while the user is holding the dictation modifier:
    /// the event source uses `.privateState` so it does not inherit the
    /// physically-held ⌥, and flags are cleared explicitly. Without both, every
    /// character arrives option-modified and comes out as `ø∂ƒ` — or worse,
    /// fires a menu shortcut in the receiving app.
    static func typeOut(_ text: String) {
        guard !text.isEmpty else { return }
        let src = CGEventSource(stateID: .privateState)
        src?.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitLocalKeyboardEvents],
            state: .eventSuppressionStateSuppressionInterval
        )
        // Chunk by character, not by UTF-16 unit: splitting a surrogate pair
        // mid-chunk delivers half an emoji and the app shows a replacement char.
        for chunk in text.map(String.init).chunked(into: 16).map({ Array($0.joined().utf16) }) {
            guard let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true),
                  let up   = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false)
            else { continue }
            var buf = chunk
            down.flags = []
            up.flags = []
            down.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: &buf)
            up.keyboardSetUnicodeString(stringLength: buf.count, unicodeString: &buf)
            down.post(tap: .cgAnnotatedSessionEventTap)
            up.post(tap: .cgAnnotatedSessionEventTap)
            usleep(1200)
        }
    }

    private static func paste(_ text: String, into target: NSRunningApplication?,
                              restoreClipboard: Bool = true) {
        let pb = NSPasteboard.general
        // ponytail: string-only clipboard save/restore. Deep-copy every
        // NSPasteboardItem if this ever eats someone's copied image.
        // Only a string can be restored. If the clipboard held something else
        // (an image, a file), leave it alone entirely rather than clearing it —
        // clearing is worse than not restoring.
        let saved = pb.string(forType: .string)

        pb.clearContents()
        pb.setString(text, forType: .string)
        let stamp = pb.changeCount

        restoreFocus(target) {
            postCommandV()
            // Give the target app time to read the pasteboard before we put
            // the old contents back.
            guard restoreClipboard, let saved else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                guard pb.changeCount == stamp else { return } // user copied since; leave it
                pb.clearContents()
                pb.setString(saved, forType: .string)
            }
        }
    }

    /// Our HUD is non-activating, but a stray click or app switch during
    /// dictation can still move focus. Put it back before pasting.
    private static func restoreFocus(_ target: NSRunningApplication?, then: @escaping () -> Void) {
        // Never activate ourselves: if Yapperroni happened to be frontmost when
        // dictation started, activating it here pulls our window over the
        // user's work after every utterance.
        guard let target, !target.isTerminated,
              target.processIdentifier != NSRunningApplication.current.processIdentifier,
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
