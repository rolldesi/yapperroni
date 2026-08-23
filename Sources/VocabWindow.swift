import Cocoa
import SwiftUI

/// A panel that can take keyboard focus.
///
/// The dictation HUD must never become key — a paste would land in it. This one
/// is the opposite: it exists to be typed into, so it opts in explicitly.
private final class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Quick-add window for the custom word list.
///
/// Opens on a global shortcut so a word can be captured the moment Yapperroni
/// gets it wrong, without leaving whatever you were doing. Stays open after
/// each entry so several words can be added in one go, and hands focus back to
/// the app you came from when it closes.
final class VocabWindow: NSObject, NSWindowDelegate {
    static let shared = VocabWindow()
    /// One source of truth for the panel and its SwiftUI content — they must
    /// agree or the window sizes itself to the view.
    static let size = CGSize(width: 460, height: 190)

    private var panel: KeyablePanel?
    private var previousApp: NSRunningApplication?

    var isOpen: Bool { panel?.isVisible == true }

    func toggle() { isOpen ? close() : show() }

    func show() {
        // Remember where to send focus back to, before we take it.
        previousApp = NSWorkspace.shared.frontmostApplication

        if panel == nil { build() }
        position()

        // An .accessory app can focus a control inside its own panel while not
        // being frontmost — the field looks focused and every keystroke goes to
        // whatever app actually is. Flipping to .regular first is what makes
        // ordinary activation land. Taking focus is the whole point here: the
        // user pressed a key to get a place to type.
        NSApp.setActivationPolicy(.regular)
        panel?.makeKeyAndOrderFront(nil)
        NSApp.activate()
        Log.write("vocab   window opened")
    }

    func close() {
        guard panel?.isVisible == true || previousApp != nil else { return }
        panel?.orderOut(nil)

        // Back to menu-bar-only, unless the main window is still up and needs
        // the Dock presence.
        if MainWindow.shared.isVisible == false {
            NSApp.setActivationPolicy(.accessory)
        }
        // Give the keyboard back to whatever the user was actually using.
        if let previous = previousApp,
           !previous.isTerminated,
           previous.processIdentifier != NSRunningApplication.current.processIdentifier {
            previous.activate()
        }
        previousApp = nil
    }

    func windowWillClose(_ notification: Notification) { close() }

    private func build() {
        let p = KeyablePanel(
            contentRect: NSRect(origin: .zero, size: VocabWindow.size),
            styleMask: [.titled, .closable, .nonactivatingPanel, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        p.title = "Add to vocabulary"
        p.titlebarAppearsTransparent = true
        p.isReleasedWhenClosed = false
        p.level = .floating
        p.hidesOnDeactivate = false
        p.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        p.delegate = self
        p.contentView = NSHostingView(rootView: VocabQuickAdd())
        panel = p
    }

    /// Upper middle of the screen — near where the eye already is, and clear of
    /// the dictation pill at the bottom.
    private func position() {
        guard let panel, let screen = NSScreen.main else { return }
        let f = screen.visibleFrame
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2,
                                     y: f.maxY - size.height - 140))
    }
}

private struct VocabQuickAdd: View {
    @ObservedObject private var settings = Settings.shared
    @State private var entry = ""
    @State private var added: [String] = []
    @State private var duplicate: String?
    @FocusState private var focused: Bool

    private var total: Int { Vocabulary.terms(settings.customVocabulary).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            TextField("Word or phrase, then Return", text: $entry)
                .textFieldStyle(.plain)
                .font(.system(size: 20))
                .focused($focused)
                .onSubmit(commit)

            Divider()

            if let duplicate {
                Text("“\(duplicate)” is already in your list.")
                    .font(.caption).foregroundStyle(.orange)
            } else if added.isEmpty {
                Text("Type a word Yapperroni keeps getting wrong. Add as many as you like — this stays open until you press Escape.")
                    .font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Added: " + added.joined(separator: ", "))
                    .font(.caption).foregroundStyle(.green)
                    .lineLimit(2)
            }

            Spacer(minLength: 0)

            HStack {
                Text("\(total) word\(total == 1 ? "" : "s") in your vocabulary")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text("esc to close").font(.caption).foregroundStyle(.tertiary)
            }
        }
        .padding(20)
        // Explicit size, not maxHeight: .infinity — an NSHostingView sizes its
        // window to the content's ideal height, and "infinity" makes that a
        // window taller than the screen.
        .frame(width: VocabWindow.size.width,
               height: VocabWindow.size.height,
               alignment: .topLeading)
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            entry = ""; added = []; duplicate = nil
            // The panel needs a beat to become key before the field can focus.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true }
        }
        .onExitCommand { VocabWindow.shared.close() }
    }

    private func commit() {
        let word = entry.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !word.isEmpty else { return }
        if let updated = Vocabulary.adding(word, to: settings.customVocabulary) {
            settings.customVocabulary = updated
            added.append(word)
            duplicate = nil
            Log.write("vocab   added a term (\(Vocabulary.terms(updated).count) total)")
        } else {
            duplicate = word
        }
        entry = ""
    }
}
