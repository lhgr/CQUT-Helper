package com.dawndrizzle.wing.cqut.widgetbridge

import java.time.Instant
import java.util.UUID
import java.lang.ref.WeakReference

class NativeDiagnosticPolicy(
  private val write: (Map<String, Any?>) -> Boolean,
  private val clock: () -> Long = System::currentTimeMillis,
) {
  private data class Breadcrumb(val time: Long, val event: Map<String, Any?>, val bytes: Int)
  private data class Duplicate(val first: Long, var last: Long, var count: Int, val event: Map<String, Any?>)
  private data class ReportedError(val error: WeakReference<Throwable>, val operationId: String, val rootEventId: String)
  private data class StackReference(val first: Long, val eventId: String)
  private val breadcrumbs = ArrayDeque<Breadcrumb>()
  private val duplicates = LinkedHashMap<String, Duplicate>()
  private val stackReferences = LinkedHashMap<String, StackReference>()
  private val sessionId = UUID.randomUUID().toString()
  private val operation = ThreadLocal<String?>()
  // Throwable identity, scoped to the operation, establishes causality. A fingerprint only groups similar failures.
  private val reportedErrors = ArrayDeque<ReportedError>()
  private var sequence = 0L
  var version: String = "unknown"
  fun currentOperationId(): String? = operation.get()

  fun <T> withOperation(name: String, operationId: String? = null, action: () -> T): T {
    val previous = operation.get()
    operation.set(operationId?.takeIf { it.isNotBlank() } ?: previous ?: "$name-${UUID.randomUUID()}")
    return try { action() } catch (error: Exception) {
      try { record("error", "WidgetRefresh", "event=${name}_failed", error) } catch (_: Exception) {}
      throw error
    } finally { operation.set(previous) }
  }

  @Synchronized
  fun record(level: String, module: String, message: String, error: Throwable? = null) {
    val now = clock()
    flushExpired(now)
    trimBreadcrumbs(now)
    val stage = Regex("event=([^\\s]+)").find(message)?.groupValues?.get(1) ?: module
    // Callers without an explicit operation share the native session scope; use withOperation for independent work.
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
    reportedErrors.removeAll { it.error.get() == null }
    val previousRoot = error?.let { throwable ->
      reportedErrors.firstOrNull { it.error.get() === throwable && it.operationId == operationId }?.rootEventId
    }
    val eventId = UUID.randomUUID().toString()
    val rootEventId = previousRoot ?: eventId
    val kind = if (error == null) "diagnostic" else if (previousRoot == null) "error" else "outcome"
    val event = linkedMapOf<String, Any?>(
      "timestamp" to Instant.ofEpochMilli(now).toString(), "level" to level, "source" to "native",
      "module" to module, "stage" to stage, "sessionId" to sessionId,
      "operationId" to operationId, "eventId" to eventId,
      "sequence" to ++sequence, "version" to version, "kind" to kind,
      "message" to DiagnosticJson.truncate(DiagnosticJson.redact(message + (error?.message?.let { ": $it" } ?: "")), 2048),
      "stackTrace" to "",
      "outcome" to (Regex("outcome=([A-Za-z_]+)").find(message)?.groupValues?.get(1) ?: if (level == "fatal") "uncaught" else "failed"),
      "fields" to emptyMap<String, Any?>(),
    )
    if (error != null) {
      event["errorType"] = error.javaClass.simpleName
      event["rootEventId"] = rootEventId
    }
    val normalizedCause = event["message"].toString().replace(
      Regex("(?i)(refreshId|widgetId|account|at|scheduledAt|delayMs|operationId|triggerAt|elapsedMs|durationMs)=[^\\s]+"), "$1=?",
    )
    val fingerprint = java.security.MessageDigest.getInstance("SHA-256")
      .digest("$module:$stage:${event["errorType"]}:$normalizedCause:${error?.stackTrace?.firstOrNull()}".toByteArray(Charsets.UTF_8))
      .joinToString("") { "%02x".format(it) }
    // Only repeated reports of the same root and phase may be omitted. Independent roots always remain events.
    val duplicateKey = if (error == null) "$operationId:$fingerprint:$kind:${event["outcome"]}" else "$rootEventId:$module:$stage:$kind:${event["outcome"]}"
    val duplicate = duplicates[duplicateKey]
    if (duplicate != null) {
      duplicate.last = now
      duplicate.count++
      return
    }
    val stackReference = stackReferences[fingerprint]
    if (previousRoot != null) {
      event["stackReferenceEventId"] = rootEventId
    } else if (error != null && stackReference != null) {
      event["stackReferenceEventId"] = stackReference.eventId
    } else if (error != null) {
      event["stackTrace"] = DiagnosticJson.truncate(DiagnosticJson.redact(error.stackTraceToString()), 8192)
    }
    event["context"] = if (event.containsKey("stackReferenceEventId")) emptyList<Any>() else breadcrumbs.filter { it.event["operationId"] == operationId }.map { it.event }
    event["fingerprint"] = fingerprint
    if (!persist(event)) return
    if (error != null && previousRoot == null) {
      if (reportedErrors.size >= 128) reportedErrors.removeFirst()
      reportedErrors.addLast(ReportedError(WeakReference(error), operationId, eventId))
    }
    if (event["stackTrace"] != "") {
      if (stackReferences.size >= 128) stackReferences.remove(stackReferences.keys.first())
      stackReferences[fingerprint] = StackReference(now, eventId)
    }
    if (kind == "error") return
    if (duplicates.size >= 128) {
      val oldest = duplicates.entries.first()
      summarize(oldest.value)
      duplicates.remove(oldest.key)
    }
    duplicates[duplicateKey] = Duplicate(now, now, 1, event)
  }

  @Synchronized
  fun flush() {
    for (duplicate in duplicates.values) summarize(duplicate)
    duplicates.clear()
  }

  @Synchronized
  fun clear() { duplicates.clear(); stackReferences.clear(); breadcrumbs.clear(); reportedErrors.clear() }

  @Synchronized
  fun flushExpired() = flushExpired(clock())

  private fun flushExpired(now: Long) {
    stackReferences.entries.removeAll { now - it.value.first >= 60_000 }
    val expired = duplicates.filterValues { now - it.first >= 60_000 }
    for ((key, duplicate) in expired) { summarize(duplicate); duplicates.remove(key) }
  }

  private fun summarize(duplicate: Duplicate) {
    if (duplicate.count <= 1) return
    persist(duplicate.event + mapOf(
      "timestamp" to Instant.ofEpochMilli(duplicate.last).toString(), "eventId" to UUID.randomUUID().toString(),
      "sequence" to ++sequence, "kind" to "summary", "stackTrace" to "", "context" to emptyList<Any>(),
      "summarizedEventId" to duplicate.event["eventId"],
      "message" to "Repeated ${duplicate.event["kind"]}: ${duplicate.count} occurrences",
      "summarizedKind" to duplicate.event["kind"],
      "repeatCount" to duplicate.count - 1, "totalCount" to duplicate.count,
      "firstSeen" to Instant.ofEpochMilli(duplicate.first).toString(), "lastSeen" to Instant.ofEpochMilli(duplicate.last).toString(),
      "fields" to emptyMap<String, Any?>(),
    ))
  }

  private fun persist(event: Map<String, Any?>): Boolean = try { write(event) } catch (_: Exception) { false }

  private fun trimBreadcrumbs(now: Long) {
    while (breadcrumbs.isNotEmpty() && (breadcrumbs.size > 64 || breadcrumbs.sumOf { it.bytes } > 64 * 1024 || now - breadcrumbs.first().time > 120_000)) breadcrumbs.removeFirst()
  }
}
