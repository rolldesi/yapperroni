import Foundation

/// Build-time constants and factory defaults. Anything the user can change
/// lives in `Settings`; this is only what it falls back to.
enum Config {
    static let sampleRate: Double = 16_000

    static let defaultModelFilename = "ggml-small.en-q5_1.bin"
    /// Gate on the loudest 100 ms window, not the whole-clip average.
    /// Reference points: speaking into the built-in mic measures 0.05–0.2;
    /// the same audio arriving across a room via speakers measured 0.0094.
    static let defaultMinPeakRMS: Float = 0.0005
    static let defaultMinSpeechSeconds: Double = 0.3

    // MARK: - Runaway sessions

    /// Hard ceiling on one dictation. A hands-free session has nothing to end
    /// it but a second keypress, so a forgotten lock (or a key that never came
    /// back up) would hold the mic — and voice processing, which ducks every
    /// other app — forever.
    static let maxSessionSeconds: Double = 180
    /// Hands-free only. A momentary hold is never cut off for going quiet:
    /// pausing mid-sentence to think is normal there.
    static let maxSilenceSeconds: Double = 3
    /// Factory setting for what counts as "not speaking", measured on the
    /// 16 kHz output RMS. Reference points: speaking into the built-in mic
    /// reads 0.05–0.2; the same voice across a room via speakers read 0.0094.
    ///
    /// The room decides this one — a fan or an air conditioner can sit above
    /// this floor and keep a session alive forever — so the user can move it
    /// in Settings. Every release logs the quietest second it measured, which
    /// is the number to set it just above.
    static let defaultAutoStopRMS: Float = 0.005

    /// Whisper loops when it runs out of speech: it emits the same clause over
    /// and over. A phrase this long or shorter, repeated back-to-back
    /// `loopRepeats` times, is a loop and not a person repeating themselves.
    static let loopWindowWords = 7
    static let loopMinWindowWords = 3
    static let loopRepeats = 3

    static let supportDir = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Yapperroni", isDirectory: true)

    /// Whisper's canned outputs for silence. Never paste these.
    static let hallucinations: Set<String> = [
        "thank you", "thanks for watching", "thank you for watching",
        ".", "...", "(silence)", "[blank_audio]", "[music]", "(music)",
        "[sound]", "[noise]", "[applause]", "[laughter]", "[inaudible]",
        "subtitles by the amara.org community", "please subscribe",
    ]
}
