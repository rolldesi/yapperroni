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

    print("stray hold release with nothing running:")
    reset()
    step(.holdUp, .hold, .none, "ignored")

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
