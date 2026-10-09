package com.dawndrizzle.wing.cqut.widgetbridge

import org.junit.Assert.*
import org.junit.Test

class DiagnosticExportBudgetTest {
  private val now = 10L * DiagnosticExportBudget.RETENTION_MILLIS
  private fun entry(index: Int, bytes: Long = 1024L * 1024) = DiagnosticExportEntry("$index", "cqut_diagnostic_$index.log", bytes, now - index)

  @Test
  fun `publication reserves a slot and bytes while keeping latest valid exports`() {
    val entries = (1..3).map { entry(it) }
    assertTrue(DiagnosticExportBudget.deletions(entries, now).isEmpty())
    assertEquals(listOf("3"), DiagnosticExportBudget.deletions(entries, now, reservedBytes = 1024 * 1024, reservedFiles = 1).map { it.key })
    assertEquals(listOf("4"), DiagnosticExportBudget.deletions(entries + entry(4), now).map { it.key })
  }

  @Test
  fun `expired oversized and interrupted pending exports never consume retention slots`() {
    val valid = entry(1)
    val expired = entry(2).copy(modified = now - DiagnosticExportBudget.RETENTION_MILLIS - 1)
    val oversized = entry(3).copy(bytes = DiagnosticExportBudget.MAX_FILE_BYTES + 1L)
    val pending = entry(4).copy(pending = true)
    val legacy = entry(6).copy(name = "cqut_export_old.log.gz.sha256", legacy = true)
    assertEquals(setOf("2", "3", "4", "6"), DiagnosticExportBudget.deletions(listOf(valid, expired, oversized, pending, legacy), now).map { it.key }.toSet())
    val boundary = entry(5).copy(modified = now - DiagnosticExportBudget.RETENTION_MILLIS)
    assertTrue(DiagnosticExportBudget.deletions(listOf(boundary), now).isEmpty())
  }
}
