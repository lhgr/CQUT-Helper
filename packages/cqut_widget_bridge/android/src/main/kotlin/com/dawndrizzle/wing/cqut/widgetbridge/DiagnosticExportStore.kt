package com.dawndrizzle.wing.cqut.widgetbridge

import android.content.ContentUris
import android.content.ContentValues
import android.content.Context
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.IOException

/** Own generated exports in scoped Downloads storage; no private duplicate or permission prompt. */
class DiagnosticExportStore(private val context: Context, private val clock: () -> Long = System::currentTimeMillis) {
  private val relativePath = "${Environment.DIRECTORY_DOWNLOADS}/CQUT-Helper/log/"
  private val namePattern = Regex("cqut_diagnostic_[^/\\\\]+\\.log")
  private val legacyNamePattern = Regex("cqut_export_[^/\\\\]+\\.log(?:\\.gz)?(?:\\.sha256)?")
  private val localDirectory: File get() = File(context.getExternalFilesDir(Environment.DIRECTORY_DOWNLOADS) ?: context.filesDir, "CQUT-Helper/log")

  @Synchronized
  fun publish(fileName: String, content: String): String {
    require(namePattern.matches(fileName)) { "Invalid diagnostic export filename" }
    val bytes = content.toByteArray(Charsets.UTF_8)
    require(bytes.size <= DiagnosticExportBudget.MAX_FILE_BYTES) { "Diagnostic export exceeds 1 MiB" }
    prune(bytes.size, 1)
    val path = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) publishMediaStore(fileName, bytes) else {
      val directory = localDirectory
      if (!directory.exists() && !directory.mkdirs()) throw IOException("Cannot create diagnostic export directory")
      val file = File(directory, fileName)
      try { file.writeBytes(bytes); file.setLastModified(clock()) } catch (error: Exception) { file.delete(); throw error }
      file.absolutePath
    }
    prune()
    return path
  }

  @Synchronized
  fun stats(): Map<String, Any> {
    prune()
    val entries = entries()
    return mapOf("bytes" to entries.sumOf { it.bytes }, "files" to entries.size)
  }

  @Synchronized
  fun clear(): Int = delete(entries())

  @Synchronized
  fun prune(reservedBytes: Int = 0, reservedFiles: Int = 0): Int = delete(DiagnosticExportBudget.deletions(entries(), clock(), reservedBytes, reservedFiles))

  private fun entries(): List<DiagnosticExportEntry> {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
      val files = localDirectory.listFiles()?.filter { it.isFile && (namePattern.matches(it.name) || legacyNamePattern.matches(it.name)) }.orEmpty().toMutableList()
      // Older public exports are only reachable when the app already has storage access.
      if (context.checkSelfPermission(android.Manifest.permission.WRITE_EXTERNAL_STORAGE) == PackageManager.PERMISSION_GRANTED) {
        @Suppress("DEPRECATION")
        val legacyDirectory = File(Environment.getExternalStoragePublicDirectory(Environment.DIRECTORY_DOWNLOADS), "CQUT-Helper/log")
        try { files.addAll(legacyDirectory.listFiles()?.filter { it.isFile && legacyNamePattern.matches(it.name) }.orEmpty()) } catch (_: SecurityException) {}
      }
      return files.map { DiagnosticExportEntry(it.absolutePath, it.name, it.length(), it.lastModified(), legacy = legacyNamePattern.matches(it.name)) }
    }
    val collection = MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY)
    val columns = arrayOf(MediaStore.MediaColumns._ID, MediaStore.MediaColumns.DISPLAY_NAME, MediaStore.MediaColumns.SIZE,
      MediaStore.MediaColumns.DATE_MODIFIED, MediaStore.MediaColumns.DATE_ADDED, MediaStore.MediaColumns.IS_PENDING)
    val selection = "${MediaStore.MediaColumns.RELATIVE_PATH} = ? AND (${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ? OR ${MediaStore.MediaColumns.DISPLAY_NAME} LIKE ?) AND ${MediaStore.MediaColumns.OWNER_PACKAGE_NAME} = ?"
    val entries = mutableListOf<DiagnosticExportEntry>()
    @Suppress("DEPRECATION")
    val includingPending = MediaStore.setIncludePending(collection)
    context.contentResolver.query(includingPending, columns, selection, arrayOf(relativePath, "cqut_diagnostic_%.log", "cqut_export_%.log%", context.packageName), null)?.use { cursor ->
      while (cursor.moveToNext()) {
        val name = cursor.getString(1)
        if (!namePattern.matches(name) && !legacyNamePattern.matches(name)) continue
        val modified = cursor.getLong(3).takeIf { it > 0 } ?: cursor.getLong(4)
        entries.add(DiagnosticExportEntry(ContentUris.withAppendedId(collection, cursor.getLong(0)).toString(), name, cursor.getLong(2), modified * 1000, cursor.getInt(5) != 0, legacyNamePattern.matches(name)))
      }
    } ?: throw IOException("Cannot query diagnostic exports")
    return entries
  }

  private fun delete(entries: List<DiagnosticExportEntry>): Int {
    for (entry in entries) {
      val deleted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) context.contentResolver.delete(Uri.parse(entry.key), null, null) > 0 else File(entry.key).delete()
      if (!deleted) throw IOException("Cannot remove diagnostic export ${entry.name}")
    }
    return entries.size
  }

  private fun publishMediaStore(fileName: String, bytes: ByteArray): String {
    val values = ContentValues().apply {
      put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
      put(MediaStore.MediaColumns.MIME_TYPE, "text/plain")
      put(MediaStore.MediaColumns.RELATIVE_PATH, relativePath)
      put(MediaStore.MediaColumns.IS_PENDING, 1)
    }
    val resolver = context.contentResolver
    val uri = resolver.insert(MediaStore.Downloads.getContentUri(MediaStore.VOLUME_EXTERNAL_PRIMARY), values)
      ?: throw IOException("Cannot create diagnostic export")
    try {
      resolver.openOutputStream(uri, "w")?.use { it.write(bytes) } ?: throw IOException("Cannot open diagnostic export")
      val published = ContentValues().apply {
        put(MediaStore.MediaColumns.IS_PENDING, 0)
        put(MediaStore.MediaColumns.DATE_MODIFIED, clock() / 1000)
      }
      if (resolver.update(uri, published, null, null) <= 0) throw IOException("Cannot publish diagnostic export")
      val actualName = resolver.query(uri, arrayOf(MediaStore.MediaColumns.DISPLAY_NAME), null, null, null)?.use {
        if (it.moveToFirst()) it.getString(0) else null
      } ?: throw IOException("Cannot verify diagnostic export")
      return "/$relativePath$actualName"
    } catch (error: Exception) {
      try { resolver.delete(uri, null, null) } catch (_: Exception) {}
      throw error
    }
  }
}
