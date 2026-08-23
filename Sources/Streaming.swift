import Foundation

/// Live transcription: words appear while you are still talking.
///
/// Whisper is not a streaming model, but re-transcribing the whole buffer is
/// cheap — the encoder runs on the mel frames that exist, so a 2 s clip and an
/// 11 s clip both cost roughly 200 ms. So every tick we transcribe everything
/// recorded so far and emit whatever new words have settled.
///
/// "Settled" matters: whisper freely rewrites the tail of its output as more
/// audio arrives ("i scream" becoming "ice cream"). Typed characters cannot be
/// taken back, so a word is only emitted once two consecutive passes agree on
/// it *and* it is not among the last few words, which are the ones still in
/// flux.
final class StreamingTranscriber {

    /// How often to re-transcribe. Each pass costs ~200 ms, so this is roughly
    /// a 50% duty cycle on one core plus the GPU.
    static let interval: TimeInterval = 0.45
    /// Trailing words held back as still-unstable, even when two passes agree.
    static let tailGuard = 2

    private let whisper: Whisper
    private let onEmit: (String) -> Void
    private let onPartial: (String) -> Void

    private var previous: [String] = []
    private var emitted: [String] = []
    private var running = false
    private let queue = DispatchQueue(label: "yapperroni.streaming", qos: .userInitiated)
    /// Signalled on stop, so the loop wakes immediately instead of sitting out
    /// the rest of its interval. Without this, releasing the key mid-sleep adds
    /// most of `interval` before the final pass can even start.
    private let wake = DispatchSemaphore(value: 0)

    /// Everything actually typed, which is what ended up in the user's document.
    var emittedText: String { emitted.joined(separator: " ") }

    init(whisper: Whisper,
         onEmit: @escaping (String) -> Void,
         onPartial: @escaping (String) -> Void) {
        self.whisper = whisper
        self.onEmit = onEmit
        self.onPartial = onPartial
    }

    // MARK: - Lifecycle

    /// Starts ticking. `sample` is asked for the audio recorded so far.
    func start(sample: @escaping () -> [Float]) {
        guard !running else { return }
        running = true
        previous = []
        emitted = []
        queue.async { [weak self] in
            while self?.running == true {
                let pcm = sample()
                guard let self, self.running else { return }
                if Double(pcm.count) / Config.sampleRate >= 0.6,
                   Double(Recorder.peakRMS(pcm)) >= Settings.shared.minPeakRMS {
                    self.tick(pcm)
                }
                _ = self.wake.wait(timeout: .now() + StreamingTranscriber.interval)
            }
        }
    }

    /// Stops the loop without waiting. Call before clearing the recorder, so a
    /// tick cannot start, read an emptied buffer, and transcribe silence.
    func stopTicking() {
        running = false
        wake.signal()
    }

    /// Stops ticking, runs one last pass over the complete audio, and emits
    /// everything still outstanding. Returns the full text that was typed.
    func finish(_ pcm: [Float]) -> String {
        stopTicking()
        // Wait for any tick already in flight, so the final pass cannot
        // interleave with it and emit the same words twice.
        queue.sync {}

        let final = StreamingTranscriber.words(whisper.transcribe(pcm))

        if let tail = alignedTail(final) {
            emit(tail)
        } else {
            // Alignment failed: the final pass segmented the speech differently
            // than every incremental pass did. Fall back to counting, which is
            // what this did before, and record it — a run of these means the
            // alignment window needs widening.
            Log.write("stream  tail alignment FAILED (final=\(final.count) emitted=\(emitted.count))")
            if final.count > emitted.count {
                emit(Array(final[emitted.count...]))
            }
        }
        return emittedText
    }

    /// The part of the final transcript that has not been typed yet.
    ///
    /// Counting words does not work: real speech re-segments between passes
    /// ("gonna" becoming "going to", filler appearing and vanishing), and an
    /// index slice then either skips real words or repeats typed ones. Instead
    /// find where the already-typed text ends inside the final transcript.
    ///
    /// Scanned from the END on purpose. "…for you, ask what you can do for your
    /// country" repeats "for you"; matching forwards would land on the first
    /// occurrence and re-type everything after it.
    private func alignedTail(_ final: [String]) -> [String]? {
        guard !emitted.isEmpty else { return final }
        let k = min(4, emitted.count)
        let needle = emitted.suffix(k).map(StreamingTranscriber.normalize)
        let hay = final.map(StreamingTranscriber.normalize)
        guard hay.count >= needle.count else { return nil }

        var i = hay.count - needle.count
        while i >= 0 {
            if Array(hay[i ..< i + needle.count]) == needle {
                return Array(final[(i + needle.count)...])
            }
            i -= 1
        }
        return nil
    }

    func cancel() {
        stopTicking()
        queue.sync {}
    }

    // MARK: - One pass

    private func tick(_ pcm: [Float]) {
        let text = whisper.transcribe(pcm)
        guard running else { return }
        let now = StreamingTranscriber.words(text)
        guard !now.isEmpty else { return }

        let partial = onPartial
        DispatchQueue.main.async { partial(text) }

        // Longest prefix on which this pass and the last one agree.
        var stable = 0
        let limit = min(now.count, previous.count)
        while stable < limit,
              StreamingTranscriber.normalize(now[stable]) == StreamingTranscriber.normalize(previous[stable]) {
            stable += 1
        }
        previous = now

        let commitTo = min(stable, max(0, now.count - StreamingTranscriber.tailGuard))
        guard commitTo > emitted.count else { return }
        emit(Array(now[emitted.count..<commitTo]))
    }

    private func emit(_ newWords: [String]) {
        guard !newWords.isEmpty else { return }
        // A space before every chunk except the very first, so words do not
        // run together and the utterance does not start with a stray space.
        let chunk = (emitted.isEmpty ? "" : " ") + newWords.joined(separator: " ")
        emitted.append(contentsOf: newWords)
        // Capture the callback, not self. `finish()` emits the last chunk and
        // then returns, at which point the caller drops its reference — a
        // `[weak self]` here resolves to nil before the main queue drains and
        // the final words are silently lost.
        let deliver = onEmit
        DispatchQueue.main.async { deliver(chunk) }
    }

    // MARK: - Words

    static func words(_ s: String) -> [String] {
        s.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\t" }).map(String.init)
    }

    /// Compared loosely: whisper adds and removes punctuation and changes case
    /// as context arrives, and re-emitting a word because a comma appeared
    /// would duplicate it in the user's document.
    static func normalize(_ w: String) -> String {
        w.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }
}
