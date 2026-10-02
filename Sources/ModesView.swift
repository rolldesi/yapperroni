import SwiftUI

/// The three ways to record, as cards. Each shows its shortcut at a glance and
/// opens to only the settings that matter for it; the ones that only matter
/// sometimes sit under Advanced. One card is open at a time.
struct ModesView: View {
    enum Card: String, Hashable { case personal, room, call }
    /// Remembered across launches. Empty — all three collapsed — on first
    /// open, so the three modes and their shortcuts are visible at once.
    @AppStorage("modesOpenCard") private var openRaw = ""
    private var open: Binding<Card?> {
        Binding(get: { Card(rawValue: openRaw) }, set: { openRaw = $0?.rawValue ?? "" })
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Modes")
                        .font(.system(size: 26, weight: .semibold))
                        .foregroundStyle(Palette.ink)
                    Text("Three ways to record, each on its own shortcut. Pick by where the voice is coming from.")
                        .font(.system(size: 13))
                        .foregroundStyle(Palette.muted)
                }
                .padding(.top, 4)
                .padding(.bottom, 6)

                ModeCard(card: .personal, open: open) { PersonalSettings() }
                ModeCard(card: .room, open: open) { RecordingModeSettings(kind: .room) }
                ModeCard(card: .call, open: open) { RecordingModeSettings(kind: .call) }
            }
            .padding(28)
            .frame(maxWidth: 600, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .background(Palette.canvas)
    }
}

private struct ModeCard<Content: View>: View {
    let card: ModesView.Card
    @Binding var open: ModesView.Card?
    @ViewBuilder let content: () -> Content
    @ObservedObject private var settings = Settings.shared

    private var kind: ModeKind? {
        switch card {
        case .personal: return nil
        case .room: return .room
        case .call: return .call
        }
    }
    private var isOpen: Bool { open == card }
    private var enabled: Bool { kind.map { settings.modes[$0.rawValue].enabled } ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if isOpen {
                Divider().padding(.horizontal, 18)
                VStack(alignment: .leading, spacing: 12) { content() }
                    .padding(18)
                    .disabled(!enabled)
                    .opacity(enabled ? 1 : 0.5)
            }
        }
        .background(Palette.surface, in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12)
            .strokeBorder(isOpen ? Palette.accent.opacity(0.45) : Color.clear, lineWidth: 1))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle().fill(Palette.accent.opacity(enabled ? 0.14 : 0.06))
                Image(systemName: symbol)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(enabled ? Palette.accent : Palette.muted)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(enabled ? Palette.ink : Palette.muted)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Palette.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            HStack(spacing: 6) {
                ForEach(shortcuts, id: \.self) { ShortcutChip(text: $0) }
            }
            .opacity(enabled ? 1 : 0.4)
            if let kind {
                Toggle("", isOn: $settings.modes[kind.rawValue].enabled)
                    .toggleStyle(.switch)
                    .labelsHidden()
                    .controlSize(.small)
                    .help(enabled ? "Turn \(title) off" : "Turn \(title) on")
            }
            Image(systemName: "chevron.right")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(Palette.muted)
                .rotationEffect(.degrees(isOpen ? 90 : 0))
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.18)) { open = isOpen ? nil : card }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
        .accessibilityHint(isOpen ? "Collapse" : "Show settings")
    }

    private var symbol: String {
        switch card {
        case .personal: return "mic.fill"
        case .room: return "building.columns.fill"
        case .call: return "video.fill"
        }
    }
    private var title: String {
        switch card {
        case .personal: return "Personal"
        case .room: return "Room"
        case .call: return "Call"
        }
    }
    private var subtitle: String {
        switch card {
        case .personal: return "You, at your Mac. Hold a key, speak, and the text lands where you're typing."
        case .room: return "Lectures and meeting rooms. Records the room through this Mac's microphone."
        case .call: return "Teams, Zoom, Meet, any call or video. Records what your Mac plays, not the room."
        }
    }
    private var shortcuts: [String] {
        switch card {
        case .personal:
            return [settings.binding.displayName] + (settings.lockEnabled ? [settings.lockBinding.displayName] : [])
        case .room, .call:
            return [settings.modes[kind!.rawValue].binding.displayName]
        }
    }
}

private struct ShortcutChip: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11, weight: .medium, design: .monospaced))
            .foregroundStyle(Palette.ink.opacity(0.8))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Palette.tint(0.06), in: RoundedRectangle(cornerRadius: 5))
            .lineLimit(1)
            .fixedSize()
    }
}

// MARK: - Personal

private struct PersonalSettings: View {
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        KeyRecorderField(title: "Hold to dictate", binding: $settings.binding,
                         conflictsWith: settings.shortcuts(except: .hold), allowBareModifier: true)
        Picker("Key behaviour", selection: $settings.activation) {
            ForEach(ActivationMode.allCases) { Text($0.label).tag($0) }
        }
        Hint("A modifier held on its own, or a function key. A plain letter cannot be used — it would type into the app you are dictating into.")

        Toggle("Hands-free shortcut", isOn: $settings.lockEnabled)
        KeyRecorderField(title: "Start / stop hands-free", binding: $settings.lockBinding,
                         conflictsWith: settings.shortcuts(except: .lock), allowBareModifier: false)
            .disabled(!settings.lockEnabled)

        Divider().padding(.vertical, 2)

        ModelAndLanguage(model: $settings.modelFilename, language: $settings.language)

        Divider().padding(.vertical, 2)

        Toggle("Type as you speak", isOn: $settings.liveTranscription)
        Hint(settings.liveTranscription
             ? "Words appear about a second behind you, typed character by character."
             : "Everything is inserted when you stop.")
        if !settings.liveTranscription {
            Picker("When finished", selection: $settings.output) {
                ForEach(OutputMode.allCases) { Text($0.label).tag($0) }
            }
            Hint(settings.output.detail)
        }
        Toggle("Filter background noise", isOn: $settings.voiceIsolation)
        Hint("Apple's voice processing: hears you over music and room noise. Tuned for a voice close to the mic.")
    }
}

// MARK: - Room and Call

private struct RecordingModeSettings: View {
    let kind: ModeKind
    @ObservedObject private var settings = Settings.shared
    @State private var advanced = false

    private var mode: Binding<RecordingMode> { $settings.modes[kind.rawValue] }

    var body: some View {
        KeyRecorderField(title: "Start / stop", binding: mode.binding,
                         conflictsWith: settings.shortcuts(except: .mode(kind)), allowBareModifier: false)

        if kind == .room {
            Picker("Microphone", selection: mode.micDevice) {
                Text("This Mac's built-in mic").tag(InputDevice.builtInMic)
                Text("System default").tag(InputDevice.systemDefault)
                ForEach(InputDevice.all(), id: \.uid) { Text($0.name).tag($0.uid) }
            }
            Hint("AirPods and headsets aim at your mouth and filter out everyone else, so a lecturer across the room is removed before Yapperroni hears it. Use the built-in mic, or an iPhone placed nearer the front.")
            Toggle("Max mic sensitivity while recording", isOn: mode.maxMicGain)
        } else {
            Hint("Captures the call itself, before it reaches your speakers or headphones — even with the Mac muted. macOS asks once to allow System Audio Recording.")
        }

        Divider().padding(.vertical, 2)

        ModelAndLanguage(model: mode.modelFilename, language: mode.language)

        Divider().padding(.vertical, 2)

        Picker("When finished", selection: mode.output) {
            ForEach(OutputMode.allCases) { Text($0.label).tag($0) }
        }
        Stepper(mode.wrappedValue.maxMinutes == 0 ? "No length limit"
                                                  : "Stop after \(Int(mode.wrappedValue.maxMinutes)) min",
                value: mode.maxMinutes, in: 0...600, step: 5)
        Hint("The transcript is also kept in History.")

        DisclosureGroup("Advanced", isExpanded: $advanced) {
            VStack(alignment: .leading, spacing: 10) {
                let whisper = mode.wrappedValue.modelFilename.hasSuffix(".bin")
                Toggle("Skip silence (voice detection)", isOn: mode.vad).disabled(!whisper)
                if mode.wrappedValue.vad {
                    Warning("Helps when a recording has long silences. On a quiet or muffled speaker it can mistake speech for silence and drop it.")
                }
                Toggle("Accurate decoding (slower)", isOn: mode.accurate).disabled(!whisper)
                if kind == .room {
                    Toggle("Filter background noise", isOn: mode.voiceIsolation)
                    Hint("Off by default: it is tuned for one voice close to the mic and treats a lecturer across the room as noise.")
                }
                Toggle("Stop after \(Int(Config.maxSilenceSeconds))s of silence", isOn: mode.stopOnSilence)
                Toggle("Type as you speak", isOn: mode.live)
                if mode.wrappedValue.live {
                    Warning("Re-transcribes the whole recording every half second, so it falls behind on long recordings.")
                }
            }
            .padding(.top, 8)
        }
        .font(.system(size: 13))
    }
}

// MARK: - Shared rows

private struct ModelAndLanguage: View {
    @Binding var model: String
    @Binding var language: String
    @ObservedObject private var settings = Settings.shared

    var body: some View {
        let models = settings.availableModels
        Picker("Model", selection: $model) {
            ForEach(models, id: \.self) { Text(Engines.label($0)).tag($0) }
            if !models.contains(model) {
                Text("\(Engines.label(model)) — missing, uses Personal's model").tag(model)
            }
        }
        Picker("Language", selection: $language) {
            ForEach(Languages.all, id: \.code) { Text($0.name).tag($0.code) }
        }
        Hint(Engines.note(model))
    }
}

private struct Hint: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(Palette.muted)
            .fixedSize(horizontal: false, vertical: true)
    }
}

private struct Warning: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(.system(size: 11.5)).foregroundStyle(.orange)
            .fixedSize(horizontal: false, vertical: true)
    }
}
