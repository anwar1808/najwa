# Najwa

Local, privacy-first voice dictation for macOS. Hold a key, speak into any app,
and polished text is injected at your cursor. Everything runs on-device —
no cloud, and **no audio is ever saved**.

> Najwa (Arabic نجوى) — an intimate, confidential, whispered conversation.

## Status

**Phase 1 — OS-integration core (built).** The full native loop compiles and
installs as a status-bar app:

- `fn` global hotkey with a two-mode state machine
  (hold-to-talk · double-tap to lock hands-free)
- In-memory audio capture (`AVAudioEngine`) with system voice processing +
  gain normalisation — nothing written to disk
- Live, voice-reactive waveform HUD (non-activating, click-through, never
  steals focus)
- Text injection at the cursor via CGEvent Unicode synthesis
- On-device transcript cleanup via Apple **Foundation Models**
- In-memory text history with a 6-hour app-uptime TTL, cleared on quit
- Menu-bar nūn (ن) mark, red while recording

**The transcriber is a labelled stub** (`StubTranscriber`) — it injects a clear
`[Najwa: ASR not wired yet …]` sentinel so the whole loop can be exercised and
permissions granted before real speech recognition is added.

**Phase 2 — real ASR (next).** Swap the stub for an on-device engine
(WhisperKit first as the known-good baseline, then the Parakeet CoreML port).
The app depends only on the `Transcriber` protocol, so it's a drop-in.

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

On first launch Najwa downloads the WhisperKit `small` model (~480 MB) from
Hugging Face — watch the menu's `model:` line; transcription is offline after.

### First-run permissions

1. **Microphone** — prompted on first dictation.
2. **Accessibility** — System Settings → Privacy & Security → Accessibility →
   add `Najwa.app`. Needed for the `fn` event tap and text injection.
3. **Free the Globe key** — System Settings → Keyboard → "Press 🌐 key to" →
   **Do Nothing**, so `fn` doesn't trigger Apple's own dictation.

Then: hold **fn** and speak (release to inject), or double-tap **fn** to lock
hands-free (double-tap again to stop).

## Layout

```
Sources/Najwa/
  main.swift              app entry (status-bar agent)
  AppDelegate.swift       menu bar, nūn glyph, wiring
  HotkeyMonitor.swift     fn event tap + two-mode state machine
  AudioCapture.swift      in-memory capture, voice processing, gain, levels
  Transcriber.swift       ASR protocol + Phase-1 stub
  Cleanup.swift           Foundation Models transcript polish
  TextInjector.swift      CGEvent Unicode injection at cursor
  HistoryStore.swift      in-memory 6h-TTL text history
  HUDPanel.swift          floating waveform HUD
  DictationController.swift  orchestration
```

## Privacy

Audio exists only as an in-memory buffer during the utterance and is freed right
after transcription. No temp files, no recordings, no network in the core flow.
Text history lives in RAM for at most 6 hours of uptime and is gone on quit.
