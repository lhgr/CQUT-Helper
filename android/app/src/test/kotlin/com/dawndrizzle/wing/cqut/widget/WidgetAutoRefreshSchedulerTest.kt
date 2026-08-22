package com.dawndrizzle.wing.cqut.widget

import org.junit.Assert.assertEquals
import org.junit.Test

class WidgetAutoRefreshSchedulerTest {
  @Test
  fun `api 31 uses exact idle alarm when access is available`() {
    assertEquals(
      WidgetAlarmScheduleMode.EXACT_ALLOW_WHILE_IDLE,
      WidgetAutoRefreshScheduler.resolveScheduleMode(31, canScheduleExact = true),
    )
  }

  @Test
  fun `api 31 safely falls back when exact access is unavailable`() {
    assertEquals(
      WidgetAlarmScheduleMode.INEXACT_ALLOW_WHILE_IDLE,
      WidgetAutoRefreshScheduler.resolveScheduleMode(31, canScheduleExact = false),
    )
  }

  @Test
  fun `pre 31 versions use the strongest supported exact alarm`() {
    assertEquals(
      WidgetAlarmScheduleMode.EXACT_ALLOW_WHILE_IDLE,
      WidgetAutoRefreshScheduler.resolveScheduleMode(30, canScheduleExact = false),
    )
    assertEquals(
      WidgetAlarmScheduleMode.EXACT,
      WidgetAutoRefreshScheduler.resolveScheduleMode(22, canScheduleExact = false),
    )
    assertEquals(
      WidgetAlarmScheduleMode.INEXACT,
      WidgetAutoRefreshScheduler.resolveScheduleMode(18, canScheduleExact = false),
    )
  }
}
