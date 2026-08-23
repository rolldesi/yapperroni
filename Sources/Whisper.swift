import Foundation

/// Thin wrapper over whisper.cpp. The context is created once and reused, so
/// per-utterance cost is encode+decode only, not a model load from disk.
final class Whisper {
    private var ctx: OpaquePointer?
    private let queue = DispatchQueue(label: "yapperroni.whisper")
    private static let englishTag = strdup("en")

    init?(modelPath: String) {
        guard FileManager.default.fileExists(atPath: modelPath) else {
            FileHandle.standardError.write("yapperroni: model not found at \(modelPath)\n".data(using: .utf8)!)
            return nil
        }
        var cparams = whisper_context_default_params()
        cparams.use_gpu = true
        cparams.flash_attn = true
        ctx = whisper_init_from_file_with_params(modelPath, cparams)
        if ctx == nil { return nil }
    }

    deinit { close() }

    /// ggml's Metal backend asserts during its atexit teardown if a context is
    /// still holding resource sets. Both `exit()` and app termination skip
    /// deinit, so the context must be released explicitly.
    func close() {
        queue.sync {
            if let c = ctx { whisper_free(c); ctx = nil }
        }
    }

    /// Whisper has no word list to update — it is end-to-end, and its sense of
    /// which words exist comes from training data that predates the model's
    /// release. It does, however, condition on an initial prompt, so naming
    /// your jargon there biases the decoder toward it.
    private static func promptText() -> String? {
        Vocabulary.prompt(Settings.shared.customVocabulary)
    }

    /// Blocking. `samples` must be 16 kHz mono float32 in [-1, 1].
    func transcribe(_ samples: [Float]) -> String {
        queue.sync {
            guard let ctx else { return "" }

            // Whisper works on 30s windows and misbehaves on very short input.
            // Pad to 1s so a two-word utterance still decodes cleanly.
            var pcm = samples
            let minFrames = Int(Config.sampleRate)
            if pcm.count < minFrames {
                pcm.append(contentsOf: [Float](repeating: 0, count: minFrames - pcm.count))
            }

            var p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY)
            p.print_realtime   = false
            p.print_progress   = false
            p.print_timestamps = false
            p.print_special    = false
            p.translate        = false
            p.no_context       = true      // each utterance is independent
            p.single_segment   = false
            p.suppress_blank   = true
            p.language         = UnsafePointer(Whisper.englishTag)
            p.n_threads        = Int32(max(1, min(6, ProcessInfo.processInfo.activeProcessorCount - 2)))
            p.temperature      = 0.0
            p.no_speech_thold  = 0.6

            // The prompt C string must outlive the call, hence the nesting.
            let rc: Int32
            if let prompt = Whisper.promptText() {
                rc = prompt.withCString { cstr in
                    var pp = p
                    pp.initial_prompt = cstr
                    return pcm.withUnsafeBufferPointer { buf in
                        whisper_full(ctx, pp, buf.baseAddress, Int32(buf.count))
                    }
                }
            } else {
                rc = pcm.withUnsafeBufferPointer { buf in
                    whisper_full(ctx, p, buf.baseAddress, Int32(buf.count))
                }
            }
            guard rc == 0 else { return "" }

            var out = ""
            for i in 0..<whisper_full_n_segments(ctx) {
                if let c = whisper_full_get_segment_text(ctx, i) {
                    out += String(cString: c)
                }
            }
            return Whisper.clean(out)
        }
    }

    /// Trim whitespace and drop whisper's canned silence outputs.
    static func clean(_ raw: String) -> String {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return "" }
        let key = text.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: " .,!?-"))
        if Config.hallucinations.contains(key) || Config.hallucinations.contains(text.lowercased()) {
            return ""
        }
        return text
    }
}
