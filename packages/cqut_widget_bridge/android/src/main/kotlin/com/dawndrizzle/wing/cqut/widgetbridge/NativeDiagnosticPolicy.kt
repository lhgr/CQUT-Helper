package com.dawndrizzle.wing.cqut.widgetbridge

import java.time.Instant
import java.util.UUID

class NativeDiagnosticPolicy(
  private val write: (Map<String, Any?>) -> Boolean,
  private val clock: () -> Long = System::currentTimeMillis,
) {
  private data class Breadcrumb(val time: Long, val event: Map<String, Any?>, val bytes: Int)
  private data class Duplicate(val first: Long, var last: Long, var count: Int, val event: Map<String, Any?>)
  private val breadcrumbs = ArrayDeque<Breadcrumb>()
  private val duplicates = LinkedHashMap<String, Duplicate>()
  private val sessionId = UUID.randomUUID().toString()
  private val operation = ThreadLocal<String?>()
  private val reportedErrors = java.util.WeakHashMap<Throwable, String>()
  private var sequence = 0L
  var version: String = "unknown"
  fun currentOperationId(): String? = operation.get()

  fun <T> withOperation(name: String, operationId: String? = null, action: () -> T): T {
    val previous = operation.get()
    operation.set(operationId?.takeIf { it.isNotBlank() } ?: previous ?: "$name-${UUID.randomUUID()}")
    return try { action() } catch (error: Exception) {
      record("error", "WidgetRefresh", "event=${name}_failed", error)
      throw error
    } finally { operation.set(previous) }
  }

  @Synchronized
  fun record(level: String, module: String, message: String, error: Throwable? = null) {
    val now = clock()
    flushExpired(now)
    trimBreadcrumbs(now)
    val stage = Regex("event=([^\\s]+)").find(message)?.groupValues?.get(1) ?: module
    val operationId = Regex("refreshId=([A-Za-z0-9_-]+)").find(message)?.groupValues?.get(1) ?: operation.get() ?: "$sessionId-native"
    if (level == "debug" || level == "info") {
      val breadcrumb = mapOf<String, Any?>(
        "timestamp" to Instant.ofEpochMilli(now).toString(), "level" to level,
        "module" to module, "stage" to stage, "operationId" to operationId,
        "message" to DiagnosticJson.truncate(DiagnosticJson.redact(message), 2048),
      )
      breadcrumbs.addLast(Breadcrumb(now, breadcrumb, DiagnosticJson.encode(breadcrumb).toByteArray(Charsets.UTF_8).size))
      trimBreadcrumbs(now)
      return
    }
    val rootEventId = error?.let { reportedErrors[it] }
    val event = linkedMapOf<String, Any?>(
      "timestamp" to Instant.ofEpochMilli(now).toString(), "level" to level, "source" to "native",
      "module" to module, "stage" to stage, "sessionId" to sessionId,
      "operationId" to operationId, "eventId" to UUID.randomUUID().toString(),
      "sequence" to ++sequence, "version" to version, "kind" to "error",
      "errorType" to (error?.javaClass?.simpleName ?: stage),
      "message" to DiagnosticJson.truncate(DiagnosticJson.redact(message + (error?.message?.let { ": $it" } ?: "")), 2048),
      "stackTrace" to if (rootEventId != null) "" else DiagnosticJson.truncate(DiagnosticJson.redact((error ?: Throwable(stage)).stackTraceToString()), 8192),
      "outcome" to (Regex("outcome=([A-Za-z_]+)").find(message)?.groupValues?.get(1) ?: if (level == "fatal") "uncaught" else "failed"),
      "fields" to emptyMap<String, Any?>(),
    )
    if (rootEventId != null) event["rootEventId"] = rootEventId
    val normalizedCause = event["message"].toString().replace(
      Regex("(?i)(refreshId|widgetId|account|at|scheduledAt|delayMs|operationId|triggerAt|elapsedMs|durationMs)=[^\\s]+"), "$1=?",
    )
    val fingerprint = java.security.MessageDigest.getInstance("SHA-256")
      .digest("$module:$stage:${event["errorType"]}:$normalizedCause:${error?.stackTrace?.firstOrNull()}".toByteArray(Charsets.UTF_8))
      .joinToString("") { "%02x".format(it) }
    val duplicate = duplicates[fingerprint]
    if (duplicate != null) {
      duplicate.last = now
      duplicate.count++
      if (error != null && rootEventId == null) {
        if (reportedErrors.size >= 128) reportedErrors.clear()
        reportedErrors[error] = duplicate.event["eventId"].toString()
      }
      return
    }
    event["context"] = breadcrumbs.map { it.event }
    event["fingerprint"] = fingerprint
    if (!write(event)) return
    if (error != null && rootEventId == null) {
      if (reportedErrors.size >= 128) reportedErrors.clear()
      reportedErrors[error] = event["eventId"].toString()
    }
    if (duplicates.size >= 128) {
      val oldest = duplicates.entries.first()
      summarize(oldest.key, oldest.value)
      duplicates.remove(oldest.key)
    }
    duplicates[fingerprint] = Duplicate(now, now, 1, event)
  }

  @Synchronized
  fun flush() {
    for ((key, duplicate) in duplicates) summarize(key, duplicate)
    duplicates.clear()
  }

  @Synchronized
  fun clear() { duplicates.clear(); breadcrumbs.clear(); reportedErrors.clear() }

  @Synchronized
  fun flushExpired() = flushExpired(clock())

  private fun flushExpired(now: Long) {
    val expired = duplicates.filterValues { now - it.first >= 60_000 }
    for ((key, duplicate) in expired) { summarize(key, duplicate); duplicates.remove(key) }
  }

  private fun summarize(key: String, duplicate: Duplicate) {
    if (duplicate.count <= 1) return
    write(duplicate.event + mapOf(
      "timestamp" to Instant.ofEpochMilli(duplicate.last).toString(), "eventId" to UUID.randomUUID().toString(),
      "sequence" to ++sequence, "kind" to "summary", "stackTrace" to "", "context" to emptyList<Any>(),
      "rootEventId" to (duplicate.event["rootEventId"] ?: duplicate.event["eventId"]),
      "message" to "Repeated error: ${duplicate.count} occurrences", "fingerprint" to key,
      "repeatCount" to duplicate.count - 1, "totalCount" to duplicate.count,
      "firstSeen" to Instant.ofEpochMilli(duplicate.first).toString(), "lastSeen" to Instant.ofEpochMilli(duplicate.last).toString(),
      "fields" to emptyMap<String, Any?>(),
    ))
  }

  private fun trimBreadcrumbs(now: Long) {
    while (breadcrumbs.isNotEmpty() && (breadcrumbs.size > 64 || breadcrumbs.sumOf { it.bytes } > 64 * 1024 || now - breadcrumbs.first().time > 120_000)) breadcrumbs.removeFirst()
  }
}
