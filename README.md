# Yapperroni

Hold-to-talk dictation for macOS. Hold **Right ⌥**, speak, release — the text
lands at your caret in whatever app you were in. Or press **⌥Space** to record
hands-free and press it again to stop.

Local Whisper (`small.en`, q5_1, 181 MB) via whisper.cpp with Metal. No API
keys, no account, no network. Transcription only — no autocorrect, no LLM
rewriting, no "AI features". It types what you said.

## Speed

~0.3–0.5 s from key release to pasted text for a normal sentence, measured on
an M5. The model is loaded once at launch and stays resident, so there is no
per-utterance load cost.

## Install

Requires an Apple Silicon Mac (M1 or later) on macOS 26 or newer.

1. Download `Yapperroni-1.0.dmg` from the
   [latest release](https://github.com/rolldesi/yapperroni/releases/latest)
   and open it.
2. Drag **Yapperroni** onto the **Applications** shortcut.
3. Eject the disk image, then launch Yapperroni from Applications, Spotlight or
   Launchpad.
4. A welcome screen explains the two permissions it needs and why. Grant them
   from there.
5. **Quit and reopen Yapperroni** after granting Accessibility — the shortcut
   only becomes live on a fresh launch.

Then hold **Right ⌥**, say something, and let go.

### If macOS refuses to open it

Release builds are signed but not notarized by Apple, so a copy that has been
*downloaded* carries a quarantine flag and Gatekeeper blocks it. Either build
from source (below), or clear the flag deliberately:

```bash
xattr -dr com.apple.quarantine /Applications/Yapperroni.app
```

Only do that for a build you trust. A DMG you built yourself on this machine
has no quarantine flag and needs none of this.

### The two permissions

| | Why |
|---|---|
| **Microphone** | To hear you while you dictate. macOS shows the orange recording dot whenever it is live. |
| **Accessibility** | To notice your shortcut while another app is focused, and to paste the result into it. |

Accessibility is the one that sounds alarming. Yapperroni does not read other
applications and does not log what you type: the key tap inspects the key code
and ignores every event that is not your shortcut. See [PRIVACY.md](PRIVACY.md),
or read `Sources/Hotkey.swift` — it is about 200 lines.

### Uninstall

```bash
rm -rf /Applications/Yapperroni.app
rm -rf ~/Library/Application\ Support/Yapperroni    # history, log, models
defaults delete com.rahuldesai.yapperroni            # settings
```

Also remove Yapperroni from System Settings → Privacy & Security →
Accessibility and → Microphone.

## Privacy

Your voice never leaves your Mac. No account, no server, no analytics, no
networking code at all. Audio lives in memory while you speak and is discarded
once it becomes text — it is never written to disk or transmitted.

Transcribed **text** is kept in `~/Library/Application Support/Yapperroni/history.json`
so you can search it. That is opt-out, from the welcome screen or Settings →
History. Full detail in [PRIVACY.md](PRIVACY.md).

## Build

Requires macOS on Apple Silicon, Xcode command line tools, and `cmake`
(`brew install cmake`).

```bash
./build.sh        # compile, sign, install to /Applications
./make-dmg.sh     # build, then package dist/Yapperroni-<version>.dmg
```

`YAPPERRONI_INSTALL_DIR=~/Applications ./build.sh` installs elsewhere. Note
that `~/Applications` does **not** appear under the Finder sidebar's
Applications shortcut, which makes the app look like it never installed —
`/Applications` is the default for that reason.

### App icon

Replace `assets/icon.png` with a square PNG (1024×1024 ideal) and run
`./build.sh`. It regenerates `assets/Yapperroni.icns` through `make-icon.sh`
whenever the source art is newer, and copies it into the bundle. The committed
icon is a placeholder.

Finder and the Dock cache icons hard; `build.sh` touches the bundle to nudge
them. If a stale icon persists, `killall Dock`.

The first build clones whisper.cpp, compiles it with Metal, and downloads the
181 MB model. Neither is in this repo. Later builds skip all of that and take
a few seconds.

The model ends up inside the app bundle, so the built `.app` and the DMG are
self-contained — nothing to download at install time.

### It lives in the menu bar

Yapperroni is a normal application — it installs to `/Applications`, launches
from Spotlight or Launchpad, and has its own icon. It simply has no permanent
Dock presence, because a dictation tool you invoke by holding a key does not
need one.

Look for the **mic icon in the menu bar**. On first launch it opens its window
so you can see it started; after that it stays out of the way. Double-clicking
it in Finder, or Open Flow from the menu bar, reopens the window. While the
window is open it takes a Dock icon like any other app, and gives it back when
you close it.

Grant two permissions on first launch:

- **Microphone** — prompt appears automatically.
- **Accessibility** — System Settings → Privacy & Security → Accessibility →
  enable **Yapperroni**. Required for both the hotkey and the paste. Quit and reopen
  Yapperroni after granting.

`build.sh` creates a self-signed **Yapperroni Local Signing** identity in your login
keychain on first run. This matters: TCC keys the Accessibility grant to the
code signature, so an ad-hoc signature would invalidate the grant on every
rebuild and the hotkey would die with no error message.

It deliberately does *not* sign with `--options runtime`. Hardened runtime
denies microphone input without a `com.apple.security.device.audio-input`
entitlement, and there is nothing to gain from it when you are not notarizing.

## Use

| Action | |
|---|---|
| Dictate | Hold **Right ⌥**, speak, release |
| Hands-free | Press **⌥Space** to start, press again to stop — no holding |
| Open the window | Menu bar → Open Yapperroni (⌘O), or double-click Yapperroni in Finder |
| History | Menu bar → History |
| Settings | Menu bar → Settings (⌘,) |

The pill at the bottom of the screen shows a live level meter while listening,
then the elapsed transcription time and word count.

### Window

**History** — every transcript, searchable, with the app it was dictated into,
word count, audio length and decode time. Select to copy or delete; the ⋯ menu
copies or clears everything. Copy only: re-inserting from here would have no
meaningful target app, since the click originates in Yapperroni's own window.

**Settings** — everything below.

**Stats** — totals, average decode time, and a rough time-saved figure against
40 wpm typing.

### Settings

| Group | |
|---|---|
| **Push to talk** | Click the shortcut button and press what you want. A modifier held on its own (either Option, Command, Control, Shift) or a function key. Hold-to-talk or press-to-start/press-to-stop. |
| **Hands-free lock** | Default **⌥Space**. Press once to record without holding anything, press again to stop. Rebindable the same way; must include a modifier. |
| **Output** | Paste at cursor, copy to clipboard only, or type character by character (slower, but works where paste is blocked). Optional trailing space. |
| **Model** | Any `.bin` in the support folder. Switching reloads in the background. |
| **Silence gate** | Loudness and length floors, with a **Test microphone** button that records two seconds and reports the measured peak — set the slider against a real number rather than guessing. |
| **Appearance** | Status pill position (bottom / top / centre / hidden), optional start and stop sounds. |
| **History** | On/off, and how many transcripts to keep. |
| **System** | Launch at login, Accessibility status, reveal the diagnostic log, reset all settings. |

Rebinding takes effect immediately — the tap is torn down and rebuilt, no
relaunch.

**Why some keys are refused.** Push-to-talk is never swallowed, so it has to be
a key that types nothing on its own: a bare modifier or a function key. A plain
letter would type into the app while you dictated into it.

The lock combo is different — Yapperroni *does* swallow it, or ⌥Space would also
insert a space. That is why it must include a modifier: binding bare `Space`
would consume every space you type system-wide, including in this settings
window, leaving no way to undo it. The recorder refuses that, along with ⌘Q,
⌘W, ⌘Tab, Escape, and whatever the other shortcut is already using.

Only an exact combo match is swallowed. Every other keystroke on the system,
including bare modifiers, passes straight through untouched.

## Self-tests

Three independent failure domains, each checkable on its own:

```bash
APP=~/Applications/Yapperroni.app/Contents/MacOS/Yapperroni

$APP --selftest-whisper vendor-whisper/samples/jfk.wav   # model + decode
$APP --selftest-audio                                     # mic + 16 kHz resample
$APP --selftest-hotkey                                    # bound modifier's bit mask, no permissions needed
$APP --selftest-toggle                                    # hold/toggle state machine, incl. rejected presses
```

The strongest one is the acoustic loopback: it plays a known clip through the
speakers, records it back, and transcribes it — proving capture, resampling and
decoding together, with nobody having to speak.

```bash
open -n ~/Applications/Yapperroni.app --args --selftest-loopback \
  ~/Projects/Yapperroni/vendor-whisper/samples/jfk.wav
tail -f ~/Library/Application\ Support/Yapperroni/yapperroni.log
```

Run it via `open`, not directly: launched from a terminal, the microphone grant
belongs to the terminal rather than to Yapperroni, and macOS feeds the process
digital silence — `rms 0.00000` with `authorized` status. The transcript it
produces will be poor; speaker-to-mic audio is heavily degraded. A non-zero
`peak100ms` is the result that matters.

Every dictation also appends a line to `~/Library/Application Support/Yapperroni/yapperroni.log`
(menu bar → Reveal Diagnostic Log). Each stage that can fail silently logs
what it saw, so "nothing happened" is always attributable to one of them.

## Layout

```
Sources/
  Config.swift     factory defaults, support paths, hallucination list
  Settings.swift   UserDefaults-backed user settings
  KeyBinding.swift bindable keys, masks, validation, display names
  KeyRecorder.swift click-then-press shortcut capture (local NSEvent monitor)
  History.swift    transcript store, JSON persisted
  Log.swift        append-only diagnostic log
  Whisper.swift    whisper.cpp wrapper; context loaded once, reused
  Recorder.swift   AVAudioEngine capture + AVAudioConverter to 16 kHz mono
  Hotkey.swift     listen-only CGEventTap; any modifier or F-key, hold or toggle
  Injector.swift   paste / copy / type, into the app captured at key-down
  HUD.swift        non-activating NSPanel status pill
  MainWindow.swift window, activation policy, main menu
  Views.swift      SwiftUI history, settings and stats
  Welcome.swift    first-run permissions and privacy screen
  App.swift        menu bar, wiring, dictation lifecycle
  main.swift       self-test modes + app entry
build.sh           bootstrap deps, icon, compile, sign, install
make-icon.sh       assets/icon.png -> multi-resolution .icns
make-dmg.sh        build, then package a styled drag-to-install DMG
assets/            app icon source and DMG background
vendor-whisper/    whisper.cpp checkout + static build
models/            downloaded GGML weights
```

State lives in `~/Library/Application Support/Yapperroni/`: the model, `history.json`,
and `yapperroni.log`. Settings are in `UserDefaults` under `com.rahuldesai.yapperroni`.

## Design notes

**Right ⌥, not fn.** fn is consumed by the system for dictation and the emoji
picker, and reports inconsistently through a flagsChanged tap.

**The tap consumes exactly one thing.** It is a `.defaultTap`, not listen-only,
because the lock combo has to be swallowed. But the callback returns the event
untouched for everything except an exact combo match — one comparison, then
pass through. It re-enables itself on `kCGEventTapDisabledByTimeout`, which
otherwise kills the hotkey after a while.

**Lock and hold share one state machine.** `Hotkey.decide` is a pure function
covering both, so "lock while holding", "hold-release while locked" and
"press rejected mid-transcription" are decided in one place and tested by
`--selftest-toggle` rather than discovered by hand.

**Flag comparison is masked.** Raw event flags carry `maskNonCoalesced` and
device-dependent bits, so a raw equality test against `maskAlternate` never
matches. `KeyBinding.normalize` masks to the four modifiers that matter.

**Paste, not synthesized keystrokes.** One event instead of N, instant
regardless of length, and it survives unicode that per-character injection
drops in some Electron apps. The clipboard is restored ~250 ms later, and
skipped if you copied something in the meantime.

**The window flips the activation policy.** Yapperroni is `.accessory` (no Dock icon)
until you open the window, then `.regular` until you close it. An accessory app
has no main menu, which means no ⌘C / ⌘V / ⌘A in the history search field or any
settings field.

**Target app captured on key-down**, before the HUD can perturb focus. The
panel is `.nonactivatingPanel` and never becomes key, but a stray click during
dictation would otherwise send the paste to the wrong window.

**Silence gating on the loudest 100 ms, not the average.** Whisper invents
confident sentences from silence ("Thank you.", "Subtitles by..."), so quiet
input is dropped before it reaches the model. The gate uses peak windowed RMS
because a whole-clip average punishes you for holding the key longer than you
speak — five seconds held, one second spoken, and the average sinks below any
useful threshold.

**Channel 0, extracted by hand.** The built-in MacBook microphone presents
**three** channels. `AVAudioConverter` will not downmix 3 → 1: it reports
success and writes zeros. The converter is therefore only ever asked to
resample, never to change channel count. Related: the tap must use the input
node's *output* format, not `inputFormat(forBus:)` — on a multi-channel mic
those differ, and the mismatch also yields silence. Both failures look
identical from the outside, which is why `Recorder` tracks the raw level
before conversion as well as after.

**Secure input.** Password fields enable secure input, which makes both the tap
and the paste no-ops. Yapperroni detects this and says so rather than failing
silently.

## Tuning

Everything worth changing is in `Sources/Config.swift`.

Everyday tuning is in **Settings** — hotkey, output mode, model, gate floors.
`Sources/Config.swift` only holds the factory defaults those fall back to.

Dictation being dropped as "Too quiet": lower the loudness floor, or press
**Test microphone** to measure. Reference points — speaking normally into the
built-in mic sits around `0.05`–`0.2`; audio arriving across a room via the
speakers measured `0.0094`; the default floor is `0.0005`.

Adding a key that is not in the list: extend `KeyBinding.modifiers` or
`functionKeys`. Modifier masks are the `NX_DEVICE*KEYMASK` bits — the generic
`maskAlternate` cannot tell left from right.

Different model: drop the `.bin` in `~/Library/Application Support/Yapperroni/` and
update `modelPath`. `large-v3-turbo-q5_0` is more accurate for roughly 2×
the latency; `base.en` is faster and noticeably worse.

## If nothing happens

Hold Right ⌥, say a sentence, release, then read the log:

```bash
cat ~/Library/Application\ Support/Yapperroni/yapperroni.log
```

| Log shows | Broken stage |
|---|---|
| no `press` line | the tap, or the key's device mask — not the recorder |
| `press` but no `release` | recorder threw, or the audio engine died |
| `release` with `peak100ms` below the floor | the gate — lower `minPeakRMS` |
| `result` with text but nothing pasted | `Injector` |
| text pasted into the wrong app | target capture in `beginDictation` |

`--selftest-hotkey` reads `CGEventSource.flagsState`, while the tap reads
`event.flags` from a real event. The device-dependent bits are not guaranteed
to show up identically in both, so a selftest failure is **not** evidence that
the binding's mask is wrong. If the two disagree, the `press` line in the log
wins — do not change the mask to chase the selftest.

## Distribution

`make-dmg.sh` produces `dist/Yapperroni-<version>.dmg` — about 176 MB, mostly
the model, which is already quantized and does not compress further.

It is the conventional drag-to-install window: app on the left, `/Applications`
alias on the right, arrow between them, on a retina background. That layout is
written by mounting a read-write image, scripting Finder to set the window
bounds, icon size and positions, then converting to a compressed read-only
image. It needs a GUI session; in a headless build the styling step is skipped
and the DMG still works, just unstyled.

The app is **self-signed, not notarized**. That is fine on this Mac: a locally
built DMG carries no quarantine flag. Handing it to someone else is a different
matter — once it has been downloaded, Gatekeeper blocks it, and on recent macOS
the right-click-Open bypass is no longer reliable for unnotarized apps. That
needs a $99 Apple Developer ID and notarization; no change to the packaging
fixes it.

## License

[MIT](LICENSE). Copyright (c) 2026 Rahul Desai.

Built on whisper.cpp and OpenAI's Whisper weights, both MIT — see
[THIRD-PARTY-NOTICES.md](THIRD-PARTY-NOTICES.md). The model ships inside the
app bundle and is therefore redistributed in release DMGs, which its license
permits.

## Known ceilings

- Batch, not streaming. Transcription starts on key release. Under a second,
  so it has not been worth the complexity of streaming partials.
- English only (`small.en`). A multilingual model is a file swap plus removing
  the hardcoded `en` language tag in `Whisper.swift`.
- Clipboard save/restore is string-only. Copying an image, dictating, and
  pasting would lose the image.
- History is rewritten as one JSON array per entry. Fine at hundreds of short
  strings; swap for append-only JSONL if it ever gets large.
- CPU/Metal encoder. Moving the encoder to the ANE via whisper.cpp's CoreML
  path would cut encode time roughly 3×, at the cost of a Python model-
  conversion step at build time.
