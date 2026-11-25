import SwiftUI

/// The three shortcuts, as cards. Personal holds every setting; Room and Call
/// are the same recorder left running, so their cards hold only a shortcut
/// and when the recording ends by itself. One card is open at a time.
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
                    Text("One recorder on three shortcuts. Room and Call keep running until you stop them, and also record what your Mac is playing.")
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
        case .room, .call:
            let m = settings.modes[kind!.rawValue]
            return "Your mic and what the Mac plays, together. "
                + (m.maxMinutes == 0 ? "Runs until you stop it" : "Stops itself after \(Int(m.maxMinutes)) min")
                + (m.stopOnSilence ? " or \(Int(Config.maxSilenceSeconds))s of silence." : ".")
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
        Hint("Apple's voice processing: hears you over music and room noise. Tuned for a voice close to the mic. Always off in Room and Call, where it would turn down the call being recorded.")
    }
}

// MARK: - Room and Call

private struct RecordingModeSettings: View {
    let kind: ModeKind
    @ObservedObject private var settings = Settings.shared

    private var mode: Binding<RecordingMode> { $settings.modes[kind.rawValue] }

    var body: some View {
        KeyRecorderField(title: "Start / stop", binding: mode.binding,
                         conflictsWith: settings.shortcuts(except: .mode(kind)), allowBareModifier: false)

        Divider().padding(.vertical, 2)

        Stepper(mode.wrappedValue.maxMinutes == 0 ? "No length limit"
                                                  : "Stop after \(Int(mode.wrappedValue.maxMinutes)) min",
                value: mode.maxMinutes, in: 0...600, step: 5)
        Toggle("Stop after \(Int(Config.maxSilenceSeconds))s of silence", isOn: mode.stopOnSilence)
        Hint("Everything else — model, language, typing as you speak — is Personal's. Words are typed where your caret was when you started — and held while that app is not in front or no text field has focus, then copied when you stop. The transcript is also kept in History.")
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
