import SwiftUI
import AVFoundation
import AppKit

/// First-run screen.
///
/// Yapperroni asks for the microphone and for Accessibility — the second of
/// which sounds like "let this app read everything I type". Saying plainly what
/// each is for, before macOS throws its own dialog, is the difference between
/// an informed yes and a nervous one.
struct WelcomeView: View {
    @ObservedObject private var state = AppState.shared
    @ObservedObject private var settings = Settings.shared

    @State private var micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
    @State private var axGranted = Hotkey.requestAccessibility(prompt: false)

    /// Permissions are granted outside this app, so poll while it is on screen.
    private let poll = Timer.publish(every: 1.0, on: .main, in: .common).autoconnect()

    private var micGranted: Bool { micStatus == .authorized }
    private var ready: Bool { micGranted && axGranted }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                privacyNote
                permissions
                historyConsent
                footer
            }
            .padding(36)
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .onReceive(poll) { _ in
            micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
            axGranted = Hotkey.requestAccessibility(prompt: false)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Yapperroni").font(.system(size: 34, weight: .semibold))
            Text("Hold \(settings.binding.displayName), speak, let go. The text lands wherever your cursor is.")
                .font(.title3).foregroundStyle(.secondary)
            Text("Or press \(settings.lockBinding.displayName) to record hands-free, and again to stop.")
                .font(.callout).foregroundStyle(.tertiary)
        }
    }

    /// Worded from the current settings. The absolute claim only holds while
    /// AI cleanup is off — once it is on, transcribed text is sent to a third
    /// party, and saying otherwise would be false.
    private var privacyNote: some View {
        // A local cleanup model sends nothing anywhere, so it does not
        // weaken the claim.
        let cleanup = settings.cleanupEnabled && !settings.cleanupProvider.isLocal
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: cleanup ? "lock.open.laptopcomputer" : "lock.laptopcomputer")
                .font(.title2).foregroundStyle(cleanup ? .orange : .green)
            VStack(alignment: .leading, spacing: 3) {
                Text(cleanup ? "Your voice stays here — your text does not"
                             : "Your voice never leaves this Mac")
                    .fontWeight(.medium)
                Text(cleanup
                     ? "Speech recognition runs on your own hardware and the audio is never uploaded. But AI cleanup is on, so each finished transcript is sent as text to \(settings.cleanupProvider.label) to be rewritten. Turn it off in Settings to keep everything local."
                     : "Speech recognition runs entirely on your own hardware. No account, no server, no analytics. Audio is held in memory while you speak and discarded once it becomes text. Nothing is sent anywhere unless you turn on AI cleanup in Settings.")
                    .font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background((cleanup ? Color.orange : Color.green).opacity(0.09),
                    in: RoundedRectangle(cornerRadius: 10))
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Two permissions").font(.headline)

            row(granted: micGranted,
                title: "Microphone",
                detail: "To hear you while you hold the key. macOS shows the orange recording dot whenever it is live.",
                action: micGranted ? nil : (micStatus == .denied ? "Open Settings…" : "Allow…")) {
                if micStatus == .denied {
                    open("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
                } else {
                    AVCaptureDevice.requestAccess(for: .audio) { _ in }
                }
            }

            row(granted: axGranted,
                title: "Accessibility",
                detail: "To notice your dictation key while another app is focused, and to paste the result into it. Yapperroni does not read other apps and does not log what you type — the key tap looks at the key code and ignores everything that is not your shortcut.",
                action: axGranted ? nil : "Open Settings…") {
                Hotkey.requestAccessibility(prompt: true)
                open("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
            }

            if axGranted && !state.tapActive {
                Text("Accessibility is granted but the shortcut is not live yet — quit and reopen Yapperroni.")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
    }

    private func row(granted: Bool, title: String, detail: String,
                     action: String?, perform: @escaping () -> Void) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.title3)
                .foregroundStyle(granted ? .green : .secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if let action {
                Button(action, action: perform).buttonStyle(.borderedProminent)
            }
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private var historyConsent: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(isOn: $settings.historyEnabled) {
                Text("Keep a history of what I dictate").fontWeight(.medium)
            }
            Text("Stored on this Mac only, as text — never the audio. You can search, delete or clear it any time, and turn this off later in Settings.")
                .font(.callout).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
    }

    private var footer: some View {
        HStack {
            Button("Privacy details") {
                open("https://github.com/rolldesi/yapperroni/blob/main/PRIVACY.md")
            }
            .buttonStyle(.link)
            Spacer()
            Button(ready ? "Start dictating" : "Continue anyway") {
                AppState.shared.showWelcome = false
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .keyboardShortcut(.defaultAction)
        }
        .padding(.top, 4)
    }

    private func open(_ url: String) {
        guard let u = URL(string: url) else { return }
        NSWorkspace.shared.open(u)
    }
}
