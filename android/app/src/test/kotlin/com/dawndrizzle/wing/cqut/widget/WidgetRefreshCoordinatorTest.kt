package com.dawndrizzle.wing.cqut.widget

import android.appwidget.AppWidgetManager
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WidgetRefreshCoordinatorTest {
  @Test
  fun `active widget ids merge providers and discard invalid duplicates`() {
    assertArrayEquals(
      intArrayOf(4, 8, 12),
      WidgetRefreshCoordinator.activeWidgetIds(
        intArrayOf(4, AppWidgetManager.INVALID_APPWIDGET_ID),
        intArrayOf(8, 4),
        intArrayOf(12),
      ),
    )
  }

  @Test
  fun `workmanager recovery uses the minimum periodic interval`() {
    org.junit.Assert.assertEquals(15L, WidgetRefreshRecoveryWork.INTERVAL_MINUTES)
    org.junit.Assert.assertEquals(
      "WidgetRefreshRecovery_Periodic",
      WidgetRefreshRecoveryWork.UNIQUE_WORK_NAME,
    )
  }

  @Test
  fun `first render date rollover and presentation changes use full update`() {
    val normal = WidgetRefreshRenderState("2026-08-28", "list:1:NORMAL")

    assertTrue(WidgetRefreshRenderStateStore.shouldUseFullUpdate(null, normal))
    assertTrue(
      WidgetRefreshRenderStateStore.shouldUseFullUpdate(
        normal,
        normal.copy(logicalDate = "2026-08-29"),
      ),
    )
    assertTrue(
      WidgetRefreshRenderStateStore.shouldUseFullUpdate(
        normal,
        normal.copy(presentationSignature = "list:1:STALE"),
      ),
    )
  }

  @Test
  fun `unchanged render state keeps lightweight partial update`() {
    val state = WidgetRefreshRenderState("2026-08-28", "list:1:NORMAL")

    assertFalse(WidgetRefreshRenderStateStore.shouldUseFullUpdate(state, state.copy()))
  }

  @Test
  fun `visible course changes require repair but remain a partial update`() {
    val previous =
      WidgetRefreshRenderState(
        logicalDate = "2026-08-28",
        presentationSignature = "list:1:NORMAL",
        contentSignature = "course-a",
        renderedAtMillis = 1_000L,
      )
    val current = previous.copy(contentSignature = "course-b", renderedAtMillis = 2_000L)

    assertTrue(WidgetRefreshRenderStateStore.shouldRefresh(previous, current))
    assertFalse(WidgetRefreshRenderStateStore.shouldUseFullUpdate(previous, current))
  }

  @Test
  fun `identical refreshes are coalesced only inside the short window`() {
    val previous =
      WidgetRefreshRenderState(
        logicalDate = "2026-08-28",
        presentationSignature = "list:1:NORMAL",
        contentSignature = "course-a",
        renderedAtMillis = 1_000L,
      )

    assertTrue(
      WidgetRefreshRenderStateStore.shouldCoalesce(
        previous,
        previous.copy(renderedAtMillis = 2_000L),
        WidgetRefreshCoordinator.REFRESH_COALESCE_WINDOW_MILLIS,
      ),
    )
    assertFalse(
      WidgetRefreshRenderStateStore.shouldCoalesce(
        previous,
        previous.copy(renderedAtMillis = 3_000L),
        WidgetRefreshCoordinator.REFRESH_COALESCE_WINDOW_MILLIS,
      ),
    )
    assertFalse(
      WidgetRefreshRenderStateStore.shouldCoalesce(
        previous,
        previous.copy(contentSignature = "course-b", renderedAtMillis = 1_100L),
        WidgetRefreshCoordinator.REFRESH_COALESCE_WINDOW_MILLIS,
      ),
    )
  }

  @Test
  fun `logical date follows Beijing midnight`() {
    val beforeMidnight = java.time.Instant.parse("2026-08-28T15:59:59Z").toEpochMilli()
    val atMidnight = java.time.Instant.parse("2026-08-28T16:00:00Z").toEpochMilli()

    assertEquals("2026-08-28", WidgetRefreshRenderStateStore.logicalDateAtMillis(beforeMidnight))
    assertEquals("2026-08-29", WidgetRefreshRenderStateStore.logicalDateAtMillis(atMidnight))
  }
}
