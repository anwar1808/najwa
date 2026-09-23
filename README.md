# Najwa

Local, privacy-first voice dictation for macOS. Hold a key, speak into any app,
and polished text is injected at your cursor. Everything runs on-device —
no cloud, and **no audio is ever saved**.

> Najwa (Arabic نجوى) — an intimate, confidential, whispered conversation.

## Status

**Phases 1 + 2 — full dictation loop (built).** The complete native loop
compiles and installs as a status-bar app:

- `fn` global hotkey with a two-mode state machine
  (hold-to-talk · double-tap to lock hands-free)
- In-memory audio capture (`AVAudioEngine`) with gain normalisation (vDSP) —
  nothing written to disk. Capture starts in ~0.1s (system voice processing was
  removed in v0.2.0: its ~1.1s spin-up ate the start of every dictation, it
  ducked system audio while live, and its session could wedge into silence)
- Live, voice-reactive waveform HUD (non-activating, click-through, never
  steals focus)
- **On-device ASR via WhisperKit** (`openai_whisper-large-v3-v20240930`),
  VAD-chunked so locked-mode dictations beyond 30s transcribe fully, with
  hallucination guards for non-speech audio
- On-device transcript cleanup via Apple **Foundation Models**
- **Personal vocabulary correction** (v0.3.0, `Vocabulary.swift`), shared with
  Pensieve: reads the `global` + `najwa` scopes of
  `~/Annie-Claude/Pensieve/Pensieve/.corrections.json` (re-read whenever the
  file changes, so a rule added in Pensieve's dictionary panel applies to the
  next dictation). After decoding: exact whole-word replacements
  ("Paykel" → PayCal), then a sound-alike pass that only touches words the
  system spell checker doesn't know (so "pensive" is left alone, "Evangelio"
  → Evangelo). Project scopes (Umbra, Defra…) are deliberately not read —
  their rules are only safe in context. Costs ≈0 ms.
  - Optional **Whisper biasing** (menu: "Bias Whisper with vocabulary
    (slower)", off by default): sends the first 12 terms as a decode prompt.
    Measured cost on M4 Max/large-v3: +0.2 s at 5 terms, +0.35 s at 10,
    +0.65 s at 20, +0.95 s at 60 — WhisperKit force-feeds each prompt token
    and drops its prefill cache. Needs the vendored WhisperKit patch
    (`v0.13.1-najwa-prompt-fix`): unpatched, a predicted EOT during the forced
    prompt ended the segment and every prompted decode returned "".
  - **Rollback:** menu toggle "Vocabulary correction" off = the pre-v0.3.0
    pipeline; git tag `pre-vocab-correction`; `backups/` holds the last
    v0.2.0 app bundle; the glossary file has a dated `.bak`.
  - Test without audio: `Najwa --vocabtest "some text"`; A/B latency:
    `--selftest clip.aiff [--no-vocab] [-NajwaVocabPrompt YES]`.
- Text injection at the cursor via CGEvent Unicode synthesis
- A transient "Najwa heard nothing" HUD pill when a dictation transcribes to
  empty — an empty result is never dropped silently
- In-memory text history with a 6-hour app-uptime TTL, cleared on quit
- Menu-bar nūn (ن) mark (always white; the HUD is the recording cue)
- Headless pipeline check: `Najwa --selftest /path/to/audio.wav`

**Phase 3 — faster ASR (later).** Try the Parakeet CoreML port as a
lower-latency engine. The app depends only on the `Transcriber` protocol,
so it's a drop-in.

## Dependencies (vendored locally)

WhisperKit's upstream repo is large and full clones kept failing mid-transfer on
a flaky connection, so the build uses **local sibling checkouts** as overrides
(see `Package.swift`):

- `~/Annie-Claude/whisperkit` — WhisperKit **v0.13.1** (lean: `swift-transformers`
  only; the v1.0 `argmax-oss-swift` rename pulls in Vapor, which we avoid).
- `~/Annie-Claude/swift-collections` — **1.6.0** (transitive dep of Jinja).

To recreate them:

```sh
git clone --depth 1 --branch v0.13.1 --filter=blob:none \
  https://github.com/argmaxinc/WhisperKit ~/Annie-Claude/whisperkit
git clone --depth 1 --branch 1.6.0 \
  https://github.com/apple/swift-collections.git ~/Annie-Claude/swift-collections
```

`swift-transformers`, `Jinja`, and `swift-argument-parser` resolve normally over
the network.

## Build & run

Requirements: Apple Silicon, macOS 26 (Tahoe), Xcode 26.

```sh
scripts/make_app.sh release   # → ./Najwa.app, installed to /Applications/Najwa.app
open /Applications/Najwa.app
```

On first launch Najwa downloads the WhisperKit `large-v3` model (~1.5 GB) from
Hugging Face — watch the menu's `model:` line; transcription is offline after.

### First-run permissions

1. **Microphone** — prompted on first dictation.
2. **Accessibility** — System Settings → Privacy & Security → Accessibility →
   add `Najwa.app` and toggle it **ON**. This powers both the `fn` event tap and
   text injection at the cursor. **Quit and reopen Najwa after granting.** If `fn`
   silently stops working, remove Najwa from this list, re-add it, and relaunch;
   to clear a stale grant from the terminal:
   `tccutil reset Accessibility com.anwarabdulhaqq.najwa`.
3. **Free the Globe key** — System Settings → Keyboard → "Press 🌐 key to" →
   **Do Nothing**, so `fn` doesn't trigger Apple's own dictation.

> fn is detected with a `CGEventTap` watching the secondary-fn modifier bit, not
> IOHIDManager — on current hardware the fn key delivers nothing through the HID
> top-case device, so **no Input Monitoring grant is needed**.
>
> Always launch the copy in **`/Applications/Najwa.app`** (what `make_app.sh`
> installs). Running a second copy from elsewhere registers a duplicate, conflicting
> TCC entry under the same bundle id, which macOS may resolve to the wrong (denied)
> grant after a reboot — the exact "worked yesterday, dead today" failure.

Then: hold **fn** and speak (release to inject), or double-tap **fn** to lock
hands-free (double-tap again to stop).

## Layout

```
Sources/Najwa/
  main.swift              app entry (status-bar agent, --selftest dispatch)
  AppDelegate.swift       menu bar, nūn glyph, wiring
  HotkeyMonitor.swift     fn via CGEventTap + two-mode state machine
  AudioCapture.swift      in-memory capture, gain normalisation, levels
  Transcriber.swift       ASR protocol (engine is a drop-in)
  WhisperKitTranscriber.swift  WhisperKit large-v3 ASR + 16kHz resampler
  Cleanup.swift           Foundation Models transcript polish
  Vocabulary.swift        shared glossary: replacements, sound-alike, Whisper prompt
  TextInjector.swift      CGEvent Unicode injection at cursor
  HistoryStore.swift      in-memory 6h-TTL text history
  HUDPanel.swift          floating waveform HUD
  Permissions.swift       Accessibility + Microphone gates
  SelfTest.swift          headless ASR pipeline verification
  DictationController.swift  orchestration
```

## Mobile stream

The Android counterpart (floating bubble → on-device Whisper → clipboard; Malay + English) lives in [`mobile/`](mobile/README.md). Research and design done 23 Sep 2026; build not started. The macOS app is unaffected.

## Privacy

Audio exists only as an in-memory buffer during the utterance and is freed right
after transcription. No temp files, no recordings, no network in the core flow.
Text history lives in RAM for at most 6 hours of uptime and is gone on quit.
