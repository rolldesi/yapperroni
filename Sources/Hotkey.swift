import Cocoa
import Carbon.HIToolbox

/// Global dictation keys: a push-to-talk key and a lock (hands-free) combo.
///
/// The tap consumes **only** an exact combo match — the lock key would
/// otherwise also reach the focused app, since ⌥Space types a space. Every
/// other event on the system, including bare modifiers, passes straight
/// through untouched. A bare modifier is never consumed: it types nothing on
/// its own, and swallowing it would break it everywhere else.
final class Hotkey {

    enum Source { case hold, lock }
    enum Action: Equatable { case activate, deactivate, none }
    enum Input { case holdDown, holdUp, lockPress }

    /// Key state, kept separate from the tap so it can be tested without
    /// synthesising events. See `--selftest-toggle`.
    struct State: Equatable {
        var recording = false
        var locked = false
        var engaged = false
    }

    static func decide(_ input: Input, mode: ActivationMode, state: inout State) -> Action {
        switch input {
        case .lockPress:
            // Always a toggle, and it takes over a hold-started recording
            // rather than starting a second one.
            if state.recording {
                state = State()
                return .deactivate
            }
            state.recording = true
            state.locked = true
            return .activate

        case .holdDown:
            guard !state.locked else { return .none }
            switch mode {
            case .hold:
                state.recording = true
                return .activate
            case .toggle:
                state.engaged.toggle()
                state.recording = state.engaged
                return state.engaged ? .activate : .deactivate
            }

        case .holdUp:
            guard !state.locked, mode == .hold, state.recording else { return .none }
            state.recording = false
            return .deactivate
        }
    }

    // MARK: - Instance

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var holdIsDown = false
    private var state = State()
    /// Key codes physically down right now. A chord is only distinguishable
    /// from the plain combo inside it by what else is held at that instant.
    private var heldKeys = Set<Int64>()
    /// The lock, waiting to see whether the chord key is about to arrive.
    private var pendingLock: DispatchWorkItem?

    /// How long the lock waits when a chord could still complete it. Long
    /// enough to cover two keys pressed "together" by a human, short enough not
    /// to feel like lag on the plain combo.
    private static let chordWindow: TimeInterval = 0.18

    private var push: KeyBinding = .pushDefault
    private var lock: KeyBinding = .lockDefault
    private var lockEnabled = true
    private var vocab: KeyBinding = .vocabDefault
    private var vocabEnabled = true
    private var mode: ActivationMode = .hold

    var onActivate: ((Source) -> Void)?
    var onDeactivate: ((Source) -> Void)?
    /// Fired by the quick-add combo. Not a dictation event — it opens a window.
    var onVocab: (() -> Void)?

    private(set) var isActive = false
    var isLocked: Bool { state.locked }

    @discardableResult
    func start(push: KeyBinding, lock: KeyBinding, lockEnabled: Bool,
               vocab: KeyBinding, vocabEnabled: Bool, mode: ActivationMode) -> Bool {
        stop()
        self.push = push
        self.lock = lock
        self.lockEnabled = lockEnabled
        self.vocab = vocab
        self.vocabEnabled = vocabEnabled
        self.mode = mode
        holdIsDown = false
        state = State()
        heldKeys.removeAll()

        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
                 | CGEventMask(1 << CGEventType.keyDown.rawValue)
                 | CGEventMask(1 << CGEventType.keyUp.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let me = Unmanaged<Hotkey>.fromOpaque(refcon).takeUnretainedValue()
            return me.handle(type: type, event: event) ? nil : Unmanaged.passUnretained(event)
        }

        // .defaultTap, not .listenOnly, so the lock combo can be swallowed.
        // The callback does one comparison and dispatches asynchronously, so it
        // never blocks the event stream.
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            isActive = false
            return false
        }

        self.tap = tap
        // A tap without a run loop source silently never fires.
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isActive = true
        return true
    }

    /// Idempotent: safe to call when never started, or twice.
    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil
        source = nil
        isActive = false
        holdIsDown = false
        state = State()
        heldKeys.removeAll()
        pendingLock?.cancel()
        pendingLock = nil
    }

    /// Clears state without emitting. Used when dictation ends for a reason
    /// other than the key — an error, or a rejected press.
    func disengage() { state = State() }

    // MARK: - Event handling

    /// Returns true if the event should be swallowed.
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        // The system disables a tap that responds too slowly. Without this the
        // hotkey works for a while and then quietly dies.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }

        // Runs for every keystroke on the system. Do the cheap read once.
        let code = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags.rawValue
        let repeated = event.getIntegerValueField(.keyboardEventAutorepeat) != 0

        // Track physical key state before matching — chords are decided by it.
        if type == .keyDown { heldKeys.insert(code) }
        if type == .keyUp { heldKeys.remove(code) }

        // Lock combo first: it is the only thing that gets consumed.
        if lockEnabled, lock.kind == .combo, lock.matches(keyCode: code, flags: flags) {
            if type == .keyDown, !repeated {
                if vocabEnabled, vocab.collides(with: lock) {
                    // Space may have landed a hair before the chord key. Hold
                    // the lock briefly rather than starting a recording the
                    // user did not ask for; the chord cancels it if it arrives.
                    scheduleLock()
                } else {
                    emit(Hotkey.decide(.lockPress, mode: mode, state: &state), .lock)
                }
            }
            // Swallow the keyUp too, or the focused app sees an orphaned release.
            return type == .keyDown || type == .keyUp
        }

        // Quick-add first: a chord is more specific than the combo it contains,
        // so ⌥R+Space must be tested before ⌥Space.
        if vocabEnabled, vocab.kind == .combo,
           vocab.matches(keyCode: code, flags: flags, held: heldKeys) {
            if type == .keyDown, !repeated {
                cancelPendingLock()
                fireVocab()
            }
            return type == .keyDown || type == .keyUp
        }

        // The chord's held key, pressed on its own. Swallow it so ⌥R does not
        // type "®" while waiting for Space — and if the lock is mid-wait
        // because Space landed a moment early, this is what completes the
        // chord.
        if vocabEnabled, vocab.kind == .combo, let chordKey = vocab.chordKeyCode,
           code == chordKey, KeyBinding.normalize(flags) == vocab.modifierFlags {
            if type == .keyDown, !repeated, pendingLock != nil,
               heldKeys.contains(vocab.keyCode) {
                cancelPendingLock()
                fireVocab()
            }
            return type == .keyDown || type == .keyUp
        }

        guard code == push.keyCode else { return false }

        let down: Bool
        switch push.kind {
        case .bareModifier:
            guard type == .flagsChanged else { return false }
            down = push.isHeld(flags: flags)
        case .plainKey, .combo:
            switch type {
            case .keyDown:
                // A held key autorepeats; only the first press counts.
                guard event.getIntegerValueField(.keyboardEventAutorepeat) == 0 else { return push.consumes }
                guard push.matches(keyCode: code, flags: flags) else { return false }
                down = true
            case .keyUp:
                // Match on the code alone: the modifier may already be released.
                down = false
            default:
                return false
            }
        }

        guard down != holdIsDown else { return push.consumes }
        holdIsDown = down
        emit(Hotkey.decide(down ? .holdDown : .holdUp, mode: mode, state: &state), .hold)
        return push.consumes
    }

    private func fireVocab() {
        DispatchQueue.main.async { [weak self] in self?.onVocab?() }
    }

    private func cancelPendingLock() {
        pendingLock?.cancel()
        pendingLock = nil
    }

    /// Fires the lock unless the chord completes first.
    private func scheduleLock() {
        cancelPendingLock()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.pendingLock != nil else { return }
            self.pendingLock = nil
            self.emit(Hotkey.decide(.lockPress, mode: self.mode, state: &self.state), .lock)
        }
        pendingLock = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Hotkey.chordWindow, execute: work)
    }

    private func emit(_ action: Action, _ src: Source) {
        guard action != .none else { return }
        DispatchQueue.main.async { [weak self] in
            action == .activate ? self?.onActivate?(src) : self?.onDeactivate?(src)
        }
    }

    // MARK: - Environment

    /// Password fields turn on secure input, which blocks event taps entirely.
    static var secureInputActive: Bool { IsSecureEventInputEnabled() }

    @discardableResult
    static func requestAccessibility(prompt: Bool) -> Bool {
        let opts = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(opts)
    }
}
