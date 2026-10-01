// Minimal JNI surface over whisper.cpp for Najwa Mobile.
//
// One context per loaded model; one call transcribes a whole utterance held in
// memory (16 kHz mono float). No audio or text is written to disk here.
// Decode options that matter for dictation are exposed, everything else stays
// at whisper.cpp defaults so a model swap never needs a native rebuild.

#include <jni.h>
#include <android/log.h>
#include <string>
#include <vector>
#include <cstring>
#include <atomic>
#include "whisper.h"

// Set by cancel(); read by whisper.cpp between ops so a runaway decode can be stopped.
static std::atomic<bool> g_abort{false};

#define TAG "NajwaWhisper"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO, TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, TAG, __VA_ARGS__)

static void log_cb(ggml_log_level level, const char *text, void *) {
    if (level == GGML_LOG_LEVEL_ERROR) __android_log_print(ANDROID_LOG_ERROR, TAG, "%s", text);
    else if (level == GGML_LOG_LEVEL_WARN) __android_log_print(ANDROID_LOG_WARN, TAG, "%s", text);
    else __android_log_print(ANDROID_LOG_DEBUG, TAG, "%s", text);
}

extern "C" {

JNIEXPORT jlong JNICALL
Java_ai_najwa_whisper_WhisperNative_initContext(JNIEnv *env, jclass, jstring modelPath) {
    whisper_log_set(log_cb, nullptr);
    const char *path = env->GetStringUTFChars(modelPath, nullptr);
    whisper_context_params cparams = whisper_context_default_params();
    cparams.use_gpu = false;
    whisper_context *ctx = whisper_init_from_file_with_params(path, cparams);
    LOGI("initContext %s -> %p", path, (void *) ctx);
    env->ReleaseStringUTFChars(modelPath, path);
    return reinterpret_cast<jlong>(ctx);
}

JNIEXPORT void JNICALL
Java_ai_najwa_whisper_WhisperNative_freeContext(JNIEnv *, jclass, jlong ctxPtr) {
    if (ctxPtr) whisper_free(reinterpret_cast<whisper_context *>(ctxPtr));
}

JNIEXPORT jboolean JNICALL
Java_ai_najwa_whisper_WhisperNative_isMultilingual(JNIEnv *, jclass, jlong ctxPtr) {
    auto *ctx = reinterpret_cast<whisper_context *>(ctxPtr);
    return ctx && whisper_is_multilingual(ctx) ? JNI_TRUE : JNI_FALSE;
}

// Returns the transcript (segments joined by spaces), or "" on failure.
// language: BCP-47-ish whisper code ("en", "ms") or "auto".
JNIEXPORT jstring JNICALL
Java_ai_najwa_whisper_WhisperNative_transcribe(JNIEnv *env, jclass, jlong ctxPtr,
                                               jfloatArray audio, jint nThreads,
                                               jstring language, jboolean translate,
                                               jstring initialPrompt,
                                               jfloat noSpeechThold, jfloat entropyThold,
                                               jfloat logprobThold) {
    auto *ctx = reinterpret_cast<whisper_context *>(ctxPtr);
    if (!ctx) return env->NewStringUTF("");

    const jsize n = env->GetArrayLength(audio);
    std::vector<float> pcm(n);
    env->GetFloatArrayRegion(audio, 0, n, pcm.data());

    const char *lang = env->GetStringUTFChars(language, nullptr);
    const char *prompt = initialPrompt ? env->GetStringUTFChars(initialPrompt, nullptr) : nullptr;

    whisper_full_params p = whisper_full_default_params(WHISPER_SAMPLING_GREEDY);
    p.n_threads = nThreads;
    p.translate = translate == JNI_TRUE;
    p.no_context = true;        // each dictation stands alone
    p.no_timestamps = true;
    p.single_segment = false;
    p.print_progress = false;
    p.print_realtime = false;
    p.print_timestamps = false;
    p.suppress_blank = true;
    p.suppress_nst = true;      // drop non-speech tokens (♪, [Music], …)
    p.no_speech_thold = noSpeechThold;
    p.entropy_thold = entropyThold;
    p.logprob_thold = logprobThold;
    if (std::strcmp(lang, "auto") == 0) {
        p.language = nullptr;
        p.detect_language = false; // nullptr language = auto-detect in whisper_full
    } else {
        p.language = lang;
    }
    if (prompt && prompt[0]) p.initial_prompt = prompt;
    g_abort.store(false);
    p.abort_callback = [](void *) -> bool { return g_abort.load(); };
    p.abort_callback_user_data = nullptr;

    std::string out;
    if (whisper_full(ctx, p, pcm.data(), n) == 0) {
        const int nseg = whisper_full_n_segments(ctx);
        for (int i = 0; i < nseg; i++) {
            const char *t = whisper_full_get_segment_text(ctx, i);
            if (!t) continue;
            std::string s(t);
            // Safety net: fine-tunes with extra tokens can leak "<|6.0|>"-style
            // markers into the text. Strip anything that looks like <|…|>.
            for (size_t p = s.find("<|"); p != std::string::npos; p = s.find("<|")) {
                size_t q = s.find("|>", p);
                if (q == std::string::npos) break;
                s.erase(p, q - p + 2);
            }
            // trim
            size_t a = s.find_first_not_of(" \t\n\r"), b = s.find_last_not_of(" \t\n\r");
            if (a == std::string::npos) continue;
            s = s.substr(a, b - a + 1);
            if (!out.empty()) out += ' ';
            out += s;
        }
    } else {
        LOGE("whisper_full failed");
    }

    env->ReleaseStringUTFChars(language, lang);
    if (prompt) env->ReleaseStringUTFChars(initialPrompt, prompt);
    return env->NewStringUTF(out.c_str());
}

JNIEXPORT void JNICALL
Java_ai_najwa_whisper_WhisperNative_cancel(JNIEnv *, jclass) {
    g_abort.store(true);
}

JNIEXPORT jstring JNICALL
Java_ai_najwa_whisper_WhisperNative_systemInfo(JNIEnv *env, jclass) {
    return env->NewStringUTF(whisper_print_system_info());
}

} // extern "C"
