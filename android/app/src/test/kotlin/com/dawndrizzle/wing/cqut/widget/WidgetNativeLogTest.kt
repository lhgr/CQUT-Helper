package com.dawndrizzle.wing.cqut.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WidgetNativeLogTest {
  @Test
  fun `native log line is export friendly and single line`() {
    val line =
      WidgetNativeLog.formatLine(
        timestampMillis = 0L,
        level = WidgetNativeLogLevel.ERROR,
        tag = "WidgetRefresh",
        message = "event=test\nnext",
        error = IllegalStateException("boom\nagain"),
      )

    assertTrue(line.startsWith("1970-01-01T00:00:00.000Z [ERROR] WidgetRefresh - "))
    assertTrue(line.contains("event=test\\nnext"))
    assertTrue(line.contains("error=IllegalStateException:boom\\nagain"))
    assertFalse(line.contains('\n'))
    assertFalse(line.contains('\r'))
  }

  @Test
  fun `rotation keeps bounded export-compatible names`() {
    assertFalse(WidgetNativeLog.shouldRotate(0L, 20L, 10L))
    assertFalse(WidgetNativeLog.shouldRotate(80L, 20L, 100L))
    assertTrue(WidgetNativeLog.shouldRotate(81L, 20L, 100L))
    assertEquals("cqut_widget_1.log", WidgetNativeLog.archiveFileName(1))
    assertEquals("cqut_widget_2.log", WidgetNativeLog.archiveFileName(2))
  }
}
