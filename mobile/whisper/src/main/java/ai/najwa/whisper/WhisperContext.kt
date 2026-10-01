package ai.najwa.whisper

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.withContext
import java.util.concurrent.Executors

/** Decode options that matter for dictation; everything else is whisper.cpp default. */
data class DecodeOptions(
    /** Whisper language code ("en", "ms") or "auto". Mixed Malay/English → "ms" (see mobile/README). */
    val language: String = "ms",
    val translate: Boolean = false,
    val initialPrompt: String? = null,
    val noSpeechThreshold: Float = 0.6f,
    val entropyThreshold: Float = 2.4f,
    val logprobThreshold: Float = -1.0f,
    val threads: Int = defaultThreads(),
) {
    companion object {
        /** Big cores only is faster than all cores on big.LITTLE; 4 is a safe default. */
        fun defaultThreads(): Int = Runtime.getRuntime().availableProcessors().coerceIn(2, 8).let { if (it > 4) 4 else it }
    }
}

/**
 * One loaded whisper.cpp model. whisper.cpp contexts are not thread-safe, so all
 * calls are serialised on a private single-thread dispatcher.
 */
class WhisperContext private constructor(private var ptr: Long) {
    private val scope = CoroutineScope(Executors.newSingleThreadExecutor().asCoroutineDispatcher())

    val isMultilingual: Boolean get() = ptr != 0L && WhisperNative.isMultilingual(ptr)

    /** [pcm16k] is 16 kHz mono float in [-1, 1]. Returns the transcript ("" if nothing). */
    suspend fun transcribe(pcm16k: FloatArray, options: DecodeOptions): String = withContext(scope.coroutineContext) {
        require(ptr != 0L) { "context released" }
        val lang = if (!isMultilingual) "en" else options.language
        WhisperNative.transcribe(
            ptr, pcm16k, options.threads, lang, options.translate, options.initialPrompt,
            options.noSpeechThreshold, options.entropyThreshold, options.logprobThreshold,
        )
    }

    /** Asks the running decode (if any) to stop at the next opportunity; it returns "" . */
    fun cancel() = WhisperNative.cancel()

    suspend fun release() = withContext(scope.coroutineContext) {
        if (ptr != 0L) {
            WhisperNative.freeContext(ptr)
            ptr = 0L
        }
    }

    companion object {
        fun load(modelPath: String): WhisperContext {
            val p = WhisperNative.initContext(modelPath)
            require(p != 0L) { "Could not load model at $modelPath" }
            return WhisperContext(p)
        }

        fun systemInfo(): String = WhisperNative.systemInfo()
    }
}
