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
  fun `heartbeat recognizes its stable job id`() {
    assertFalse(WidgetRefreshHeartbeatJobService.hasPendingJob(listOf(1, 2, 3)))
    assertTrue(
      WidgetRefreshHeartbeatJobService.hasPendingJob(
        listOf(1, WidgetRefreshHeartbeatJobService.JOB_ID, 3),
      ),
    )
  }

  @Test
  fun `heartbeat uses android minimum periodic interval`() {
    assertEquals(
      15L * 60 * 1000,
      WidgetRefreshHeartbeatJobService.INTERVAL_MILLIS,
    )
  }
}
