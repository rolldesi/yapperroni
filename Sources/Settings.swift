import Cocoa
import ServiceManagement
import Combine

enum ActivationMode: String, Codable, CaseIterable, Identifiable {
    case hold, toggle
    var id: String { rawValue }
    var label: String { self == .hold ? "Hold to talk" : "Press to start, press to stop" }
}

enum OutputMode: String, Codable, CaseIterable, Identifiable {
    case paste, copy, type
    var id: String { rawValue }
    var label: String {
        switch self {
        case .paste: return "Paste at cursor"
        case .copy:  return "Copy to clipboard only"
        case .type:  return "Type character by character"
        }
    }
    var detail: String {
        switch self {
        case .paste: return "Fastest. Briefly replaces your clipboard, then restores it."
        case .copy:  return "Never touches the focused app. Paste it yourself."
        case .type:  return "Slower, but works where paste is blocked. May drop characters in some apps."
        }
    }
}

/// Where a recording mode listens.
enum AudioInput: String, Codable, CaseIterable, Identifiable {
    /// The microphone, through `AVAudioEngine`.
    case microphone
    /// Everything the Mac is playing — a Teams call, a lecture in a browser —
    /// taken digitally before it reaches the speakers, so there is no room,
    /// no echo and no volume knob between the lecturer and the model.
    case system
    var id: String { rawValue }
    var label: String { self == .microphone ? "Microphone" : "Computer audio (calls, videos)" }
}

/// Spoken-language choices. Whisper knows 99; these are the ones worth a row.
/// `auto` lets whisper detect it from the first 30 s of each recording.
enum Languages {
    static let all: [(code: String, name: String)] = [
        ("auto", "Detect automatically"), ("en", "English"), ("fr", "French"),
        ("de", "German"), ("es", "Spanish"), ("it", "Italian"), ("pt", "Portuguese"),
        ("nl", "Dutch"), ("hi", "Hindi"), ("ar", "Arabic"), ("zh", "Chinese"),
        ("ja", "Japanese"), ("ko", "Korean"), ("ru", "Russian"),
    ]
}

enum AppTheme: String, Codable, CaseIterable, Identifiable {
    case system, light, dark
    var id: String { rawValue }
    var label: String {
        switch self {
        case .system: return "Match system"
        case .light:  return "Light"
        case .dark:   return "Dark"
        }
    }
}

enum HUDPosition: String, Codable, CaseIterable, Identifiable {
    case bottom, top, center, hidden
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// A second way to record, on its own shortcut: a lecture, a meeting, a long
/// dictation into a smarter model. Dictation itself stays the push-to-talk key
/// and the lock in Shortcuts, running on the global model and settings.
///
/// A mode is always hands-free — press to start, press to stop. Nobody holds a
/// key down through an hour of lecture.
struct RecordingMode: Codable, Equatable, Identifiable {
    var id = UUID()
    var name: String
    var enabled = true
    var binding: KeyBinding
    /// A `.bin` for whisper.cpp or a sherpa-onnx folder name, like `modelFilename`.
    var modelFilename: String
    var voiceIsolation: Bool
    var live: Bool
    var output: OutputMode
    /// Beam search instead of greedy. Whisper only; slower.
    var accurate: Bool
    /// Ceiling on one recording. 0 means none.
    var maxMinutes: Double
    /// End by itself after `Config.maxSilenceSeconds` of quiet. Off for a
    /// lecture: a lecturer pausing at the board is not the end.
    var stopOnSilence: Bool
    /// A code from `Languages.all`. English-only models ignore it.
    var language = "auto"
    /// Silero voice-activity detection before whisper: silence is cut out
    /// instead of decoded, which is where whisper invents its sentences.
    var vad = true
    var input = AudioInput.microphone

    /// ⌥L. Greedy, not accurate: beam search made the long-lecture benchmark
    /// worse (see `Whisper.transcribe`). Voice processing off because it is
    /// tuned for a voice near the mic and treats a lecturer across the room as
    /// noise to suppress. Live off because live mode re-transcribes the whole
    /// buffer every tick, which grows without bound over an hour. Copy, not
    /// paste: an hour of text at whatever caret happens to be frontmost is
    /// never what anyone wants.
    static let lecture = RecordingMode(
        name: "Lecture",
        binding: KeyBinding(keyCode: 37, deviceMask: 0,
                            modifierFlags: CGEventFlags.maskAlternate.rawValue, kind: .combo),
        modelFilename: Config.accurateModelFilename,
        voiceIsolation: false, live: false, output: .copy,
        accurate: false, maxMinutes: 180, stopOnSilence: false)

    /// ⌥O. A class on Teams, Zoom or in a browser tab, recorded from the
    /// computer's own audio rather than through the air to the mic.
    static let onlineClass = RecordingMode(
        name: "Online class",
        binding: KeyBinding(keyCode: 31, deviceMask: 0,
                            modifierFlags: CGEventFlags.maskAlternate.rawValue, kind: .combo),
        modelFilename: Config.accurateModelFilename,
        voiceIsolation: false, live: false, output: .copy,
        accurate: false, maxMinutes: 180, stopOnSilence: false,
        input: .system)

    static let defaults: [RecordingMode] = [.lecture, .onlineClass]

    /// What "Add mode" starts from: dictation defaults on the accurate model.
    init(name: String, binding: KeyBinding, modelFilename: String,
         voiceIsolation: Bool, live: Bool, output: OutputMode,
         accurate: Bool, maxMinutes: Double, stopOnSilence: Bool,
         language: String = "auto", vad: Bool = true, input: AudioInput = .microphone) {
        self.name = name; self.binding = binding; self.modelFilename = modelFilename
        self.voiceIsolation = voiceIsolation; self.live = live; self.output = output
        self.accurate = accurate; self.maxMinutes = maxMinutes; self.stopOnSilence = stopOnSilence
        self.language = language; self.vad = vad; self.input = input
    }

    // Decoded field by field so a mode saved by an older build, missing the
    // newer fields, keeps its shortcut and model instead of failing the whole
    // list back to the defaults.
    private enum CodingKeys: String, CodingKey {
        case id, name, enabled, binding, modelFilename, voiceIsolation, live, output,
             accurate, maxMinutes, stopOnSilence, language, vad, input
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id             = try c.decode(UUID.self, forKey: .id)
        name           = try c.decode(String.self, forKey: .name)
        enabled        = try c.decode(Bool.self, forKey: .enabled)
        binding        = try c.decode(KeyBinding.self, forKey: .binding)
        modelFilename  = try c.decode(String.self, forKey: .modelFilename)
        voiceIsolation = try c.decode(Bool.self, forKey: .voiceIsolation)
        live           = try c.decode(Bool.self, forKey: .live)
        output         = try c.decode(OutputMode.self, forKey: .output)
        accurate       = try c.decode(Bool.self, forKey: .accurate)
        maxMinutes     = try c.decode(Double.self, forKey: .maxMinutes)
        stopOnSilence  = try c.decode(Bool.self, forKey: .stopOnSilence)
        language       = try c.decodeIfPresent(String.self, forKey: .language) ?? "auto"
        vad            = try c.decodeIfPresent(Bool.self, forKey: .vad) ?? true
        input          = try c.decodeIfPresent(AudioInput.self, forKey: .input) ?? .microphone
    }

    static func blank(binding: KeyBinding) -> RecordingMode {
        RecordingMode(name: "New mode", binding: binding,
                      modelFilename: Config.accurateModelFilename,
                      voiceIsolation: true, live: false, output: .paste,
                      accurate: false, maxMinutes: 3, stopOnSilence: true)
    }
}

/// UserDefaults-backed app settings.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    /// Set when a change requires the event tap to be rebuilt.
    let hotkeyChanged = PassthroughSubject<Void, Never>()
    /// Fired when the window needs its appearance reapplied.
    let themeChanged = PassthroughSubject<Void, Never>()

    /// Push-to-talk key.
    @Published var binding: KeyBinding {
        didSet {
            guard binding != oldValue else { return }
            if let data = try? JSONEncoder().encode(binding) { d.set(data, forKey: "binding") }
            hotkeyChanged.send()
        }
    }
    /// Hands-free lock combo. Consumed when it fires, so it must carry a
    /// modifier — see `KeyBinding.validate`.
    @Published var lockBinding: KeyBinding {
        didSet {
            guard lockBinding != oldValue else { return }
            if let data = try? JSONEncoder().encode(lockBinding) { d.set(data, forKey: "lockBinding") }
            hotkeyChanged.send()
        }
    }
    /// Quick-add combo. Consumed like the lock, so it needs a modifier.
    @Published var vocabBinding: KeyBinding {
        didSet {
            guard vocabBinding != oldValue else { return }
            if let data = try? JSONEncoder().encode(vocabBinding) { d.set(data, forKey: "vocabBinding") }
            hotkeyChanged.send()
        }
    }
    @Published var vocabEnabled: Bool {
        didSet {
            guard vocabEnabled != oldValue else { return }
            d.set(vocabEnabled, forKey: "vocabEnabled")
            hotkeyChanged.send()
        }
    }
    @Published var lockEnabled: Bool {
        didSet {
            guard lockEnabled != oldValue else { return }
            d.set(lockEnabled, forKey: "lockEnabled")
            hotkeyChanged.send()
        }
    }
    @Published var activation: ActivationMode {
        didSet {
            guard activation != oldValue else { return }
            d.set(activation.rawValue, forKey: "activation")
            hotkeyChanged.send()
        }
    }
    @Published var output: OutputMode          { didSet { d.set(output.rawValue, forKey: "output") } }
    /// Type words as they settle, instead of pasting everything at the end.
    @Published var liveTranscription: Bool     { didSet { d.set(liveTranscription, forKey: "liveTranscription") } }
    @Published var hudPosition: HUDPosition    { didSet { d.set(hudPosition.rawValue, forKey: "hudPosition") } }
    @Published var theme: AppTheme {
        didSet {
            guard theme != oldValue else { return }
            d.set(theme.rawValue, forKey: "theme")
            themeChanged.send()
        }
    }
    /// Leave every transcript on the clipboard, so it can be pasted anywhere
    /// even when nothing was focused to type into.
    @Published var copyToClipboard: Bool       { didSet { d.set(copyToClipboard, forKey: "copyToClipboard") } }
    @Published var trailingSpace: Bool         { didSet { d.set(trailingSpace, forKey: "trailingSpace") } }
    /// Apple's voice-processing unit on the input node: echo cancellation,
    /// noise suppression and automatic gain. Helps Whisper hear you over music
    /// and room noise. Takes effect on the next dictation.
    @Published var voiceIsolation: Bool        { didSet { d.set(voiceIsolation, forKey: "voiceIsolation") } }
    /// Send the finished transcript to an LLM to be tidied up. Text only —
    /// the audio never leaves the machine either way.
    @Published var cleanupEnabled: Bool {
        didSet {
            guard cleanupEnabled != oldValue else { return }
            d.set(cleanupEnabled, forKey: "cleanupEnabled")
        }
    }
    @Published var cleanupProvider: CleanupProvider {
        didSet {
            guard cleanupProvider != oldValue else { return }
            d.set(cleanupProvider.rawValue, forKey: "cleanupProvider")
            // Each provider names its models differently; carry the user to a
            // working default rather than leaving a stale ID behind.
            if cleanupModel.isEmpty || cleanupModel == oldValue.defaultModel {
                cleanupModel = cleanupProvider.defaultModel
            }
            if cleanupBaseURL.isEmpty || cleanupBaseURL == oldValue.defaultBaseURL {
                cleanupBaseURL = cleanupProvider.defaultBaseURL
            }
        }
    }
    @Published var cleanupModel: String   { didSet { d.set(cleanupModel, forKey: "cleanupModel") } }
    @Published var cleanupPrompt: String  { didSet { d.set(cleanupPrompt, forKey: "cleanupPrompt") } }
    @Published var cleanupBaseURL: String { didSet { d.set(cleanupBaseURL, forKey: "cleanupBaseURL") } }

    /// Words and names to prime the decoder with. Whisper has no dictionary to
    /// update, but it conditions on an initial prompt, so listing your jargon
    /// here biases recognition toward it.
    @Published var customVocabulary: String    { didSet { d.set(customVocabulary, forKey: "customVocabulary") } }
    @Published var soundFeedback: Bool         { didSet { d.set(soundFeedback, forKey: "soundFeedback") } }
    @Published var historyEnabled: Bool        { didSet { d.set(historyEnabled, forKey: "historyEnabled") } }
    @Published var historyLimit: Int           { didSet { d.set(historyLimit, forKey: "historyLimit") } }
    @Published var minPeakRMS: Double          { didSet { d.set(minPeakRMS, forKey: "minPeakRMS") } }
    /// Loudness under which a hands-free session counts as silent and ends
    /// itself. Adjustable because it is the one number that depends on the
    /// room: a fan or an air conditioner sits above the factory default and
    /// keeps the session alive forever.
    @Published var autoStopRMS: Double         { didSet { d.set(autoStopRMS, forKey: "autoStopRMS") } }
    @Published var minSpeechSeconds: Double    { didSet { d.set(minSpeechSeconds, forKey: "minSpeechSeconds") } }
    @Published var modelFilename: String       { didSet { d.set(modelFilename, forKey: "modelFilename") } }
    /// Dictation's spoken language. English by default: the bundled model is
    /// English-only, and auto-detect on a two-second utterance guesses wrong.
    @Published var language: String           { didSet { d.set(language, forKey: "language") } }
    @Published var modes: [RecordingMode] {
        didSet {
            guard modes != oldValue else { return }
            if let data = try? JSONEncoder().encode(modes) { d.set(data, forKey: "modes") }
            // Only a shortcut change rebuilds the tap. Rebuilding ends any
            // recording in progress, so renaming a lecture mid-lecture must not.
            func keys(_ m: [RecordingMode]) -> [String] {
                m.map { "\($0.enabled) \($0.binding)" }
            }
            if keys(modes) != keys(oldValue) { hotkeyChanged.send() }
        }
    }

    /// A silent decode failure would reset the user's key with no trace, so
    /// say so in the log when the stored shape no longer parses.
    private static func decodeBinding(_ data: Data?, _ name: String, _ fallback: KeyBinding) -> KeyBinding {
        guard let data else { return fallback }
        do {
            return try JSONDecoder().decode(KeyBinding.self, from: data)
        } catch {
            Log.write("settings \(name) failed to decode (\(error)); using \(fallback.displayName)")
            return fallback
        }
    }

    private init() {
        d.register(defaults: [
            "activation": ActivationMode.hold.rawValue,
            "output": OutputMode.paste.rawValue,
            "hudPosition": HUDPosition.bottom.rawValue,
            "theme": AppTheme.light.rawValue,
            "copyToClipboard": true,
            "trailingSpace": true,
            "voiceIsolation": true,
            "cleanupEnabled": false,
            "cleanupProvider": CleanupProvider.anthropic.rawValue,
            "cleanupModel": CleanupProvider.anthropic.defaultModel,
            "cleanupPrompt": Cleanup.defaultPrompt,
            "cleanupBaseURL": "",
            "customVocabulary": "",
            "soundFeedback": false,
            "lockEnabled": true,
            "vocabEnabled": true,
            "liveTranscription": true,
            "historyEnabled": true,
            "historyLimit": 500,
            "minPeakRMS": Double(Config.defaultMinPeakRMS),
            "autoStopRMS": Double(Config.defaultAutoStopRMS),
            "minSpeechSeconds": Config.defaultMinSpeechSeconds,
            "modelFilename": Config.defaultModelFilename,
            "language": "en",
        ])

        binding     = Settings.decodeBinding(d.data(forKey: "binding"), "binding", .pushDefault)
        lockBinding = Settings.decodeBinding(d.data(forKey: "lockBinding"), "lockBinding", .lockDefault)
        lockEnabled = d.bool(forKey: "lockEnabled")
        vocabBinding = Settings.decodeBinding(d.data(forKey: "vocabBinding"), "vocabBinding", .vocabDefault)
        vocabEnabled = d.bool(forKey: "vocabEnabled")
        liveTranscription = d.bool(forKey: "liveTranscription")
        activation       = ActivationMode(rawValue: d.string(forKey: "activation") ?? "") ?? .hold
        output           = OutputMode(rawValue: d.string(forKey: "output") ?? "") ?? .paste
        hudPosition      = HUDPosition(rawValue: d.string(forKey: "hudPosition") ?? "") ?? .bottom
        theme            = AppTheme(rawValue: d.string(forKey: "theme") ?? "") ?? .light
        copyToClipboard  = d.bool(forKey: "copyToClipboard")
        trailingSpace    = d.bool(forKey: "trailingSpace")
        voiceIsolation   = d.bool(forKey: "voiceIsolation")
        cleanupEnabled   = d.bool(forKey: "cleanupEnabled")
        cleanupProvider  = CleanupProvider(rawValue: d.string(forKey: "cleanupProvider") ?? "") ?? .anthropic
        cleanupModel     = d.string(forKey: "cleanupModel") ?? CleanupProvider.anthropic.defaultModel
        cleanupPrompt    = d.string(forKey: "cleanupPrompt") ?? Cleanup.defaultPrompt
        cleanupBaseURL   = d.string(forKey: "cleanupBaseURL") ?? ""
        customVocabulary = d.string(forKey: "customVocabulary") ?? ""
        soundFeedback    = d.bool(forKey: "soundFeedback")
        historyEnabled   = d.bool(forKey: "historyEnabled")
        historyLimit     = d.integer(forKey: "historyLimit")
        minPeakRMS       = d.double(forKey: "minPeakRMS")
        autoStopRMS      = d.double(forKey: "autoStopRMS")
        minSpeechSeconds = d.double(forKey: "minSpeechSeconds")
        modelFilename    = d.string(forKey: "modelFilename") ?? Config.defaultModelFilename
        language         = d.string(forKey: "language") ?? "en"
        modes            = Settings.decodeModes(d.data(forKey: "modes"))
    }

    private static func decodeModes(_ data: Data?) -> [RecordingMode] {
        guard let data else { return RecordingMode.defaults }
        do {
            return try JSONDecoder().decode([RecordingMode].self, from: data)
        } catch {
            Log.write("settings modes failed to decode (\(error)); using the defaults")
            return RecordingMode.defaults
        }
    }

    /// A model the user dropped into the support folder wins over the one
    /// shipped inside the app, so a bundled default can still be overridden.
    var modelPath: String { modelPath(for: modelFilename) }

    func modelPath(for name: String) -> String {
        let fm = FileManager.default
        let support = Config.supportDir.appendingPathComponent(name).path
        if fm.fileExists(atPath: support) { return support }
        if let bundled = Bundle.main.resourcePath.map({ $0 + "/" + name }),
           fm.fileExists(atPath: bundled) { return bundled }
        return support
    }

    /// Models shipped in the bundle plus any the user added: whisper `.bin`
    /// files and sherpa-onnx model folders.
    var availableModels: [String] {
        let fm = FileManager.default
        var names = Set<String>()
        for dir in [Config.supportDir.path, Bundle.main.resourcePath].compactMap({ $0 }) {
            for f in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where Engines.isModel(f, in: dir) {
                names.insert(f)
            }
        }
        return names.sorted()
    }

    /// Keeps the Settings picker from pointing at a model that is not there —
    /// an empty selection renders as a blank row and loads nothing.
    func reconcileModelSelection() {
        let available = availableModels
        guard !available.isEmpty, !available.contains(modelFilename) else { return }
        Log.write("model   \(modelFilename) missing; falling back to \(available[0])")
        modelFilename = available[0]
    }

    // Launch-at-login lives in SMAppService, not UserDefaults; it is system state.
    var launchAtLogin: Bool {
        get { SMAppService.mainApp.status == .enabled }
        set {
            do {
                newValue ? try SMAppService.mainApp.register()
                         : try SMAppService.mainApp.unregister()
            } catch {
                Log.write("settings launchAtLogin \(newValue) failed: \(error.localizedDescription)")
            }
            objectWillChange.send()
        }
    }

    func resetToDefaults() {
        binding          = .pushDefault
        lockBinding      = .lockDefault
        lockEnabled      = true
        vocabBinding     = .vocabDefault
        vocabEnabled     = true
        liveTranscription = true
        activation       = .hold
        output           = .paste
        hudPosition      = .bottom
        theme            = .light
        copyToClipboard  = true
        trailingSpace    = true
        voiceIsolation   = true
        cleanupEnabled   = false
        cleanupProvider  = .anthropic
        cleanupModel     = CleanupProvider.anthropic.defaultModel
        cleanupPrompt    = Cleanup.defaultPrompt
        cleanupBaseURL   = ""
        customVocabulary = ""
        soundFeedback    = false
        historyEnabled   = true
        historyLimit     = 500
        minPeakRMS       = Double(Config.defaultMinPeakRMS)
        autoStopRMS      = Double(Config.defaultAutoStopRMS)
        minSpeechSeconds = Config.defaultMinSpeechSeconds
        modelFilename    = Config.defaultModelFilename
        language         = "en"
        modes            = RecordingMode.defaults
    }
}
