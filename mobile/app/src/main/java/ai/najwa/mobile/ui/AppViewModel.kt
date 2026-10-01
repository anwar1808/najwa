package ai.najwa.mobile.ui

import android.app.Application
import android.net.Uri
import android.os.Build
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import ai.najwa.mobile.NajwaApp
import ai.najwa.mobile.audio.Recorder
import ai.najwa.mobile.core.Auth
import ai.najwa.mobile.core.CatalogEntry
import ai.najwa.mobile.core.Engines
import ai.najwa.mobile.core.ModelSpec
import ai.najwa.mobile.core.Transcriber
import ai.najwa.whisper.DecodeOptions
import ai.najwa.whisper.WhisperContext
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

data class BenchRow(val model: String, val loadMs: Long, val asrMs: Long, val text: String, val error: String? = null)

data class UiState(
    val installed: List<ModelSpec> = emptyList(),
    val activeId: String? = null,
    val activeState: String = "no model",        // "loading…", "ready", "failed: …"
    val recording: Boolean = false,
    val level: Float = 0f,
    val busy: String? = null,                    // e.g. "transcribing…"
    val lastAudioSec: Float = 0f,
    val lastText: String = "",
    val lastAsrMs: Long = 0,
    val bench: List<BenchRow> = emptyList(),
    val downloads: Map<String, Pair<Long, Long>> = emptyMap(), // id → (done, total)
    val errors: List<String> = emptyList(),
    val hfToken: String = "",
    val githubToken: String = "",
    val threads: Int = 0,
)

class AppViewModel(app: Application) : AndroidViewModel(app) {
    private val najwa get() = getApplication<NajwaApp>()
    private val store get() = najwa.models
    private val prefs get() = najwa.prefs
    val catalog get() = najwa.catalog.entries

    private val _state = MutableStateFlow(UiState())
    val state: StateFlow<UiState> = _state

    private val recorder = Recorder()
    private var active: Transcriber? = null
    private var lastPcm: FloatArray? = null
    private val downloadJobs = HashMap<String, Job>()
    private var levelJob: Job? = null

    val threads: Int get() = prefs.threads.takeIf { it > 0 } ?: DecodeOptions.defaultThreads()

    init {
        _state.update { it.copy(hfToken = prefs.hfToken, githubToken = prefs.githubToken, threads = threads) }
        refreshInstalled()
        loadActive()
    }

    // ── Models ────────────────────────────────────────────────────────────

    fun refreshInstalled() {
        val list = store.installed()
        val activeId = prefs.activeModelId?.takeIf { id -> list.any { it.id == id } } ?: list.firstOrNull()?.id
        if (activeId != prefs.activeModelId) prefs.activeModelId = activeId
        _state.update { it.copy(installed = list, activeId = activeId) }
    }

    fun setActive(id: String) {
        if (id == prefs.activeModelId && active != null) return
        prefs.activeModelId = id
        _state.update { it.copy(activeId = id) }
        loadActive()
    }

    private fun loadActive() = viewModelScope.launch {
        val spec = prefs.activeModelId?.let { store.get(it) }
        active?.release(); active = null
        if (spec == null) { _state.update { it.copy(activeState = "no model installed") }; return@launch }
        _state.update { it.copy(activeState = "loading…") }
        runCatching { Engines.load(spec, store.weightsFor(spec)) }
            .onSuccess { t -> active = t; _state.update { it.copy(activeState = "ready") } }
            .onFailure { e -> _state.update { it.copy(activeState = "failed: ${e.message}") } }
    }

    fun setHfToken(token: String) { prefs.hfToken = token; _state.update { it.copy(hfToken = token) } }
    fun setGithubToken(token: String) { prefs.githubToken = token; _state.update { it.copy(githubToken = token.trim()) } }

    fun setThreads(n: Int) { prefs.threads = n; _state.update { it.copy(threads = n) } }

    fun download(entry: CatalogEntry) {
        if (downloadJobs[entry.id]?.isActive == true) return
        downloadJobs[entry.id] = viewModelScope.launch {
            _state.update { it.copy(downloads = it.downloads + (entry.id to (0L to -1L))) }
            runCatching {
                store.install(entry, prefs.hfToken.ifBlank { null }, prefs.githubToken.ifBlank { null }) { done, total ->
                    _state.update { it.copy(downloads = it.downloads + (entry.id to (done to total))) }
                }
            }.onFailure { e -> pushError("${entry.name}: ${e.message}") }
            _state.update { it.copy(downloads = it.downloads - entry.id) }
            refreshInstalled()
            if (active == null) loadActive()
        }
    }

    fun cancelDownload(id: String) { downloadJobs[id]?.cancel() }

    fun downloadUrl(url: String, name: String, language: String) {
        val id = name.lowercase().replace(Regex("[^a-z0-9._-]+"), "-").trim('-').ifBlank { "custom" }
        val auth = when {
            url.contains("api.github.com") -> Auth.GITHUB
            url.contains("huggingface.co") -> Auth.HUGGINGFACE
            else -> Auth.NONE
        }
        download(CatalogEntry(id, name, url, language, 0, auth, "custom URL"))
    }

    fun importUri(uri: Uri, displayName: String, language: String) = viewModelScope.launch {
        _state.update { it.copy(busy = "importing…") }
        runCatching { store.importFromUri(uri, displayName, language) }
            .onFailure { e -> pushError("import: ${e.message}") }
        _state.update { it.copy(busy = null) }
        refreshInstalled()
        if (active == null) loadActive()
    }

    fun delete(id: String) = viewModelScope.launch {
        if (id == prefs.activeModelId) { active?.release(); active = null }
        store.delete(id)
        refreshInstalled()
        loadActive()
    }

    fun setLanguage(id: String, language: String) {
        store.setLanguage(id, language)
        refreshInstalled()
        if (id == prefs.activeModelId) loadActive()
    }

    // ── Dictation ─────────────────────────────────────────────────────────

    fun startRecording() {
        if (_state.value.recording) return
        if (!recorder.start()) { pushError("microphone could not start"); return }
        _state.update { it.copy(recording = true) }
        levelJob = viewModelScope.launch {
            while (_state.value.recording) {
                _state.update { it.copy(level = recorder.level) }
                kotlinx.coroutines.delay(50)
            }
        }
    }

    fun stopRecording() {
        if (!_state.value.recording) return
        val pcm = recorder.stop()
        levelJob?.cancel()
        lastPcm = pcm
        _state.update { it.copy(recording = false, level = 0f, lastAudioSec = pcm.size / 16_000f) }
        transcribeLast()
    }

    private fun transcribeLast() = viewModelScope.launch {
        val pcm = lastPcm ?: return@launch
        val t = active ?: run { pushError("no model loaded"); return@launch }
        _state.update { it.copy(busy = "transcribing…") }
        val t0 = System.nanoTime()
        val text = runCatching { t.transcribe(pcm, threads) }.getOrElse { e -> pushError("transcribe: ${e.message}"); "" }
        val ms = (System.nanoTime() - t0) / 1_000_000
        _state.update { it.copy(busy = null, lastText = text, lastAsrMs = ms) }
    }

    /** Loads every installed model in turn (one at a time, to bound RAM) and runs the last recording through it. */
    fun benchmarkAll() = viewModelScope.launch {
        val pcm = lastPcm ?: run { pushError("record something first"); return@launch }
        val models = store.installed()
        if (models.isEmpty()) { pushError("no models installed"); return@launch }
        active?.release(); active = null
        val rows = ArrayList<BenchRow>()
        _state.update { it.copy(bench = emptyList()) }
        for (spec in models) {
            _state.update { it.copy(busy = "benchmark: ${spec.name}") }
            val t0 = System.nanoTime()
            val t = runCatching { Engines.load(spec, store.weightsFor(spec)) }.getOrElse { e ->
                rows += BenchRow(spec.name, 0, 0, "", "load failed: ${e.message}"); _state.update { it.copy(bench = rows.toList()) }; continue
            }
            val loadMs = (System.nanoTime() - t0) / 1_000_000
            val t1 = System.nanoTime()
            val text = runCatching { t.transcribe(pcm, threads) }.getOrElse { e -> "ERROR: ${e.message}" }
            val asrMs = (System.nanoTime() - t1) / 1_000_000
            t.release()
            rows += BenchRow(spec.name, loadMs, asrMs, text)
            _state.update { it.copy(bench = rows.toList()) }
        }
        _state.update { it.copy(busy = null) }
        loadActive()
    }

    fun resultsReport(): String {
        val s = _state.value
        val sb = StringBuilder()
        sb.appendLine("Najwa Mobile benchmark — " + SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.UK).format(Date()))
        sb.appendLine("Device: ${Build.MANUFACTURER} ${Build.MODEL}, Android ${Build.VERSION.RELEASE}, threads=${threads}")
        sb.appendLine("whisper.cpp: " + runCatching { WhisperContext.systemInfo() }.getOrDefault("?").trim())
        sb.appendLine(String.format(Locale.UK, "Audio: %.1f s", s.lastAudioSec))
        sb.appendLine()
        if (s.bench.isEmpty()) {
            sb.appendLine("Active model: ${s.installed.firstOrNull { it.id == s.activeId }?.name ?: "-"}")
            sb.appendLine("asr_ms=${s.lastAsrMs}")
            sb.appendLine("text: ${s.lastText}")
        } else {
            for (r in s.bench) {
                sb.appendLine("## ${r.model}")
                if (r.error != null) sb.appendLine("error: ${r.error}") else {
                    sb.appendLine("load_ms=${r.loadMs} asr_ms=${r.asrMs}")
                    sb.appendLine("text: ${r.text}")
                }
                sb.appendLine()
            }
        }
        return sb.toString()
    }

    fun pushError(msg: String) { _state.update { it.copy(errors = (it.errors + msg).takeLast(5)) } }
    fun clearErrors() { _state.update { it.copy(errors = emptyList()) } }
}
