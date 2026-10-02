import AVFoundation

/// Captures mic audio — or the computer's own output, see `SystemAudioTap` —
/// and hands back 16 kHz mono float32.
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
    private let engine = AVAudioEngine()
    private var converter: AVAudioConverter?
    private var monoFormat: AVAudioFormat?
    private var samples: [Float] = []
    private let lock = NSLock()
    private(set) var isRecording = false

    /// Most recent RMS of the 16 kHz output, for the HUD level meter.
    private(set) var level: Float = 0
    /// Peak RMS of the raw buffer before conversion. Diagnostic: separates
    /// "mic gave us silence" from "the conversion ate the audio".
    private(set) var rawPeak: Float = 0
    private(set) var tapFormat: AVAudioFormat?
    private var releaseWork: DispatchWorkItem?
    private let systemTap = SystemAudioTap()
    private var configObserver: NSObjectProtocol?

    /// How long voice processing stays warm after a dictation ends.
    ///
    /// While it is enabled the system is in voice-chat mode and ducks every
    /// other app — music and video go quiet as if you were on a call. But
    /// re-enabling it costs 300-500 ms, which would clip the first word of
    /// every utterance. So it is released on a delay: back-to-back dictations
    /// keep it warm and start instantly, and audio returns to normal shortly
    /// after you stop.
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
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine, queue: .main) { [weak self] _ in
                self?.reconfigure()
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

    /// Which mic, as a mode's `micDevice` preference; resolved on every arm so
    /// a dictation after a lecture goes back to the system default.
    private var wantDevice = InputDevice.systemDefault
    private var armedDevice = AudioObjectID(kAudioObjectUnknown)
    /// Input gain to put back when the recording ends, if this session raised it.
    private var restoreGain: (AudioObjectID, Float32)?

    func start(voiceIsolation: Bool, input: AudioInput = .microphone,
               systemScope: SystemAudioTap.Scope = .everything,
               micDevice: String = InputDevice.systemDefault, maxGain: Bool = false) throws {
        guard !isRecording else { return }
        if input == .system {
            try armSystem(systemScope)
            isRecording = true
            return
        }
        wantVoiceProcessing = voiceIsolation
        wantDevice = micDevice
        releaseWork?.cancel()
        releaseWork = nil
        // Gain first: changing it posts a device reconfiguration, and after
        // the tap is live that rebuild costs the first ~0.2 s of the lecture.
        if maxGain {
            raiseGain(InputDevice.resolve(micDevice, in: InputDevice.all(),
                                          default: InputDevice.defaultInput()))
        }
        try arm(keepingAudio: false)
        isRecording = true
    }

    /// A far voice arrives near the floor of the mic's range; the system's
    /// input slider is often left mid-way. Raised for the recording only.
    private func raiseGain(_ id: AudioObjectID) {
        guard let old = InputDevice.inputVolume(id) else {
            Log.write("audio   \"\(InputDevice.name(of: id))\" has no adjustable gain")
            return
        }
        if old < 1, InputDevice.setInputVolume(id, 1) {
            restoreGain = (id, old)
            Log.write(String(format: "audio   mic gain %.2f -> 1.00 for this recording", old))
        }
    }

    private func restoreGainIfRaised() {
        guard let (id, old) = restoreGain else { return }
        restoreGain = nil
        InputDevice.setInputVolume(id, old)
        Log.write(String(format: "audio   mic gain restored to %.2f", old))
    }

    /// Voice processing does not apply: there is no room and no echo to
    /// remove from a digital mix, and turning it on would duck the very audio
    /// being recorded.
    private func armSystem(_ scope: SystemAudioTap.Scope) throws {
        // A dictation just before this leaves voice processing warm for its
        // grace period, and the delayed release skips while recording — so it
        // would stay on, ducking the very call being recorded, for the whole
        // class. Release it now instead.
        releaseWork?.cancel()
        releaseWork = nil
        if engine.inputNode.isVoiceProcessingEnabled {
            do {
                try engine.inputNode.setVoiceProcessingEnabled(false)
                Log.write("audio   released voice processing for a computer-audio recording")
            } catch {
                Log.write("audio   could not release voice processing: \(error.localizedDescription)")
            }
        }
        let rate = try systemTap.prepare(scope)
        guard let mono = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: rate,
                                       channels: 1, interleaved: false),
              let conv = AVAudioConverter(from: mono, to: Recorder.outputFormat)
        else { systemTap.stop(); throw RecorderError.converterFailed }
        monoFormat = mono
        converter = conv
        rawPeak = 0
        lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()
        try systemTap.run { [weak self] ptr, n in self?.appendMono(ptr, frames: n) }
    }

    /// Builds the tap on whatever format the input device is offering now and
    /// starts the engine. `keepingAudio` is false for a new dictation and true
    /// when rebuilding mid-recording after the device changed underneath us —
    /// there the samples already captured must survive.
    private func arm(keepingAudio: Bool) throws {
        let input = engine.inputNode
        engine.stop()
        input.removeTap(onBus: 0)

        // Point the engine at the chosen mic before anything reads its format.
        // Only when it differs: setting the device posts a configuration
        // change, which re-arms, which would set it again.
        let target = InputDevice.resolve(wantDevice, in: InputDevice.all(),
                                         default: InputDevice.defaultInput())
        if let unit = input.audioUnit, target != kAudioObjectUnknown {
            var current = AudioObjectID(kAudioObjectUnknown)
            var size = UInt32(MemoryLayout<AudioObjectID>.size)
            AudioUnitGetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                 kAudioUnitScope_Global, 0, &current, &size)
            if current != target {
                var t = target
                let s = AudioUnitSetProperty(unit, kAudioOutputUnitProperty_CurrentDevice,
                                             kAudioUnitScope_Global, 0, &t,
                                             UInt32(MemoryLayout<AudioObjectID>.size))
                if s != noErr { Log.write("audio   could not switch to \"\(InputDevice.name(of: target))\" (\(s))") }
            }
            armedDevice = target
        }

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

        monoFormat = mono
        converter = conv
        tapFormat = tapF
        if !keepingAudio {
            rawPeak = 0
            lock.lock(); samples.removeAll(keepingCapacity: true); lock.unlock()
        }

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
                         InputDevice.name(of: armedDevice), tapF.sampleRate,
                         tapF.channelCount, input.isVoiceProcessingEnabled ? "on" : "off"))
    }

    /// The input device was reconfigured under us. While recording that means
    /// the tap is dead and must be rebuilt on the new format; the audio already
    /// captured is kept.
    private func reconfigure() {
        // Another app grabbing the mic says nothing about the computer-audio
        // tap, and re-arming here would start the mic under it.
        guard !systemTap.isRunning else { return }
        guard isRecording else {
            Log.write("audio   input device reconfigured while idle")
            return
        }
        Log.write("audio   input device reconfigured mid-recording — rebuilding the tap")
        do {
            try arm(keepingAudio: true)
        } catch {
            // ponytail: leaves the recording running on a dead tap rather than
            // ending the utterance from underneath the user. The release gate
            // then reports "too quiet", which is at least honest. Recover by
            // ending the recording and starting again if this ever shows up in
            // a log.
            Log.write("audio   could not rebuild the tap: \(error)")
        }
    }

    /// Everything captured so far, without stopping. Used by live
    /// transcription, which re-reads the whole buffer on every pass.
    func snapshot() -> [Float] {
        lock.lock(); defer { lock.unlock() }
        return samples
    }

    /// Stops capture and returns everything recorded, resampled to 16 kHz mono.
    @discardableResult
    func stop() -> [Float] {
        guard isRecording else { return [] }
        isRecording = false
        if systemTap.isRunning {
            systemTap.stop()
        } else {
            engine.inputNode.removeTap(onBus: 0)
            engine.stop()
            restoreGainIfRaised()
            scheduleVoiceProcessingRelease()
        }

        // Deliberately NOT clearing converter/monoFormat: a tap callback may
        // still be mid-flight and reads both. start() replaces them anyway.
        level = 0
        lock.lock(); let out = samples; samples.removeAll(); lock.unlock()
        return out
    }

    private func append(_ buffer: AVAudioPCMBuffer) {
        guard let src = buffer.floatChannelData else { return }
        // Channel 0 only. Averaging a mic array's channels risks phase
        // cancellation, which would quietly reduce the level instead of
        // improving it.
        appendMono(src[0], frames: Int(buffer.frameLength))
    }

    /// Mono float at `monoFormat`'s rate, from either source.
    private func appendMono(_ ch0: UnsafePointer<Float>, frames: Int) {
        guard let conv = converter, let mono = monoFormat, frames > 0 else { return }
        var sq: Float = 0
        for i in 0..<frames { sq += ch0[i] * ch0[i] }
        rawPeak = max(rawPeak, (sq / Float(frames)).squareRoot())

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
        level = (osq / Float(n)).squareRoot()

        lock.lock(); samples.append(contentsOf: slice); lock.unlock()
    }

    /// Loudest 100 ms window. Global RMS is the wrong gate: hold the key for
    /// five seconds and speak for one, and the silence drags the average under
    /// any useful threshold.
    /// Releases voice processing once dictation has been idle for a while.
    /// Cancelled by the next `start()`.
    private func scheduleVoiceProcessingRelease() {
        releaseWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, !self.isRecording else { return }
            let input = self.engine.inputNode
            guard input.isVoiceProcessingEnabled else { return }
            do {
                try input.setVoiceProcessingEnabled(false)
                Log.write("audio   released voice processing (other apps back to full volume)")
            } catch {
                Log.write("audio   could not release voice processing: \(error.localizedDescription)")
            }
        }
        releaseWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + Recorder.voiceProcessingGrace,
                                      execute: work)
    }

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
