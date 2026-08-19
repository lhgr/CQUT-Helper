package com.dawndrizzle.wing.cqut.widget

import dev.fluttercommunity.workmanager.BackgroundWorker
import dev.fluttercommunity.workmanager.decodePayload
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class ScheduleWidgetRefreshWorkTest {
  @Test
  fun `manual refresh input uses current workmanager payload encoding`() {
    val input = ScheduleWidgetRefreshWork.buildWorkerInput("refresh-1")

    assertEquals(
      "schedule_notice_poll_task",
      input.getString(BackgroundWorker.DART_TASK_KEY),
    )
    assertEquals(
      mapOf(
        "trigger" to "widget_manual",
        "logicalDateBjt" to "",
        "refreshId" to "refresh-1",
      ),
      decodePayload(input.keyValueMap),
    )
  }

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
  fun `provider update immediately after manual refresh is suppressed`() {
    assertTrue(ScheduleWidgetRefreshWork.shouldSuppressProviderUpdate(1_000L, 5_000L))
  }

  @Test
  fun `provider update after suppression window is allowed`() {
    assertFalse(ScheduleWidgetRefreshWork.shouldSuppressProviderUpdate(1_000L, 11_000L))
  }

  @Test
  fun `provider update without manual refresh is allowed`() {
    assertFalse(ScheduleWidgetRefreshWork.shouldSuppressProviderUpdate(0L, 5_000L))
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

  @Test
  fun `normal header action toggles the displayed day`() {
    assertEquals(
      TodayCourseHeaderAction.TOGGLE_DAY,
      TodayCourseWidgetProvider
        .headerActionFor(TodayWidgetData.RefreshPresentationState.NORMAL),
    )
  }

  @Test
  fun `credential failure header action opens the app`() {
    assertEquals(
      TodayCourseHeaderAction.OPEN_APP,
      TodayCourseWidgetProvider
        .headerActionFor(TodayWidgetData.RefreshPresentationState.CREDENTIAL_INVALID),
    )
  }

  @Test
  fun `non-normal refresh states replace the arrow with refresh action`() {
    listOf(
      TodayWidgetData.RefreshPresentationState.NEEDS_SYNC,
      TodayWidgetData.RefreshPresentationState.STALE,
      TodayWidgetData.RefreshPresentationState.LOADING,
      TodayWidgetData.RefreshPresentationState.FAILED,
    ).forEach { state ->
      assertEquals(
        TodayCourseHeaderAction.MANUAL_REFRESH,
        TodayCourseWidgetProvider.headerActionFor(state),
      )
    }
  }
}
