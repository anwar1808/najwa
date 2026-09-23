package ai.najwa.mobile

import android.app.Application
import ai.najwa.mobile.core.ModelCatalog
import ai.najwa.mobile.core.ModelStore
import ai.najwa.mobile.core.Prefs

class NajwaApp : Application() {
    lateinit var prefs: Prefs; private set
    lateinit var models: ModelStore; private set
    lateinit var catalog: ModelCatalog; private set

    override fun onCreate() {
        super.onCreate()
        prefs = Prefs(this)
        models = ModelStore(this)
        catalog = ModelCatalog.fromAssets(this)
    }
}
