package com.dawndrizzle.wing.cqut.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WidgetRefreshPolicyTest {
  private val day = 24L * 60 * 60 * 1000
  private val stale = TodayWidgetData.RefreshPresentation(
    TodayWidgetData.RefreshPresentationState.STALE, "课表可能已过期",
  )

  @Test
  fun `button appears only when the instance reminder interval expires`() {
    for (days in listOf(1, 3, 7)) {
      val boundary = day + days * day
      assertFalse(TodayWidgetData.applyRefreshPolicy(stale, false, day, boundary - 1, days).showsRefreshButton)
      assertTrue(TodayWidgetData.applyRefreshPolicy(stale, false, day, boundary, days).showsRefreshButton)
    }
    assertFalse(TodayWidgetData.applyRefreshPolicy(stale, false, null, 30 * day, 3).showsRefreshButton)
  }

  @Test
  fun `notice polling suppresses manual refresh in every state and keeps day navigation`() {
    for (state in TodayWidgetData.RefreshPresentationState.values()) {
      val result = TodayWidgetData.applyRefreshPolicy(
        TodayWidgetData.RefreshPresentation(state, "状态"), true, day, 30 * day, 3,
      )
      assertFalse(result.showsRefreshButton)
      assertFalse(result.usesRefreshAction)
      assertEquals(TodayCourseHeaderAction.TOGGLE_DAY, TodayCourseWidgetProvider.headerActionFor(result))
    }
  }

  @Test
  fun `fresh failures do not invite users to press a hidden button`() {
    val failure = TodayWidgetData.RefreshPresentation(
      TodayWidgetData.RefreshPresentationState.FAILED, "更新失败，点右上角重试",
    )
    val fresh = TodayWidgetData.applyRefreshPolicy(failure, false, day, day + 1, 3)
    assertFalse(fresh.showsRefreshButton)
    assertEquals("更新失败，请打开应用", fresh.text)
    val expired = TodayWidgetData.applyRefreshPolicy(failure, false, day, 4 * day, 3)
    assertTrue(expired.showsRefreshButton)
    assertEquals(TodayCourseHeaderAction.MANUAL_REFRESH, TodayCourseWidgetProvider.headerActionFor(expired))
  }

  @Test
  fun `toggling notifications invalidates rendering even with identical cached courses`() {
    val normal = TodayWidgetData.RefreshPresentation(TodayWidgetData.RefreshPresentationState.NORMAL, "同步于08:00")
    val manual = TodayWidgetData.applyRefreshPolicy(normal, false, day, day + 1, 3)
    val automatic = TodayWidgetData.applyRefreshPolicy(normal, true, day, day + 1, 3)
    assertEquals("同步于08:00", manual.text)
    assertEquals("", automatic.text)
    assertNotEquals(manual.renderSignature, automatic.renderSignature)
    assertEquals(manual, TodayWidgetData.applyRefreshPolicy(normal, false, day, day + 1, 3))
  }
}
