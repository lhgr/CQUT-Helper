package com.dawndrizzle.wing.cqut.widgetbridge

import org.junit.Assert.*
import org.junit.Test

class NativeDiagnosticPolicyTest {
  @Test
  fun `failed persistence does not suppress the next complete error`() {
    var succeeds = false
    val written = mutableListOf<Map<String, Any?>>()
    val policy = NativeDiagnosticPolicy({ event -> if (succeeds) written.add(event) else false }) { 1_000L }
    val error = IllegalStateException("failed")
    policy.record("error", "Widget", "event=render_failed", error)
    succeeds = true
    policy.record("error", "Widget", "event=render_failed", error)
    assertEquals(1, written.size)
    assertTrue(written.single()["stackTrace"].toString().contains("IllegalStateException"))
    assertEquals("error", written.single()["kind"])
    assertEquals(written.single()["eventId"], written.single()["rootEventId"])
  }

  @Test
  fun `repeated propagation emits one root one outcome and metadata for omitted outcomes`() {
    var now = 1000L
    val written = mutableListOf<Map<String, Any?>>()
    val policy = NativeDiagnosticPolicy({ written.add(it) }) { now }
    val error = IllegalStateException("failed")
    repeat(100) { policy.record("error", "Widget", "event=render_failed", error); now++ }
    assertEquals(listOf("error", "outcome"), written.map { it["kind"] })
    now = 61_001
    policy.flushExpired()
    assertEquals(3, written.size)
    assertEquals("summary", written.last()["kind"])
    assertEquals("outcome", written.last()["summarizedKind"])
    assertEquals(99, written.last()["totalCount"])
    assertEquals(98, written.last()["repeatCount"])
    assertEquals(written.first()["eventId"], written.last()["rootEventId"])
    assertEquals("1970-01-01T00:00:01.001Z", written.last()["firstSeen"])
    assertEquals("", written.last()["stackTrace"])
    assertTrue((written.last()["context"] as List<*>).isEmpty())
    policy.flush()
    assertEquals(3, written.size)
  }

  @Test
  fun `context expires and excludes routine stacks while reused throwable links one root`() {
    var now = 1000L
    val written = mutableListOf<Map<String, Any?>>()
    val policy = NativeDiagnosticPolicy({ written.add(it) }) { now }
    policy.record("info", "Widget", "event=old")
    now += 120_001
    policy.record("info", "Widget", "event=new token=private123")
    val error = IllegalArgumentException("boom")
    policy.record("error", "Widget", "event=parse_failed", error)
    policy.record("error", "Widget", "event=refresh_failed", error)
    val context = (written.first()["context"] as List<*>).single() as Map<*, *>
    assertFalse(context.containsKey("stackTrace"))
    assertFalse(context["message"].toString().contains("private123"))
    assertEquals("", written.last()["stackTrace"])
    assertEquals("outcome", written.last()["kind"])
    assertEquals(written.first()["eventId"], written.last()["rootEventId"])
    assertTrue((written.last()["context"] as List<*>).isEmpty())
  }

  @Test
  fun `equal fingerprints keep every independent root and share only persisted stack context`() {
    val written = mutableListOf<Map<String, Any?>>()
    val policy = NativeDiagnosticPolicy({ written.add(it) }) { 1_000L }
    policy.record("info", "Widget", "event=before_parse")
    repeat(100) {
      policy.record("error", "Widget", "event=parse_failed", identicalFailure())
    }
    policy.flush()
    assertEquals(100, written.size)
    assertEquals(1, written.map { it["fingerprint"] }.toSet().size)
    assertEquals(100, written.map { it["rootEventId"] }.toSet().size)
    assertTrue(written.all { it["kind"] == "error" && it["eventId"] == it["rootEventId"] })
    assertTrue(written.first()["stackTrace"].toString().contains("IllegalStateException"))
    assertEquals(1, (written.first()["context"] as List<*>).size)
    written.drop(1).forEach {
      assertEquals(written.first()["eventId"], it["stackReferenceEventId"])
      assertEquals("", it["stackTrace"])
      assertTrue((it["context"] as List<*>).isEmpty())
    }
  }

  @Test
  fun `throwable identity cannot link roots across operations`() {
    val written = mutableListOf<Map<String, Any?>>()
    val policy = NativeDiagnosticPolicy({ written.add(it) }) { 1_000L }
    val error = identicalFailure()
    policy.withOperation("render", "one") {
      policy.record("error", "Widget", "event=parse_failed", error)
      policy.record("error", "Widget", "event=render_failed", error)
    }
    policy.withOperation("render", "two") {
      policy.record("error", "Widget", "event=parse_failed", error)
      policy.record("error", "Widget", "event=render_failed", error)
    }
    assertEquals(listOf("error", "outcome", "error", "outcome"), written.map { it["kind"] })
    assertNotEquals(written[0]["rootEventId"], written[2]["rootEventId"])
    assertEquals(written[2]["eventId"], written[3]["rootEventId"])
    assertNull(policy.currentOperationId())
  }

  @Test
  fun `failure context contains only breadcrumbs from its operation`() {
    val written = mutableListOf<Map<String, Any?>>()
    val policy = NativeDiagnosticPolicy({ written.add(it) }) { 1_000L }
    policy.withOperation("render", "one") { policy.record("info", "Widget", "event=unrelated") }
    policy.withOperation("render", "two") {
      policy.record("info", "Widget", "event=related")
      policy.record("error", "Widget", "event=parse_failed", identicalFailure())
    }
    val context = written.single()["context"] as List<*>
    assertEquals(1, context.size)
    assertEquals("related", (context.single() as Map<*, *>)["stage"])
  }

  @Test
  fun `warnings without exceptions remain diagnostics without manufactured error identity`() {
    val written = mutableListOf<Map<String, Any?>>()
    val policy = NativeDiagnosticPolicy({ written.add(it) }) { 1_000L }
    repeat(3) { policy.record("warn", "Widget", "event=refresh_skipped outcome=skipped") }
    policy.flush()
    assertEquals(listOf("diagnostic", "summary"), written.map { it["kind"] })
    assertEquals("diagnostic", written.last()["summarizedKind"])
    assertEquals(2, written.last()["repeatCount"])
    written.forEach {
      assertFalse(it.containsKey("errorType"))
      assertFalse(it.containsKey("rootEventId"))
      assertEquals("", it["stackTrace"])
    }
  }

  @Test
  fun `throwable equals implementation cannot merge independent failures`() {
    val written = mutableListOf<Map<String, Any?>>()
    val policy = NativeDiagnosticPolicy({ written.add(it) }) { 1_000L }
    class EqualFailure : IllegalStateException("same") {
      override fun equals(other: Any?) = other is EqualFailure
      override fun hashCode() = 1
    }
    repeat(2) { policy.record("error", "Widget", "event=parse_failed", EqualFailure()) }
    assertEquals(listOf("error", "error"), written.map { it["kind"] })
    assertNotEquals(written[0]["rootEventId"], written[1]["rootEventId"])
  }

  @Test
  fun `outcome stages stay separate and stack window expires`() {
    val written = mutableListOf<Map<String, Any?>>()
    var now = 1_000L
    val policy = NativeDiagnosticPolicy({ written.add(it) }) { now }
    val error = identicalFailure()
    policy.record("error", "Widget", "event=parse_failed", error)
    repeat(3) { policy.record("error", "Widget", "event=render_failed", error) }
    repeat(2) { policy.record("error", "Widget", "event=refresh_failed", error) }
    now = 61_000L
    policy.record("error", "Widget", "event=parse_failed", identicalFailure())
    val summaries = written.filter { it["kind"] == "summary" }
    assertEquals(listOf(2, 1), summaries.map { it["repeatCount"] })
    assertEquals(listOf("render_failed", "refresh_failed"), summaries.map { it["stage"] })
    assertEquals("error", written.last()["kind"])
    assertTrue(written.last()["stackTrace"].toString().isNotEmpty())
    assertFalse(written.last().containsKey("stackReferenceEventId"))
  }

  @Test
  fun `diagnostic write failure preserves business exception and retries complete root`() {
    val error = identicalFailure()
    var throws = true
    val written = mutableListOf<Map<String, Any?>>()
    val policy = NativeDiagnosticPolicy({ if (throws) throw IllegalStateException("disk") else written.add(it) }) { 1_000L }
    try {
      policy.withOperation("render", "one") { throw error }
      fail("The business failure must propagate")
    } catch (caught: IllegalStateException) {
      assertSame(error, caught)
    }
    assertNull(policy.currentOperationId())
    throws = false
    policy.withOperation("render", "one") { policy.record("error", "Widget", "event=render_failed", error) }
    assertEquals("error", written.single()["kind"])
    assertTrue(written.single()["stackTrace"].toString().isNotEmpty())
  }

  private fun identicalFailure() = IllegalStateException("failed").apply {
    stackTrace = arrayOf(StackTraceElement("Parser", "parse", "Parser.kt", 12))
  }
}
