package ai.najwa.mobile.ui

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.widget.Toast
import androidx.compose.foundation.background
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

@Composable
fun BenchmarkScreen(vm: AppViewModel, ensureMic: (onGranted: () -> Unit) -> Unit) {
    val s by vm.state.collectAsState()
    val ctx = LocalContext.current
    val activeName = s.installed.firstOrNull { it.id == s.activeId }?.name ?: "—"

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp)) {
        Text("Model", style = MaterialTheme.typography.labelMedium, color = MaterialTheme.colorScheme.secondary)
        Text(activeName, style = MaterialTheme.typography.titleMedium)
        Text(s.activeState, color = if (s.activeState.startsWith("failed")) MaterialTheme.colorScheme.error else MaterialTheme.colorScheme.secondary)
        Spacer(Modifier.height(24.dp))

        // Hold-to-talk. Press = record, release = transcribe.
        Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
            val ring = 0.35f + s.level.coerceIn(0f, 1f) * 0.65f
            Box(
                Modifier
                    .size(180.dp)
                    .background(
                        if (s.recording) Color(0xFFF4F4F5).copy(alpha = 0.10f + 0.25f * ring) else MaterialTheme.colorScheme.surfaceVariant,
                        CircleShape,
                    )
                    .pointerInput(s.activeState) {
                        detectTapGestures(onPress = {
                            if (s.activeState != "ready") return@detectTapGestures
                            var started = false
                            ensureMic { vm.startRecording(); started = true }
                            tryAwaitRelease()
                            if (started || vm.state.value.recording) vm.stopRecording()
                        })
                    },
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    if (s.recording) "listening…" else if (s.busy != null) s.busy!! else "hold to dictate",
                    textAlign = TextAlign.Center, style = MaterialTheme.typography.titleMedium,
                )
            }
        }
        Spacer(Modifier.height(20.dp))

        if (s.lastAudioSec > 0f) {
            Text(
                if (s.busy != null) String.format("%.1f s audio · transcribing…", s.lastAudioSec)
                else String.format("%.1f s audio · %d ms", s.lastAudioSec, s.lastAsrMs),
                color = MaterialTheme.colorScheme.secondary,
            )
            Spacer(Modifier.height(6.dp))
            Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surface, modifier = Modifier.fillMaxWidth()) {
                Text(if (s.lastText.isBlank()) "(heard nothing)" else s.lastText, Modifier.padding(14.dp), fontSize = 17.sp)
            }
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                OutlinedButton(onClick = { copy(ctx, s.lastText) }, enabled = s.busy == null && s.lastText.isNotBlank()) { Text("Copy text") }
                Button(onClick = { vm.benchmarkAll() }, enabled = s.busy == null && s.installed.isNotEmpty()) {
                    Text("Run all ${s.installed.size} models on this")
                }
            }
        }

        if (s.bench.isNotEmpty()) {
            Spacer(Modifier.height(20.dp))
            Text("Benchmark", style = MaterialTheme.typography.titleMedium)
            Spacer(Modifier.height(6.dp))
            for (r in s.bench) {
                Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surface, modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                    Column(Modifier.padding(12.dp)) {
                        Text(r.model, style = MaterialTheme.typography.labelLarge)
                        if (r.error != null) Text(r.error, color = MaterialTheme.colorScheme.error)
                        else {
                            Text("load ${r.loadMs} ms · asr ${r.asrMs} ms", color = MaterialTheme.colorScheme.secondary, fontFamily = FontFamily.Monospace, fontSize = 12.sp)
                            Text(r.text.ifBlank { "(heard nothing)" })
                        }
                    }
                }
            }
        }

        if (s.lastAudioSec > 0f) {
            Spacer(Modifier.height(16.dp))
            Button(onClick = { copy(ctx, vm.resultsReport()); Toast.makeText(ctx, "Results copied", Toast.LENGTH_SHORT).show() },
                   enabled = s.busy == null, modifier = Modifier.fillMaxWidth()) {
                Text(if (s.busy != null) "Working… (${s.busy})" else "Copy results for Claude")
            }
        }

        if (s.errors.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            for (e in s.errors) Text(e, color = MaterialTheme.colorScheme.error, fontSize = 13.sp)
            TextButton(onClick = { vm.clearErrors() }) { Text("clear") }
        }
        Spacer(Modifier.height(40.dp))
    }
}

private fun copy(ctx: Context, text: String) {
    val cm = ctx.getSystemService(Context.CLIPBOARD_SERVICE) as ClipboardManager
    cm.setPrimaryClip(ClipData.newPlainText("Najwa", text))
}
