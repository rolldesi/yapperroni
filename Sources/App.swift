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
    /// Runaway-session watchdog. A hands-free recording has nothing to end it
    /// but a second keypress, so it ends itself on a ceiling: total length,
    /// a stretch of silence, or whisper looping on one clause.
    private var sessionStart = Date()
    private var lastVoiceAt = Date()
    private var voicePeak: Float = 0
    private var lastSilenceCheck = Date()
    /// Silence only ends a session that has no key held down to end it.
    private var handsFree = false
    /// Silence cannot end a session that has not heard anything yet: pressing
    /// the key and then gathering your thought is normal, and the engine plus
    /// voice-processing warmup already eats part of the first second.
    private var heardVoice = false
    /// When the last dictation ended. Starting capture tears the audio engine
    /// down and builds it back up, and AVAudioEngine is not safe to churn at
    /// key-repeat speed — a held-down or hammered hotkey would otherwise
    /// restart it dozens of times a second.
    private var lastEndedAt = Date.distantPast
    private static let minRestartGap: TimeInterval = 0.3
    private var wordCount = 0
    /// Transcription is async. Without this, starting again before it finishes
    /// interleaves two Injector calls, and the second saves the first one's
    /// pasted text as the "original" clipboard to restore.
    private var isTranscribing = false
    private let launchedAt = Date()
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
            // Exit quietly. Activating the running instance would drag it in
            // front of whatever the user is doing, which is exactly the
            // interruption this app must never cause.
            Log.write("launch  another Yapperroni is already running (pid \(other.processIdentifier)); exiting quietly")
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

        hotkey.onVocab      = { VocabWindow.shared.toggle() }
        hotkey.onActivate   = { [weak self] src in self?.beginDictation(src) }
        hotkey.onDeactivate = { [weak self] _   in self?.endDictation() }

        // Rebinding must tear the tap down and rebuild it: a rebind mid-hold
        // would otherwise leave the old key's state stuck.
        settings.hotkeyChanged
            .receive(on: DispatchQueue.main)
            .sink { [weak self] in self?.startHotkey() }
            .store(in: &bag)

        settings.themeChanged
            .receive(on: DispatchQueue.main)
            .sink { MainWindow.shared.applyTheme() }
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
            MainWindow.shared.show(section: Section(rawValue: name) ?? .history, reason: "launch flag")
        } else if !UserDefaults.standard.bool(forKey: "hasLaunchedBefore") {
            // Yapperroni has no Dock icon and opens no window, so a first launch
            // with nothing on screen reads as "it didn't start". Show what it
            // needs and why, before macOS throws its own permission dialogs.
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
            state.showWelcome = true
            MainWindow.shared.show(section: .history, reason: "first run")
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
        // Only a real user gesture should open the window. macOS also sends
        // this for launches that are not a click — a second `open` of an
        // already-running app, Launch Services re-registering it — and honoring
        // those is why the window kept appearing unbidden.
        guard !flag, launchedLongEnoughAgo else {
            Log.write("window  reopen ignored (visibleWindows=\(flag))")
            return true
        }
        MainWindow.shared.show(section: .history, reason: "dock/finder reopen")
        return true
    }

    /// Reopen events arriving in the first moments after launch are startup
    /// noise, not someone clicking the icon.
    private var launchedLongEnoughAgo: Bool {
        Date().timeIntervalSince(launchedAt) > 3.0
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
        // Dropped, not queued: a press this close to the last release is a
        // hammered key, and honouring it restarts the audio engine mid-teardown.
        guard Date().timeIntervalSince(lastEndedAt) >= AppDelegate.minRestartGap else {
            Log.write("press   ignored — too soon after the last release")
            hotkey.disengage(); return
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
        sessionStart = Date()
        lastVoiceAt = sessionStart
        lastSilenceCheck = sessionStart
        voicePeak = 0
        heardVoice = false
        handsFree = (source == .lock) || settings.activation == .toggle
        Log.write("press   source=\(source == .lock ? "lock" : "hold") target=\(targetAppName)")
        if settings.soundFeedback { NSSound(named: "Tink")?.play() }

        hud.show(source == .lock ? .locked : .listening, at: settings.hudPosition)

        // Live mode types words as they settle. It must own the whole
        // utterance: batch would paste the same text again at the end.
        if settings.liveTranscription, !settings.cleanupEnabled, let w = whisper {
            let s = StreamingTranscriber(
                whisper: w,
                onEmit: { [weak self] chunk in
                    self?.typeQueue.async { Injector.typeOut(chunk) }
                },
                onPartial: { [weak self] text in
                    guard let self, self.recorder.isRecording else { return }
                    self.hud.setPartial(text)
                    // Words already typed cannot be retracted, but a loop that
                    // is left running keeps typing the same clause forever.
                    if StreamingTranscriber.isLooping(StreamingTranscriber.words(text)) {
                        self.autoStop("transcript looping")
                    }
                })
            streamer = s
            s.start(sample: { [weak self] in self?.recorder.snapshot() ?? [] })
        }

        levelTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.hud.setLevel(self.recorder.level)
            self.watchdogTick()
        }
    }

    /// Ends a session that has run away: a lock left on, a key that never came
    /// back up, an open mic in an empty room. Whatever was said still goes
    /// through the normal transcribe-and-insert path — the ceiling stops the
    /// recording, it does not throw the speech away.
    private func watchdogTick() {
        guard recorder.isRecording else { return }
        let now = Date()

        if now.timeIntervalSince(sessionStart) >= Config.maxSessionSeconds {
            return autoStop("\(Int(Config.maxSessionSeconds / 60)) minute limit")
        }
        guard handsFree else { return }

        // `recorder.level` is overwritten per audio buffer, so a 30 Hz sample
        // of it misses buffers. Accumulate the peak between checks instead.
        voicePeak = max(voicePeak, recorder.level)
        guard now.timeIntervalSince(lastSilenceCheck) >= 1 else { return }
        lastSilenceCheck = now
        if voicePeak >= Config.silenceRMS {
            lastVoiceAt = now
            heardVoice = true
        }
        voicePeak = 0

        guard heardVoice else { return }
        if now.timeIntervalSince(lastVoiceAt) >= Config.maxSilenceSeconds {
            autoStop("\(Int(Config.maxSilenceSeconds))s of silence")
        }
    }

    /// Stops as if the user had pressed the key themselves.
    private func autoStop(_ why: String) {
        guard recorder.isRecording else { return }
        Log.write("auto    stopping — \(why)")
        // The lock's state machine still thinks it is recording; without this
        // the next press of the lock key would only clear it, not start again.
        hotkey.disengage()
        endDictation()
        flash("Stopped — \(why)", 1.6)
    }

    private func endDictation() {
        guard recorder.isRecording else { return }
        lastEndedAt = Date()
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
                // NOT cleared here: cleanup is a network call with retries, and
                // a second utterance landing during it interleaves two Injector
                // calls — the second saves the first one's pasted text as the
                // "original" clipboard to restore. Cleared at every exit below.
                Log.write(String(format: "result  %.2fs \"%@\"", elapsed, raw))

                guard !raw.isEmpty else {
                    self.isTranscribing = false
                    Log.write("        empty after cleaning (silence or hallucination filter)")
                    self.hud.show(.message("No speech detected"), at: self.settings.hudPosition)
                    self.hud.hide(after: 1.2)
                    return
                }

                guard self.settings.cleanupEnabled else {
                    self.isTranscribing = false
                    self.deliver(raw, target: target, seconds: seconds,
                                 elapsed: elapsed, appName: appName)
                    return
                }

                self.hud.show(.message("Cleaning up…"), at: self.settings.hudPosition)
                let s = self.settings
                Task {
                    var text = raw
                    let t1 = Date()
                    do {
                        text = try await Cleanup.run(raw,
                                                     provider: s.cleanupProvider,
                                                     model: s.cleanupModel,
                                                     prompt: s.cleanupPrompt,
                                                     baseURL: s.cleanupBaseURL)
                        Log.write(String(format: "cleanup %@ ok in %.2fs",
                                         s.cleanupProvider.rawValue, Date().timeIntervalSince(t1)))
                    } catch {
                        // The user already spoke these words — never drop them
                        // because a network call failed. Insert the raw text and
                        // say why. Status codes only; never the key or the body.
                        Log.write("cleanup \(s.cleanupProvider.rawValue) FAILED: \(error)")
                        await MainActor.run {
                            self.flash("Cleanup failed (\(error)) — inserted raw text", 2.5)
                        }
                    }
                    let final = text
                    await MainActor.run {
                        self.isTranscribing = false
                        self.deliver(final, target: target, seconds: seconds,
                                     elapsed: elapsed, appName: appName)
                    }
                }
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

    /// Types or pastes the finished text and records it.
    private func deliver(_ raw: String, target: NSRunningApplication?,
                         seconds: Double, elapsed: Double, appName: String) {
        let text = settings.trailingSpace ? raw + " " : raw
        Injector.inject(text, into: target, mode: settings.output,
                        leaveOnClipboard: settings.copyToClipboard)

        history.add(Utterance(date: Date(), text: raw, duration: seconds,
                              latency: elapsed, appName: appName))
        wordCount += raw.split(separator: " ").count

        let verb = settings.output == .copy ? "copied" : "inserted"
        hud.show(.message(String(format: "%.1fs · %d words %@",
                                 elapsed, raw.split(separator: " ").count, verb)),
                 at: settings.hudPosition)
        hud.hide(after: 1.0)
        refreshMenu()
    }

    private func flash(_ message: String, _ seconds: TimeInterval) {
        hud.show(.message(message), at: settings.hudPosition)
        hud.hide(after: seconds)
    }

    // MARK: - Setup

    private func startHotkey() {
        // Rebinding while a key is held would otherwise strand the recorder:
        // the release event arrives for a binding the tap no longer watches, so
        // no deactivate ever reaches endDictation and capture runs forever.
        if recorder.isRecording { endDictation() }

        let live = hotkey.start(push: settings.binding,
                                lock: settings.lockBinding,
                                lockEnabled: settings.lockEnabled,
                                vocab: settings.vocabBinding,
                                vocabEnabled: settings.vocabEnabled,
                                mode: settings.activation)
        state.tapActive = live
        state.accessibilityGranted = Hotkey.requestAccessibility(prompt: false)
        setBadge(live ? nil : "!")
        Log.write("hotkey  push=\(settings.binding.displayName) "
                + "lock=\(settings.lockEnabled ? settings.lockBinding.displayName : "off") "
                + "vocab=\(settings.vocabEnabled ? settings.vocabBinding.displayName : "off") "
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

    @objc private func openWindow()   { MainWindow.shared.show(section: .history,  reason: "menu") }
    @objc private func openHistory()  { MainWindow.shared.show(section: .history,  reason: "menu") }
    @objc private func openSettings() { MainWindow.shared.show(section: .settings, reason: "menu") }

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
