package com.dawndrizzle.wing.cqut.widget

import com.dawndrizzle.wing.cqut.widgetbridge.NativeDiagnosticPolicy
import org.junit.Assert.*
import org.junit.Test

class WidgetNativeLogTest {
  @Test
  fun `normal widget refresh remains memory only while a failure includes recent context`() {
    val written = mutableListOf<Map<String, Any?>>()
    val policy = NativeDiagnosticPolicy({ written.add(it) }) { 1_000L }
    policy.withOperation("widget_refresh") {
      policy.record("info", "WidgetRefresh", "event=render_started widgets=2")
      assertTrue(written.isEmpty())
      policy.record("error", "WidgetRefresh", "event=render_failed", IllegalStateException("launcher failed"))
    }
    assertEquals(1, written.size)
    assertTrue(written.single()["stackTrace"].toString().contains("IllegalStateException"))
    val breadcrumb = (written.single()["context"] as List<*>).single() as Map<*, *>
    assertEquals(breadcrumb["operationId"], written.single()["operationId"])
  }
}
