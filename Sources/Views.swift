import SwiftUI
import AppKit

/// Adaptive surfaces. `Color.primary` is black in light and white in dark, so
/// tinting with it gives the same subtle separation in both themes — hardcoded
/// black would vanish on a dark background.
enum Palette {
    static let canvas = Color(nsColor: .textBackgroundColor)
    static func tint(_ o: Double) -> Color { Color.primary.opacity(o) }
}

// A plain white canvas, forced regardless of system appearance — the brief
// asked for this twice. Two tabs, nothing else.

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
                    .foregroundStyle(active ? Color.primary : Palette.tint(0.45))
                Rectangle()
                    .fill(active ? Color.primary : Color.clear)
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
            Text(text).font(.caption).foregroundStyle(.secondary)
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
                .foregroundStyle(.primary)

            searchBar
        }
        .padding(.horizontal, 24)
        .padding(.top, 4)
        .padding(.bottom, 16)
    }

    private var searchBar: some View {
        HStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Search transcripts", text: $query)
                    .textFieldStyle(.plain)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Palette.tint(0.035), in: RoundedRectangle(cornerRadius: 7))

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
        .foregroundStyle(.secondary)
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
                    .foregroundStyle(.primary)
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
                .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            if hovering == u.id {
                HStack(spacing: 14) {
                    Button { copy(u.text) } label: { Image(systemName: "doc.on.doc") }
                    Button(role: .destructive) { store.delete([u.id]) } label: { Image(systemName: "trash") }
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(hovering == u.id ? Palette.tint(0.025) : Color.clear)
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
            Text("No dictations yet").font(.system(size: 15, weight: .medium)).foregroundStyle(.primary)
            Text("Hold \(Settings.shared.binding.displayName) and speak.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
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
                    .foregroundStyle(.primary)
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
                                .monospacedDigit().foregroundStyle(.secondary)
                        }
                        Slider(value: $settings.minPeakRMS, in: 0.0001...0.02)
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text("Minimum length")
                            Spacer()
                            Text(String(format: "%.2fs", settings.minSpeechSeconds))
                                .monospacedDigit().foregroundStyle(.secondary)
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
                            .foregroundStyle(.secondary)
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
        .background(Palette.tint(0.02), in: RoundedRectangle(cornerRadius: 12))
    }

    private func hint(_ s: String) -> some View {
        Text(s).font(.system(size: 11.5)).foregroundStyle(.secondary)
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
