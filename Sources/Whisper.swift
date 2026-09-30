import Foundation

/// Thin wrapper over whisper.cpp. The context is created once and reused, so
/// per-utterance cost is encode+decode only, not a model load from disk.
final class Whisper: Transcriber {
    private var ctx: OpaquePointer?
    private let queue = DispatchQueue(label: "yapperroni.whisper")

    /// Silero weights for whisper.cpp's built-in VAD. Bundled by build.sh; a
    /// copy in the support folder wins, like the models.
    static let vadModelPath: String? = {
        let fm = FileManager.default
        for dir in [Config.supportDir.path, Bundle.main.resourcePath].compactMap({ $0 }) {
            let hit = ((try? fm.contentsOfDirectory(atPath: dir)) ?? [])
                .filter { $0.hasPrefix("ggml-silero") && $0.hasSuffix(".bin") }.sorted().last
            if let hit { return dir + "/" + hit }
        }
        return nil
    }()

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
    ///
    /// `accurate` swaps greedy for beam search. Measured on turbo, it is not a
    /// free win: 21 s far-field clips went from 6.1% to 4.7% WER, but an 82 s
    /// lecture went from 7.0% to 10.1% because beam search invented a phrase
    /// at a window boundary (with or without context carried across windows).
    /// The vocabulary prompt beat both: 3.8% and 5.7%.
    ///
    /// Language "auto" is detected once, from the first 30 s. An English-only
    /// model (`.en`) is always told English: auto-detect on one reports
    /// garbage, since it has no other language tokens to compare against.
    func transcribe(_ samples: [Float], options: DecodeOptions) -> String {
        queue.sync {
            guard let ctx else { return "" }
            let accurate = options.accurate

            // Whisper works on 30s windows and misbehaves on very short input.
            // Pad to 1s so a two-word utterance still decodes cleanly.
            var pcm = samples
            let minFrames = Int(Config.sampleRate)
            if pcm.count < minFrames {
                pcm.append(contentsOf: [Float](repeating: 0, count: minFrames - pcm.count))
            }

            var p = whisper_full_default_params(accurate ? WHISPER_SAMPLING_BEAM_SEARCH
                                                         : WHISPER_SAMPLING_GREEDY)
            if accurate { p.beam_search.beam_size = 5 }
            p.print_realtime   = false
            p.print_progress   = false
            p.print_timestamps = false
            p.print_special    = false
            p.translate        = false
            p.no_context       = true      // each utterance is independent
            p.single_segment   = false
            p.suppress_blank   = true
            p.n_threads        = Int32(max(1, min(6, ProcessInfo.processInfo.activeProcessorCount - 2)))
            p.temperature      = 0.0
            p.no_speech_thold  = 0.6

            // Every C string must outlive the call.
            let language = whisper_is_multilingual(ctx) != 0 ? options.language : "en"
            var owned: [UnsafeMutablePointer<CChar>?] = []
            defer { owned.forEach { free($0) } }
            func cstr(_ s: String) -> UnsafePointer<CChar>? {
                let c = strdup(s); owned.append(c); return UnsafePointer(c)
            }
            p.language = cstr(language)
            if let prompt = Whisper.promptText() { p.initial_prompt = cstr(prompt) }
            if options.vad {
                if let vad = Whisper.vadModelPath {
                    p.vad = true
                    p.vad_model_path = cstr(vad)
                    // Defaults (0.5, 30 ms pad) clipped "Good morning everyone.
                    // Today" off a lecture starting after 20 s of room noise.
                    // 0.35 and 300 ms kept every word on all 12 test clips and
                    // still dropped the trailing "Thank you." hallucination.
                    p.vad_params = whisper_vad_default_params()
                    p.vad_params.threshold = 0.35
                    p.vad_params.speech_pad_ms = 300
                } else {
                    Log.write("whisper VAD requested but no ggml-silero model found; decoding without it")
                }
            }

            let rc = pcm.withUnsafeBufferPointer { buf in
                whisper_full(ctx, p, buf.baseAddress, Int32(buf.count))
            }
            guard rc == 0 else { return "" }
            if language == "auto", let lang = whisper_lang_str(whisper_full_lang_id(ctx)) {
                Log.write("whisper detected language \(String(cString: lang))")
            }

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
