package ai.najwa.mobile.core

import android.content.Context

/** App-private preferences. The HF token only ever goes to huggingface.co (see Downloader). */
class Prefs(context: Context) {
    private val sp = context.getSharedPreferences("najwa", Context.MODE_PRIVATE)

    var activeModelId: String?
        get() = sp.getString("activeModelId", null)
        set(v) = sp.edit().putString("activeModelId", v).apply()

    var hfToken: String
        get() = sp.getString("hfToken", "") ?: ""
        set(v) = sp.edit().putString("hfToken", v.trim()).apply()

    var threads: Int
        get() = sp.getInt("threads", 0)
        set(v) = sp.edit().putInt("threads", v).apply()
}
