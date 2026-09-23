package ai.najwa.mobile.core

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import java.io.File
import java.io.IOException
import java.net.HttpURLConnection
import java.net.URL

/**
 * Resumable HTTP download to `dest` via a `.part` file. Redirects are followed
 * by hand so the bearer token is only ever sent to huggingface.co, never to the
 * CDN host a model download redirects to.
 */
object Downloader {
    class HttpError(val code: Int, msg: String) : IOException(msg)

    suspend fun download(
        url: String,
        dest: File,
        token: String?,
        onProgress: (downloaded: Long, total: Long) -> Unit,
    ) = withContext(Dispatchers.IO) {
        val part = File(dest.path + ".part")
        dest.parentFile?.mkdirs()
        var existing = if (part.exists()) part.length() else 0L

        var current = url
        var conn: HttpURLConnection? = null
        for (hop in 0..6) {
            val u = URL(current)
            val c = (u.openConnection() as HttpURLConnection).apply {
                instanceFollowRedirects = false
                connectTimeout = 20_000
                readTimeout = 90_000
                setRequestProperty("User-Agent", "NajwaMobile/0.1")
                if (!token.isNullOrBlank() && u.host.endsWith("huggingface.co")) {
                    setRequestProperty("Authorization", "Bearer $token")
                }
                if (existing > 0) setRequestProperty("Range", "bytes=$existing-")
            }
            val code = c.responseCode
            if (code in 300..399) {
                val loc = c.getHeaderField("Location") ?: throw HttpError(code, "redirect without Location")
                c.disconnect()
                current = URL(u, loc).toString()
                continue
            }
            conn = c
            break
        }
        val c = conn ?: throw IOException("too many redirects")
        val code = c.responseCode
        when {
            code == 416 -> { // range not satisfiable: .part already complete
                c.disconnect()
                if (part.exists()) part.renameTo(dest)
                onProgress(dest.length(), dest.length())
                return@withContext
            }
            code == 401 || code == 403 -> throw HttpError(code, "Access denied (HTTP $code). Private model? Check the Hugging Face token.")
            code == 404 -> throw HttpError(code, "Not found (HTTP 404). The model file isn't published yet.")
            code !in 200..299 -> throw HttpError(code, "HTTP $code")
        }
        val append = code == 206
        if (!append) existing = 0L
        val total = c.contentLengthLong.let { if (it > 0) it + existing else -1L }

        c.inputStream.use { input ->
            java.io.FileOutputStream(part, append).use { out ->
                val buf = ByteArray(1 shl 16)
                var done = existing
                var lastReport = 0L
                while (true) {
                    ensureActive()
                    val n = input.read(buf)
                    if (n < 0) break
                    out.write(buf, 0, n)
                    done += n
                    if (done - lastReport > (1 shl 20)) { onProgress(done, total); lastReport = done }
                }
                onProgress(done, total)
            }
        }
        c.disconnect()
        if (total > 0 && part.length() != total) throw IOException("Incomplete download (${part.length()} of $total bytes)")
        if (dest.exists()) dest.delete()
        if (!part.renameTo(dest)) throw IOException("Could not move downloaded file into place")
    }
}
