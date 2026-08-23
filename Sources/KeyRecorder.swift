import SwiftUI
import AppKit

/// Click, then press the key or combination you want.
///
/// Uses a local NSEvent monitor rather than the global tap: it needs no
/// permission, and it only listens while this window is focused. The monitor
/// returns nil so the captured keystroke does not also land in the UI behind it.
struct KeyRecorderField: View {
    let title: String
    @Binding var binding: KeyBinding
    /// The other shortcut, so we can refuse a duplicate.
    /// Every binding this one must not duplicate. A vocab combo set to ⌥Space
    /// would silently swallow the hands-free lock, so each field checks all the
    /// others, not just one.
    var conflictsWith: [KeyBinding]
    /// Push-to-talk accepts a modifier held on its own; the lock combo does not.
    var allowBareModifier: Bool

    @State private var recording = false
    @State private var monitor: Any?
    @State private var pendingModifier: KeyBinding?
    @State private var sawKeyDown = false
    @State private var problem: String?
    /// First key of a possible chord, still held. ⌥R+Space arrives as R then
    /// Space, so the first key is the one held and the second is the trigger.
    @State private var chordFirst: Int64?
    @State private var chordFlags: UInt64 = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Button(recording ? "Press keys…  (esc to cancel)" : binding.displayName) {
                    recording ? cancel() : begin()
                }
                .buttonStyle(.bordered)
                .tint(recording ? .accentColor : nil)
                .monospaced()
            }
            if let problem {
                Text(problem).font(.caption).foregroundStyle(.orange)
            } else if recording {
                Text(allowBareModifier
                     ? "Hold a modifier on its own, press a function key, or press a combination."
                     : "Press a combination — it must include a modifier.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .onDisappear(perform: teardown)
    }

    // MARK: - Capture

    private func begin() {
        problem = nil
        pendingModifier = nil
        sawKeyDown = false
        chordFirst = nil
        recording = true
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) { event in
            handle(event)
            return nil   // swallow, so it does not reach the UI behind us
        }
    }

    private func cancel() {
        recording = false
        problem = nil
        chordFirst = nil
        teardown()
    }

    private func teardown() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private func handle(_ event: NSEvent) {
        let flags = KeyBinding.normalize(UInt64(event.modifierFlags.rawValue))

        switch event.type {
        case .keyUp:
            // Released without a second key — it was a plain combo after all.
            if let first = chordFirst, Int64(event.keyCode) == first {
                chordFirst = nil
                commit(KeyBinding(keyCode: first, deviceMask: 0,
                                  modifierFlags: chordFlags, kind: .combo))
            }

        case .keyDown:
            if event.keyCode == 53, flags == 0 { return cancel() }   // escape
            sawKeyDown = true

            // Second key while the first is still held: that is the chord.
            if let first = chordFirst, Int64(event.keyCode) != first, flags != 0 {
                chordFirst = nil
                commit(KeyBinding(keyCode: Int64(event.keyCode), deviceMask: 0,
                                  modifierFlags: flags, chordKeyCode: first, kind: .combo))
                return
            }

            if flags != 0 {
                // Hold it: a second key may follow, making this a chord.
                chordFirst = Int64(event.keyCode)
                chordFlags = flags
            } else if KeyBinding.functionKeys.contains(where: { $0.binding.keyCode == Int64(event.keyCode) }) {
                commit(KeyBinding(keyCode: Int64(event.keyCode), deviceMask: 0,
                                  modifierFlags: 0, kind: .plainKey))
            } else {
                // A bare letter would be swallowed system-wide, or typed into
                // the app while dictating. Neither is acceptable.
                problem = KeyBinding.Problem.noModifier.rawValue
            }

        case .flagsChanged:
            guard allowBareModifier,
                  let choice = KeyBinding.modifiers.first(where: { $0.binding.keyCode == Int64(event.keyCode) })
            else { return }

            let isDown = (UInt64(event.modifierFlags.rawValue) & choice.binding.deviceMask) != 0
            if isDown {
                pendingModifier = choice.binding
                sawKeyDown = false
            } else if let pending = pendingModifier,
                      pending.keyCode == Int64(event.keyCode), !sawKeyDown {
                // Pressed and released with nothing in between: a bare modifier.
                commit(pending)
            }

        default:
            break
        }
    }

    private func commit(_ candidate: KeyBinding) {
        if let bad = candidate.validate(against: conflictsWith) {
            problem = bad.rawValue
            return
        }
        if !allowBareModifier, candidate.kind != .combo {
            problem = KeyBinding.Problem.noModifier.rawValue
            return
        }
        binding = candidate
        problem = nil
        recording = false
        teardown()
    }
}
