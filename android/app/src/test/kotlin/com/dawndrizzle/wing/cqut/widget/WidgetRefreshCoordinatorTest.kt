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
        intArrayOf(8),
        intArrayOf(),
      ),
    )
  }

  @Test
  fun `vertical list count follows configured day without automatic tomorrow preview`() {
    assertEquals("剩余2节", VerticalScheduleWidgetProvider.courseCountText(0, 2))
    assertEquals("共2节", VerticalScheduleWidgetProvider.courseCountText(1, 2))
    assertEquals("", VerticalScheduleWidgetProvider.courseCountText(0, 0))
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
  fun `visible course changes require a full collection rebind`() {
    val previous =
      WidgetRefreshRenderState(
        logicalDate = "2026-08-28",
        presentationSignature = "list:1:NORMAL",
        contentSignature = "course-a",
        renderedAtMillis = 1_000L,
      )
    val current = previous.copy(contentSignature = "course-b", renderedAtMillis = 2_000L)

    assertTrue(WidgetRefreshRenderStateStore.shouldRefresh(previous, current))
    assertTrue(WidgetRefreshRenderStateStore.shouldUseFullUpdate(previous, current))
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

  @Test
  fun `day toggle saves either target before full rebind when refresh is pending`() {
    val previous = WidgetRefreshRenderState("2026-08-28", "course:7:NORMAL", "today")
    val current = previous.copy(logicalDate = "2026-08-29")
    listOf(previous, null).forEach { storedState ->
      listOf(0, 1).forEach { currentOffset ->
        val events = mutableListOf<String>()
        var dayOffset = currentOffset
        val nextOffset = 1 - currentOffset

        WidgetRefreshCoordinator.applyDayToggleRender(
          previous = storedState,
          current = current,
          saveDayOffset = {
            dayOffset = nextOffset
            events += "saved:$dayOffset"
          },
          fullUpdate = { events += "full:$dayOffset" },
          partialUpdate = { events += "partial:$dayOffset" },
          recordRenderedState = { events += "record:$dayOffset" },
        )

        assertEquals(listOf("saved:$nextOffset", "full:$nextOffset"), events)
      }
    }
  }

  @Test
  fun `current same-day toggle stays partial in either direction and records after rendering`() {
    val current = WidgetRefreshRenderState("2026-08-28", "course:7:NORMAL", "today")
    listOf(0, 1).forEach { currentOffset ->
      val events = mutableListOf<String>()
      var dayOffset = currentOffset
      val nextOffset = 1 - currentOffset

      WidgetRefreshCoordinator.applyDayToggleRender(
        previous = current,
        current = current.copy(),
        saveDayOffset = {
          dayOffset = nextOffset
          events += "saved:$dayOffset"
        },
        fullUpdate = { events += "full:$dayOffset" },
        partialUpdate = { events += "partial:$dayOffset" },
        recordRenderedState = { events += "record:$dayOffset" },
      )

      assertEquals(
        listOf("saved:$nextOffset", "partial:$nextOffset", "record:$nextOffset"),
        events,
      )
    }
  }

  @Test
  fun `day toggle preserves pending refresh changes outside the selected widget`() {
    val previous =
      WidgetRefreshRenderState(
        logicalDate = "2026-08-28",
        presentationSignature = "course:7:NORMAL|list:9:NORMAL",
        contentSignature = "course:7:today|list:9:course-a",
      )
    val current =
      previous.copy(
        presentationSignature = "course:7:NORMAL|list:9:STALE",
        contentSignature = "course:7:today|list:9:course-b",
      )
    val events = mutableListOf<String>()
    val offsets = mutableMapOf(7 to 0, 9 to 1)

    WidgetRefreshCoordinator.applyDayToggleRender(
      previous = previous,
      current = current,
      saveDayOffset = {
        offsets[7] = 1
        events += "saved:${offsets[7]}:${offsets[9]}"
      },
      fullUpdate = { events += "full:${offsets[7]}:${offsets[9]}" },
      partialUpdate = { events += "partial:${offsets[7]}:${offsets[9]}" },
      recordRenderedState = { events += "record:${offsets[7]}:${offsets[9]}" },
    )

    assertEquals(listOf("saved:1:1", "full:1:1"), events)
  }
}
