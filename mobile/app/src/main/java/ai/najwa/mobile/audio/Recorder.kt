package ai.najwa.mobile.audio

import android.annotation.SuppressLint
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import kotlin.math.abs
import kotlin.math.max

/**
 * In-memory 16 kHz mono float capture. Nothing is written to disk. Gain is
 * normalised after capture so a whispered dictation still reaches the model at
 * a sensible level (same approach as the macOS app).
 */
class Recorder {
    private var record: AudioRecord? = null
    private var thread: Thread? = null
    @Volatile private var running = false
    private val chunks = ArrayList<FloatArray>()
    @Volatile var level: Float = 0f; private set
    var startedAt: Long = 0L; private set

    @SuppressLint("MissingPermission") // caller checks RECORD_AUDIO
    fun start(): Boolean {
        if (running) return true
        val minBuf = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT)
        val rec = AudioRecord(
            SOURCE, SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_FLOAT,
            max(minBuf, SAMPLE_RATE * 4 /* 1 s */),
        )
        if (rec.state != AudioRecord.STATE_INITIALIZED) { rec.release(); return false }
        synchronized(chunks) { chunks.clear() }
        record = rec
        running = true
        startedAt = System.nanoTime()
        rec.startRecording()
        thread = Thread({
            val buf = FloatArray(SAMPLE_RATE / 10) // 100 ms
            while (running) {
                val n = rec.read(buf, 0, buf.size, AudioRecord.READ_BLOCKING)
                if (n > 0) {
                    var peak = 0f
                    for (i in 0 until n) peak = max(peak, abs(buf[i]))
                    level = peak
                    synchronized(chunks) { chunks.add(buf.copyOf(n)) }
                }
            }
        }, "najwa-rec").also { it.start() }
        return true
    }

    /** Stops capture and returns the normalised utterance. */
    fun stop(): FloatArray {
        running = false
        thread?.join(500); thread = null
        record?.run { runCatching { stop() }; release() }; record = null
        level = 0f
        val all: FloatArray = synchronized(chunks) {
            val total = chunks.sumOf { it.size }
            val out = FloatArray(total); var o = 0
            for (c in chunks) { c.copyInto(out, o); o += c.size }
            chunks.clear()
            out
        }
        return normalise(all)
    }

    private fun normalise(x: FloatArray): FloatArray {
        var peak = 0f
        for (v in x) peak = max(peak, abs(v))
        if (peak < 1e-4f) return x            // silence: leave it, the model will say so
        val gain = (TARGET_PEAK / peak).coerceAtMost(MAX_GAIN)
        if (gain <= 1.02f) return x
        for (i in x.indices) x[i] = (x[i] * gain).coerceIn(-1f, 1f)
        return x
    }

    companion object {
        const val SAMPLE_RATE = 16_000
        /** VOICE_RECOGNITION = the platform's ASR-tuned path (no AGC/aggressive NS). Flip to MIC to compare. */
        private const val SOURCE = MediaRecorder.AudioSource.VOICE_RECOGNITION
        private const val TARGET_PEAK = 0.9f
        private const val MAX_GAIN = 20f
    }
}
