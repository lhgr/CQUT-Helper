package com.dawndrizzle.wing.cqut.widgetbridge

import java.io.File
import java.io.FileOutputStream
import java.time.Instant
import java.time.ZoneOffset

/** Fixed slots, including the active file. All callers share one serialized writer. */
class DiagnosticFileStore(private val directory: File, private val clock: () -> Long = System::currentTimeMillis) {
  companion object {
    const val FILE_BYTES = 256 * 1024
    const val EVENT_BYTES = 16 * 1024
    const val RETENTION_MILLIS = 3L * 24 * 60 * 60 * 1000
    val capacities = mapOf("foreground" to 4, "background" to 2, "native" to 2)
    private val timestampPattern = Regex("\"timestamp\"\\s*:\\s*\"([^\"]+)\"")
    fun timestamp(line: String): Long? = try {
      timestampPattern.find(line)?.groupValues?.get(1)?.let { Instant.parse(it).toEpochMilli() }
    } catch (_: Exception) { null }
  }

  @Synchronized
  fun write(source: String, line: String): Boolean {
    val count = capacities[source] ?: return false
    val bytes = (line + "\n").toByteArray(Charsets.UTF_8)
    if (bytes.size > EVENT_BYTES || line.contains('\n') || timestamp(line) == null) return false
    val now = clock()
    if (timestamp(line)!! < now - RETENTION_MILLIS) return false
    directory.mkdirs()
    prune()
    val current = slot(source, 0)
    val dayChanged = current.exists() && day(current.lastModified()) != day(now)
    if (current.length() > 0 && (current.length() + bytes.size > FILE_BYTES || dayChanged)) {
      for (index in count - 1 downTo 1) {
        val previous = slot(source, index - 1)
        val destination = slot(source, index)
        if (destination.exists() && !destination.delete()) throw java.io.IOException("Cannot release diagnostic slot")
        if (previous.exists() && !previous.renameTo(destination)) throw java.io.IOException("Cannot rotate diagnostic slot")
      }
    }
    FileOutputStream(current, true).use { it.write(bytes) }
    current.setLastModified(now)
    return true
  }

  @Synchronized
  fun snapshotLines(): List<String> {
    prune()
    val cutoff = clock() - RETENTION_MILLIS
    return files().flatMap { file -> file.useLines { lines ->
      lines.filter { (timestamp(it) ?: Long.MIN_VALUE) >= cutoff }.toList()
    } }.sortedBy { timestamp(it) }
  }

  @Synchronized
  fun stats(): Map<String, Any> = mapOf("bytes" to files().sumOf { it.length() }, "files" to files().size, "path" to directory.absolutePath)

  @Synchronized
  fun clear(): Int = files().count { it.delete() }

  @Synchronized
  fun prune(): Int {
    val cutoff = clock() - RETENTION_MILLIS
    var deleted = 0
    for (file in files()) {
      val modified = file.lastModified()
      if (modified < cutoff) {
        if (file.delete()) deleted++
      } else if (modified - 24 * 60 * 60 * 1000L < cutoff) {
        val existing = file.readLines()
        val kept = existing.filter { (timestamp(it) ?: Long.MIN_VALUE) >= cutoff }
        if (kept.size != existing.size) {
          if (kept.isEmpty()) { if (file.delete()) deleted++ }
          else { file.writeText(kept.joinToString("\n", postfix = "\n")); file.setLastModified(modified) }
        }
      }
    }
    return deleted
  }

  private fun files(): List<File> = directory.listFiles()?.filter { it.isFile && Regex("(foreground|background|native)-[0-3]\\.jsonl").matches(it.name) } ?: emptyList()
  private fun slot(source: String, index: Int) = File(directory, "$source-$index.jsonl")
  private fun day(time: Long) = Instant.ofEpochMilli(time).atOffset(ZoneOffset.UTC).toLocalDate()
}

/** Small JSON encoder independent of Android's mockable org.json classes. */
object DiagnosticJson {
  private val privateKey = Regex("(?i)^(password|passwd|token|authorization|cookie|secret|access_?token|refresh_?token|set-cookie)$")
  private val bodyKey = Regex("(?i)^(request_?body|response_?body|course_?data|timetable_?data)$")
  private fun sanitized(value: Any?): Any? = when (value) {
    is Map<*, *> -> value.entries.associate { entry ->
      val key = entry.key.toString()
      key to when { privateKey.matches(key) -> "[redacted]"; bodyKey.matches(key) -> "[omitted]"; else -> sanitized(entry.value) }
    }
    is Iterable<*> -> value.map { sanitized(it) }
    is String -> redact(value)
    else -> value
  }
  fun encode(value: Any?): String = when (value) {
    null -> "null"
    is String -> buildString {
      append('"')
      for (char in value) when (char) {
        '"' -> append("\\\""); '\\' -> append("\\\\"); '\n' -> append("\\n"); '\r' -> append("\\r"); '\t' -> append("\\t")
        else -> if (char.code < 32) append("\\u%04x".format(char.code)) else append(char)
      }
      append('"')
    }
    is Map<*, *> -> value.entries.joinToString(",", "{", "}") { encode(it.key.toString()) + ":" + encode(it.value) }
    is Iterable<*> -> value.joinToString(",", "[", "]") { encode(it) }
    is Number, is Boolean -> value.toString()
    else -> encode(value.toString())
  }

  fun truncate(value: String, limit: Int): String {
    if (value.toByteArray(Charsets.UTF_8).size <= limit) return value
    val suffix = " [truncated]"
    var low = 0
    var high = value.length
    while (low < high) {
      val middle = (low + high + 1) / 2
      if (value.substring(0, middle).toByteArray(Charsets.UTF_8).size + suffix.length <= limit) low = middle else high = middle - 1
    }
    if (low > 0 && Character.isHighSurrogate(value[low - 1])) low--
    return value.substring(0, low) + suffix
  }

  fun redact(value: String): String = value.replace(
    Regex("(?i)(password|passwd|token|authorization|cookie|secret|access_token|refresh_token)([\\s=:]+)([^\\s&,;]+)"), "$1$2[redacted]",
  ).replace(Regex("(?i)Bearer\\s+[^\\s,;]+"), "Bearer [redacted]")

  /** Reserve stack space before reducing breadcrumbs and optional fields. */
  fun bounded(event: Map<String, Any?>): String {
    val result = LinkedHashMap<String, Any?>()
    event.forEach { (key, value) -> result[key] = sanitized(value) }
    result["stackTrace"] = truncate(redact(event["stackTrace"]?.toString().orEmpty()), 8 * 1024)
    result["message"] = truncate(redact(event["message"]?.toString().orEmpty()), 2048)
    for (key in listOf("module", "stage", "errorType", "outcome", "sessionId", "operationId", "version")) {
      result[key] = truncate(redact(event[key]?.toString().orEmpty()), 256)
    }
    var line = encode(result)
    val context = (result["context"] as? List<*>)?.toMutableList()
    while (line.toByteArray(Charsets.UTF_8).size + 1 > DiagnosticFileStore.EVENT_BYTES && !context.isNullOrEmpty()) {
      context.removeAt(0)
      result["context"] = context
      result["contextTruncated"] = true
      line = encode(result)
    }
    if (line.toByteArray(Charsets.UTF_8).size + 1 > DiagnosticFileStore.EVENT_BYTES) {
      result["fields"] = mapOf("truncated" to true)
      line = encode(result)
    }
    // JSON escaping can expand a stack substantially; reduce encoded size, not only raw bytes.
    while (line.toByteArray(Charsets.UTF_8).size + 1 > DiagnosticFileStore.EVENT_BYTES && result["stackTrace"].toString().length > 100) {
      result["stackTrace"] = truncate(result["stackTrace"].toString(), result["stackTrace"].toString().toByteArray(Charsets.UTF_8).size / 2)
      line = encode(result)
    }
    return line
  }
}
