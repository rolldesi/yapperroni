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

enum HUDPosition: String, Codable, CaseIterable, Identifiable {
    case bottom, top, center, hidden
    var id: String { rawValue }
    var label: String { rawValue.capitalized }
}

/// UserDefaults-backed app settings.
final class Settings: ObservableObject {
    static let shared = Settings()
    private let d = UserDefaults.standard

    /// Set when a change requires the event tap to be rebuilt.
    let hotkeyChanged = PassthroughSubject<Void, Never>()

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
    @Published var hudPosition: HUDPosition    { didSet { d.set(hudPosition.rawValue, forKey: "hudPosition") } }
    @Published var trailingSpace: Bool         { didSet { d.set(trailingSpace, forKey: "trailingSpace") } }
    @Published var soundFeedback: Bool         { didSet { d.set(soundFeedback, forKey: "soundFeedback") } }
    @Published var historyEnabled: Bool        { didSet { d.set(historyEnabled, forKey: "historyEnabled") } }
    @Published var historyLimit: Int           { didSet { d.set(historyLimit, forKey: "historyLimit") } }
    @Published var minPeakRMS: Double          { didSet { d.set(minPeakRMS, forKey: "minPeakRMS") } }
    @Published var minSpeechSeconds: Double    { didSet { d.set(minSpeechSeconds, forKey: "minSpeechSeconds") } }
    @Published var modelFilename: String       { didSet { d.set(modelFilename, forKey: "modelFilename") } }

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
            "trailingSpace": true,
            "soundFeedback": false,
            "lockEnabled": true,
            "historyEnabled": true,
            "historyLimit": 500,
            "minPeakRMS": Double(Config.defaultMinPeakRMS),
            "minSpeechSeconds": Config.defaultMinSpeechSeconds,
            "modelFilename": Config.defaultModelFilename,
        ])

        binding     = Settings.decodeBinding(d.data(forKey: "binding"), "binding", .pushDefault)
        lockBinding = Settings.decodeBinding(d.data(forKey: "lockBinding"), "lockBinding", .lockDefault)
        lockEnabled = d.bool(forKey: "lockEnabled")
        activation       = ActivationMode(rawValue: d.string(forKey: "activation") ?? "") ?? .hold
        output           = OutputMode(rawValue: d.string(forKey: "output") ?? "") ?? .paste
        hudPosition      = HUDPosition(rawValue: d.string(forKey: "hudPosition") ?? "") ?? .bottom
        trailingSpace    = d.bool(forKey: "trailingSpace")
        soundFeedback    = d.bool(forKey: "soundFeedback")
        historyEnabled   = d.bool(forKey: "historyEnabled")
        historyLimit     = d.integer(forKey: "historyLimit")
        minPeakRMS       = d.double(forKey: "minPeakRMS")
        minSpeechSeconds = d.double(forKey: "minSpeechSeconds")
        modelFilename    = d.string(forKey: "modelFilename") ?? Config.defaultModelFilename
    }

    /// A model the user dropped into the support folder wins over the one
    /// shipped inside the app, so a bundled default can still be overridden.
    var modelPath: String {
        let fm = FileManager.default
        let support = Config.supportDir.appendingPathComponent(modelFilename).path
        if fm.fileExists(atPath: support) { return support }
        if let bundled = Bundle.main.resourcePath.map({ $0 + "/" + modelFilename }),
           fm.fileExists(atPath: bundled) { return bundled }
        return support
    }

    /// Models shipped in the bundle plus any the user added.
    var availableModels: [String] {
        let fm = FileManager.default
        var names = Set<String>()
        for dir in [Config.supportDir.path, Bundle.main.resourcePath].compactMap({ $0 }) {
            for f in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where f.hasSuffix(".bin") {
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
        activation       = .hold
        output           = .paste
        hudPosition      = .bottom
        trailingSpace    = true
        soundFeedback    = false
        historyEnabled   = true
        historyLimit     = 500
        minPeakRMS       = Double(Config.defaultMinPeakRMS)
        minSpeechSeconds = Config.defaultMinSpeechSeconds
        modelFilename    = Config.defaultModelFilename
    }
}
