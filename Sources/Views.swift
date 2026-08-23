import SwiftUI
import AppKit

/// The app's palette.
///
/// Neutrals are tinted rather than pure — pure #000/#888 is the giveaway of an
/// undesigned interface, and a hair of blue in the greys reads as intentional
/// at no cost to legibility. Every colour is a dynamic NSColor so light and
/// dark each get a hand-picked value instead of one value at two opacities.
enum Palette {
    private static func dynamic(light: (Double, Double, Double),
                                dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let c = isDark ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }

    /// Page background.
    static let canvas   = dynamic(light: (1.00, 1.00, 1.00), dark: (0.075, 0.075, 0.086))
    /// Grouped panels and input fields.
    static let surface  = dynamic(light: (0.969, 0.969, 0.980), dark: (0.110, 0.110, 0.125))
    /// Primary text — near-black, never pure.
    static let ink      = dynamic(light: (0.090, 0.090, 0.106), dark: (0.957, 0.957, 0.969))
    /// Secondary text and metadata.
    static let muted    = dynamic(light: (0.443, 0.443, 0.478), dark: (0.604, 0.604, 0.651))
    /// Separators.
    static let hairline = dynamic(light: (0.902, 0.902, 0.922), dark: (0.165, 0.165, 0.188))
    /// Row hover.
    static let hover    = dynamic(light: (0.957, 0.957, 0.973), dark: (0.137, 0.137, 0.153))
    /// Taken from the waveform in the app icon, so the interface and the icon
    /// belong to the same object.
    static let accent   = dynamic(light: (0.918, 0.435, 0.212), dark: (1.000, 0.573, 0.325))

    static func tint(_ o: Double) -> Color { Color.primary.opacity(o) }
}

struct ContentView: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        if state.showWelcome {
            WelcomeView()
        } else {
            VStack(spacing: 0) {
                TabBar()
                Divider()
                Group {
                    switch state.section {
                    case .history:  HistoryView()
                    case .settings: SettingsView()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            .background(Palette.canvas)
            // Controls pick up the accent from the app icon rather than
            // system blue, so the interface reads as part of the same object.
            .tint(Palette.accent)
        }
    }
}

private struct TabBar: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        ZStack {
            HStack(spacing: 32) {
                ForEach(Section.allCases) { section in
                    tab(section)
                }
            }
            HStack {
                Spacer()
                StatusPill().padding(.trailing, 20)
            }
        }
        .padding(.top, 22)
        .padding(.bottom, 14)
        .background(Palette.canvas)
    }

    private func tab(_ section: Section) -> some View {
        let active = state.section == section
        return Button {
            state.section = section
        } label: {
            VStack(spacing: 7) {
                Text(section.label)
                    .font(.system(size: 14, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? Palette.ink : Palette.muted)
                Rectangle()
                    .fill(active ? Palette.accent : Color.clear)
                    .frame(width: 20, height: 2)
            }
        }
        .buttonStyle(.plain)
    }
}

private struct StatusPill: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        let (text, color): (String, Color) =
            !state.accessibilityGranted ? ("Accessibility needed", .orange)
          : !state.tapActive            ? ("Hotkey inactive", .orange)
          : !state.modelReady           ? ("Loading model", .secondary)
          :                               ("Ready", .green)

        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text).font(.caption).foregroundStyle(Palette.muted)
        }
    }
}

// MARK: - History

struct HistoryView: View {
    @ObservedObject private var store = HistoryStore.shared
    @State private var query = ""
    @State private var selection = Set<UUID>()
    @State private var confirmClear = false
    @State private var hovering: UUID?

    private var rows: [Utterance] { store.filtered(query) }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if store.entries.isEmpty {
                empty
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(rows) { u in
                            row(u)
                            Divider().padding(.leading, 20)
                        }
                    }
                }
                summary
            }
        }
        .background(Palette.canvas)
        .confirmationDialog("Delete all \(store.entries.count) transcripts?",
                            isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { store.clear(); selection.removeAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("History")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(Palette.ink)

            searchBar
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.muted)
                TextField("Search transcripts", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Palette.surface, in: RoundedRectangle(cornerRadius: 8))

            if !selection.isEmpty {
                Button {
                    copy(rows.filter { selection.contains($0.id) }.map(\.text).joined(separator: "\n"))
                } label: { Image(systemName: "doc.on.doc") }
                .help("Copy selected")
                Button(role: .destructive) {
                    store.delete(selection); selection.removeAll()
                } label: { Image(systemName: "trash") }
                .help("Delete selected")
            }

            Menu {
                Button("Copy All") { copy(store.exportText()) }
                Button("Clear History…", role: .destructive) { confirmClear = true }
            } label: { Image(systemName: "ellipsis.circle") }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
        .buttonStyle(.plain)
        .foregroundStyle(Palette.muted)
    }

    private func row(_ u: Utterance) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if !selection.isEmpty || hovering == u.id {
                Button {
                    if selection.contains(u.id) { selection.remove(u.id) } else { selection.insert(u.id) }
                } label: {
                    Image(systemName: selection.contains(u.id) ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(selection.contains(u.id) ? Color.accentColor : Palette.tint(0.25))
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            } else {
                Color.clear.frame(width: 14)
            }

            VStack(alignment: .leading, spacing: 5) {
                Text(u.text)
                    .font(.system(size: 14))
                    .foregroundStyle(Palette.ink)
                    .textSelection(.enabled)
                    .lineLimit(4)
                HStack(spacing: 10) {
                    Text(u.date, format: .dateTime.month().day().hour().minute())
                    Text("·").foregroundStyle(.tertiary)
                    Text(u.appName)
                    Text("·").foregroundStyle(.tertiary)
                    Text("\(u.wordCount) words")
                }
                .font(.system(size: 11.5))
                .foregroundStyle(Palette.muted)
            }

            Spacer(minLength: 8)

            if hovering == u.id {
                HStack(spacing: 14) {
                    Button { copy(u.text) } label: { Image(systemName: "doc.on.doc") }
                    Button(role: .destructive) { store.delete([u.id]) } label: { Image(systemName: "trash") }
                }
                .buttonStyle(.plain)
                .foregroundStyle(Palette.muted)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(hovering == u.id ? Palette.hover : Color.clear)
        .onHover { hovering = $0 ? u.id : (hovering == u.id ? nil : hovering) }
        .contextMenu {
            Button("Copy") { copy(u.text) }
            Button("Delete", role: .destructive) { store.delete([u.id]) }
        }
    }

    private var summary: some View {
        HStack {
            Text("\(store.entries.count) dictations · \(store.totalWords) words")
            Spacer()
            if store.minutesSaved > 0 {
                Text(String(format: "~%.0f min saved vs. typing", store.minutesSaved))
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.tertiary)
        .padding(.horizontal, 24)
        .padding(.vertical, 10)
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform").font(.system(size: 36)).foregroundStyle(.tertiary)
            Text("No dictations yet").font(.system(size: 15, weight: .medium)).foregroundStyle(Palette.ink)
            Text("Hold \(Settings.shared.binding.displayName) and speak.")
                .font(.system(size: 13)).foregroundStyle(Palette.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func copy(_ s: String) {
        guard !s.isEmpty else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(s, forType: .string)
    }
}

// MARK: - Settings

struct SettingsView: View {
    @ObservedObject private var settings = Settings.shared
    @ObservedObject private var state = AppState.shared
    @StateObject private var tester = MicTester()

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 36) {
                Text("Settings")
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(Palette.ink)
                    .padding(.top, 4)

                group("Shortcuts") {
                    KeyRecorderField(title: "Hold to dictate",
                                     binding: $settings.binding,
                                     conflictsWith: settings.lockEnabled ? settings.lockBinding : nil,
                                     allowBareModifier: true)
                    Picker("Mode", selection: $settings.activation) {
                        ForEach(ActivationMode.allCases) { Text($0.label).tag($0) }
                    }
                    hint("A modifier held on its own, or a function key. A plain letter cannot be used — it would type into whatever app you are dictating into.")

                    Divider().padding(.vertical, 4)

                    Toggle("Enable hands-free lock", isOn: $settings.lockEnabled)
                    KeyRecorderField(title: "Lock combo",
                                     binding: $settings.lockBinding,
                                     conflictsWith: settings.binding,
                                     allowBareModifier: false)
                        .disabled(!settings.lockEnabled)
                    hint("Press once to start recording hands-free, press again to stop. It must include a modifier, because Yapperroni swallows this combination so it does not also type.")

                    Divider()

                    Toggle("Enable quick-add to vocabulary", isOn: $settings.vocabEnabled)
                    KeyRecorderField(title: "Add a word",
                                     binding: $settings.vocabBinding,
                                     conflictsWith: settings.binding,
                                     allowBareModifier: false)
                        .disabled(!settings.vocabEnabled)
                    hint("Opens a small window anywhere you are, so you can add a word the moment Yapperroni gets it wrong. Stays open until you press Escape, then hands focus back.")
                }

                group("Output") {
                    Toggle("Live transcription", isOn: $settings.liveTranscription)
                    hint("Types each word as soon as it settles, instead of inserting everything when you stop. Words appear about a second behind you.")

                    if settings.liveTranscription {
                        hint("Live mode always types character by character, so the output mode below does not apply.")
                    } else {
                        Picker("When finished", selection: $settings.output) {
                            ForEach(OutputMode.allCases) { Text($0.label).tag($0) }
                        }
                        hint(settings.output.detail)
                    }
                    Toggle("Add a trailing space", isOn: $settings.trailingSpace)
                    Toggle("Copy each transcript to the clipboard", isOn: $settings.copyToClipboard)
                    hint("So you can paste it anywhere, even if no text field was focused.")
                }

                group("Model") {
                    Picker("Model", selection: $settings.modelFilename) {
                        ForEach(settings.availableModels, id: \.self) { Text($0).tag($0) }
                    }
                    HStack {
                        hint("Drop more `.bin` models into the support folder to see them here.")
                        Spacer()
                        Button("Reveal") {
                            NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Config.supportDir.path)
                        }
                    }
                }

                group("Silence gate") {
                    Toggle("Filter background noise", isOn: $settings.voiceIsolation)
                    hint("Uses Apple's voice processing to hear you over music and room noise. Applies to your next dictation.")

                    Divider().padding(.vertical, 4)

                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Minimum loudness")
                            Spacer()
                            Text(String(format: "%.4f", settings.minPeakRMS))
                                .monospacedDigit().foregroundStyle(Palette.muted)
                        }
                        Slider(value: $settings.minPeakRMS, in: 0.0001...0.02)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Minimum length")
                            Spacer()
                            Text(String(format: "%.2fs", settings.minSpeechSeconds))
                                .monospacedDigit().foregroundStyle(Palette.muted)
                        }
                        Slider(value: $settings.minSpeechSeconds, in: 0.05...2.0)
                    }
                    HStack {
                        Button(tester.running ? "Listening…" : "Test microphone") { tester.run() }
                            .disabled(tester.running)
                        if let r = tester.result {
                            Text(r).font(.caption).foregroundStyle(tester.passed ? .green : .orange)
                        }
                    }
                    hint("Quieter input is dropped rather than sent to the model — Whisper invents confident sentences out of silence.")
                }

                group("Cleanup") {
                    Toggle("Clean up transcripts with an AI model", isOn: $settings.cleanupEnabled)
                    hint("After transcribing, the text is sent to a model you choose and rewritten — punctuation, capitalisation, filler words. Only the text is sent; the audio never leaves this Mac.")

                    if settings.cleanupEnabled {
                        if settings.liveTranscription {
                            Text("Live transcription is on, so cleanup is skipped — words already typed cannot be rewritten. Turn live transcription off under Output to use cleanup.")
                                .font(.caption).foregroundStyle(.orange)
                        }

                        Picker("Service", selection: $settings.cleanupProvider) {
                            ForEach(CleanupProvider.allCases) { Text($0.label).tag($0) }
                        }

                        if settings.cleanupProvider == .local {
                            hint("Runs on this Mac, so nothing is sent anywhere. Works with Ollama (default) or anything else that serves an OpenAI-compatible API, such as LM Studio on http://localhost:1234/v1.")
                        }

                        if settings.cleanupProvider == .custom || settings.cleanupProvider == .local {
                            LabeledContent("Server URL") {
                                TextField(settings.cleanupProvider.defaultBaseURL.isEmpty
                                          ? "https://host/v1" : settings.cleanupProvider.defaultBaseURL,
                                          text: $settings.cleanupBaseURL)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                            }
                            if settings.cleanupProvider == .custom {
                                hint("Any OpenAI-compatible endpoint. Yapperroni appends /chat/completions.")
                            }
                        }

                        if settings.cleanupProvider == .local {
                            LocalModelPicker()
                        } else {
                            LabeledContent("Model") {
                                TextField(settings.cleanupProvider.defaultModel,
                                          text: $settings.cleanupModel)
                                    .textFieldStyle(.roundedBorder)
                                    .font(.system(size: 12, design: .monospaced))
                            }
                        }
                        hint(settings.cleanupProvider.modelHint)

                        if settings.cleanupProvider.requiresKey {
                            APIKeyField(provider: settings.cleanupProvider)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text("How it should clean up").font(.callout)
                            TextEditor(text: $settings.cleanupPrompt)
                                .font(.system(size: 12, design: .monospaced))
                                .frame(minHeight: 120)
                                .padding(6)
                                .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
                                .overlay(RoundedRectangle(cornerRadius: 8)
                                    .strokeBorder(Palette.hairline, lineWidth: 1))
                                .scrollContentBackground(.hidden)
                            HStack {
                                Button("Restore default prompt") {
                                    settings.cleanupPrompt = Cleanup.defaultPrompt
                                }
                                Spacer()
                                CleanupTestButton()
                            }
                        }
                        hint("The system prompt. Change it to set tone, formatting, or language — for example \"rewrite in British English and keep it formal\".")
                    }
                }

                group("Vocabulary") {
                    Text("Words to listen for").font(.system(size: 13, weight: .medium))
                    TextEditor(text: $settings.customVocabulary)
                        .font(.system(size: 12.5, design: .monospaced))
                        .frame(height: 92)
                        .padding(8)
                        .background(Palette.tint(0.035), in: RoundedRectangle(cornerRadius: 8))
                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.tint(0.06)))
                    hint("Names and jargon the model gets wrong — one per line, or comma separated. Whisper has no dictionary to update, so these are used to prime it.")
                }

                group("Appearance & feedback") {
                    Picker("Theme", selection: $settings.theme) {
                        ForEach(AppTheme.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("Status pill", selection: $settings.hudPosition) {
                        ForEach(HUDPosition.allCases) { Text($0.label).tag($0) }
                    }
                    Toggle("Play a sound when dictation starts and stops", isOn: $settings.soundFeedback)
                }

                group("History") {
                    Toggle("Keep a history of transcripts", isOn: $settings.historyEnabled)
                    Stepper("Keep the last \(settings.historyLimit)",
                            value: $settings.historyLimit, in: 25...5000, step: 25)
                        .disabled(!settings.historyEnabled)
                }

                group("System") {
                    Toggle("Launch at login", isOn: Binding(
                        get: { settings.launchAtLogin },
                        set: { settings.launchAtLogin = $0 }
                    ))
                    HStack {
                        Circle()
                            .fill(state.accessibilityGranted ? Color.green : Color.orange)
                            .frame(width: 8, height: 8)
                        Text(state.accessibilityGranted
                             ? "Accessibility granted"
                             : "Accessibility required for the hotkey and pasting")
                            .foregroundStyle(Palette.muted)
                        Spacer()
                        Button("Open Settings…") {
                            NSWorkspace.shared.open(URL(string:
                                "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
                        }
                    }
                    HStack {
                        Button("Reveal Diagnostic Log") {
                            NSWorkspace.shared.selectFile(Log.path, inFileViewerRootedAtPath: Config.supportDir.path)
                        }
                        Spacer()
                        Button("Reset All Settings") { settings.resetToDefaults() }
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 560, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.canvas)
    }

    /// Whitespace and a soft tint separate groups — no boxes inside boxes.
    private func group<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Palette.tint(0.85))
            VStack(alignment: .leading, spacing: 12) {
                content()
            }
        }
        .padding(18)
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
    }

    private func hint(_ s: String) -> some View {
        Text(s).font(.system(size: 11.5)).foregroundStyle(Palette.muted)
    }
}

/// Echoes back the terms actually parsed out of the vocabulary field.
///
/// The separator is the thing most likely to be misunderstood, so rather than
/// documenting it, show the result — a wrong separator is then obvious at a
/// glance instead of silently producing one long "word".
private struct ParsedVocabulary: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        let terms = Vocabulary.terms(settings.customVocabulary)
        return Group {
            if terms.isEmpty {
                Text("No words yet.")
                    .font(.caption).foregroundStyle(Palette.muted)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(terms.count) word\(terms.count == 1 ? "" : "s")")
                        .font(.caption).fontWeight(.medium)
                    Text(terms.joined(separator: "   ·   "))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(Palette.muted)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10)
                .background(Palette.canvas, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Palette.hairline, lineWidth: 1))
            }
        }
    }
}

/// Lists the models a local server actually has, so the field is a choice
/// rather than a guess. Falls back to free text when nothing is listening.
private struct LocalModelPicker: View {
    @ObservedObject private var settings = Settings.shared
    @State private var models: [String]?
    @State private var checking = true

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let models, !models.isEmpty {
                Picker("Model", selection: $settings.cleanupModel) {
                    ForEach(models, id: \.self) { Text($0).tag($0) }
                    if !models.contains(settings.cleanupModel) {
                        Text("\(settings.cleanupModel) (not installed)").tag(settings.cleanupModel)
                    }
                }
            } else {
                LabeledContent("Model") {
                    TextField(CleanupProvider.local.defaultModel, text: $settings.cleanupModel)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 12, design: .monospaced))
                }
            }

            HStack(spacing: 8) {
                Circle()
                    .fill(checking ? Color.secondary : (models == nil ? Color.orange : Color.green))
                    .frame(width: 7, height: 7)
                Text(checking ? "Looking for a local server…"
                     : models == nil ? "No server responding — start Ollama, or point the URL at your own"
                     : "\(models!.count) model\(models!.count == 1 ? "" : "s") installed")
                    .font(.caption).foregroundStyle(Palette.muted)
                Spacer()
                Button("Refresh") { probe() }.controlSize(.small)
            }
        }
        .onAppear(perform: probe)
    }

    private func probe() {
        checking = true
        let base = settings.cleanupBaseURL
        Task {
            let found = await Cleanup.localModels(baseURL: base)
            await MainActor.run {
                models = found
                checking = false
                // Adopt an installed model if the saved one is not there.
                if let found, !found.isEmpty, !found.contains(settings.cleanupModel) {
                    settings.cleanupModel = found[0]
                }
            }
        }
    }
}

/// API key entry. The value lives in the Keychain, never in UserDefaults —
/// so the field shows whether one is stored rather than the key itself.
private struct APIKeyField: View {
    let provider: CleanupProvider
    @State private var entry = ""
    @State private var stored = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            LabeledContent(provider.keyLabel) {
                HStack {
                    SecureField(stored ? "•••••••• stored in Keychain" : "Paste key",
                                text: $entry)
                        .textFieldStyle(.roundedBorder)
                    if !entry.isEmpty {
                        Button("Save") {
                            Keychain.set(entry, for: provider.keychainAccount)
                            entry = ""
                            stored = Keychain.has(provider.keychainAccount)
                        }
                    } else if stored {
                        Button("Remove") {
                            Keychain.remove(provider.keychainAccount)
                            stored = false
                        }
                    }
                }
            }
            Text(stored
                 ? "Stored in your login Keychain, not in Yapperroni's settings file."
                 : "Kept in your login Keychain — never written to disk in plain text.")
                .font(.caption).foregroundStyle(Palette.muted)
        }
        .onAppear { stored = Keychain.has(provider.keychainAccount) }
        .onChange(of: provider) { _, new in
            entry = ""
            stored = Keychain.has(new.keychainAccount)
        }
    }
}

/// Runs one real cleanup call so configuration errors surface here rather than
/// in the middle of dictating.
private struct CleanupTestButton: View {
    @ObservedObject private var settings = Settings.shared
    @State private var running = false
    @State private var result: String?
    @State private var ok = false

    var body: some View {
        HStack(spacing: 8) {
            if let result {
                Text(result).font(.caption)
                    .foregroundStyle(ok ? .green : .orange)
                    .lineLimit(2)
            }
            Button(running ? "Testing…" : "Test") { run() }.disabled(running)
        }
    }

    private func run() {
        running = true
        result = nil
        let sample = "um so this is uh a test of the the cleanup thing i think it works"
        let s = settings
        Task {
            do {
                let out = try await Cleanup.run(sample,
                                                provider: s.cleanupProvider,
                                                model: s.cleanupModel,
                                                prompt: s.cleanupPrompt,
                                                baseURL: s.cleanupBaseURL)
                await MainActor.run { ok = true; result = out; running = false }
            } catch {
                await MainActor.run { ok = false; result = "\(error)"; running = false }
            }
        }
    }
}

/// Records briefly and reports the peak level, so the gate slider can be set
/// against a real measurement instead of guessed at.
final class MicTester: ObservableObject {
    @Published var running = false
    @Published var result: String?
    @Published var passed = false
    private let recorder = Recorder()

    func run() {
        result = nil
        guard !AppState.shared.dictating else {
            result = "finish dictating first"; passed = false; return
        }
        do { try recorder.start() } catch {
            result = "\(error)"; passed = false; return
        }
        running = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            guard let self else { return }
            let pcm = self.recorder.stop()
            let peak = Recorder.peakRMS(pcm)
            self.passed = Double(peak) >= Settings.shared.minPeakRMS
            self.result = String(format: "peak %.4f — %@", peak,
                                 self.passed ? "above the gate" : "below the gate")
            self.running = false
        }
    }
}
