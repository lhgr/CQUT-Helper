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
    assertFalse(written.single().containsKey("rootEventId"))
  }

  @Test
  fun `duplicate storm emits first error then accurate summary at window deadline`() {
    var now = 1000L
    val written = mutableListOf<Map<String, Any?>>()
    val policy = NativeDiagnosticPolicy({ written.add(it) }) { now }
    val error = IllegalStateException("failed")
    repeat(100) { policy.record("error", "Widget", "event=render_failed", error); now++ }
    assertEquals(1, written.size)
    now = 61_000
    policy.flushExpired()
    assertEquals(2, written.size)
    assertEquals(100, written.last()["totalCount"])
    assertEquals(99, written.last()["repeatCount"])
    assertEquals(written.first()["eventId"], written.last()["rootEventId"])
    assertEquals("1970-01-01T00:00:01Z", written.last()["firstSeen"])
    policy.flush()
    assertEquals(2, written.size)
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
    assertEquals(written.first()["eventId"], written.last()["rootEventId"])
  }
}
