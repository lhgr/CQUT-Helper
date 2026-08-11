package com.dawndrizzle.wing.cqut.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar

class TodayWidgetDataTest {
  @Test
  fun `covered day without courses shows empty course state`() {
    assertEquals(
      "暂无课程",
      TodayWidgetData.emptyStateTextFor(
        TodayWidgetData.DayScheduleAvailability.COVERED,
      ),
    )
  }

  @Test
  fun `cached schedule outside teaching week is not reported as unsynced`() {
    assertEquals(
      "当前不在教学周",
      TodayWidgetData.emptyStateTextFor(
        TodayWidgetData.DayScheduleAvailability.OUTSIDE_TEACHING_WEEK,
      ),
    )
  }

  @Test
  fun `missing schedule cache asks for synchronization`() {
    assertEquals(
      "课表尚未同步",
      TodayWidgetData.emptyStateTextFor(
        TodayWidgetData.DayScheduleAvailability.MISSING_CACHE,
      ),
    )
  }

  @Test
  fun `same day update only displays time`() {
    val now = Calendar.getInstance().apply { set(2026, Calendar.AUGUST, 11, 18, 30, 0) }
    val updatedAt = Calendar.getInstance().apply { set(2026, Calendar.AUGUST, 11, 9, 5, 0) }

    assertEquals(
      "09:05",
      TodayWidgetData.formatLastUpdated(updatedAt.timeInMillis, now.timeInMillis),
    )
  }

  @Test
  fun `earlier date update only displays calendar day distance`() {
    val now = Calendar.getInstance().apply { set(2026, Calendar.AUGUST, 11, 1, 0, 0) }
    val updatedAt = Calendar.getInstance().apply { set(2026, Calendar.AUGUST, 9, 23, 30, 0) }

    assertEquals(
      "2天前",
      TodayWidgetData.formatLastUpdated(updatedAt.timeInMillis, now.timeInMillis),
    )
  }

  @Test
  fun `custom refresh suggestion controls stale boundary`() {
    val now = 10L * 24 * 60 * 60 * 1000
    val lastUpdated = now - 5L * 24 * 60 * 60 * 1000

    assertTrue(TodayWidgetData.isRefreshStale(lastUpdated, now, 3))
    assertFalse(TodayWidgetData.isRefreshStale(lastUpdated, now, 7))
  }
}
