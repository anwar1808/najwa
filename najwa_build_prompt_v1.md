# Build Prompt — Najwa (local macOS voice dictation app)

You are building **Najwa**, a fully local, privacy-first voice-dictation app for macOS — a personal, single-user reimagining of Wispr Flow. Hold a key, speak into any app, and polished text is injected at the cursor. Everything runs on this Mac; nothing is sent to the cloud and no audio is ever saved.

This is a personal tool for one user on one machine. Optimise for privacy, low latency, and a clean native feel — not for scale, accounts, or multi-user concerns.

---

## Non-negotiable privacy constraints (treat as acceptance criteria)

1. **No audio is ever written to disk.** Mic audio lives only in an in-memory buffer (`AVAudioPCMBuffer` / float arrays), is fed directly to the speech model, and is freed immediately after transcription. No temp `.wav`, no cache file, nothing. **Verify the chosen ASR accepts an in-memory buffer and does not internally spill a temp file** — if a wrapper insists on a file path, pick a different port.
2. **Fully local / offline.** No network calls for the core flow. Audio never leaves the machine.
3. **Transcript text history is in-memory only**, with a **6-hour-of-app-uptime TTL**: each cleaned-text entry is timestamped, a timer sweeps entries older than 6 hours, and quitting the app clears everything immediately. Text is never persisted to disk.

---

## Platform & stack

- **Native macOS app in Swift** (menu-bar / status-bar app, no main window). Swift is required because the hard parts are OS integration: global hotkey capture, system-wide text injection, and a non-activating floating overlay.
- **Target:** Apple Silicon, recent macOS. Confirm the exact minimum at build time (Apple Foundation Models needs macOS 26 Tahoe on an Apple-Intelligence-capable Mac; `voiceIsolation` mic mode needs a 2018+ Mac on Monterey+).

### Models

- **Speech-to-text (ASR):** Prefer **Parakeet** (Apple-Silicon port via MLX / Core ML) for its ~80ms streaming latency and filler-dropping behaviour. Fall back to **WhisperKit** if Parakeet integration is problematic. The reference project `moona3k/macparakeet` (GitHub) already does system-wide Parakeet dictation on Apple Silicon — study it for the capture-to-injection plumbing before writing from scratch.
- **Cleanup / formatting LLM:** **Apple Foundation Models framework** (on-device ~3B model) for short-form rewriting — strip filler words ("um", "uh", false starts), add punctuation and capitalisation, and lightly format. Free, offline, Swift-native, no data leaves the device.
- **Optional future toggle (do NOT build in v1):** a Claude Haiku cleanup option for higher-quality polish. Leave a clean seam for it; ship local-only first.

---

## Core flow

1. User presses/holds the hotkey → mic capture starts immediately into an in-memory buffer.
2. Live audio drives the on-screen waveform HUD (same buffer, two consumers).
3. On stop, the buffer goes to ASR → raw text → cleanup LLM → polished text.
4. Polished text is injected at the cursor in whatever app currently has focus.
5. Polished text is added to the in-memory 6-hour history; audio buffer is discarded.

### Audio processing order (this ordering matters)

**Isolate, then amplify.** Request the macOS **`AVCaptureDevice.MicrophoneMode.voiceIsolation`** mode so the OS strips background noise (TV, nearby talkers, ambient) and prioritises the foreground voice. **Then** apply gain normalisation to the cleaned buffer so a genuine whisper becomes readable. Never amplify first (that boosts the room too). There is no separate "whisper detector" — whisper handling = voice isolation + gain + the recommendation that the user keep the mic close (close-mic proximity is what actually preserves signal-to-noise).

---

## Push-to-talk: two modes on one configurable hotkey

Default hotkey is **`fn`** (the Globe key), but **make the hotkey configurable**.

- **Mode 1 — Hold-to-talk:** press and hold the key → records while held → stops and transcribes the instant the key is released.
- **Mode 2 — Locked / hands-free:** double-tap the key → records continuously with the finger off the key → double-tap again to stop and transcribe.

### State machine (single key serves both)

- **Key down →** start capturing immediately (zero added latency for hold mode).
- **Released after > ~250ms →** it was a hold; stop and transcribe.
- **Released as a quick tap →** wait a ~250ms window for a second tap:
  - **Second tap arrives →** enter locked mode; keep recording until the next double-tap.
  - **No second tap →** treat as a short dictation and transcribe it.

### `fn`-key specifics (important)

- `fn` is not a normal key — it arrives as a modifier-flag change. Capture it via a **`CGEventTap` / `flagsChanged`**, not a standard global shortcut. This needs **Accessibility** permission.
- macOS may already bind double-tap-`fn` to its own dictation. First-run setup must instruct the user to set **System Settings → Keyboard → "Press 🌐 key to" → Do Nothing** so `fn` is free.

---

## On-screen feedback: floating waveform HUD

A **bottom-centre floating pill** that appears while recording:

- **Look:** translucent dark "HUD" pill using `NSVisualEffectView` (dark HUD material), rounded corners, subtle shadow — white/light waveform on a dark, slightly see-through background.
- **Waveform:** live and **voice-reactive**, driven by the same in-memory audio buffer (amplitude/levels → bar heights). It reacts to a whisper too.
- **Behaviour:** fades/slides in on key-down; in **hold mode** it shows while the key is held; in **locked mode** it stays visible the entire time (it doubles as the "still listening" indicator); fades out on stop.
- **Critical — must NOT steal focus.** The text is injected into the currently focused app, so the HUD must be a **non-activating `NSPanel`** (`.nonactivatingPanel`), **click-through** (`ignoresMouseEvents = true`), at a **floating window level**, and set to appear on **all Spaces**. If the HUD ever grabs focus, injection breaks.

---

## Text injection

Inject the polished text at the cursor of the focused app via the **Accessibility API + `CGEvent` keystroke synthesis**. Requires Accessibility permission.

---

## Branding & assets

- **Name:** **Najwa** (Arabic نجوى — an intimate, confidential, whispered conversation; chosen for the privacy/intimacy meaning).
- **Logo mark — the nūn (ن):** a shallow curved bowl (which also reads as a low, gentle waveform trough — a whisper) with a single dot floating above. The **dot is the recording-state indicator**.
- **Menu-bar status icon:** a **template image** (monochrome, ~16–18px, auto-inverts for light/dark menu bars) of the nūn mark.
  - **Idle:** dot is hollow/outline.
  - **Recording:** dot is filled / tinted accent (or red).
- **App icon (Dock/Finder):** full-colour rounded-rect echoing the HUD pill — dark, slightly translucent-looking base, the nūn curve as a soft luminous waveform, the dot a warm point of light above. Keep it visually distinct from any Bitcoin-orange branding (unrelated project).
- Through-line across all surfaces: **dark translucent pill + waveform**, rendered three ways (flat mono in the menu bar, live in the HUD, polished pill as the app icon).

---

## Permissions to request (with clear first-run prompts)

- **Microphone** — for capture.
- **Accessibility** — for `fn`/hotkey capture via the event tap and for text injection.
- Guidance step: set the Globe key to "Do Nothing" (see above).

---

## v1 scope (build this) vs later (do NOT build yet)

**v1:** the full flow above — two-mode push-to-talk, in-memory no-save audio, 6-hour in-memory text history, voice-isolation + gain, local ASR + Apple Foundation Models cleanup, text injection, the waveform HUD, menu-bar icon with both states, configurable hotkey.

**Later (leave seams, don't build):** Claude Haiku cleanup toggle, personal dictionary / custom vocabulary, snippets / voice shortcuts, per-app context formatting (email vs code), multi-language UI. Keep v1 tight.

---

## Build-time verifications (don't assume — check and report)

1. The chosen ASR port genuinely accepts an in-memory buffer with **no temp file on disk**.
2. Apple Foundation Models is available and performs the cleanup acceptably on this specific Mac/OS; if not available, state it and propose the fallback.
3. Whisper-mode accuracy: record a real whisper through `voiceIsolation` + gain and measure how usable the transcription is before claiming the feature works.
4. End-to-end latency from key-release to injected text — report it; aim for sub-second.
