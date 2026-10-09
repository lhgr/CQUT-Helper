package com.dawndrizzle.wing.cqut.widgetbridge

import android.content.Context
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.io.File
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/** One process-wide writer for UI engines, background engines and native widgets. */
object CqutDiagnostics {
  private var store: DiagnosticFileStore? = null
  private var exportStore: DiagnosticExportStore? = null
  private var installedHandler = false
  private val policy = NativeDiagnosticPolicy({ event -> persist("native", event) })
  private val timer = Executors.newSingleThreadScheduledExecutor { action -> Thread(action, "cqut-diagnostic-summary").apply { isDaemon = true } }

  init { timer.scheduleAtFixedRate({ try { policy.flushExpired() } catch (_: Exception) {} }, 1, 1, TimeUnit.SECONDS) }

  @Synchronized
  fun initialize(context: Context) {
    if (store != null) return
    val app = context.applicationContext
    val root = File(app.filesDir, "logs")
    store = DiagnosticFileStore(File(root, "diagnostics"))
    exportStore = DiagnosticExportStore(app)
    val preferences = app.getSharedPreferences("cqut_diagnostics", Context.MODE_PRIVATE)
    if (!preferences.getBoolean("bounded_storage_initialized", false)) {
      val legacyRoots = listOf(root, File(app.getDir("flutter", Context.MODE_PRIVATE), ".runtime"), app.getExternalFilesDir(null)?.let { File(it, "logs") })
      for (directory in legacyRoots.filterNotNull()) directory.listFiles()?.filter {
        it.isFile && Regex("cqut.*\\.(log|gz|sha256|sha)$", RegexOption.IGNORE_CASE).matches(it.name)
      }?.forEach { it.delete() }
      preferences.edit().putBoolean("bounded_storage_initialized", true).apply()
    }
    @Suppress("DEPRECATION")
    policy.version = try { app.packageManager.getPackageInfo(app.packageName, 0).versionName ?: "unknown" } catch (_: Exception) { "unknown" }
    store?.prune()
    try { exportStore?.prune() } catch (error: Exception) { Log.e("CqutDiagnostics", "Diagnostic export pruning failed", error) }
    if (!installedHandler) {
      installedHandler = true
      val previous = Thread.getDefaultUncaughtExceptionHandler()
      Thread.setDefaultUncaughtExceptionHandler { thread, error ->
        try { policy.record("fatal", "NativeRuntime", "event=uncaught_exception thread=${thread.name}", error); policy.flush() } catch (_: Throwable) {}
        previous?.uncaughtException(thread, error)
      }
    }
  }

  fun record(context: Context, level: String, module: String, message: String, error: Throwable? = null) {
    try { initialize(context); policy.record(level, module, message, error) } catch (_: Exception) {}
  }

  fun <T> withOperation(name: String, operationId: String? = null, action: () -> T): T = policy.withOperation(name, operationId, action)
  fun operationId(): String? = policy.currentOperationId()

  @Synchronized
  fun persist(source: String, event: Map<String, Any?>): Boolean = try {
    store?.write(source, DiagnosticJson.bounded(event + mapOf("source" to source))) ?: false
  } catch (error: Exception) { Log.e("CqutDiagnostics", "Diagnostic persistence failed", error); false }

  fun snapshot(): List<Map<String, Any?>> {
    policy.flush()
    return synchronized(this) { store?.snapshotLines()?.mapNotNull { line ->
      try { jsonMap(JSONObject(line)) } catch (_: Exception) { null }
    } ?: emptyList() }
  }

  @Synchronized
  fun stats(): Map<String, Any> = store?.stats() ?: mapOf("bytes" to 0L, "files" to 0, "path" to "")
  fun clear(): Int { policy.clear(); return synchronized(this) { store?.clear() ?: 0 } }
  fun prune(): Int { policy.flush(); return synchronized(this) { (store?.prune() ?: 0) + (exportStore?.prune() ?: 0) } }
  @Synchronized
  fun publishExport(fileName: String, content: String): String = exportStore?.publish(fileName, content) ?: throw java.io.IOException("Diagnostics not initialized")
  @Synchronized
  fun exportStats(): Map<String, Any> = exportStore?.stats() ?: mapOf("bytes" to 0L, "files" to 0)
  @Synchronized
  fun pruneExports(): Int = exportStore?.prune() ?: 0
  @Synchronized
  fun clearExports(): Int = exportStore?.clear() ?: 0

  private fun jsonMap(json: JSONObject): Map<String, Any?> = json.keys().asSequence().associateWith { jsonValue(json.get(it)) }
  private fun jsonValue(value: Any?): Any? = when (value) {
    null, JSONObject.NULL -> null
    is JSONObject -> jsonMap(value)
    is JSONArray -> (0 until value.length()).map { jsonValue(value.get(it)) }
    else -> value
  }
}
