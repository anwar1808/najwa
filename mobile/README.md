# Najwa Mobile (Android) — stream

Android counterpart to the macOS Najwa. Same promise: fully on-device dictation,
nothing leaves the phone. Different shape: a floating bubble you hold to dictate,
with the result copied to the clipboard for pasting into any app. It never reads
the app in use.

Status: **research and design complete, build not started** (23 Sep 2026).
The macOS app in the repo root is untouched by this stream.

## Target device

Huawei Pura 70 Ultra (HBP-LX9) · EMUI 14.2 (HarmonyOS 4.2 international =
Android 12 core, no Google services) · Kirin 9010 · 16 GB RAM · 1 TB.
Install path: sideloaded APK (no Play Store). No USB debugging in the loop —
every test APK shows its results on screen with a "copy results" button.

## Requirements (Annie, 23 Sep 2026)

- Floating bubble; **hold** to dictate, release to transcribe.
- **Hands-free lock mode in v1** (double-tap), with auto-stop on silence and a
  hard session cap.
- Result → **clipboard** (Android's own "Copied" chip is the confirmation).
  No accessibility service, no reading the foreground app.
- **Malay + English, mixed in one sentence** (Manglish).
- **Must not drain battery.**
- Persistent notification while armed is acceptable.
- **Model must be swappable in seconds** without a rebuild.
- Vocabulary is standalone (no link to the Mac/Pensieve glossary), but the
  Mac `Vocabulary` logic (rules + sound-alike) is ported.

## Platform constraints (verified against Android docs, Sep 2026)

- Overlay = `SYSTEM_ALERT_WINDOW` ("Display over other apps").
- Microphone is a *while-in-use* permission: a `microphone`-type foreground
  service **cannot be created while the app is in the background**, and holding
  the overlay permission or being the IME does not exempt it. Exemptions that
  do: notification action, app widget, `VoiceInteractionService`.
  → Pattern: start the mic-type foreground service while the app is visible
  ("Start Najwa"), keep it alive as the bubble host, record inside it.
  Fallback: a "Dictate" action on the persistent notification.
- EMUI kills foreground services 5–10 min after screen-off unless the app is
  set to **Manage manually** (Battery → App launch), **Ignore battery
  optimisation**, and **locked in Recents**. The app must onboard these and
  detect/recover a dead service.
- Clipboard writes from a service are fine; background *reads* are blocked
  (not needed).

## Battery design

- Idle = mic closed, no VAD loop, nothing computing; the bubble is a drawn window.
- Model stays loaded in RAM (cheap) — never reloaded per dictation.
- Lock mode: Silero VAD auto-stop after ~8 s silence + hard cap per session.
- Inference in bursts (on release / on VAD pause), never streaming.
- Measure with the system per-app battery stats; target low single digits/day.

## Engine and model strategy

Malay/English code-switching rules out Parakeet (EN/EU) and Moonshine (EN).
Pensieve precedent: force Whisper `language = "ms"` for mixed audio — Malay
stays Malay, English stays English; `en`/`auto` half-translates the Malay.

- Engine: **whisper.cpp** (one adapter covers every Whisper-family model).
- Default candidate: **mesolitica/Malaysian-whisper-large-v3-turbo-v3** (0.8B,
  fine-tuned on Malay/Manglish/Mandarin/Tamil; turbo decoder = fast).
  Fallbacks: `malaysian-whisper-small-v3` (0.2B); stock `large-v3-turbo` with
  `ms`; `base.en`/`small.en` for a pure-English profile.
- Stock Whisper Malay WER (FLEURS, published): medium ~12%, large-v2 ~8.7% —
  small/base are noticeably worse on Malay.
- Last resort: Omnilingual ASR 300M CTC via sherpa-onnx (no punctuation,
  language-hint issue open, Malay coverage unverified).

### Swappable models (the "change it in seconds" requirement)

- The app depends on a `Transcriber` interface, never on a model.
- Each model = a folder in app-private storage: weights + `model.json`
  (name, engine, language `ms|en|auto`, decode options).
- **Models screen**: list installed models, one active, tap to switch; "Add
  model" imports from phone storage; delete. Active model loads in the
  background.
- Vocabulary's sound-alike gate uses the active model's language to choose
  which word lists count as "known" (EN only vs EN + MS) — every Malay word is
  "unknown" to an English spell checker, so the Mac gate is not enough here.

## Build sequence

1. **Model conversion + on-phone benchmark** — convert Mesolitica turbo-v3 and
   small-v3 plus stock large-v3-turbo and base.en to whisper.cpp format; a
   benchmark APK shows ms-per-sentence and transcript per model with a copy
   button. Test set: pure English with project names, pure Malay, real Manglish.
   Pick the largest model under ~1.5 s for a 5-second sentence.
2. **EMUI service-survival spike** — bubble + mic foreground service + the
   three battery settings, left running a day; in-app log with copy button.
   Decides bubble vs keyboard (IME) for v1.
3. **App proper**: engine + Models screen → bubble/hold/lock → clipboard →
   vocabulary → EMUI onboarding + service recovery.
4. Release via the standard APK flow (version bump, signed build, GitHub release).

Phase 2 (later): a "Najwa keyboard" IME for direct insertion without the paste step.

## Stack

Kotlin-native (Compose for the few screens). Flutter deliberately not used:
~80% of this app is platform plumbing (overlay, foreground service,
AudioRecord, clipboard, EMUI onboarding) and a Flutter engine adds nothing.

## Existing tools considered

- **FUTO Voice Input** — open-source on-device Whisper voice keyboard; works with
  FUTO/HeliBoard/FlorisBoard/SwiftKey, not Gboard/Samsung. Good benchmark for
  "what does on-device Whisper feel like on this phone".
- **Murmur** — Wispr-Flow-style floating pill, Android 8+, mostly cloud/local-server models.

## Sources

- Android FGS background-start restrictions: https://developer.android.com/develop/background-work/services/fgs/restrictions-bg-start
- Android FGS changes by version: https://developer.android.com/develop/background-work/services/fgs/changes
- Don't kill my app — Huawei: https://dontkillmyapp.com/huawei
- whisper.cpp: https://github.com/ggml-org/whisper.cpp · prebuilt Android AAR: https://github.com/ffmpegkit-maintained/whisper
- sherpa-onnx: https://github.com/k2-fsa/sherpa-onnx · Whisper models: https://k2-fsa.github.io/sherpa/onnx/pretrained_models/whisper/index.html
- Mesolitica Malaysian Whisper: https://huggingface.co/collections/mesolitica/malaysian-whisper-6590b6b733d72b44f0cfae79
- Whisper Malay WER discussion: https://github.com/openai/whisper/discussions/1973
- FUTO Voice Input: https://github.com/futo-org/voice-input
