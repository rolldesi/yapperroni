import SwiftUI
import AppKit

struct ContentView: View {
    @ObservedObject private var state = AppState.shared

    var body: some View {
        NavigationSplitView {
            List(Section.allCases, selection: Binding(
                get: { state.section },
                set: { state.section = $0 ?? .history }
            )) { section in
                Label(section.label, systemImage: section.icon).tag(section)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 240)
        } detail: {
            Group {
                switch state.section {
                case .history:  HistoryView()
                case .settings: SettingsView()
                case .stats:    StatsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .toolbar { ToolbarItem(placement: .status) { StatusPill() } }
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
            Circle().fill(color).frame(width: 8, height: 8)
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

    private var rows: [Utterance] { store.filtered(query) }

    var body: some View {
        VStack(spacing: 0) {
            if store.entries.isEmpty {
                empty
            } else {
                List(rows, selection: $selection) { u in
                    row(u).tag(u.id)
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Search transcripts")
        .toolbar {
            ToolbarItemGroup {
                Button {
                    copy(rows.filter { selection.contains($0.id) }
                            .map(\.text).joined(separator: "\n"))
                } label: { Label("Copy", systemImage: "doc.on.doc") }
                .disabled(selection.isEmpty)
                .help("Copy selected transcripts")

                Button {
                    store.delete(selection); selection.removeAll()
                } label: { Label("Delete", systemImage: "trash") }
                .disabled(selection.isEmpty)

                Menu {
                    Button("Copy All") { copy(store.exportText()) }
                    Button("Clear History…", role: .destructive) { confirmClear = true }
                } label: { Label("More", systemImage: "ellipsis.circle") }
            }
        }
        .confirmationDialog("Delete all \(store.entries.count) transcripts?",
                            isPresented: $confirmClear, titleVisibility: .visible) {
            Button("Delete All", role: .destructive) { store.clear(); selection.removeAll() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    private func row(_ u: Utterance) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(u.text)
                .font(.body)
                .textSelection(.enabled)
                .lineLimit(4)
            HStack(spacing: 10) {
                Text(u.date, format: .dateTime.month().day().hour().minute())
                Text(u.appName)
                Text("\(u.wordCount)w")
                Text(String(format: "%.1fs audio · %.1fs decode", u.duration, u.latency))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
        .contextMenu {
            Button("Copy") { copy(u.text) }
            Button("Delete", role: .destructive) { store.delete([u.id]) }
        }
    }

    private var empty: some View {
        VStack(spacing: 10) {
            Image(systemName: "waveform").font(.system(size: 42)).foregroundStyle(.tertiary)
            Text("No dictations yet").font(.title3)
            Text("Hold \(Settings.shared.binding.displayName) and speak.")
                .foregroundStyle(.secondary)
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
        Form {
            SwiftUI.Section("Push to talk") {
                KeyRecorderField(title: "Hold to dictate",
                                 binding: $settings.binding,
                                 conflictsWith: settings.lockEnabled ? settings.lockBinding : nil,
                                 allowBareModifier: true)
                Picker("Mode", selection: $settings.activation) {
                    ForEach(ActivationMode.allCases) { Text($0.label).tag($0) }
                }
                Text("A modifier held on its own, or a function key. A plain letter cannot be used — it would type into whatever app you are dictating into.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SwiftUI.Section("Hands-free lock") {
                Toggle("Enable the lock shortcut", isOn: $settings.lockEnabled)
                KeyRecorderField(title: "Lock",
                                 binding: $settings.lockBinding,
                                 conflictsWith: settings.binding,
                                 allowBareModifier: false)
                    .disabled(!settings.lockEnabled)
                Text("Press once to start recording hands-free, press again to stop — no need to keep holding. It must include a modifier, because Yapperroni swallows this combination so it does not also type.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SwiftUI.Section("Output") {
                Picker("When finished", selection: $settings.output) {
                    ForEach(OutputMode.allCases) { Text($0.label).tag($0) }
                }
                Text(settings.output.detail).font(.caption).foregroundStyle(.secondary)
                Toggle("Add a trailing space", isOn: $settings.trailingSpace)
            }

            SwiftUI.Section("Model") {
                Picker("Model", selection: $settings.modelFilename) {
                    ForEach(settings.availableModels, id: \.self) { Text($0).tag($0) }
                }
                HStack {
                    Text("Drop more `.bin` models into the support folder to see them here.")
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Reveal") {
                        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: Config.supportDir.path)
                    }
                }
            }

            SwiftUI.Section("Silence gate") {
                VStack(alignment: .leading) {
                    HStack {
                        Text("Minimum loudness")
                        Spacer()
                        Text(String(format: "%.4f", settings.minPeakRMS))
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                    Slider(value: $settings.minPeakRMS, in: 0.0001...0.02)
                }
                VStack(alignment: .leading) {
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
                Text("Quieter input is dropped rather than sent to the model — Whisper invents confident sentences out of silence.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            SwiftUI.Section("Appearance") {
                Picker("Status pill", selection: $settings.hudPosition) {
                    ForEach(HUDPosition.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Play a sound when dictation starts and stops", isOn: $settings.soundFeedback)
            }

            SwiftUI.Section("History") {
                Toggle("Keep a history of transcripts", isOn: $settings.historyEnabled)
                Stepper("Keep the last \(settings.historyLimit)",
                        value: $settings.historyLimit, in: 25...5000, step: 25)
                    .disabled(!settings.historyEnabled)
            }

            SwiftUI.Section("System") {
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
        .formStyle(.grouped)
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

// MARK: - Stats

struct StatsView: View {
    @ObservedObject private var store = HistoryStore.shared

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                HStack(spacing: 16) {
                    tile("Dictations", "\(store.entries.count)")
                    tile("Words", "\(store.totalWords)")
                }
                HStack(spacing: 16) {
                    tile("Audio recorded", format(store.totalSeconds))
                    tile("Average decode", String(format: "%.2fs", store.averageLatency))
                }
                tile("Time saved vs typing", format(max(0, store.minutesSaved) * 60),
                     note: "Assuming 40 words per minute typed.")
            }
            .padding(24)
        }
    }

    private func tile(_ title: String, _ value: String, note: String? = nil) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(size: 32, weight: .medium, design: .rounded))
                .monospacedDigit()
            if let note { Text(note).font(.caption2).foregroundStyle(.tertiary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func format(_ seconds: Double) -> String {
        seconds < 60 ? String(format: "%.0fs", seconds)
                     : String(format: "%.0fm %02.0fs", (seconds / 60).rounded(.down), seconds.truncatingRemainder(dividingBy: 60))
    }
}
