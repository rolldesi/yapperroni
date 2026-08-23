import Cocoa
import AVFoundation
import ServiceManagement
import Combine

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let hotkey = Hotkey()
    private let recorder = Recorder()
    private let hud = HUD()
    private var whisper: Whisper?

    private let settings = Settings.shared
    private let history = HistoryStore.shared
    private let state = AppState.shared
    private var bag = Set<AnyCancellable>()

    private var statusItem: NSStatusItem!
    private var targetApp: NSRunningApplication?
    private var targetAppName = "?"
    private var levelTimer: Timer?
    private var wordCount = 0
    /// Transcription is async. Without this, starting again before it finishes
    /// interleaves two Injector calls, and the second saves the first one's
    /// pasted text as the "original" clipboard to restore.
    private var isTranscribing = false
    private var streamer: StreamingTranscriber?
    /// Serial, so live chunks reach the target app in the order they settled.
    private let typeQueue = DispatchQueue(label: "yapperroni.typing")

    func applicationDidFinishLaunching(_ note: Notification) {
        // After a DMG install, an older copy elsewhere on disk can still be
        // running (or launching at login). Two instances means two event taps
        // and every utterance dictated twice.
        if let other = NSRunningApplication
            .runningApplications(withBundleIdentifier: Bundle.main.bundleIdentifier ?? "")
            .first(where: { $0.processIdentifier != NSRunningApplication.current.processIdentifier }) {
            Log.write("launch  another Yapperroni is already running (pid \(other.processIdentifier)); handing over")
            other.activate()
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(.accessory)
        buildStatusItem()

        loadModel()
        if UserDefaults.standard.bool(forKey: "hasLaunchedBefore") { requestMicrophone() }

        state.accessibilityGranted = Hotkey.requestAccessibility(
            prompt: UserDefaults.standard.bool(forKey: "hasLaunchedBefore"))
        startHotkey()

        hotkey.onActivate   = { [weak self] src in self?.beginDictation(src) }
        hotkey.onDeactivate = { [weak self] _   in self?.endDictation() }

        // Rebinding must tear the tap down and rebuild it: a rebind mid-hold
        // would otherwise leave the old key's state stuck.
        settings.hotkeyChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.startHotkey() }
            .store(in: &bag)

        settings.$modelFilename
            .dropFirst()
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.loadModel() }
            .store(in: &bag)

        settings.reconcileModelSelection()

        if let arg = CommandLine.arguments.first(where: { $0.hasPrefix("--open-window") }) {
            let name = arg.split(separator: "=").last.map(String.init) ?? ""
            MainWindow.shared.show(section: Section(rawValue: name) ?? .history)
        } else if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            // Yapperroni has no Dock icon and opens no window, so a first launch
            // with nothing on screen reads as "it didn't start". Show what it
            // needs and why, before macOS throws its own permission dialogs.
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            state.showWelcome = true
            MainWindow.shared.show(section: .history)
        }

        Log.write("launch  accessibility=\(state.accessibilityGranted) tap=\(hotkey.isActive) "
                + "push=\(settings.binding.displayName) "
                + "lock=\(settings.lockEnabled ? settings.lockBinding.displayName : "off") "
                + "mode=\(settings.activation.rawValue) "
                + "model=\(settings.modelPath)")
        if !hotkey.isActive {
            Log.write("launch  TAP DEAD — grant Accessibility, then quit and reopen Yapperroni")
        }
    }

    /// Double-clicking an already-running LSUIElement app fires this and
    /// nothing else. Without it, the app can never be reopened from Finder.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { MainWindow.shared.show(section: .history) }
        return true
    }

    func applicationWillTerminate(_ note: Notification) {
        hotkey.stop()
        streamer?.cancel()
        streamer = nil
        recorder.stop()
        whisper?.close()
        whisper = nil
    }

    // MARK: - Dictation

    private func beginDictation(_ source: Hotkey.Source = .hold) {
        guard state.modelReady else {
            flash("Loading model…", 1.5); hotkey.disengage(); return
        }
        guard !recorder.isRecording else { return }
        guard !isTranscribing else {
            Log.write("press   ignored — previous utterance still transcribing")
            flash("Still transcribing…", 1.0); hotkey.disengage(); return
        }
        // Password fields enable secure input, which makes both the tap and the
        // paste no-ops. Say so instead of failing silently.
        if Hotkey.secureInputActive {
            flash("Secure field — dictation blocked", 2); hotkey.disengage(); return
        }

        // Resolve the destination now, before the HUD can perturb focus.
        targetApp = NSWorkspace.shared.frontmostApplication
        targetAppName = targetApp?.localizedName ?? "?"

        do {
            try recorder.start()
        } catch {
            Log.write("press   recorder failed: \(error)")
            flash("\(error)", 3); hotkey.disengage(); return
        }

        state.dictating = true
        Log.write("press   source=\(source == .lock ? "lock" : "hold") target=\(targetAppName)")
        if settings.soundFeedback { NSSound(named: "Tink")?.play() }

        hud.show(source == .lock ? .locked : .listening, at: settings.hudPosition)

        // Live mode types words as they settle. It must own the whole
        // utterance: batch would paste the same text again at the end.
        if settings.liveTranscription, let w = whisper {
            let s = StreamingTranscriber(
                whisper: w,
                onEmit: { [weak self] chunk in
                    self?.typeQueue.async { Injector.typeOut(chunk) }
                },
                onPartial: { [weak self] text in
                    guard let self, self.recorder.isRecording else { return }
                    self.hud.setPartial(text)
                })
            streamer = s
            s.start(sample: { [weak self] in self?.recorder.snapshot() ?? [] })
        }

        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.hud.setLevel(self.recorder.level)
        }
    }

    private func endDictation() {
        guard recorder.isRecording else { return }
        levelTimer?.invalidate(); levelTimer = nil
        // Stop ticking before the recorder is cleared: a tick starting in that
        // window would read an emptied buffer.
        streamer?.stopTicking()

        let pcm = recorder.stop()
        state.dictating = false
        let seconds = Double(pcm.count) / Config.sampleRate
        let target = targetApp
        let appName = targetAppName
        if settings.soundFeedback { NSSound(named: "Pop")?.play() }

        let peak = Recorder.peakRMS(pcm)
        Log.write(String(format: "release samples=%d secs=%.2f peak100ms=%.5f (floors: %.2fs / %.5f)",
                         pcm.count, seconds, peak, settings.minSpeechSeconds, settings.minPeakRMS))

        if let live = streamer {
            streamer = nil
            finishLive(live, pcm: pcm, seconds: seconds, appName: appName)
            return
        }

        guard seconds >= settings.minSpeechSeconds, Double(peak) >= settings.minPeakRMS else {
            Log.write("        DROPPED by gate — adjust the silence gate in Settings")
            hud.show(.message(Double(peak) < settings.minPeakRMS
                              ? "Too quiet (peak \(String(format: "%.4f", peak)))"
                              : "Too short"), at: settings.hudPosition)
            hud.hide(after: 1.6)
            return
        }

        hud.show(.transcribing, at: settings.hudPosition)
        isTranscribing = true
        let t0 = Date()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, let whisper = self.whisper else {
                DispatchQueue.main.async { self?.isTranscribing = false }
                return
            }
            let raw = whisper.transcribe(pcm)
            let elapsed = Date().timeIntervalSince(t0)

            DispatchQueue.main.async {
                self.isTranscribing = false
                Log.write(String(format: "result  %.2fs \"%@\"", elapsed, raw))

                guard !raw.isEmpty else {
                    Log.write("        empty after cleaning (silence or hallucination filter)")
                    self.hud.show(.message("No speech detected"), at: self.settings.hudPosition)
                    self.hud.hide(after: 1.2)
                    return
                }

                let text = self.settings.trailingSpace ? raw + " " : raw
                Injector.inject(text, into: target, mode: self.settings.output,
                                leaveOnClipboard: self.settings.copyToClipboard)

                self.history.add(Utterance(date: Date(), text: raw, duration: seconds,
                                           latency: elapsed, appName: appName))
                self.wordCount += raw.split(separator: " ").count

                let verb = self.settings.output == .copy ? "copied" : "inserted"
                self.hud.show(.message(String(format: "%.1fs · %d words %@",
                                              elapsed, raw.split(separator: " ").count, verb)),
                              at: self.settings.hudPosition)
                self.hud.hide(after: 1.0)
                self.refreshMenu()
            }
        }
    }

    /// Final pass for a live utterance: emits whatever the incremental passes
    /// held back, then records it. The gate is not applied here — words are
    /// already in the user's document and cannot be retracted.
    private func finishLive(_ live: StreamingTranscriber,
                            pcm: [Float], seconds: Double, appName: String) {
        hud.show(.transcribing, at: settings.hudPosition)
        isTranscribing = true
        let t0 = Date()

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let text = live.finish(pcm)
            let elapsed = Date().timeIntervalSince(t0)

            DispatchQueue.main.async {
                guard let self else { return }
                self.isTranscribing = false
                Log.write(String(format: "result  live %.2fs tail \"%@\"", elapsed, text))

                guard !text.isEmpty else {
                    self.hud.show(.message("No speech detected"), at: self.settings.hudPosition)
                    self.hud.hide(after: 1.2)
                    return
                }
                if self.settings.trailingSpace {
                    self.typeQueue.async { Injector.typeOut(" ") }
                }
                if self.settings.copyToClipboard {
                    Injector.setClipboard(text)
                }
                self.history.add(Utterance(date: Date(), text: text, duration: seconds,
                                           latency: elapsed, appName: appName))
                self.wordCount += text.split(separator: " ").count
                self.hud.show(.message("\(text.split(separator: " ").count) words"),
                              at: self.settings.hudPosition)
                self.hud.hide(after: 1.0)
                self.refreshMenu()
            }
        }
    }

    private func flash(_ message: String, _ seconds: TimeInterval) {
        hud.show(.message(message), at: settings.hudPosition)
        hud.hide(after: seconds)
    }

    // MARK: - Setup

    private func startHotkey() {
        let live = hotkey.start(push: settings.binding,
                                lock: settings.lockBinding,
                                lockEnabled: settings.lockEnabled,
                                mode: settings.activation)
        state.tapActive = live
        state.accessibilityGranted = Hotkey.requestAccessibility(prompt: false)
        setBadge(live ? nil : "!")
        Log.write("hotkey  push=\(settings.binding.displayName) "
                + "lock=\(settings.lockEnabled ? settings.lockBinding.displayName : "off") "
                + "mode=\(settings.activation.rawValue) live=\(live)")
        refreshMenu()
    }

    private func loadModel() {
        state.modelReady = false
        let path = settings.modelPath
        let previous = whisper
        whisper = nil
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            previous?.close()
            let w = Whisper(modelPath: path)
            DispatchQueue.main.async {
                guard let self else { return }
                self.whisper = w
                self.state.modelReady = (w != nil)
                if w == nil {
                    self.setBadge("!")
                    self.flash("Model failed to load", 5)
                    Log.write("model   FAILED to load \(path)")
                } else {
                    Log.write("model   loaded \(path)")
                }
                self.refreshMenu()
            }
        }
    }

    private func requestMicrophone() {
        guard AVCaptureDevice.authorizationStatus(for: .audio) != .authorized else { return }
        AVCaptureDevice.requestAccess(for: .audio) { ok in
            Log.write("mic     access granted=\(ok)")
        }
    }

    // MARK: - Menu bar

    private func buildStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        setBadge(nil)
        refreshMenu()
    }

    private func setBadge(_ badge: String?) {
        guard let button = statusItem?.button else { return }
        button.image = NSImage(systemSymbolName: "mic.fill", accessibilityDescription: "Yapperroni")
        button.image?.isTemplate = true
        button.title = badge.map { " \($0)" } ?? ""
    }

    private func refreshMenu() {
        let menu = NSMenu()

        if !hotkey.isActive {
            menu.addItem(withTitle: "Accessibility not granted", action: nil, keyEquivalent: "")
        } else if !state.modelReady {
            menu.addItem(withTitle: "Loading model…", action: nil, keyEquivalent: "")
        } else {
            menu.addItem(withTitle: "Hold \(settings.binding.displayName) to dictate",
                         action: nil, keyEquivalent: "")
            if settings.lockEnabled {
                menu.addItem(withTitle: "\(settings.lockBinding.displayName) to lock hands-free",
                             action: nil, keyEquivalent: "")
            }
        }
        menu.addItem(withTitle: "\(wordCount) words this session", action: nil, keyEquivalent: "")
        menu.addItem(.separator())

        add(menu, "Open Yapperroni", #selector(openWindow), key: "o")
        add(menu, "History…", #selector(openHistory))
        add(menu, "Settings…", #selector(openSettings), key: ",")
        menu.addItem(.separator())

        let login = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        login.target = self
        login.state = settings.launchAtLogin ? .on : .off
        menu.addItem(login)
        add(menu, "Open Accessibility Settings…", #selector(openAX))
        add(menu, "Reveal Diagnostic Log…", #selector(revealLog))

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit Yapperroni",
                                action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu
    }

    private func add(_ menu: NSMenu, _ title: String, _ action: Selector, key: String = "") {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        menu.addItem(item)
    }

    @objc private func openWindow()   { MainWindow.shared.show(section: .history) }
    @objc private func openHistory()  { MainWindow.shared.show(section: .history) }
    @objc private func openSettings() { MainWindow.shared.show(section: .settings) }

    @objc private func toggleLogin() {
        settings.launchAtLogin.toggle()
        refreshMenu()
    }

    @objc private func revealLog() {
        NSWorkspace.shared.selectFile(Log.path, inFileViewerRootedAtPath: Config.supportDir.path)
    }

    @objc private func openAX() {
        NSWorkspace.shared.open(URL(string:
            "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
}
