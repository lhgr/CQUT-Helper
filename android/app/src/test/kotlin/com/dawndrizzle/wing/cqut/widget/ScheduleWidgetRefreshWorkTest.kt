package com.dawndrizzle.wing.cqut.widget

import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ScheduleWidgetRefreshWorkTest {
  @Test
  fun `first click is accepted`() {
    assertTrue(ScheduleWidgetRefreshWork.shouldAcceptClick(null, 0L, 1_000L))
  }

  @Test
  fun `rapid repeated click is deduplicated`() {
    assertFalse(ScheduleWidgetRefreshWork.shouldAcceptClick("refresh-1", 1_000L, 1_100L))
  }

  @Test
  fun `stale lease can be recovered`() {
    assertTrue(
      ScheduleWidgetRefreshWork.shouldAcceptClick(
        "refresh-1",
        1_000L,
        16L * 60 * 1_000L,
      ),
    )
  }

  @Test
  fun `display fingerprint changes only with visible schedule input`() {
    val original = TodayWidgetData.displayedScheduleFingerprint("u", "t", "1", "{\"events\":[]}")
    val same = TodayWidgetData.displayedScheduleFingerprint("u", "t", "1", "{\"events\":[]}")
    val changed = TodayWidgetData.displayedScheduleFingerprint("u", "t", "1", "{\"events\":[1]}")

    assertTrue(original == same)
    assertNotEquals(original, changed)
  }

  @Test
  fun `successful refresh with unchanged content keeps existing remote list`() {
    assertFalse(TodayCourseWidgetProvider.shouldRefreshData(true, "same", "same"))
  }

  @Test
  fun `successful refresh with changed content refreshes remote list`() {
    assertTrue(TodayCourseWidgetProvider.shouldRefreshData(true, "before", "after"))
  }

  @Test
  fun `failed refresh never clears existing remote list`() {
    assertFalse(TodayCourseWidgetProvider.shouldRefreshData(false, "before", "after"))
  }
}
