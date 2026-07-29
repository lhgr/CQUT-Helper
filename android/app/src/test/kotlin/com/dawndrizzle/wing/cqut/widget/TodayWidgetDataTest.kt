package com.dawndrizzle.wing.cqut.widget

import org.junit.Assert.assertEquals
import org.junit.Test

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
}
