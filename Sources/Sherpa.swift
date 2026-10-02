import Foundation

/// One loaded speech model. Whisper (whisper.cpp) and the NeMo models
/// (sherpa-onnx) both take 16 kHz mono float and return text, so everything
/// above this line — live mode, the watchdog, delivery — is engine-blind.
protocol Transcriber: AnyObject {
    /// Blocking. Each engine honours the options it has a knob for and
    /// ignores the rest; the Settings UI greys out what a model cannot do.
    func transcribe(_ samples: [Float], options: DecodeOptions) -> String
    /// Must be called before exit — see `Whisper.close`.
    func close()
}

struct DecodeOptions: Equatable {
    /// Whisper only: beam search instead of greedy.
    var accurate = false
    /// A code from `Languages.all`, or "auto".
    var language = "en"
    /// Whisper only: Silero VAD drops silence before decoding.
    var vad = false
}

extension Transcriber {
    func transcribe(_ samples: [Float]) -> String { transcribe(samples, options: DecodeOptions()) }
}

enum Engines {
    /// A model is either a whisper.cpp `.bin` file or a sherpa-onnx directory
    /// (`tokens.txt` plus encoder/decoder[/joiner] `.onnx`). Which NeMo family
    /// a directory holds is read off its files: only the transducer has a joiner.
    static func load(path: String) -> Transcriber? {
        if path.hasSuffix(".bin") { return Whisper(modelPath: path) }
        return SherpaEngine(directory: path)
    }

    /// Picker text. Unknown files show as themselves.
    static func label(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("parakeet") { return "Parakeet TDT 0.6B v3 (sherpa-onnx)" }
        if n.contains("canary") { return "Canary 180M Flash (sherpa-onnx)" }
        if n.contains("large-v3-turbo") { return "Whisper large-v3-turbo" }
        if n.contains("small.en") { return "Whisper small.en" }
        return name
    }

    /// What a model does with the language, skip-silence and vocabulary settings.
    static func note(_ name: String) -> String {
        let n = name.lowercased()
        if n.contains("parakeet") {
            return "Parakeet detects the language itself (25 European languages) and ignores the language setting, skip silence, accurate decoding and the Vocabulary list."
        }
        if n.contains("canary") {
            return "Canary hears English, French, German or Spanish, and must be told which: \"Detect automatically\" means English. It ignores skip silence, accurate decoding and the Vocabulary list."
        }
        if n.contains(".en") {
            return "English-only model: the language setting is ignored."
        }
        return "Detect automatically listens to the first 30 seconds and keeps that language for the whole recording."
    }

    static func isModel(_ name: String, in dir: String) -> Bool {
        // The VAD weights are a whisper.cpp .bin too, but not a speech model.
        if name.hasSuffix(".bin") { return !name.contains("silero") }
        return FileManager.default.fileExists(atPath: dir + "/" + name + "/tokens.txt")
    }
}

/// Parakeet (TDT transducer) and Canary (encoder-decoder) via sherpa-onnx's C API.
final class SherpaEngine: Transcriber {
    private var recognizer: OpaquePointer?
    private let queue = DispatchQueue(label: "yapperroni.sherpa")
    let family: String
    /// The config points into these, and `SetConfig` re-reads it, so both
    /// live as long as the engine.
    private var cstrs: [UnsafeMutablePointer<CChar>?] = []
    private var config = SherpaOnnxOfflineRecognizerConfig()
    private var canaryLang = "en"
    /// Canary has no language detection; it is told which one it is hearing.
    /// Parakeet detects on its own and ignores all of this.
    static let canaryLanguages = ["en", "es", "de", "fr"]
    private lazy var langStrings = Dictionary(uniqueKeysWithValues:
        SherpaEngine.canaryLanguages.map { ($0, strdup($0)) })

    /// NeMo encoders are full-attention: an hour of audio in one pass does not
    /// fit in memory, and Canary was trained on clips under 40 s. So long input
    /// is decoded in windows, cut at the quietest moment near each boundary.
    static let maxChunkSeconds: Double = 28
    static let cutSearchSeconds: Double = 4

    init?(directory dir: String) {
        let fm = FileManager.default
        let files = (try? fm.contentsOfDirectory(atPath: dir)) ?? []
        func find(_ prefix: String) -> String? {
            // Prefer int8 when both precisions sit in the folder.
            let hits = files.filter { $0.hasPrefix(prefix) && $0.hasSuffix(".onnx") }.sorted()
            return (hits.first { $0.contains("int8") } ?? hits.first).map { dir + "/" + $0 }
        }
        guard let encoder = find("encoder"), let decoder = find("decoder"),
              fm.fileExists(atPath: dir + "/tokens.txt") else {
            Log.write("model   \(dir) is not a sherpa-onnx model folder")
            return nil
        }
        let joiner = find("joiner")
        family = joiner != nil ? "nemo_transducer" : "canary"

        let strings = [encoder, decoder, joiner ?? "", dir + "/tokens.txt",
                       "cpu", family == "canary" ? "" : family, "greedy_search"]
        cstrs = strings.map { strdup($0) }

        var c = SherpaOnnxOfflineRecognizerConfig()
        c.feat_config.sample_rate = Int32(Config.sampleRate)
        c.feat_config.feature_dim = 80   // NeMo models override this from their metadata
        if family == "nemo_transducer" {
            c.model_config.transducer.encoder = UnsafePointer(cstrs[0])
            c.model_config.transducer.decoder = UnsafePointer(cstrs[1])
            c.model_config.transducer.joiner  = UnsafePointer(cstrs[2])
        } else {
            c.model_config.canary.encoder  = UnsafePointer(cstrs[0])
            c.model_config.canary.decoder  = UnsafePointer(cstrs[1])
            c.model_config.canary.src_lang = UnsafePointer(langStrings["en"]!)
            c.model_config.canary.tgt_lang = UnsafePointer(langStrings["en"]!)
            c.model_config.canary.use_pnc  = 1
        }
        c.model_config.tokens      = UnsafePointer(cstrs[3])
        // ponytail: CPU provider. onnxruntime's CoreML provider could move the
        // encoder onto the ANE; measure it before assuming it is faster.
        c.model_config.provider    = UnsafePointer(cstrs[4])
        c.model_config.model_type  = UnsafePointer(cstrs[5])
        c.model_config.num_threads = Int32(max(1, min(6, ProcessInfo.processInfo.activeProcessorCount - 2)))
        c.decoding_method          = UnsafePointer(cstrs[6])

        config = c
        recognizer = SherpaOnnxCreateOfflineRecognizer(&c)
        if recognizer == nil {
            Log.write("model   sherpa-onnx rejected \(dir) as \(family)")
            return nil
        }
    }

    deinit {
        close()
        cstrs.forEach { free($0) }
        langStrings.values.forEach { free($0) }
    }

    func close() {
        queue.sync {
            if let r = recognizer { SherpaOnnxDestroyOfflineRecognizer(r); recognizer = nil }
        }
    }

    // ponytail: vocabulary is ignored here. sherpa-onnx has hotword boosting,
    // but only under modified_beam_search on transducers; wire it through
    // `hotwords_file` if Parakeet keeps missing names.
    func transcribe(_ samples: [Float], options: DecodeOptions) -> String {
        queue.sync {
            guard let recognizer else { return "" }
            if family == "canary" {
                // Transcribing French with src_lang "en" gets you an English
                // translation, confidently. "auto" has nothing to map to.
                let want = SherpaEngine.canaryLanguages.contains(options.language) ? options.language : "en"
                if want != canaryLang, let p = langStrings[want] {
                    config.model_config.canary.src_lang = UnsafePointer(p)
                    config.model_config.canary.tgt_lang = UnsafePointer(p)
                    SherpaOnnxOfflineRecognizerSetConfig(recognizer, &config)
                    canaryLang = want
                    Log.write("model   canary language \(want)")
                }
            }
            let cuts = SherpaEngine.cutPoints(samples,
                                              maxLen: Int(SherpaEngine.maxChunkSeconds * Config.sampleRate),
                                              search: Int(SherpaEngine.cutSearchSeconds * Config.sampleRate),
                                              window: Int(Config.sampleRate / 10))
            var parts: [String] = []
            var start = 0
            for end in cuts + [samples.count] where end > start {
                // Same reason as whisper's pad: a sub-second tail decodes badly.
                var chunk = Array(samples[start..<end])
                let minFrames = Int(Config.sampleRate)
                if chunk.count < minFrames {
                    chunk.append(contentsOf: [Float](repeating: 0, count: minFrames - chunk.count))
                }
                start = end
                guard let stream = SherpaOnnxCreateOfflineStream(recognizer) else { continue }
                chunk.withUnsafeBufferPointer {
                    SherpaOnnxAcceptWaveformOffline(stream, Int32(Config.sampleRate),
                                                    $0.baseAddress, Int32($0.count))
                }
                SherpaOnnxDecodeOfflineStream(recognizer, stream)
                if let r = SherpaOnnxGetOfflineStreamResult(stream) {
                    if let t = r.pointee.text {
                        let s = String(cString: t).trimmingCharacters(in: .whitespacesAndNewlines)
                        if !s.isEmpty { parts.append(s) }
                    }
                    SherpaOnnxDestroyOfflineRecognizerResult(r)
                }
                SherpaOnnxDestroyOfflineStream(stream)
            }
            return Whisper.clean(parts.joined(separator: " "))
        }
    }

    /// Where to split `pcm` so no piece exceeds `maxLen`: at the quietest
    /// `window` inside the last `search` samples before each limit, so a cut
    /// lands in a pause instead of through a word. Pure, for `--selftest-chunk`.
    static func cutPoints(_ pcm: [Float], maxLen: Int, search: Int, window: Int) -> [Int] {
        var cuts: [Int] = []
        var start = 0
        while pcm.count - start > maxLen {
            let limit = start + maxLen
            var best = limit, bestEnergy = Float.infinity
            var w = max(start + 1, limit - search)
            while w + window <= limit {
                var e: Float = 0
                for i in w..<(w + window) { e += pcm[i] * pcm[i] }
                if e < bestEnergy { bestEnergy = e; best = w + window / 2 }
                w += window / 2
            }
            cuts.append(best)
            start = best
        }
        return cuts
    }
}
