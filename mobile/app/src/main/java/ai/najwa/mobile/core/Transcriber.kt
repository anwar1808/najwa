package ai.najwa.mobile.core

import ai.najwa.whisper.DecodeOptions
import ai.najwa.whisper.WhisperContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/**
 * What the rest of the app depends on. An engine is chosen per model from
 * `ModelSpec.engine`; adding a non-Whisper engine means one more adapter here
 * and nothing else changes.
 */
interface Transcriber {
    val spec: ModelSpec
    /** 16 kHz mono float PCM in → text out ("" if nothing heard). */
    suspend fun transcribe(pcm16k: FloatArray, threads: Int): String
    /** Stop an in-flight transcribe early (it returns ""). */
    fun cancel()
    suspend fun release()
}

class WhisperCppTranscriber private constructor(
    override val spec: ModelSpec,
    private val ctx: WhisperContext,
) : Transcriber {
    override suspend fun transcribe(pcm16k: FloatArray, threads: Int): String {
        val opts = DecodeOptions(language = spec.language, threads = threads)
        return ctx.transcribe(pcm16k, opts)
    }

    override fun cancel() = ctx.cancel()
    override suspend fun release() = ctx.release()

    companion object {
        suspend fun load(spec: ModelSpec, weights: File): WhisperCppTranscriber = withContext(Dispatchers.IO) {
            WhisperCppTranscriber(spec, WhisperContext.load(weights.absolutePath))
        }
    }
}

object Engines {
    suspend fun load(spec: ModelSpec, weights: File): Transcriber = when (spec.engine) {
        "whisper.cpp" -> WhisperCppTranscriber.load(spec, weights)
        else -> throw IllegalArgumentException("Unknown engine '${spec.engine}' for model ${spec.id}")
    }
}
