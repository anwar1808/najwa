package ai.najwa.mobile.core

import android.content.Context
import android.net.Uri
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.File

/** Installed models live under app-private storage; nothing else can read them. */
class ModelStore(private val context: Context) {
    val root: File = File(context.filesDir, "models").apply { mkdirs() }

    fun dirFor(id: String) = File(root, id)
    fun weightsFor(spec: ModelSpec) = File(dirFor(spec.id), spec.file)

    fun installed(): List<ModelSpec> =
        root.listFiles { f -> f.isDirectory }
            ?.mapNotNull { d ->
                val j = File(d, "model.json")
                if (!j.exists()) return@mapNotNull null
                runCatching { ModelSpec.fromJson(j.readText()) }.getOrNull()
                    ?.takeIf { File(d, it.file).exists() }
            }
            ?.sortedBy { it.name } ?: emptyList()

    fun get(id: String): ModelSpec? = installed().firstOrNull { it.id == id }

    fun delete(id: String) { dirFor(id).deleteRecursively() }

    /** Download a catalogue entry (or any URL) into place. */
    suspend fun install(entry: CatalogEntry, hfToken: String?, githubToken: String?, onProgress: (Long, Long) -> Unit): ModelSpec {
        val dir = dirFor(entry.id).apply { mkdirs() }
        val weights = File(dir, "model.bin")
        Downloader.download(entry.url, weights, hfToken, githubToken, onProgress)
        val spec = entry.toSpec(weights.length())
        File(dir, "model.json").writeText(spec.toJson())
        return spec
    }

    /** Copy a model file the user picked from device storage (e.g. a ggml .bin). */
    suspend fun importFromUri(uri: Uri, displayName: String, language: String): ModelSpec = withContext(Dispatchers.IO) {
        val base = displayName.substringBeforeLast('.').ifBlank { "imported" }
        val id = base.lowercase().replace(Regex("[^a-z0-9._-]+"), "-").trim('-')
        val dir = dirFor(id).apply { mkdirs() }
        val weights = File(dir, "model.bin")
        context.contentResolver.openInputStream(uri)!!.use { input ->
            weights.outputStream().use { input.copyTo(it, 1 shl 20) }
        }
        val spec = ModelSpec(id = id, name = displayName, language = language, sizeBytes = weights.length(), source = "imported")
        File(dir, "model.json").writeText(spec.toJson())
        spec
    }

    fun setLanguage(id: String, language: String) {
        val spec = get(id) ?: return
        File(dirFor(id), "model.json").writeText(spec.copy(language = language).toJson())
    }
}
