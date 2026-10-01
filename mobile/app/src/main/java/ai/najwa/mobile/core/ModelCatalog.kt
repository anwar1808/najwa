package ai.najwa.mobile.core

import android.content.Context
import org.json.JSONObject

class ModelCatalog(val entries: List<CatalogEntry>) {
    companion object {
        fun fromAssets(context: Context, name: String = "models.json"): ModelCatalog {
            val text = context.assets.open(name).bufferedReader().use { it.readText() }
            val arr = JSONObject(text).getJSONArray("models")
            val list = (0 until arr.length()).map { i ->
                val o = arr.getJSONObject(i)
                CatalogEntry(
                    id = o.getString("id"),
                    name = o.getString("name"),
                    url = o.getString("url"),
                    language = o.optString("language", "ms"),
                    sizeMB = o.optInt("sizeMB", 0),
                    auth = when (o.optString("auth", "none")) {
                        "github" -> Auth.GITHUB
                        "huggingface" -> Auth.HUGGINGFACE
                        else -> Auth.NONE
                    },
                    notes = o.optString("notes", ""),
                )
            }
            return ModelCatalog(list)
        }
    }
}
