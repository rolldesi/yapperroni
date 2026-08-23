# Privacy

Short version: **your voice never leaves your Mac.** Speech recognition runs
entirely on your own hardware — there is no server, no account, no analytics,
and no telemetry.

One feature is the exception, and it is **off by default**: AI cleanup. When you
turn it on and supply your own API key, each finished transcript is sent **as
text** to the provider you chose. Audio is never sent, under any setting. The
section below spells out exactly what that means.

## What it records, and when

Only while you are holding the dictation key, or between the two presses of the
hands-free lock. Nothing is captured when you are not actively dictating —
there is no wake word, no always-on listening, no background buffer.

The recording indicator (the orange dot in the menu bar, and Yapperroni's own
on-screen pill) is on for exactly as long as the microphone is.

## Where the audio goes

Into memory, then into the speech model running in this process on your own
CPU and GPU, then it is discarded. Audio is never written to disk and never
transmitted. When transcription finishes, the samples are freed.

## What is stored on disk

All of it under `~/Library/Application Support/Yapperroni/`:

| File | Contents |
|---|---|
| `history.json` | Transcribed **text**, with timestamp, the app it was dictated into, audio length and decode time. No audio. |
| `yapperroni.log` | Diagnostic lines: durations, measured loudness, and the transcribed text. |
| `ggml-*.bin` | The speech model, if you added your own. |

API keys are **not** in that folder — they are in your login Keychain under
`com.rahuldesai.yapperroni`.

Settings live in macOS preferences under `com.rahuldesai.yapperroni`.

**History is on by default.** Turn it off in Settings → History, which stops new
entries; existing ones stay until you clear them. Settings → History → Clear
deletes everything, and the ⋯ menu in the History view clears it too.

To remove every trace:

```bash
rm -rf ~/Library/Application\ Support/Yapperroni
defaults delete com.rahuldesai.yapperroni
```

## AI cleanup (off by default)

Settings → Cleanup can send each finished transcript to Claude, OpenAI, Gemini,
or any OpenAI-compatible endpoint you point it at, to fix punctuation and remove
filler words.

When it is enabled:

- **What is sent:** the transcribed text of that utterance, plus your cleanup
  instructions. Nothing else — not the audio, not your history, not the name of
  the app you were dictating into.
- **Who receives it:** the provider you selected, using your own API key.
- **What they do with it:** their policy, not ours. Check your provider's data
  retention and training terms — for API traffic these usually differ from their
  consumer products.
- **The welcome screen and this document both change wording** when cleanup is
  on. Yapperroni will not claim to be fully local while it is sending your text
  somewhere.

When it is off, no network request is made at any point.

**Your API key** is stored in your **login Keychain**, not in Yapperroni's
settings file — a settings plist is readable by any process running as you and
gets copied around by backups and sync. The key is never logged: failures record
the provider name and HTTP status code only, never the key or the response body.

Turning cleanup off, or removing the key with the Remove button, stops all
outbound traffic immediately.

## What the clipboard does

In the default **Paste** output mode, Yapperroni briefly puts the transcript on
your clipboard, sends ⌘V, and restores what was there about a quarter second
later. If you copied something else in that window, it backs off and leaves
your copy alone. Choose **Copy to clipboard only** or **Type character by
character** in Settings → Output if you would rather it not paste for you.

Clipboard restore preserves text only. Copy an image, dictate, and the image is
gone from your clipboard.

## Why it asks for Accessibility

Accessibility is the permission that sounds alarming, so here is exactly what
it is used for:

1. **Watching for your dictation key.** A global key tap is the only way to
   notice a keypress while another app is focused.
2. **Pasting.** Synthesizing ⌘V into the app you were typing in.

Yapperroni does not read the contents of other applications, does not log your
keystrokes, and does not record what you type. The key tap inspects one field —
the key code — and ignores every event that is not the shortcut you configured.
The single exception is the hands-free lock combo, which is swallowed so it
does not also type into your document. Everything else passes through untouched.

You can read all of it: `Sources/Hotkey.swift` is about 200 lines.

## Microphone

Required, for the obvious reason. macOS shows the orange recording indicator
whenever it is live.

## If you did not build it yourself

Release builds are self-signed rather than notarized by Apple, which means
Apple has not reviewed them. If that matters to you, clone the repository and
run `./build.sh` — you get the same app, compiled on your own machine.
