import Cocoa
import Carbon.HIToolbox

enum KeyKind: String, Codable {
    /// A modifier held on its own, e.g. Right ⌥. Never consumed — a bare
    /// modifier types nothing, and swallowing it would break it everywhere else.
    case bareModifier
    /// A key with no modifier that types nothing, e.g. F5. Arrives as ordinary
    /// keyDown/keyUp and is never consumed.
    case plainKey
    /// A modifier plus a key, e.g. ⌥Space. Always consumed, or the key would
    /// also reach the focused app.
    case combo
}

struct KeyBinding: Codable, Equatable, Hashable {
    var keyCode: Int64
    /// Device-dependent flag bit (NX_DEVICE*KEYMASK), set while a specific
    /// left/right modifier is physically held. `bareModifier` only — the
    /// generic masks cannot tell the two sides apart.
    var deviceMask: UInt64
    /// Required standard modifier bits. `combo` only.
    var modifierFlags: UInt64
    /// A second key that must already be held when `keyCode` is pressed —
    /// ⌥R+Space is `keyCode: Space, chordKeyCode: R`. `combo` only.
    ///
    /// Exists so a chord can be distinguished from the plain combo it contains:
    /// ⌥Space and ⌥R+Space differ only by whether R is down at that instant.
    var chordKeyCode: Int64?
    var kind: KeyKind

    // MARK: - Masks

    /// The modifier bits worth comparing. Raw event flags also carry
    /// `maskNonCoalesced` and device-dependent bits, so a raw equality test
    /// against `maskAlternate` never matches.
    static let relevantFlags: UInt64 =
        CGEventFlags.maskShift.rawValue
      | CGEventFlags.maskControl.rawValue
      | CGEventFlags.maskAlternate.rawValue
      | CGEventFlags.maskCommand.rawValue

    static func normalize(_ flags: UInt64) -> UInt64 { flags & relevantFlags }

    // MARK: - Defaults

    static let pushDefault = KeyBinding(keyCode: 61, deviceMask: 0x0000_0040,
                                        modifierFlags: 0, kind: .bareModifier)
    /// ⌥Space.
    static let lockDefault = KeyBinding(keyCode: 49, deviceMask: 0,
                                        modifierFlags: CGEventFlags.maskAlternate.rawValue,
                                        kind: .combo)
    /// ⌥R — quick-add to the vocabulary list. A plain combo: it does not
    /// collide with anything, so the chord support below stays available for a
    /// binding that needs it rather than being the default.
    static let vocabDefault = KeyBinding(keyCode: 15, deviceMask: 0,
                                         modifierFlags: CGEventFlags.maskAlternate.rawValue,
                                         kind: .combo)

    var isModifier: Bool { kind == .bareModifier }
    /// Only combos are swallowed; everything else passes through to the app.
    var consumes: Bool { kind == .combo }
    var isChord: Bool { chordKeyCode != nil }

    // MARK: - Matching

    /// `held` is the set of key codes physically down right now — needed only
    /// for chords, where the distinguishing fact is which other key is held.
    func matches(keyCode code: Int64, flags: UInt64, held: Set<Int64> = []) -> Bool {
        guard code == keyCode else { return false }
        switch kind {
        case .bareModifier: return true
        case .plainKey:     return KeyBinding.normalize(flags) == 0
        case .combo:
            guard KeyBinding.normalize(flags) == modifierFlags else { return false }
            if let chord = chordKeyCode { return held.contains(chord) }
            return true
        }
    }

    /// True when this binding could be confused with `other` — same trigger key
    /// and modifiers, differing only by a chord key. The lock has to wait a
    /// moment in that case to see whether the chord key is coming.
    func collides(with other: KeyBinding) -> Bool {
        kind == .combo && other.kind == .combo
            && keyCode == other.keyCode
            && modifierFlags == other.modifierFlags
            && chordKeyCode != other.chordKeyCode
    }

    /// True while the modifier is physically down. `bareModifier` only.
    func isHeld(flags: UInt64) -> Bool { (flags & deviceMask) != 0 }

    // MARK: - Validation

    enum Problem: String {
        case noModifier = "Add at least one modifier — a bare key would be swallowed system-wide."
        case reserved   = "That combination is reserved by macOS."
        case duplicate  = "Already used by the other shortcut."
    }

    /// A combo with no modifier would consume that key everywhere, leaving the
    /// user unable to type — including in this settings window.
    func validate(against others: [KeyBinding]) -> Problem? {
        if kind == .combo && modifierFlags == 0 { return .noModifier }
        if kind == .combo {
            let cmd = CGEventFlags.maskCommand.rawValue
            let reserved: [(Int64, UInt64)] = [
                (12, cmd),  // ⌘Q
                (13, cmd),  // ⌘W
                (48, cmd),  // ⌘Tab
                (53, 0),    // Escape
            ]
            if reserved.contains(where: { $0.0 == keyCode && ($0.1 == 0 || modifierFlags == $0.1) }) {
                return .reserved
            }
        }
        if others.contains(self) { return .duplicate }
        return nil
    }

    // MARK: - Display

    var displayName: String {
        switch kind {
        case .bareModifier:
            return KeyBinding.modifiers.first { $0.binding.keyCode == keyCode
                                             && $0.binding.deviceMask == deviceMask }?.label
                ?? KeyBinding.keyName(keyCode)
        case .plainKey:
            return KeyBinding.keyName(keyCode)
        case .combo:
            let mods = KeyBinding.flagSymbols(modifierFlags)
            if let chord = chordKeyCode {
                return mods + KeyBinding.keyName(chord) + "+" + KeyBinding.keyName(keyCode)
            }
            return mods + KeyBinding.keyName(keyCode)
        }
    }

    static func flagSymbols(_ flags: UInt64) -> String {
        var s = ""
        if flags & CGEventFlags.maskControl.rawValue   != 0 { s += "⌃" }
        if flags & CGEventFlags.maskAlternate.rawValue != 0 { s += "⌥" }
        if flags & CGEventFlags.maskShift.rawValue     != 0 { s += "⇧" }
        if flags & CGEventFlags.maskCommand.rawValue   != 0 { s += "⌘" }
        return s
    }

    static func keyName(_ code: Int64) -> String {
        if let n = namedKeys[code] { return n }
        if let f = functionKeys.first(where: { $0.binding.keyCode == code }) { return f.label }
        return characterName(for: code) ?? "Key \(code)"
    }

    /// Asks the current keyboard layout what the key produces, so a French or
    /// Dvorak layout shows the right letter instead of a US-QWERTY guess.
    private static func characterName(for code: Int64) -> String? {
        guard let source = TISCopyCurrentKeyboardLayoutInputSource()?.takeRetainedValue(),
              let ptr = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData)
        else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(ptr).takeUnretainedValue() as Data
        var deadKeys: UInt32 = 0
        var length = 0
        var chars = [UniChar](repeating: 0, count: 4)
        let status = data.withUnsafeBytes { raw -> OSStatus in
            guard let layout = raw.bindMemory(to: UCKeyboardLayout.self).baseAddress else { return -1 }
            return UCKeyTranslate(layout, UInt16(code), UInt16(kUCKeyActionDisplay), 0,
                                  UInt32(LMGetKbdType()), UInt32(kUCKeyTranslateNoDeadKeysBit),
                                  &deadKeys, chars.count, &length, &chars)
        }
        guard status == noErr, length > 0 else { return nil }
        return String(utf16CodeUnits: chars, count: length).uppercased()
    }

    static let namedKeys: [Int64: String] = [
        49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Escape",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        115: "Home", 119: "End", 116: "Page Up", 121: "Page Down",
        117: "Forward Delete", 24: "=", 27: "-", 47: ".", 43: ",", 44: "/", 39: "'",
    ]

    // MARK: - Catalog (bare modifiers)

    struct Choice: Identifiable, Hashable {
        let id: String
        let label: String
        let binding: KeyBinding
    }

    private static func mod(_ id: String, _ label: String, _ code: Int64, _ mask: UInt64) -> Choice {
        Choice(id: id, label: label,
               binding: KeyBinding(keyCode: code, deviceMask: mask, modifierFlags: 0, kind: .bareModifier))
    }

    static let modifiers: [Choice] = [
        mod("ropt",   "Right Option ⌥",  61, 0x0000_0040),
        mod("lopt",   "Left Option ⌥",   58, 0x0000_0020),
        mod("rcmd",   "Right Command ⌘", 54, 0x0000_0010),
        mod("lcmd",   "Left Command ⌘",  55, 0x0000_0008),
        mod("rctl",   "Right Control ⌃", 62, 0x0000_2000),
        mod("lctl",   "Left Control ⌃",  59, 0x0000_0001),
        mod("rshift", "Right Shift ⇧",   60, 0x0000_0004),
        mod("lshift", "Left Shift ⇧",    56, 0x0000_0002),
        mod("fn",     "Fn (unreliable)", 63, 0x0080_0000),
    ]

    static let functionKeys: [Choice] = {
        let codes: [(String, Int64)] = [
            ("F1", 122), ("F2", 120), ("F3", 99), ("F4", 118), ("F5", 96), ("F6", 97),
            ("F7", 98), ("F8", 100), ("F9", 101), ("F10", 109), ("F11", 103), ("F12", 111),
            ("F13", 105), ("F14", 107), ("F15", 113), ("F16", 106), ("F17", 64),
            ("F18", 79), ("F19", 80), ("F20", 90),
        ]
        return codes.map { name, code in
            Choice(id: name.lowercased(), label: name,
                   binding: KeyBinding(keyCode: code, deviceMask: 0, modifierFlags: 0, kind: .plainKey))
        }
    }()

    // MARK: - Codable

    /// Tolerates the older stored shape, which had `isModifier` and no `kind`.
    /// A silent decode failure here would reset the user's key with no trace.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        keyCode       = try c.decode(Int64.self, forKey: .keyCode)
        deviceMask    = try c.decodeIfPresent(UInt64.self, forKey: .deviceMask) ?? 0
        modifierFlags = try c.decodeIfPresent(UInt64.self, forKey: .modifierFlags) ?? 0
        chordKeyCode  = try c.decodeIfPresent(Int64.self, forKey: .chordKeyCode)
        if let k = try c.decodeIfPresent(KeyKind.self, forKey: .kind) {
            kind = k
        } else {
            let legacy = try c.decodeIfPresent(Bool.self, forKey: .isModifier) ?? true
            kind = legacy ? .bareModifier : .plainKey
        }
    }

    init(keyCode: Int64, deviceMask: UInt64, modifierFlags: UInt64,
         chordKeyCode: Int64? = nil, kind: KeyKind) {
        self.keyCode = keyCode
        self.deviceMask = deviceMask
        self.modifierFlags = modifierFlags
        self.chordKeyCode = chordKeyCode
        self.kind = kind
    }

    /// Written explicitly: the legacy `isModifier` key exists only for reading
    /// older stored values, so the synthesised encoder cannot be used.
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(keyCode, forKey: .keyCode)
        try c.encode(deviceMask, forKey: .deviceMask)
        try c.encode(modifierFlags, forKey: .modifierFlags)
        try c.encodeIfPresent(chordKeyCode, forKey: .chordKeyCode)
        try c.encode(kind, forKey: .kind)
    }

    private enum CodingKeys: String, CodingKey {
        case keyCode, deviceMask, modifierFlags, chordKeyCode, kind, isModifier
    }
}
