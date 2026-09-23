package ai.najwa.whisper

/** Raw JNI bindings. Use [WhisperContext] rather than calling these directly. */
internal object WhisperNative {
    init {
        System.loadLibrary("najwa_whisper")
    }

    external fun initContext(modelPath: String): Long
    external fun freeContext(ctx: Long)
    external fun isMultilingual(ctx: Long): Boolean
    external fun transcribe(
        ctx: Long,
        audio: FloatArray,
        nThreads: Int,
        language: String,
        translate: Boolean,
        initialPrompt: String?,
        noSpeechThold: Float,
        entropyThold: Float,
        logprobThold: Float,
    ): String

    external fun systemInfo(): String
}
