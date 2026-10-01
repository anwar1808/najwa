package ai.najwa.mobile.core

import org.json.JSONObject

/**
 * One installed model = a folder `<filesDir>/models/<id>/` holding the weights
 * and this descriptor as `model.json`. Swapping models is picking a different
 * folder; nothing in the app is tied to a specific model.
 */
data class ModelSpec(
    val id: String,
    val name: String,
    val engine: String = "whisper.cpp",
    val file: String = "model.bin",
    /** Whisper language code or "auto" (default; "ms" only when you want Malay forced). */
    val language: String = "auto",
    val sizeBytes: Long = 0,
    val source: String = "",
    val notes: String = "",
) {
    fun toJson(): String = JSONObject().apply {
        put("id", id); put("name", name); put("engine", engine); put("file", file)
        put("language", language); put("sizeBytes", sizeBytes); put("source", source); put("notes", notes)
    }.toString(2)

    companion object {
        fun fromJson(s: String): ModelSpec {
            val o = JSONObject(s)
            return ModelSpec(
                id = o.getString("id"),
                name = o.optString("name", o.getString("id")),
                engine = o.optString("engine", "whisper.cpp"),
                file = o.optString("file", "model.bin"),
                language = o.optString("language", "auto"),
                sizeBytes = o.optLong("sizeBytes", 0),
                source = o.optString("source", ""),
                notes = o.optString("notes", ""),
            )
        }
    }
}

/** Which credential a download needs. Tokens are only ever sent to their own host. */
enum class Auth { NONE, HUGGINGFACE, GITHUB }

/** A downloadable entry from the bundled catalogue (assets/models.json). */
data class CatalogEntry(
    val id: String,
    val name: String,
    val url: String,
    val language: String,
    val sizeMB: Int,
    val auth: Auth,
    val notes: String,
) {
    fun toSpec(sizeBytes: Long) = ModelSpec(
        id = id, name = name, language = language, sizeBytes = sizeBytes, source = url, notes = notes,
    )
}
