package com.dawndrizzle.wing.cqut.widgetbridge

data class DiagnosticExportEntry(val key: String, val name: String, val bytes: Long, val modified: Long, val pending: Boolean = false, val legacy: Boolean = false)

object DiagnosticExportBudget {
  const val MAX_FILE_BYTES = 1024 * 1024
  const val MAX_FILES = 3
  const val MAX_BYTES = 3L * 1024 * 1024
  const val RETENTION_MILLIS = 3L * 24 * 60 * 60 * 1000
  fun deletions(entries: List<DiagnosticExportEntry>, now: Long, reservedBytes: Int = 0, reservedFiles: Int = 0): List<DiagnosticExportEntry> {
    var count = reservedFiles
    var bytes = reservedBytes.toLong()
    return entries.sortedWith(compareByDescending<DiagnosticExportEntry> { it.modified }.thenBy { it.key }).filter { entry ->
      if (entry.legacy || entry.pending || entry.modified < now - RETENTION_MILLIS || entry.bytes > MAX_FILE_BYTES || count >= MAX_FILES || bytes + entry.bytes > MAX_BYTES) true
      else { count++; bytes += entry.bytes; false }
    }
  }
}
