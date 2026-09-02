package com.dawndrizzle.wing.cqut.widget

import android.content.Context
import android.util.Log
import java.io.File
import java.io.FileOutputStream
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

internal enum class WidgetNativeLogLevel {
  INFO,
  WARN,
  ERROR,
}

/**
 * Mirrors widget diagnostics to Logcat and to AppLogger's runtime directory.
 * The latter lets background-only events appear in the normal in-app export
 * without starting Flutter or requesting privileged Logcat access.
 */
internal object WidgetNativeLog {
  private const val DEFAULT_TAG = "WidgetRefresh"
  private const val RUNTIME_DIRECTORY_NAME = ".runtime"
  internal const val FILE_NAME = "cqut_widget.log"
  internal const val MAX_FILE_BYTES = 512L * 1024
  internal const val MAX_ARCHIVES = 2
  private const val MAX_LINE_CHARS = 12_000
  private val utc = TimeZone.getTimeZone("UTC")

  @Suppress("UNUSED_PARAMETER")
  fun debug(
    context: Context,
    message: String,
    tag: String = DEFAULT_TAG,
  ) {
    // High-frequency state probes remain available in Logcat without causing
    // synchronous file I/O in background receivers and periodic workers.
    Log.d(tag, message)
  }

  fun info(
    context: Context,
    message: String,
    tag: String = DEFAULT_TAG,
  ) {
    Log.i(tag, message)
    write(context, WidgetNativeLogLevel.INFO, tag, message, null)
  }

  fun warn(
    context: Context,
    message: String,
    error: Throwable? = null,
    tag: String = DEFAULT_TAG,
  ) {
    if (error == null) Log.w(tag, message) else Log.w(tag, message, error)
    write(context, WidgetNativeLogLevel.WARN, tag, message, error)
  }

  fun error(
    context: Context,
    message: String,
    error: Throwable? = null,
    tag: String = DEFAULT_TAG,
  ) {
    if (error == null) Log.e(tag, message) else Log.e(tag, message, error)
    write(context, WidgetNativeLogLevel.ERROR, tag, message, error)
  }

  @Synchronized
  private fun write(
    context: Context,
    level: WidgetNativeLogLevel,
    tag: String,
    message: String,
    error: Throwable?,
  ) {
    try {
      val directory = File(context.getDir("flutter", Context.MODE_PRIVATE), RUNTIME_DIRECTORY_NAME)
      if (!directory.exists() && !directory.mkdirs()) return
      val current = File(directory, FILE_NAME)
      val line = formatLine(System.currentTimeMillis(), level, tag, message, error) + "\n"
      val bytes = line.toByteArray(Charsets.UTF_8)
      if (shouldRotate(current.length(), bytes.size.toLong(), MAX_FILE_BYTES)) {
        rotate(directory, current)
      }
      FileOutputStream(current, true).use { output ->
        output.write(bytes)
      }
    } catch (writeError: Exception) {
      // Do not recurse through this logger when persistence itself fails.
      Log.e(DEFAULT_TAG, "event=native_log_write_failed", writeError)
    }
  }

  private fun rotate(
    directory: File,
    current: File,
  ) {
    for (index in MAX_ARCHIVES downTo 1) {
      val source = if (index == 1) current else File(directory, archiveFileName(index - 1))
      if (!source.exists()) continue
      val destination = File(directory, archiveFileName(index))
      if (destination.exists()) destination.delete()
      if (!source.renameTo(destination)) {
        source.copyTo(destination, overwrite = true)
        source.delete()
      }
    }
  }

  internal fun formatLine(
    timestampMillis: Long,
    level: WidgetNativeLogLevel,
    tag: String,
    message: String,
    error: Throwable? = null,
  ): String {
    val timestamp =
      SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US).apply {
        timeZone = utc
      }.format(Date(timestampMillis))
    val errorText =
      error?.let {
        " error=${it.javaClass.simpleName}:${it.message.orEmpty()} " +
          "stack=${it.stackTraceToString()}"
      }.orEmpty()
    return "$timestamp [${level.name}] ${singleLine(tag)} - " +
      singleLine(message + errorText)
  }

  internal fun shouldRotate(
    currentBytes: Long,
    incomingBytes: Long,
    maxBytes: Long,
  ): Boolean = currentBytes > 0L && currentBytes + incomingBytes > maxBytes

  internal fun archiveFileName(index: Int): String = "cqut_widget_$index.log"

  private fun singleLine(value: String): String =
    value
      .replace("\r", "\\r")
      .replace("\n", "\\n")
      .replace("\t", "\\t")
      .take(MAX_LINE_CHARS)
}
