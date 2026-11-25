import Cocoa
import AVFoundation

// Three separable failure domains: whisper, audio capture, hotkey+paste.
// The first two get a headless check so they are never debugged through the
// app's permission layer.

func loadWav(_ path: String) -> [Float]? {
    guard let file = try? AVAudioFile(forReading: URL(fileURLWithPath: path)) else { return nil }
    let inFormat = file.processingFormat
    guard let inBuf = AVAudioPCMBuffer(pcmFormat: inFormat, frameCapacity: AVAudioFrameCount(file.length)),
          (try? file.read(into: inBuf)) != nil else { return nil }

    if inFormat.sampleRate == Config.sampleRate && inFormat.channelCount == 1,
       let ch = inBuf.floatChannelData?[0] {
        return Array(UnsafeBufferPointer(start: ch, count: Int(inBuf.frameLength)))
    }

    guard let conv = AVAudioConverter(from: inFormat, to: Recorder.outputFormat) else { return nil }
    let ratio = Config.sampleRate / inFormat.sampleRate
    let cap = AVAudioFrameCount(Double(inBuf.frameLength) * ratio) + 4096
    guard let out = AVAudioPCMBuffer(pcmFormat: Recorder.outputFormat, frameCapacity: cap) else { return nil }

    var fed = false
    var err: NSError?
    _ = conv.convert(to: out, error: &err) { _, status in
        if fed { status.pointee = .noDataNow; return nil }
        fed = true; status.pointee = .haveData; return inBuf
    }
    guard err == nil, let ch = out.floatChannelData?[0] else { return nil }
    return Array(UnsafeBufferPointer(start: ch, count: Int(out.frameLength)))
}

/// Any engine: `model` is a name from the support folder or bundle (a `.bin`
/// or a sherpa-onnx folder), defaulting to the dictation model.
func selftestWhisper(_ wav: String, model: String? = nil,
                     options: DecodeOptions = DecodeOptions()) -> Never {
    let path = Settings.shared.modelPath(for: model ?? Settings.shared.modelFilename)
    print("model: \(path) \(options)")
    guard let pcm = loadWav(wav) else {
        print("FAIL: could not read \(wav)"); exit(1)
    }
    print("audio: \(pcm.count) samples (\(String(format: "%.2f", Double(pcm.count) / Config.sampleRate))s), rms \(String(format: "%.4f", Recorder.rms(pcm)))")
    let l0 = Date()
    guard let w = Engines.load(path: path) else {
        print("FAIL: engine init"); exit(1)
    }
    print(String(format: "load: %.2fs", Date().timeIntervalSince(l0)))
    let t0 = Date()
    let text = StreamingTranscriber.collapseRepeats(w.transcribe(pcm, options: options))
    let dt = Date().timeIntervalSince(t0)
    w.close()
    print("transcript: \"\(text)\"")
    print(String(format: "elapsed: %.2fs  (%.1fx realtime)", dt, Double(pcm.count) / Config.sampleRate / dt))
    guard !text.isEmpty else { print("FAIL: empty transcript"); exit(1) }
    print("PASS")
    exit(0)
}

/// Levels only — nothing is transcribed, so a room full of people is not
/// written down.
func selftestAudio() -> Never {
    func say(_ m: String) { print(m); Log.write("selftest \(m)") }
    // Distinguishes "mic denied" from "mic authorized but silent". Launched
    // from a terminal, the grant belongs to the terminal, not to Yapperroni.
    let auth = AVCaptureDevice.authorizationStatus(for: .audio)
    let authName: String
    switch auth {
    case .authorized:    authName = "authorized"
    case .denied:        authName = "denied"
    case .restricted:    authName = "restricted"
    case .notDetermined: authName = "notDetermined"
    @unknown default:    authName = "unknown"
    }
    print("mic authorization: \(authName)")

    let r = Recorder()
    do { try r.start(voiceIsolation: Settings.shared.voiceIsolation) } catch {
        print("FAIL: \(error)"); exit(1)
    }
    say("recording 3s from the default mic…")
    RunLoop.current.run(until: Date().addingTimeInterval(3))
    let pcm = r.stop()
    let secs = Double(pcm.count) / Config.sampleRate
    let rms = Recorder.rms(pcm)
    say(String(format: "captured %d samples (%.2fs) at 16 kHz, rms %.4f, peak100ms %.4f",
               pcm.count, secs, rms, Recorder.peakRMS(pcm)))
    guard secs > 1.8 else { print("FAIL: short capture — resample path is wrong"); exit(1) }
    guard Double(Recorder.peakRMS(pcm)) > Settings.shared.minPeakRMS else {
        print(auth == .authorized
            ? "FAIL: authorized but silent — mic muted, wrong input device, or nobody spoke"
            : "FAIL: silent because microphone access is \(authName) for this process")
        exit(1)
    }
    say("PASS")
    exit(0)
}

/// The sequence that broke the engine: dictation (voice processing on), a
/// long recording straight after (off, with the computer's audio alongside),
/// then dictation again — on one recorder, as the app does. Each must capture,
/// and in a long recording the mic must be delivering, not just the tap.
/// Levels only. Launch with `open` so the mic grant is the app's.
func selftestMicSequence() -> Never {
    func say(_ m: String) { print(m); Log.write("selftest \(m)") }
    let r = Recorder()
    var fails = 0
    for (what, long) in [("dictation", false), ("call", true), ("dictation again", false), ("call again", true)] {
        do {
            try r.start(voiceIsolation: !long, computerAudio: long ? .everything : nil)
        } catch {
            fails += 1; say("FAIL \(what): \(error)"); continue
        }
        RunLoop.current.run(until: Date().addingTimeInterval(1.5))
        let pcm = r.stop()
        let ok = pcm.count > Int(Config.sampleRate) && r.micPeak > 0
        fails += ok ? 0 : 1
        say(String(format: "%@ %@: %.2fs captured, peak100ms %.4f, mic %.5f, computer audio %.5f",
                   ok ? "ok  " : "FAIL", what, Double(pcm.count) / Config.sampleRate,
                   Recorder.peakRMS(pcm), r.micPeak, r.systemPeak))
    }
    say(fails == 0 ? "PASS" : "FAIL: \(fails)")
    exit(fails == 0 ? 0 : 1)
}

/// Verifies the Right-Option bit mask without needing Accessibility.
/// `rightAltMask` is the one arithmetic constant that fails silently: the tap
/// fires, the bit test never matches, and onPress simply never runs.
func selftestHotkey() -> Never {
    let bound = Settings.shared.binding
    guard bound.kind == .bareModifier else {
        print("push-to-talk is bound to \(bound.displayName), which arrives as a key event, not a")
        print("modifier flag. This probe only applies to bare-modifier bindings — use the")
        print("`press` line in the log instead.")
        exit(0)
    }
    print("hold \(bound.displayName) for a moment — watching modifier flags for 10s…")
    var sawRightAlt = false
    var sawAnyAlt = false
    let deadline = Date().addingTimeInterval(10)
    var lastRaw: UInt64 = 0

    while Date() < deadline {
        let raw = CGEventSource.flagsState(.combinedSessionState).rawValue
        if raw != lastRaw {
            lastRaw = raw
            if raw != 0 { print(String(format: "  flags 0x%08llx", raw)) }
            if raw & bound.deviceMask != 0 { sawRightAlt = true }
            if raw & CGEventFlags.maskAlternate.rawValue != 0 { sawAnyAlt = true }
        }
        usleep(20_000)
    }

    if sawRightAlt {
        print(String(format: "PASS: %@ bit 0x%llx observed", bound.displayName, bound.deviceMask))
        exit(0)
    }
    print(sawAnyAlt
        ? "FAIL: a modifier was seen but not the bound one — you held the wrong side, or the mask is wrong"
        : "FAIL: no modifier seen at all — nothing was held, or this shell lacks input access")
    exit(1)
}

/// End-to-end acoustic check: play a known clip through the speakers, capture
/// it with the microphone, and transcribe what came back.
///
/// Proves capture + resample + decode together under the app's own identity.
/// Results go to the log as well as stdout, so this is meaningful when the
/// bundle is launched with `open` and has no terminal attached.
///
/// `system: true` records the way Room and Call do — the mic and the
/// computer's own output together — so the clip comes back twice: through the
/// process tap, and through the air. Both must have delivered, and the
/// transcript says whether hearing it twice hurts. Also launch it with `open`
/// — the System Audio Recording grant belongs to the app, not the terminal.
func selftestLoopback(_ wav: String, system: Bool = false) -> Never {
    func say(_ m: String) { print(m); Log.write("loopback \(m)") }

    if AVCaptureDevice.authorizationStatus(for: .audio) != .authorized {
        say("requesting microphone access — answer the prompt (waiting up to 60s)")
        let sem = DispatchSemaphore(value: 0)
        AVCaptureDevice.requestAccess(for: .audio) { _ in sem.signal() }
        _ = sem.wait(timeout: .now() + 60)
    }
    let auth = AVCaptureDevice.authorizationStatus(for: .audio)
    say("mic authorization: \(auth == .authorized ? "authorized" : "NOT authorized (raw \(auth.rawValue))")")
    guard auth == .authorized else {
        say("FAIL: grant Yapperroni microphone access in System Settings, then rerun")
        exit(1)
    }

    let r = Recorder()
    do { try r.start(voiceIsolation: !system && Settings.shared.voiceIsolation,
                     computerAudio: system ? .everything : nil) }
    catch { say("FAIL: \(error)"); exit(1) }

    say("source: \(system ? "microphone + computer audio" : "microphone")")
    say("tap format: \(r.tapFormat.map { "\($0.sampleRate)Hz \($0.channelCount)ch" } ?? "?")")
    say("playing \(wav) through the speakers and listening…")
    let task = Process()
    task.executableURL = URL(fileURLWithPath: "/usr/bin/afplay")
    task.arguments = [wav]
    do { try task.run() } catch { say("FAIL: afplay: \(error)"); r.stop(); exit(1) }
    task.waitUntilExit()

    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    let pcm = r.stop()
    let secs = Double(pcm.count) / Config.sampleRate
    let rms = Recorder.rms(pcm)
    let peak = Recorder.peakRMS(pcm)
    say(String(format: "captured %.2fs, raw mic %.5f heard to %.1fs, raw computer audio %.5f heard to %.1fs, converted rms %.5f, peak100ms %.5f (gate floor %.5f)",
               secs, r.micPeak, r.micSeconds, r.systemPeak, r.systemSeconds, rms, peak, Settings.shared.minPeakRMS))

    if system, r.systemPeak == 0 {
        say("FAIL: exact digital silence from the computer — System Audio Recording is not granted to Yapperroni")
        exit(1)
    }
    if system, r.micPeak == 0 {
        say("FAIL: the microphone delivered nothing alongside the computer audio")
        exit(1)
    }
    guard Double(peak) > Settings.shared.minPeakRMS else {
        say("FAIL: heard nothing — output volume at zero, or capture is returning silence")
        exit(1)
    }

    guard let w = Whisper(modelPath: Settings.shared.modelPath) else { say("FAIL: whisper init"); exit(1) }
    let text = w.transcribe(pcm)
    w.close()
    say("heard: \"\(text)\"")
    guard !text.isEmpty else { say("FAIL: audio captured but transcript empty"); exit(1) }
    say("PASS — \(system ? "mic + computer audio" : "mic") to text works end to end")
    exit(0)
}

/// Drives the hold / toggle / lock state machine directly, including the case
/// where a press is rejected downstream (model loading, still transcribing,
/// secure field) and `disengage()` resyncs it.
func selftestToggle() -> Never {
    var failures = 0
    var state = Hotkey.State()

    func step(_ input: Hotkey.Input, _ mode: ActivationMode,
              _ want: Hotkey.Action, _ what: String) {
        let got = Hotkey.decide(input, mode: mode, state: &state)
        let ok = got == want
        if !ok { failures += 1 }
        print("  \(ok ? "ok  " : "FAIL") \(what): got \(got), want \(want)")
    }
    func reset() { state = Hotkey.State() }

    print("hold mode:")
    reset()
    step(.holdDown, .hold, .activate,   "key down starts")
    step(.holdUp,   .hold, .deactivate, "key up stops")

    print("toggle mode:")
    reset()
    step(.holdDown, .toggle, .activate,   "press 1 starts")
    step(.holdUp,   .toggle, .none,       "release is ignored")
    step(.holdDown, .toggle, .deactivate, "press 2 stops")

    print("toggle mode, press rejected mid-transcription:")
    reset()
    step(.holdDown, .toggle, .activate,   "press 1 starts")
    step(.holdDown, .toggle, .deactivate, "press 2 stops, decode begins")
    step(.holdDown, .toggle, .activate,   "press 3 tries to start")
    reset()  // beginDictation rejected it and called disengage()
    step(.holdDown, .toggle, .activate,   "press 4 starts (one press, not two)")

    print("lock, on its own:")
    reset()
    step(.lockPress, .hold, .activate,   "lock starts hands-free")
    step(.lockPress, .hold, .deactivate, "lock again stops")
    if state != Hotkey.State() { failures += 1; print("  FAIL state not clean after lock cycle") }
    else { print("  ok   state clean after lock cycle") }

    print("lock while the hold key is down:")
    reset()
    step(.holdDown,  .hold, .activate,   "hold starts")
    step(.lockPress, .hold, .deactivate, "lock takes over and stops, not a second recording")

    print("hold key is inert while locked:")
    reset()
    step(.lockPress, .hold, .activate, "lock starts")
    step(.holdDown,  .hold, .none,     "hold press ignored while locked")
    step(.holdUp,    .hold, .none,     "hold release does not stop a locked recording")
    step(.lockPress, .hold, .deactivate, "lock stops it")

    print("chord vs the combo inside it:")
    let lock = KeyBinding.lockDefault           // ⌥Space
    let opt = CGEventFlags.maskAlternate.rawValue
    // The default quick-add is plain ⌥R; a chord is what someone gets by
    // recording two keys, and it is the case that can be confused with the
    // combo inside it.
    let vocab = KeyBinding(keyCode: 49, deviceMask: 0, modifierFlags: opt,
                           chordKeyCode: 15, kind: .combo)
    func check(_ what: String, _ got: Bool, _ want: Bool) {
        let ok = got == want
        if !ok { failures += 1 }
        print("  \(ok ? "ok  " : "FAIL") \(what)")
    }
    check("⌥R+Space matches when R is held",
          vocab.matches(keyCode: 49, flags: opt, held: [15, 49]), true)
    check("⌥R+Space does NOT match when R is not held",
          vocab.matches(keyCode: 49, flags: opt, held: [49]), false)
    check("⌥Space still matches on its own",
          lock.matches(keyCode: 49, flags: opt, held: [49]), true)
    check("⌥Space is not confused by an unrelated held key",
          lock.matches(keyCode: 49, flags: opt, held: [49, 8]), true)
    check("wrong modifier matches neither",
          vocab.matches(keyCode: 49, flags: 0, held: [15, 49]), false)
    check("the two collide, so the lock must wait for the chord",
          vocab.collides(with: lock), true)
    check("a non-overlapping combo does not collide",
          KeyBinding(keyCode: 11, deviceMask: 0, modifierFlags: opt, kind: .combo)
            .collides(with: lock), false)
    check("display name reads as a chord",
          vocab.displayName == "⌥R+Space", true)

    print("which combo owns a keystroke (precedence):")
    func owner(_ what: String, code: Int64, flags: UInt64, held: Set<Int64>,
               _ want: Hotkey.Combo) {
        let got = Hotkey.combo(code: code, flags: flags, held: held,
                               lock: lock, lockEnabled: true,
                               vocab: vocab, vocabEnabled: true)
        let ok = got == want
        if !ok { failures += 1 }
        print("  \(ok ? "ok  " : "FAIL") \(what)")
        if !ok { print("        got \(got), want \(want)") }
    }

    // The bug this exists to catch: ⌥Space was tested first, so the chord was
    // never reached and quick-add could not fire at all.
    owner("Space with R held is quick-add, not the lock",
          code: 49, flags: opt, held: [15, 49], .quickAdd)
    owner("Space on its own is the lock",
          code: 49, flags: opt, held: [49], .lock)
    owner("R on its own is the chord's held key",
          code: 15, flags: opt, held: [15], .quickAddHeldKey)
    // Pressing them the other way round: Space lands first, the lock is held
    // for a moment, and R completing the chord is what cancels it. Classifying
    // R is all this does — whether it fires is the pending lock's business.
    owner("R arriving after Space is still the held key",
          code: 15, flags: opt, held: [15, 49], .quickAddHeldKey)
    owner("an unrelated combo belongs to nobody",
          code: 11, flags: opt, held: [11], Hotkey.Combo.none)
    owner("Space with no modifier belongs to nobody",
          code: 49, flags: 0, held: [49], Hotkey.Combo.none)

    let plainVocab = KeyBinding.vocabDefault    // ⌥R
    func plainOwner(_ what: String, code: Int64, held: Set<Int64>, _ want: Hotkey.Combo) {
        let got = Hotkey.combo(code: code, flags: opt, held: held,
                               lock: lock, lockEnabled: true,
                               vocab: plainVocab, vocabEnabled: true)
        let ok = got == want
        if !ok { failures += 1 }
        print("  \(ok ? "ok  " : "FAIL") \(what)")
    }
    plainOwner("the default plain ⌥R quick-add", code: 15, held: [15], .quickAdd)
    plainOwner("and does not steal the lock", code: 49, held: [49], .lock)

    func disabled(_ what: String, vocabOn: Bool, lockOn: Bool,
                  code: Int64, held: Set<Int64>, _ want: Hotkey.Combo) {
        let got = Hotkey.combo(code: code, flags: opt, held: held,
                               lock: lock, lockEnabled: lockOn,
                               vocab: vocab, vocabEnabled: vocabOn)
        let ok = got == want
        if !ok { failures += 1 }
        print("  \(ok ? "ok  " : "FAIL") \(what)")
    }
    disabled("quick-add off — the chord falls through to the lock",
             vocabOn: false, lockOn: true, code: 49, held: [15, 49], .lock)
    disabled("quick-add off — R is not swallowed",
             vocabOn: false, lockOn: true, code: 15, held: [15], Hotkey.Combo.none)
    disabled("lock off — the chord still fires",
             vocabOn: true, lockOn: false, code: 49, held: [15, 49], .quickAdd)
    disabled("lock off — plain Space belongs to nobody",
             vocabOn: true, lockOn: false, code: 49, held: [49], Hotkey.Combo.none)

    print("recording-mode combos:")
    let modeL = KeyBinding(keyCode: 37, deviceMask: 0, modifierFlags: opt, kind: .combo)   // ⌥L
    let modeChord = KeyBinding(keyCode: 49, deviceMask: 0, modifierFlags: opt,
                               chordKeyCode: 37, kind: .combo)                      // ⌥L+Space
    func modeOwner(_ what: String, code: Int64, held: Set<Int64>,
                   modes: [KeyBinding?], _ want: Hotkey.Combo) {
        let got = Hotkey.combo(code: code, flags: opt, held: held,
                               lock: lock, lockEnabled: true,
                               vocab: plainVocab, vocabEnabled: true, modes: modes)
        let ok = got == want
        if !ok { failures += 1 }
        print("  \(ok ? "ok  " : "FAIL") \(what)")
        if !ok { print("        got \(got), want \(want)") }
    }
    modeOwner("⌥L is its mode", code: 37, held: [37], modes: [modeL], .mode(0))
    modeOwner("index follows position", code: 37, held: [37], modes: [nil, modeL], .mode(1))
    modeOwner("a disabled mode belongs to nobody", code: 37, held: [37], modes: [nil], Hotkey.Combo.none)
    modeOwner("modes do not steal the lock", code: 49, held: [49], modes: [modeL], .lock)
    modeOwner("a chord mode beats the lock inside it", code: 49, held: [37, 49], modes: [modeChord], .mode(0))
    modeOwner("quick-add still beats every mode", code: 15, held: [15],
              modes: [KeyBinding.vocabDefault], .quickAdd)

    print("mode press shares the lock's toggle:")
    reset()
    step(.lockPress, .hold, .activate,   "mode key starts")
    step(.holdDown,  .hold, .none,       "hold key is inert during a mode recording")
    step(.lockPress, .hold, .deactivate, "any toggle key stops it")

    print("stray hold release with nothing running:")
    reset()
    step(.holdUp, .hold, .none, "ignored")

    print(failures == 0 ? "PASS" : "FAIL: \(failures) case(s)")
    exit(failures == 0 ? 0 : 1)
}

/// Feeds a known clip through the live transcriber in simulated real time and
/// prints each emission as it settles. Exercises the prefix-commitment logic
/// without needing anyone to speak.
func selftestStreaming(_ wav: String, model: String? = nil) -> Never {
    guard let pcm = loadWav(wav) else { print("FAIL: could not read \(wav)"); exit(1) }
    guard let w = Whisper(modelPath: model.map { Settings.shared.modelPath(for: $0) } ?? Settings.shared.modelPath) else {
        print("FAIL: whisper init"); exit(1)
    }
    let total = Double(pcm.count) / Config.sampleRate
    print(String(format: "clip: %.2fs — emitting as it settles\n", total))

    let start = Date()
    var emissions: [(Double, String)] = []
    let lock = NSLock()

    let live = StreamingTranscriber(
        whisper: w,
        onEmit: { chunk in
            let t = Date().timeIntervalSince(start)
            lock.lock(); emissions.append((t, chunk)); lock.unlock()
            print(String(format: "  %5.2fs  %@", t, chunk))
        },
        onPartial: { _ in })

    // The sample closure returns only the audio that would have been recorded
    // by now, so the transcriber sees the clip arrive at real-time speed.
    live.start(sample: { from in
        let elapsed = Date().timeIntervalSince(start)
        let n = min(pcm.count, Int(elapsed * Config.sampleRate))
        return Array(pcm[min(from, n)..<n])
    })

    // Let it play out, pumping the run loop so main-queue callbacks fire.
    while Date().timeIntervalSince(start) < total {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    let ended = Date()
    let text = live.finish(pcm)
    // How far behind live is when the speaker stops: the last pass only reads
    // the audio after the last cut, so this should not grow with the clip.
    print(String(format: "\nfinal pass after the audio ended: %.2fs", Date().timeIntervalSince(ended)))
    RunLoop.current.run(until: Date().addingTimeInterval(0.3))
    w.close()

    lock.lock(); let count = emissions.count; lock.unlock()
    print("\nfinal: \"\(text)\"")
    print("emissions during speech: \(count)")

    guard !text.isEmpty else { print("FAIL: nothing transcribed"); exit(1) }
    guard count >= 2 else {
        print("FAIL: everything arrived at the end — not streaming"); exit(1)
    }
    // A word emitted twice would appear twice in the document.
    let words = StreamingTranscriber.words(text)
    var seen = Set<String>(), dupeRun = 0
    for (a, b) in zip(words, words.dropFirst()) where StreamingTranscriber.normalize(a) == StreamingTranscriber.normalize(b) {
        dupeRun += 1
        _ = seen.insert(a)
    }
    if dupeRun > 1 { print("FAIL: \(dupeRun) adjacent duplicate words — commitment is double-emitting"); exit(1) }
    print("PASS")
    exit(0)
}

/// Measures the speech detector instead of trusting it: per 24 s window (the
/// most a live pass reads), the highest speech probability, the longest run of
/// frames at or above the threshold, and whether the window would be decoded.
/// A lecture must have no window that reads as silent; room noise must have
/// none that reads as speech.
func selftestVAD(_ what: String) -> Never {
    func say(_ m: String) { print(m); Log.write("vad     \(m)") }
    var pcm: [Float]
    if what.hasPrefix("--mic=") {
        let secs = Double(what.dropFirst(6)) ?? 20
        let r = Recorder()
        do { try r.start(voiceIsolation: false) } catch { say("FAIL: \(error)"); exit(1) }
        say("listening to the room for \(Int(secs))s…")
        RunLoop.current.run(until: Date().addingTimeInterval(secs))
        pcm = r.stop()
        say(String(format: "room: rms %.5f, peak100ms %.5f", Recorder.rms(pcm), Recorder.peakRMS(pcm)))
    } else {
        guard let w = loadWav(what) else { say("FAIL: could not read \(what)"); exit(1) }
        pcm = w
    }
    guard let vad = SpeechDetector() else { say("FAIL: no ggml-silero model"); exit(1) }
    let window = Int(StreamingTranscriber.windowSeconds * Config.sampleRate)
    let t0 = Date()
    var silent = 0, total = 0, lowestMax: Float = 1, highestMax: Float = 0
    var rows: [String] = []
    var i = 0
    while i < pcm.count {
        let chunk = Array(pcm[i..<min(pcm.count, i + window)])
        let probs = vad.probabilities(chunk)
        let mx = probs.max() ?? 0
        var longest = 0, streak = 0
        for p in probs { streak = p >= SpeechDetector.threshold ? streak + 1 : 0; longest = max(longest, streak) }
        let speech = SpeechDetector.firstSpeech(probs) != nil
        total += 1; if !speech { silent += 1 }
        lowestMax = min(lowestMax, mx); highestMax = max(highestMax, mx)
        rows.append(String(format: "%4ds max %.2f run %3d %@", i / Int(Config.sampleRate), mx, longest, speech ? "speech" : "-"))
        i += window
    }
    let dt = Date().timeIntervalSince(t0)
    rows.forEach { print("  " + $0) }
    say(String(format: "%@: %d of %d windows read as silent; window max between %.2f and %.2f; %.0fx real time",
               (what as NSString).lastPathComponent, silent, total, lowestMax, highestMax,
               Double(pcm.count) / Config.sampleRate / max(dt, 0.001)))
    exit(0)
}

/// Exercises tail alignment directly — the logic that decides which words the
/// final pass still owes the user. Its failure modes are silent: too far right
/// drops real words, too far left retypes them.
func selftestAlign() -> Never {
    var failures = 0
    func check(_ what: String, emitted: [String], final: [String], want: [String]?) {
        let got = StreamingTranscriber.tailAfter(emitted: emitted, final: final)
        let ok = got.map { $0.map(StreamingTranscriber.normalize) }
               == want.map { $0.map(StreamingTranscriber.normalize) }
        if !ok { failures += 1 }
        print("  \(ok ? "ok  " : "FAIL") \(what)")
        if !ok { print("        got \(got as Any)\n       want \(want as Any)") }
    }

    func overlap(_ what: String, _ closed: [String], _ next: [String], want: Int) {
        let got = StreamingTranscriber.overlap(closed, next).count
        if got != want { failures += 1 }
        print("  \(got == want ? "ok  " : "FAIL") \(what)\(got == want ? "" : " — got \(got), want \(want)")")
    }
    overlap("a word on the cut is heard by both stretches", ["look", "at", "and"], ["and", "take", "a"], want: 1)
    overlap("punctuation and case do not hide the repeat", ["very", "important", "for"], ["For", "function."], want: 1)
    overlap("two repeated words", ["the", "cell", "membrane"], ["cell", "membrane,", "which"], want: 2)
    overlap("no repeat, nothing skipped", ["look", "at", "this"], ["and", "take", "a"], want: 0)
    overlap("nothing closed yet", [], ["and", "take"], want: 0)

    check("nothing emitted yet — everything is owed",
          emitted: [], final: ["hello", "there"], want: ["hello", "there"])

    check("clean continuation",
          emitted: ["hello", "there"], final: ["hello", "there", "friend"], want: ["friend"])

    check("nothing left to emit",
          emitted: ["hello", "there"], final: ["hello", "there"], want: [])

    check("punctuation and case added by the final pass are not re-emitted",
          emitted: ["hello", "there"], final: ["Hello,", "there!", "friend"], want: ["friend"])

    // Repeated phrase: taking the LAST match would skip "for your country".
    check("repeated phrase — anchor must not jump to the later occurrence",
          emitted: "ask not what your country can do for you".split(separator: " ").map(String.init),
          final: "ask not what your country can do for you ask what you can do for your country".split(separator: " ").map(String.init),
          want: "ask what you can do for your country".split(separator: " ").map(String.init))

    // Genuinely repeated words: taking the last match returns nothing and the
    // real repeats are lost.
    check("go go go go — repeats must survive",
          emitted: ["go", "go", "go", "go"],
          final: ["go", "go", "go", "go", "go", "go"],
          want: ["go", "go"])

    check("re-segmentation — gonna becomes going to",
          emitted: ["i", "am", "gonna"], final: ["i", "am", "gonna", "leave", "now"],
          want: ["leave", "now"])

    check("no anchor found — caller falls back",
          emitted: ["completely", "different", "words", "here"],
          final: ["nothing", "matches"], want: nil)

    print("loop detection — stopping a runaway session:")
    func loops(_ what: String, _ text: String, _ want: Bool) {
        let got = StreamingTranscriber.isLooping(StreamingTranscriber.words(text))
        let ok = got == want
        if !ok { failures += 1 }
        print("  \(ok ? "ok  " : "FAIL") \(what)")
    }

    loops("whisper stuck on one clause",
          "so anyway the thing is the thing is the thing is the thing is", true)
    loops("a longer clause, three times over",
          "thanks for watching this video thanks for watching this video thanks for watching this video",
          true)
    loops("ordinary speech is left alone",
          "the quick brown fox jumps over the lazy dog and then it runs away", false)
    loops("saying no six times is not a loop",
          "no no no no no no", false)
    loops("counting out loud is not a loop",
          "one two one two one two one two", false)
    loops("twice is a person repeating themselves",
          "let me say that again let me say that again", false)
    loops("empty transcript", "", false)
    loops("punctuation and case do not hide a loop",
          "It is what it is. it is what it is, IT IS WHAT IT IS!", true)

    print("batch loop removal:")
    func collapsed(_ what: String, _ text: String, _ want: String) {
        let got = StreamingTranscriber.collapseRepeats(text)
        let ok = got == want
        if !ok { failures += 1 }
        print("  \(ok ? "ok  " : "FAIL") \(what)")
        if !ok { print("        got \"\(got)\"") }
    }
    collapsed("a looped sentence is cut to one",
              "We agree. The UK has been given to the EU. The UK has been given to the EU. The UK has been given to the EU. Next point.",
              "We agree. The UK has been given to the EU. Next point.")
    collapsed("case and punctuation do not hide it",
              "It is what it is. it is what it is! Fine.", "It is what it is. Fine.")
    collapsed("short repeats are a person", "No. No. We disagree.", "No. No. We disagree.")
    collapsed("the same sentence later on is kept",
              "The vote is today. Then something else. The vote is today.",
              "The vote is today. Then something else. The vote is today.")
    collapsed("decimals and abbreviations are not split", "Growth was 2.5 percent in the U.S. economy.",
              "Growth was 2.5 percent in the U.S. economy.")
    collapsed("no punctuation at all", "just words here", "just words here")
    collapsed("empty", "", "")

    print(failures == 0 ? "PASS" : "FAIL: \(failures) case(s)")
    exit(failures == 0 ? 0 : 1)
}

/// Retry policy for cleanup calls. A rate-limited provider must not lose the
/// transcript, and must not make the user wait longer than typing it again.
func selftestRetry() -> Never {
    var failures = 0
    func resp(_ code: Int, retryAfter: String? = nil) -> URLResponse {
        HTTPURLResponse(url: URL(string: "https://example.invalid")!,
                        statusCode: code, httpVersion: nil,
                        headerFields: retryAfter.map { ["Retry-After": $0] })!
    }
    func check(_ what: String, _ got: TimeInterval?, _ want: TimeInterval?) {
        let ok = got == want
        if !ok { failures += 1 }
        print("  \(ok ? "ok  " : "FAIL") \(what)")
        if !ok { print("        got \(got as Any)  want \(want as Any)") }
    }

    check("429 with no header — backoff",
          Cleanup.retryDelay(after: 429, response: resp(429), attempt: 0), 0.5)
    check("429 again — backoff doubles",
          Cleanup.retryDelay(after: 429, response: resp(429), attempt: 1), 1.0)
    check("backoff is capped",
          Cleanup.retryDelay(after: 429, response: resp(429), attempt: 9), 3.0)
    check("a short Retry-After is honoured",
          Cleanup.retryDelay(after: 429, response: resp(429, retryAfter: "2"), attempt: 0), 2.0)
    check("Retry-After: 0 still waits a tick",
          Cleanup.retryDelay(after: 429, response: resp(429, retryAfter: "0"), attempt: 0), 0.1)
    check("a long Retry-After means give up, not wait a minute",
          Cleanup.retryDelay(after: 429, response: resp(429, retryAfter: "60"), attempt: 0), nil)
    check("an HTTP-date Retry-After falls through to the backoff",
          Cleanup.retryDelay(after: 503,
                             response: resp(503, retryAfter: "Wed, 21 Oct 2026 07:28:00 GMT"),
                             attempt: 0), 0.5)
    check("503 is transient",
          Cleanup.retryDelay(after: 503, response: resp(503), attempt: 0), 0.5)
    check("401 is not — a bad key fails the same way twice",
          Cleanup.retryDelay(after: 401, response: resp(401), attempt: 0), nil)
    check("404 is not — the model does not exist",
          Cleanup.retryDelay(after: 404, response: resp(404), attempt: 0), nil)
    check("400 is not — the body is wrong",
          Cleanup.retryDelay(after: 400, response: resp(400), attempt: 0), nil)

    print(failures == 0 ? "PASS" : "FAIL: \(failures) case(s)")
    exit(failures == 0 ? 0 : 1)
}

/// Vocabulary parsing: the separator rules and the de-duplication that the
/// quick-add window depends on.
func selftestVocab() -> Never {
    var failures = 0
    func eq(_ what: String, _ got: [String], _ want: [String]) {
        let ok = got == want
        if !ok { failures += 1 }
        print("  \(ok ? "ok  " : "FAIL") \(what)")
        if !ok { print("        got \(got)\n       want \(want)") }
    }
    func eqs(_ what: String, _ got: String?, _ want: String?) {
        let ok = got == want
        if !ok { failures += 1 }
        print("  \(ok ? "ok  " : "FAIL") \(what)")
        if !ok { print("        got \(got ?? "nil")\n       want \(want ?? "nil")") }
    }

    print("separators:")
    eq("comma separated", Vocabulary.terms("gooning, codex, Yapperroni"),
       ["gooning", "codex", "Yapperroni"])
    eq("no spaces after commas", Vocabulary.terms("a,b,c"), ["a", "b", "c"])
    eq("newline separated", Vocabulary.terms("a\nb\nc"), ["a", "b", "c"])
    eq("mixed, as pasted from anywhere", Vocabulary.terms("a, b\nc,d"), ["a", "b", "c", "d"])
    eq("empties and stray commas dropped", Vocabulary.terms(" , a ,, b , "), ["a", "b"])
    eq("multi-word phrases survive", Vocabulary.terms("ice cream, whisper.cpp"),
       ["ice cream", "whisper.cpp"])
    eq("empty input", Vocabulary.terms("   "), [])

    print("adding:")
    eqs("appends comma separated", Vocabulary.adding("codex", to: "a, b"), "a, b, codex")
    eqs("first term", Vocabulary.adding("codex", to: ""), "codex")
    eqs("duplicate rejected", Vocabulary.adding("codex", to: "a, codex"), nil)
    eqs("duplicate is case-insensitive", Vocabulary.adding("CODEX", to: "a, codex"), nil)
    eqs("blank rejected", Vocabulary.adding("   ", to: "a"), nil)
    eqs("normalises a newline list on append",
        Vocabulary.adding("c", to: "a\nb"), "a, b, c")

    print("prompt:")
    eqs("nil when empty", Vocabulary.prompt("  "), nil)
    eqs("glossary form", Vocabulary.prompt("a, b"), "Glossary: a, b.")
    let long = Vocabulary.prompt(Array(repeating: "abcdefghij", count: 200).joined(separator: ", "))
    let capped = (long?.count ?? 0) < 420
    if !capped { failures += 1 }
    print("  \(capped ? "ok  " : "FAIL") long list is capped (\(long?.count ?? 0) chars)")

    print(failures == 0 ? "PASS" : "FAIL: \(failures) case(s)")
    exit(failures == 0 ? 0 : 1)
}

/// Long-audio windowing for the sherpa engines: cuts must land in the quiet
/// stretch, no piece may exceed the limit, and short input is never cut.
func selftestChunk() -> Never {
    var failures = 0
    func check(_ what: String, _ ok: Bool) {
        if !ok { failures += 1 }
        print("  \(ok ? "ok  " : "FAIL") \(what)")
    }
    let loud: Float = 0.3
    // 100 samples a "second": loud everywhere except a quiet gap at 85–90.
    var pcm = [Float](repeating: loud, count: 250)
    for i in 85..<90 { pcm[i] = 0 }
    let cuts = SherpaEngine.cutPoints(pcm, maxLen: 100, search: 30, window: 4)
    check("short input is not cut", SherpaEngine.cutPoints(pcm, maxLen: 300, search: 30, window: 4).isEmpty)
    check("first cut lands in the quiet gap (\(cuts.first ?? -1))", (85...90).contains(cuts.first ?? -1))
    var prev = 0
    var within = true
    for c in cuts + [pcm.count] { within = within && c - prev <= 100 && c > prev; prev = c }
    check("no piece exceeds the limit (\(cuts))", within)
    let flat = [Float](repeating: loud, count: 1000)
    let flatCuts = SherpaEngine.cutPoints(flat, maxLen: 100, search: 30, window: 4)
    check("no quiet anywhere still terminates (\(flatCuts.count) cuts)", flatCuts.count >= 9 && flatCuts.count <= 15)
    print(failures == 0 ? "PASS" : "FAIL: \(failures) case(s)")
    exit(failures == 0 ? 0 : 1)
}

/// Plays a clip inside this process and records it back through the
/// computer-audio tap — scoped to this process and muted, so the clip never
/// reaches the speakers and every other app is left alone. Then transcribes
/// the capture with each model in turn. Launch with `open` (the System Audio
/// Recording grant is the app's). Text results go to `--out` as JSON; the
/// captured audio stays in memory like any other recording.
///
/// `mic: true` records the microphone alongside, as Room and Call do: the
/// silent proof that both sources run together and land in one recording.
/// Leave it off to score a model — the room would be on top of the clip.
func selftestCapture(_ wav: String, models: [String], options: DecodeOptions, out: String?,
                     mic: Bool = false) -> Never {
    func say(_ m: String) { print(m); Log.write("capture  \(m)") }
    let url = URL(fileURLWithPath: wav)
    guard let file = try? AVAudioFile(forReading: url) else { say("FAIL: cannot read \(wav)"); exit(1) }
    let clipSecs = Double(file.length) / file.processingFormat.sampleRate

    // The player must be running before the tap: a process has no audio
    // object for the tap to target until it has talked to coreaudiod.
    let engine = AVAudioEngine()
    let player = AVAudioPlayerNode()
    engine.attach(player)
    engine.connect(player, to: engine.mainMixerNode, format: file.processingFormat)
    do { try engine.start() } catch { say("FAIL: player engine: \(error)"); exit(1) }

    let r = Recorder()
    do {
        try r.start(voiceIsolation: false, computerAudio: .process(getpid(), muted: true),
                    microphone: mic)
    } catch { say("FAIL: \(error)"); exit(1) }

    say(String(format: "playing %.0fs muted through the computer-audio tap (nothing on the speakers)…", clipSecs))
    var done = false
    player.scheduleFile(file, at: nil) { done = true }
    player.play()
    let t0 = Date()
    while !done && Date().timeIntervalSince(t0) < clipSecs + 30 {
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }
    RunLoop.current.run(until: Date().addingTimeInterval(0.5))
    let pcm = r.stop()
    engine.stop()
    let secs = Double(pcm.count) / Config.sampleRate
    say(String(format: "captured %.1fs of %.1fs in %.1fs wall, peak100ms %.4f",
               secs, clipSecs, Date().timeIntervalSince(t0), Recorder.peakRMS(pcm)))
    guard r.systemPeak > 0 else { say("FAIL: exact silence — System Audio Recording not granted"); exit(1) }
    if mic {
        say(String(format: "raw mic %.5f heard to %.1fs, raw computer audio %.5f heard to %.1fs",
                   r.micPeak, r.micSeconds, r.systemPeak, r.systemSeconds))
        guard r.micPeak > 0 else { say("FAIL: the microphone delivered nothing alongside the computer audio"); exit(1) }
        // Another app opening the mic mid-recording rebuilds the tap; a mic
        // that never came back stops well short of the end.
        guard r.micSeconds > secs - 2 else { say("FAIL: the microphone stopped part-way through"); exit(1) }
    }

    var results: [[String: Any]] = []
    for name in models {
        let path = Settings.shared.modelPath(for: name)
        guard let e = Engines.load(path: path) else { say("FAIL: load \(name)"); continue }
        let t = Date()
        let text = StreamingTranscriber.collapseRepeats(e.transcribe(pcm, options: options))
        let dt = Date().timeIntervalSince(t)
        e.close()
        say(String(format: "%@ %.1fs (%.1fx): %@", name, dt, secs / dt, String(text.prefix(160))))
        results.append(["model": name, "elapsed": dt, "captured": secs, "text": text])
    }
    if let out, let data = try? JSONSerialization.data(withJSONObject: results, options: .prettyPrinted) {
        try? data.write(to: URL(fileURLWithPath: out))
    }
    say("PASS — \(results.count) of \(models.count) models transcribed the capture")
    exit(0)
}

/// A mode saved by any earlier build must still decode — the fallback on
/// failure is the default list, which silently wipes the user's shortcuts.
/// Also where the two sources of a long recording are checked to land in the
/// right place in the mix.
func selftestModes() -> Never {
    var failures = 0
    func check(_ what: String, _ ok: Bool) {
        if !ok { failures += 1 }
        print("  \(ok ? "ok  " : "FAIL") \(what)")
    }
    // What the build before this one saved: every setting a mode used to own.
    var old = try! JSONSerialization.jsonObject(with: JSONEncoder().encode(RecordingMode.room)) as! [String: Any]
    for (k, v) in ["modelFilename": "ggml-large-v3-turbo-q5_0.bin", "voiceIsolation": true, "live": true,
                   "output": "copy", "accurate": false, "language": "en", "vad": false,
                   "input": "microphone", "micDevice": "builtin", "maxMicGain": true] as [String: Any] {
        old[k] = v
    }
    old["maxMinutes"] = 90
    let data = try! JSONSerialization.data(withJSONObject: [old])
    let decoded = try? JSONDecoder().decode([RecordingMode].self, from: data)
    check("a mode saved with the old settings decodes", decoded?.count == 1)
    check("its shortcut and limits survive", decoded?.first?.binding == RecordingMode.room.binding
          && decoded?.first?.maxMinutes == 90 && decoded?.first?.stopOnSilence == false)

    print("modes as the two kinds:")
    var room = RecordingMode.room; room.maxMinutes = 90
    var extra = RecordingMode.room; extra.name = "Extra"
    let n = RecordingMode.normalized([RecordingMode.call, extra, room])
    check("Room and Call found by name, settings kept",
          n[0].name == "Room" && n[0].maxMinutes == 90 && n[1] == RecordingMode.call)
    check("always exactly [Room, Call]", n.count == 2)
    check("nothing saved gives the defaults", RecordingMode.normalized([]) == RecordingMode.defaults)

    let round = try? JSONDecoder().decode(RecordingMode.self,
                                          from: JSONEncoder().encode(RecordingMode.call))
    check("a current mode round-trips", round == RecordingMode.call)

    print("where a source lands in the mix:")
    let second = Int(Config.sampleRate)
    check("in step with the clock: straight after its last samples",
          Recorder.mixPosition(cursor: 16_000, frames: 1_365, elapsed: 17_400) == 16_000)
    check("a little late is still in step",
          Recorder.mixPosition(cursor: 16_000, frames: 1_365, elapsed: 17_365 + Recorder.mixSlack) == 16_000)
    check("the tap, started 0.8 s after the mic, starts 0.8 s in",
          Recorder.mixPosition(cursor: 0, frames: 160, elapsed: 12_960) == 12_800)
    check("a mic rebuilt after a 3 s gap resumes where the clock is",
          Recorder.mixPosition(cursor: 10 * second, frames: 1_365, elapsed: 13 * second + 1_365) == 13 * second)
    check("a source ahead of the clock is never moved back",
          Recorder.mixPosition(cursor: 20_000, frames: 1_365, elapsed: 17_000) == 20_000)

    var mix: [Float] = []
    func add(_ v: [Float], at: Int) { v.withUnsafeBufferPointer { Recorder.add($0, to: &mix, at: at) } }
    add([1, 1, 1], at: 0)
    add([2, 2], at: 2)
    check("two sources over the same moment are summed", mix == [1, 1, 3, 2])
    add([5], at: 6)
    check("a gap before a late source is silence", mix == [1, 1, 3, 2, 0, 0, 5])

    print(failures == 0 ? "PASS" : "FAIL: \(failures) case(s)")
    exit(failures == 0 ? 0 : 1)
}

let args = CommandLine.arguments
switch args.dropFirst().first {
case "--selftest-whisper":
    guard args.count > 2 else { print("usage: yapperroni --selftest-whisper <file.wav> [model] [--accurate]"); exit(2) }
    // [model] [--accurate] [--vad] [--lang=xx]
    let rest = Array(args.dropFirst(3))
    var opts = DecodeOptions(accurate: rest.contains("--accurate"), vad: rest.contains("--vad"))
    if let l = rest.first(where: { $0.hasPrefix("--lang=") }) { opts.language = String(l.dropFirst(7)) }
    selftestWhisper(args[2], model: rest.first { !$0.hasPrefix("-") }, options: opts)
case "--selftest-chunk":
    selftestChunk()
case "--selftest-modes":
    selftestModes()
case "--selftest-capture":
    // <wav> --models=a,b [--vad] [--lang=xx] [--out=results.json] [--mic]
    guard args.count > 2 else { print("usage: yapperroni --selftest-capture <file.wav> --models=a,b [--vad] [--lang=xx] [--out=path] [--mic]"); exit(2) }
    let rest = Array(args.dropFirst(3))
    func value(_ k: String) -> String? { rest.first { $0.hasPrefix(k) }.map { String($0.dropFirst(k.count)) } }
    var opts = DecodeOptions(vad: rest.contains("--vad"))
    if let l = value("--lang=") { opts.language = l }
    selftestCapture(args[2], models: (value("--models=") ?? Settings.shared.modelFilename)
                        .split(separator: ",").map(String.init),
                    options: opts, out: value("--out="), mic: rest.contains("--mic"))
case "--selftest-audio":
    selftestAudio()
case "--selftest-mic-sequence":
    selftestMicSequence()
case "--selftest-hotkey":
    selftestHotkey()
case "--selftest-toggle":
    selftestToggle()
case "--selftest-align":
    selftestAlign()
case "--selftest-vocab":
    selftestVocab()
case "--selftest-retry":
    selftestRetry()
case "--selftest-streaming":
    guard args.count > 2 else { print("usage: yapperroni --selftest-streaming <file.wav> [model]"); exit(2) }
    selftestStreaming(args[2], model: args.count > 3 ? args[3] : nil)
case "--selftest-loopback":
    guard args.count > 2 else { print("usage: yapperroni --selftest-loopback <file.wav>"); exit(2) }
    selftestLoopback(args[2], system: args.contains("--system"))
case "--selftest-vad":
    // <wav> | --mic=<seconds>   What the speech detector makes of a clip, or
    // of this room right now (launch with `open`; levels only, nothing kept).
    guard args.count > 2 else { print("usage: yapperroni --selftest-vad <file.wav> | --mic=<seconds>"); exit(2) }
    selftestVAD(args[2])
case "--selftest-focus":
    // [app name]  What Room and Call would do with a live word right now:
    // typed, or held. With a name, that app's own focus, wherever it is on
    // screen. Launch with `open` — the Accessibility grant is the app's.
    var name = NSWorkspace.shared.frontmostApplication?.localizedName ?? "?"
    var role = Injector.focusedRole()
    if args.count > 2 {
        name = args[2]
        guard let app = NSWorkspace.shared.runningApplications.first(where: { $0.localizedName == name }) else {
            print("FAIL: \(name) is not running"); exit(1)
        }
        role = Injector.focusedRole(in: AXUIElementCreateApplication(app.processIdentifier))
    }
    let line = "focus   \(name) role=\(role ?? "none") types=\(Injector.textRoles.contains(role ?? ""))"
    print(line); Log.write(line)
    exit(0)
case "--log":
    print(Log.path)
    exit(0)
default:
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
