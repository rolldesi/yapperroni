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

func selftestWhisper(_ wav: String) -> Never {
    print("model: \(Settings.shared.modelPath)")
    guard let pcm = loadWav(wav) else {
        print("FAIL: could not read \(wav)"); exit(1)
    }
    print("audio: \(pcm.count) samples (\(String(format: "%.2f", Double(pcm.count) / Config.sampleRate))s), rms \(String(format: "%.4f", Recorder.rms(pcm)))")
    guard let w = Whisper(modelPath: Settings.shared.modelPath) else {
        print("FAIL: whisper init"); exit(1)
    }
    let t0 = Date()
    let text = w.transcribe(pcm)
    let dt = Date().timeIntervalSince(t0)
    w.close()
    print("transcript: \"\(text)\"")
    print(String(format: "elapsed: %.2fs", dt))
    guard !text.isEmpty else { print("FAIL: empty transcript"); exit(1) }
    print("PASS")
    exit(0)
}

func selftestAudio() -> Never {
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
    do { try r.start() } catch {
        print("FAIL: \(error)"); exit(1)
    }
    print("recording 3s — say something…")
    RunLoop.current.run(until: Date().addingTimeInterval(3))
    let pcm = r.stop()
    let secs = Double(pcm.count) / Config.sampleRate
    let rms = Recorder.rms(pcm)
    print(String(format: "captured %d samples (%.2fs) at 16 kHz, rms %.4f", pcm.count, secs, rms))
    guard secs > 1.8 else { print("FAIL: short capture — resample path is wrong"); exit(1) }
    guard Double(Recorder.peakRMS(pcm)) > Settings.shared.minPeakRMS else {
        print(auth == .authorized
            ? "FAIL: authorized but silent — mic muted, wrong input device, or nobody spoke"
            : "FAIL: silent because microphone access is \(authName) for this process")
        exit(1)
    }
    print("PASS")
    exit(0)
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
func selftestLoopback(_ wav: String) -> Never {
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
    do { try r.start() } catch { say("FAIL: \(error)"); exit(1) }

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
    say(String(format: "captured %.2fs, raw %.5f, converted rms %.5f, peak100ms %.5f (gate floor %.5f)",
               secs, r.rawPeak, rms, peak, Settings.shared.minPeakRMS))

    guard Double(peak) > Settings.shared.minPeakRMS else {
        say("FAIL: heard nothing — output volume at zero, or capture is returning silence")
        exit(1)
    }

    guard let w = Whisper(modelPath: Settings.shared.modelPath) else { say("FAIL: whisper init"); exit(1) }
    let text = w.transcribe(pcm)
    w.close()
    say("heard: \"\(text)\"")
    guard !text.isEmpty else { say("FAIL: audio captured but transcript empty"); exit(1) }
    say("PASS — mic to text works end to end")
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
    let vocab = KeyBinding.vocabDefault         // ⌥R+Space
    let opt = CGEventFlags.maskAlternate.rawValue
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

    print("stray hold release with nothing running:")
    reset()
    step(.holdUp, .hold, .none, "ignored")

    print(failures == 0 ? "PASS" : "FAIL: \(failures) case(s)")
    exit(failures == 0 ? 0 : 1)
}

/// Feeds a known clip through the live transcriber in simulated real time and
/// prints each emission as it settles. Exercises the prefix-commitment logic
/// without needing anyone to speak.
func selftestStreaming(_ wav: String) -> Never {
    guard let pcm = loadWav(wav) else { print("FAIL: could not read \(wav)"); exit(1) }
    guard let w = Whisper(modelPath: Settings.shared.modelPath) else {
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
    live.start(sample: {
        let elapsed = Date().timeIntervalSince(start)
        let n = min(pcm.count, Int(elapsed * Config.sampleRate))
        return Array(pcm[0..<max(0, n)])
    })

    // Let it play out, pumping the run loop so main-queue callbacks fire.
    while Date().timeIntervalSince(start) < total {
        RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    let text = live.finish(pcm)
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

let args = CommandLine.arguments
switch args.dropFirst().first {
case "--selftest-whisper":
    guard args.count > 2 else { print("usage: yapperroni --selftest-whisper <file.wav>"); exit(2) }
    selftestWhisper(args[2])
case "--selftest-audio":
    selftestAudio()
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
    guard args.count > 2 else { print("usage: yapperroni --selftest-streaming <file.wav>"); exit(2) }
    selftestStreaming(args[2])
case "--selftest-loopback":
    guard args.count > 2 else { print("usage: yapperroni --selftest-loopback <file.wav>"); exit(2) }
    selftestLoopback(args[2])
case "--log":
    print(Log.path)
    exit(0)
default:
    let app = NSApplication.shared
    let delegate = AppDelegate()
    app.delegate = delegate
    app.run()
}
