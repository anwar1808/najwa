package ai.najwa.mobile

import android.Manifest
import android.content.pm.PackageManager
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.core.content.ContextCompat
import ai.najwa.mobile.ui.AppViewModel
import ai.najwa.mobile.ui.BenchmarkScreen
import ai.najwa.mobile.ui.ModelsScreen
import ai.najwa.mobile.ui.NajwaTheme

class MainActivity : ComponentActivity() {
    private val vm: AppViewModel by viewModels()
    private var pendingMic: (() -> Unit)? = null
    private val micRequest = registerForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) pendingMic?.invoke() else vm.pushError("microphone permission denied")
        pendingMic = null
    }

    private fun ensureMic(onGranted: () -> Unit) {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) onGranted()
        else { pendingMic = onGranted; micRequest.launch(Manifest.permission.RECORD_AUDIO) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent {
            NajwaTheme {
                var tab by remember { mutableIntStateOf(0) }
                Scaffold { pad ->
                    Column(Modifier.fillMaxSize().padding(pad)) {
                        TabRow(selectedTabIndex = tab) {
                            Tab(selected = tab == 0, onClick = { tab = 0 }, text = { Text("Dictate") })
                            Tab(selected = tab == 1, onClick = { tab = 1 }, text = { Text("Models") })
                        }
                        when (tab) {
                            0 -> BenchmarkScreen(vm, ::ensureMic)
                            else -> ModelsScreen(vm)
                        }
                    }
                }
            }
        }
    }
}
