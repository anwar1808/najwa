package ai.najwa.mobile.ui

import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import ai.najwa.mobile.core.Auth

private val LANGS = listOf("ms", "en", "auto")

@Composable
fun ModelsScreen(vm: AppViewModel) {
    val s by vm.state.collectAsState()
    val ctx = LocalContext.current
    var token by remember(s.hfToken) { mutableStateOf(s.hfToken) }
    var ghToken by remember(s.githubToken) { mutableStateOf(s.githubToken) }
    var customUrl by remember { mutableStateOf("") }
    var customName by remember { mutableStateOf("") }
    var customLang by remember { mutableStateOf("ms") }
    var importLang by remember { mutableStateOf("ms") }

    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri: Uri? ->
        if (uri == null) return@rememberLauncherForActivityResult
        var name = "imported.bin"
        ctx.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { c ->
            if (c.moveToFirst()) name = c.getString(0) ?: name
        }
        vm.importUri(uri, name, importLang)
    }

    Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(20.dp)) {
        Text("Installed", style = MaterialTheme.typography.titleMedium)
        Spacer(Modifier.height(6.dp))
        if (s.installed.isEmpty()) Text("None yet — download one below.", color = MaterialTheme.colorScheme.secondary)
        for (m in s.installed) {
            Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surface, modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                Row(Modifier.padding(10.dp), verticalAlignment = Alignment.CenterVertically) {
                    RadioButton(selected = m.id == s.activeId, onClick = { vm.setActive(m.id) })
                    Column(Modifier.weight(1f)) {
                        Text(m.name)
                        Text("${m.sizeBytes / 1_048_576} MB · ${m.engine}", color = MaterialTheme.colorScheme.secondary, fontSize = 12.sp)
                    }
                    LangPicker(m.language) { vm.setLanguage(m.id, it) }
                    TextButton(onClick = { vm.delete(m.id) }) { Text("Delete") }
                }
            }
        }

        Spacer(Modifier.height(20.dp))
        Text("Available", style = MaterialTheme.typography.titleMedium)
        Text("The Malaysian (Mesolitica) models live in your private GitHub repo, so they need a GitHub token once. Stock models download without one.", color = MaterialTheme.colorScheme.secondary, fontSize = 12.sp)
        Spacer(Modifier.height(6.dp))
        OutlinedTextField(
            value = ghToken, onValueChange = { ghToken = it },
            label = { Text("GitHub token (github_pat_…)") }, singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            trailingIcon = { TextButton(onClick = { vm.setGithubToken(ghToken) }) { Text(if (ghToken.trim() == s.githubToken && ghToken.isNotBlank()) "saved" else "save") } },
            modifier = Modifier.fillMaxWidth(),
        )
        Text("github.com → Settings → Developer settings → Fine-grained tokens → Generate. Repository access: only anwar1808/najwa. Permissions: Contents → Read-only. Stored only on this phone and sent only to api.github.com.", color = MaterialTheme.colorScheme.secondary, fontSize = 11.sp)
        Spacer(Modifier.height(10.dp))
        OutlinedTextField(
            value = token, onValueChange = { token = it },
            label = { Text("Hugging Face token (optional)") }, singleLine = true,
            visualTransformation = PasswordVisualTransformation(),
            trailingIcon = { TextButton(onClick = { vm.setHfToken(token) }) { Text(if (token == s.hfToken && token.isNotBlank()) "saved" else "save") } },
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(8.dp))
        for (e in vm.catalog) {
            val installed = s.installed.any { it.id == e.id }
            val dl = s.downloads[e.id]
            Surface(shape = RoundedCornerShape(12.dp), color = MaterialTheme.colorScheme.surface, modifier = Modifier.fillMaxWidth().padding(vertical = 4.dp)) {
                Column(Modifier.padding(12.dp)) {
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Column(Modifier.weight(1f)) {
                            Text(e.name)
                            Text("${e.sizeMB} MB · lang ${e.language}" + when (e.auth) { Auth.GITHUB -> " · GitHub token"; Auth.HUGGINGFACE -> " · HF token"; Auth.NONE -> "" }, color = MaterialTheme.colorScheme.secondary, fontSize = 12.sp)
                            if (e.notes.isNotBlank()) Text(e.notes, color = MaterialTheme.colorScheme.secondary, fontSize = 12.sp)
                        }
                        when {
                            installed -> Text("installed", color = MaterialTheme.colorScheme.secondary)
                            dl != null -> TextButton(onClick = { vm.cancelDownload(e.id) }) { Text("cancel") }
                            else -> Button(onClick = { vm.download(e) }, enabled = when (e.auth) {
                                Auth.NONE -> true
                                Auth.GITHUB -> s.githubToken.isNotBlank()
                                Auth.HUGGINGFACE -> s.hfToken.isNotBlank()
                            }) { Text("Get") }
                        }
                    }
                    if (dl != null) {
                        val (done, total) = dl
                        Spacer(Modifier.height(6.dp))
                        if (total > 0) LinearProgressIndicator(progress = { done.toFloat() / total }, modifier = Modifier.fillMaxWidth())
                        else LinearProgressIndicator(modifier = Modifier.fillMaxWidth())
                        Text("${done / 1_048_576} MB" + if (total > 0) " / ${total / 1_048_576} MB" else "", fontSize = 12.sp, color = MaterialTheme.colorScheme.secondary)
                    }
                }
            }
        }

        Spacer(Modifier.height(20.dp))
        Text("Add your own", style = MaterialTheme.typography.titleMedium)
        Text("Any whisper.cpp ggml model (.bin). Paste a direct URL, or pick a file already on the phone.", color = MaterialTheme.colorScheme.secondary, fontSize = 12.sp)
        Spacer(Modifier.height(6.dp))
        OutlinedTextField(value = customUrl, onValueChange = { customUrl = it }, label = { Text("Direct download URL") }, singleLine = true, modifier = Modifier.fillMaxWidth())
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedTextField(value = customName, onValueChange = { customName = it }, label = { Text("Name") }, singleLine = true, modifier = Modifier.weight(1f))
            Spacer(Modifier.width(8.dp))
            LangPicker(customLang) { customLang = it }
            Spacer(Modifier.width(8.dp))
            Button(onClick = { vm.downloadUrl(customUrl.trim(), customName.trim().ifBlank { "custom" }, customLang); customUrl = ""; customName = "" }, enabled = customUrl.startsWith("https://")) { Text("Get") }
        }
        Spacer(Modifier.height(8.dp))
        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedButton(onClick = { picker.launch(arrayOf("*/*")) }, enabled = s.busy == null) { Text("Import file from phone") }
            Spacer(Modifier.width(8.dp))
            LangPicker(importLang) { importLang = it }
        }

        Spacer(Modifier.height(20.dp))
        Text("Decode threads: ${s.threads}", style = MaterialTheme.typography.labelLarge)
        Slider(value = s.threads.toFloat(), onValueChange = { vm.setThreads(it.toInt()) }, valueRange = 1f..8f, steps = 6)
        Text("Fewer threads = big cores only, often faster on big.LITTLE chips. Default 4.", color = MaterialTheme.colorScheme.secondary, fontSize = 12.sp)

        if (s.errors.isNotEmpty()) {
            Spacer(Modifier.height(16.dp))
            for (e in s.errors) Text(e, color = MaterialTheme.colorScheme.error, fontSize = 13.sp)
            TextButton(onClick = { vm.clearErrors() }) { Text("clear") }
        }
        Spacer(Modifier.height(40.dp))
    }
}

@Composable
private fun LangPicker(value: String, onChange: (String) -> Unit) {
    var open by remember { mutableStateOf(false) }
    Box {
        OutlinedButton(onClick = { open = true }) { Text(value) }
        DropdownMenu(expanded = open, onDismissRequest = { open = false }) {
            for (l in LANGS) DropdownMenuItem(text = { Text(l) }, onClick = { onChange(l); open = false })
        }
    }
}
