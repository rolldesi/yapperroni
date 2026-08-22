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
