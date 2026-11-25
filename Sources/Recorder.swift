import AVFoundation

/// Captures the microphone and, when asked, the computer's own output (see
/// `SystemAudioTap`), and hands back one 16 kHz mono float32 recording with
/// the two summed.
///
/// One path for every way of recording. Dictation is the mic alone; Room and
/// Call add the computer's audio on top of the same mic. They used to have a
/// capture path each, and each recorded half a meeting: Call heard the far
/// end but not the user, Room the user but not the far end. Room also pinned
/// the built-in mic and raised its gain, and with voice processing on that
/// looped forever on a refused device switch — nothing recorded, and the
/// Mac's audio output cut in and out for as long as it ran.
///
/// Two traps live here, both of which produce perfect silence rather than an
/// error:
///   1. The tap must use the input node's *output* format. On a mic that
///      reports 3 hardware channels, the hardware format is not what the tap
///      delivers.
///   2. AVAudioConverter will not downmix 3 channels to mono — it returns
///      success and writes zeros. So we take channel 0 ourselves and leave the
///      converter with nothing to do but resample.
final class Recorder {
    /// Replaced, not just restarted, when it fails: once an AVAudioEngine has
    /// thrown -10875 (failed initialisation) it fails every later start too,
    /// and the app could not record again until relaunched.
    private var engine = AVAudioEngine()

    /// One source on its way into the mix.
    private final class Lane {
        var converter: AVAudioConverter?
        var format: AVAudioFormat?
        /// Where its next samples go in `samples`. Guarded by `lock`.
        var cursor = 0
        var level: Float = 0
        var peak: Float = 0
    }
    private let mic = Lane()
    private let system = Lane()

    /// The recording so far: every source summed at its own position.
    private var samples: [Float] = []
    /// When sample 0 was heard, on the uptime clock. Set by the first buffer.
    private var origin: TimeInterval?
    /// False outside a recording, so a callback still in flight after `stop`
    /// cannot write into the next one. Guarded by `lock`.
    private var accepting = false
    private let lock = NSLock()
    private(set) var isRecording = false
    private var micArmed = false

    /// Most recent RMS of the 16 kHz output, for the HUD level meter. The
    /// louder source: two sources overwriting one value made the meter jump
    /// between the room and the call thirty times a second.
    var level: Float { max(mic.level, system.level) }
    /// Peak RMS of each source's raw buffers, before conversion. Diagnostic:
    /// separates "this source gave us silence" from "the conversion ate the
    /// audio", and says which half of a meeting was missing.
    var micPeak: Float { mic.peak }
    var systemPeak: Float { system.peak }
    /// How far into the recording each source was last heard. A source that
    /// died part-way — a mic never rebuilt after a call app took it — stops
    /// short of the recording's length, which no peak can show.
    var micSeconds: Double { Double(mic.cursor) / Config.sampleRate }
    var systemSeconds: Double { Double(system.cursor) / Config.sampleRate }
    private(set) var tapFormat: AVAudioFormat?
    private var releaseWork: DispatchWorkItem?
    private let systemTap = SystemAudioTap()
    private var configObserver: NSObjectProtocol?

    /// Backstop delay for voice processing release. VP is now disabled
    /// synchronously in stop(); this grace period only fires if the
    /// synchronous disable threw. The 300-500 ms re-enable cost on the next
    /// start() is acceptable to avoid AirPods switching to HFP/SCO between
    /// dictations.
    private static let voiceProcessingGrace: TimeInterval = 6

    static let outputFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: Config.sampleRate,
        channels: 1,
        interleaved: false
    )!

    init() {
        // Another app opening or closing the microphone — Claude, FaceTime, a
        // meeting in a browser tab — reconfigures the input device, and
        // AVAudioEngine tears its graph down when that happens. The tap then
        // stays installed but delivers nothing, so dictation records perfect
        // silence and reports "no speech detected". Rebuilding the tap on the
        // new format is the only fix.
        observeEngine()
    }

    private func observeEngine() {
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine, queue: .main) { [weak self] _ in
                self?.reconfigure()
            }
    }

    private func replaceEngine(_ why: String) {
        Log.write("audio   new engine: \(why)")
        engine.stop()
        engine = AVAudioEngine()
        observeEngine()
    }

    /// One retry on a fresh engine, then the error stands.
    private func armWithRecovery() throws {
        do {
            try arm()
        } catch {
            replaceEngine("the old one failed (\(error))")
            try arm()
        }
    }

    deinit {
        if let o = configObserver { NotificationCenter.default.removeObserver(o) }
    }

    enum RecorderError: Error, CustomStringConvertible {
        case noInput
        case converterFailed
        case engineFailed(String)

        var description: String {
            switch self {
            case .noInput: return "no usable audio input device"
            case .converterFailed: return "could not build a 16 kHz converter"
            case .engineFailed(let m): return "audio engine failed: \(m)"
            }
        }
    }

    /// Held for the whole session so a mid-recording rebuild re-arms the same way.
    private var wantVoiceProcessing = true

    /// `computerAudio` adds what the Mac is playing to the recording.
    /// `microphone: false` leaves the mic out; only the model benchmark wants
    /// that, to score a clip without the room on top of it.
    func start(voiceIsolation: Bool, computerAudio: SystemAudioTap.Scope? = nil,
               microphone: Bool = true) throws {
        guard !isRecording else { return }
        wantVoiceProcessing = voiceIsolation
        releaseWork?.cancel()
        releaseWork = nil
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        origin = nil
        for lane in [mic, system] { lane.cursor = 0; lane.level = 0; lane.peak = 0 }
        accepting = true
        lock.unlock()

        // The mic first. Opening it is what moves Bluetooth headphones to
        // their call profile, and the computer-audio tap is built on whatever
        // output format that leaves behind.
        micArmed = false
        var micFailure: Error?
        if microphone {
            do { try armWithRecovery(); micArmed = true } catch { micFailure = error }
        }
        // Either source alone is still a recording. Refusing to start because
        // one is missing would lose the half that could have been heard.
        if let scope = computerAudio {
            do { try armSystem(scope) } catch {
                guard micArmed else { accepting = false; throw error }
                Log.write("audio   no computer audio, recording the mic alone: \(error)")
            }
        }
        if let micFailure {
            guard systemTap.isRunning else { accepting = false; throw micFailure }
            Log.write("audio   no microphone, recording computer audio alone: \(micFailure)")
        }
        isRecording = true
    }

    private func armSystem(_ scope: SystemAudioTap.Scope) throws {
        let rate = try systemTap.prepare(scope)
        guard let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                                       channels: 1, interleaved: false),
              let conv = AVAudioConverter(from: mono, to: Recorder.outputFormat)
        else { systemTap.stop(); throw RecorderError.converterFailed }
        system.format = mono
        system.converter = conv
        try systemTap.run { [weak self] ptr, n in
            guard let self else { return }
            self.appendMono(ptr, frames: n, to: self.system)
        }
    }

    /// Builds the mic tap on whatever format the input device is offering now
    /// and starts the engine. Also what rebuilds it mid-recording after the
    /// device changed underneath us; the audio already captured is untouched.
    ///
    /// Always the system default mic. The input unit's `CurrentDevice` is
    /// never set: once voice processing has run, the unit reports an internal
    /// device of its own, every comparison differs, the set fails (-10851),
    /// the failure posts a configuration change, and the re-arm sets it again
    /// — for as long as the recording runs, with nothing recorded.
    private func arm() throws {
        // Turning voice processing off on a live unit changes the format and
        // posts two configuration changes, each re-arm costing the start of
        // the recording (0.85 s of 1.5 s captured). A fresh engine starts off.
        if !wantVoiceProcessing, engine.inputNode.isVoiceProcessingEnabled {
            replaceEngine("voice processing off")
        }

        let input = engine.inputNode
        engine.stop()
        input.removeTap(onBus: 0)

        // Apple's voice-processing unit: echo cancellation, noise suppression
        // and gain control, the same path FaceTime uses. This is what lets
        // Whisper hear speech over background music. It must be set before the
        // engine starts, and it CHANGES the node's format — which is why the
        // tap format is read afterwards, not before.
        let wantVP = wantVoiceProcessing
        if input.isVoiceProcessingEnabled != wantVP {
            do { try input.setVoiceProcessingEnabled(wantVP) }
            catch { Log.write("audio   voice processing unavailable: \(error.localizedDescription)") }
        }

        let tapF = input.outputFormat(forBus: 0)
        guard tapF.sampleRate > 0, tapF.channelCount > 0 else { throw RecorderError.noInput }

        // Mono at the *input* sample rate: the converter then only resamples.
        guard let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                       sampleRate: tapF.sampleRate,
                                       channels: 1,
                                       interleaved: false),
              let conv = AVAudioConverter(from: mono, to: Recorder.outputFormat)
        else { throw RecorderError.converterFailed }

        mic.format = mono
        mic.converter = conv
        tapFormat = tapF

        input.installTap(onBus: 0, bufferSize: 4096, format: tapF) { [weak self] buffer, _ in
            self?.append(buffer)
        }

        engine.prepare()
        do { try engine.start() } catch {
            input.removeTap(onBus: 0)
            throw RecorderError.engineFailed(error.localizedDescription)
        }
        // Which device, at what format, with voice processing in what state.
        // Every "it works everywhere except in that one app" report comes down
        // to one of these three changing without anyone asking.
        Log.write(String(format: "audio   input \"%@\" %gHz x%u vp=%@",
                         InputDevice.name(of: InputDevice.defaultInput()), tapF.sampleRate,
                         tapF.channelCount, input.isVoiceProcessingEnabled ? "on" : "off"))
    }

    /// The input device was reconfigured under us. While recording that means
    /// the mic tap is dead and must be rebuilt on the new format. The computer
    /// audio keeps running throughout: a meeting app opening the mic is the
    /// start of the call, not a reason to stop hearing either side of it.
    private func reconfigure() {
        guard isRecording, micArmed else {
            Log.write("audio   input device reconfigured while idle")
            return
        }
        Log.write("audio   input device reconfigured mid-recording — rebuilding the tap")
        do {
            try armWithRecovery()
        } catch {
            // ponytail: leaves the recording running on a dead tap rather than
            // ending the utterance from underneath the user. The release gate
            // then reports "too quiet", which is at least honest. Recover by
            // ending the recording and starting again if this ever shows up in
            // a log.
            Log.write("audio   could not rebuild the tap: \(error)")
        }
    }

    /// Everything captured from sample `from` on, without stopping. Live
    /// transcription reads only the stretch it has not closed yet: handing it
    /// the whole recording twice a second copied 230 MB a pass by the end of
    /// an hour.
    func snapshot(from: Int = 0) -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return from < samples.count ? Array(samples[from...]) : []
    }

    /// Stops capture and returns everything recorded, resampled to 16 kHz mono.
    @discardableResult
    func stop() -> [Float] {
        guard isRecording else { return [] }
        isRecording = false
        systemTap.stop()
        if micArmed {
            engine.inputNode.removeTap(onBus: 0)
            // Disable voice processing immediately so AirPods switch back to
            // A2C (music) profile now, not after the grace period.
            let input = engine.inputNode
            if input.isVoiceProcessingEnabled {
                do { try input.setVoiceProcessingEnabled(false) }
                catch { Log.write("audio   could not release voice processing on stop: \(error.localizedDescription)") }
            }
            engine.stop()
        }

        // Deliberately NOT clearing the converters and formats: a tap callback
        // may still be mid-flight and reads both. start() replaces them anyway.
        mic.level = 0
        system.level = 0
        lock.lock()
        accepting = false
        let out = samples
        samples.removeAll()
        lock.unlock()
        return out
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let src = buffer.floatChannelData else { return }
        // Channel 0 only. Averaging a mic array's channels risks phase
        // cancellation, which would quietly reduce the level instead of
        // improving it.
        appendMono(src[0], frames: Int(buffer.frameLength), to: mic)
    }

    /// Mono float at the lane's own rate, resampled and added to the mix.
    private func appendMono(_ ch0: UnsafePointer<Float>, frames: Int, to lane: Lane) {
        guard let conv = lane.converter, let mono = lane.format, frames > 0 else { return }
        var sq: Float = 0
        for i in 0..<frames { sq += ch0[i] * ch0[i] }
        lane.peak = max(lane.peak, (sq / Float(frames)).squareRoot())

        guard let monoBuf = AVAudioPCMBuffer(pcmFormat: mono, frameCapacity: AVAudioFrameCount(frames)),
              let dst = monoBuf.floatChannelData?[0] else { return }
        dst.update(from: ch0, count: frames)
        monoBuf.frameLength = AVAudioFrameCount(frames)

        let ratio = Recorder.outputFormat.sampleRate / mono.sampleRate
        let capacity = AVAudioFrameCount(Double(frames) * ratio) + 1024
        guard let out = AVAudioPCMBuffer(pcmFormat: Recorder.outputFormat, frameCapacity: capacity) else { return }

        var fed = false
        var err: NSError?
        let status = conv.convert(to: out, error: &err) { _, outStatus in
            if fed { outStatus.pointee = .noDataNow; return nil }
            fed = true
            outStatus.pointee = .haveData
            return monoBuf
        }
        guard status != .error, err == nil, out.frameLength > 0,
              let outCh = out.floatChannelData?[0] else { return }

        let n = Int(out.frameLength)
        let slice = UnsafeBufferPointer(start: outCh, count: n)
        var osq: Float = 0
        for v in slice { osq += v * v }
        lane.level = (osq / Float(n)).squareRoot()

        lock.lock(); defer { lock.unlock() }
        guard accepting else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // The first buffer of the recording ends now, so it began `n` ago.
        let began = origin ?? now - Double(n) / Config.sampleRate
        origin = began
        let at = Recorder.mixPosition(cursor: lane.cursor, frames: n,
                                      elapsed: Int((now - began) * Config.sampleRate))
        Recorder.add(slice, to: &samples, at: at)
        lane.cursor = at + n
    }

    /// How far a source may fall behind the clock before its next buffer is
    /// placed by time instead of straight after its last one.
    static let mixSlack = Int(Config.sampleRate / 2)

    /// Where a source's next `frames` samples go in the mix, `elapsed` samples
    /// into the recording. Normally straight after its last ones. But a source
    /// that starts late — the tap is built after the mic — or goes away and
    /// comes back — the mic rebuilt when a call app opens it — has to land
    /// where the clock says. Appending would slide everything it says from
    /// then on earlier, on top of the other side of the conversation.
    /// Static and pure so it can be tested directly — see `--selftest-modes`.
    static func mixPosition(cursor: Int, frames: Int, elapsed: Int) -> Int {
        let due = elapsed - frames
        return due - cursor > mixSlack ? due : cursor
    }

    /// Sums `slice` into `mix` at `at`, growing it with silence as needed.
    /// Summed, not averaged: halving the mic whenever the computer is also
    /// being recorded would move every loudness gate in the app.
    static func add(_ slice: UnsafeBufferPointer<Float>, to mix: inout [Float], at: Int) {
        let end = at + slice.count
        if mix.count < end { mix.append(contentsOf: repeatElement(0, count: end - mix.count)) }
        mix.withUnsafeMutableBufferPointer { m in
            for i in 0..<slice.count { m[at + i] += slice[i] }
        }
    }

    /// Releases voice processing once dictation has been idle for a while.
    /// Cancelled by the next `start()`.
    ///
    /// ponytail: VP is now disabled immediately in stop(), so this only
    /// serves as a backstop if the synchronous disable in stop() throws.
    /// Remove entirely if the immediate path proves reliable.
    private func scheduleVoiceProcessingRelease() {
        releaseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isRecording else { return }
            let input = self.engine.inputNode
            guard input.isVoiceProcessingEnabled else { return }
            do {
                try input.setVoiceProcessingEnabled(false)
                Log.write("audio   released voice processing (backstop)")
            } catch {
                Log.write("audio   could not release voice processing: \(error.localizedDescription)")
            }
        }
        releaseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Recorder.voiceProcessingGrace,
                                      execute: work)
    }

    /// Loudest 100 ms window. Global RMS is the wrong gate: hold the key for
    /// five seconds and speak for one, and the silence drags the average under
    /// any useful threshold.
    static func peakRMS(_ s: [Float], windowSeconds: Double = 0.1) -> Float {
        let w = max(1, Int(Config.sampleRate * windowSeconds))
        guard s.count >= w else { return rms(s) }
        var peak: Float = 0
        var i = 0
        while i + w <= s.count {
            var sq: Float = 0
            for j in i..<(i + w) { sq += s[j] * s[j] }
            peak = max(peak, (sq / Float(w)).squareRoot())
            i += w
        }
        return peak
    }

    static func rms(_ s: [Float]) -> Float {
        guard !s.isEmpty else { return 0 }
        var sumSq: Float = 0
        for v in s { sumSq += v * v }
        return (sumSq / Float(s.count)).squareRoot()
    }
}
