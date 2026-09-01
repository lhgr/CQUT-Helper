package com.dawndrizzle.wing.cqut.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Calendar
import java.util.TimeZone

class TodayWidgetDataTest {
  private fun beijingCalendar(
    year: Int,
    month: Int,
    day: Int,
    hour: Int = 0,
    minute: Int = 0,
    second: Int = 0,
  ): Calendar =
    Calendar.getInstance(TimeZone.getTimeZone(TodayWidgetData.WIDGET_TIME_ZONE_ID)).apply {
      clear()
      set(year, month, day, hour, minute, second)
    }

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
    val now = beijingCalendar(2026, Calendar.AUGUST, 11, 18, 30)
    val updatedAt = beijingCalendar(2026, Calendar.AUGUST, 11, 9, 5)

    assertEquals(
      "09:05",
      TodayWidgetData.formatLastUpdated(updatedAt.timeInMillis, now.timeInMillis),
    )
  }

  @Test
  fun `earlier date update only displays calendar day distance`() {
    val now = beijingCalendar(2026, Calendar.AUGUST, 11, 1)
    val updatedAt = beijingCalendar(2026, Calendar.AUGUST, 9, 23, 30)

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

  @Test
  fun `refresh becomes stale exactly at its configured boundary`() {
    val day = 24L * 60 * 60 * 1000
    val lastUpdated = 1_000L
    val boundary = TodayWidgetData.staleRefreshAtMillis(lastUpdated, 3)

    assertEquals(lastUpdated + 3 * day, boundary)
    assertFalse(TodayWidgetData.isRefreshStale(lastUpdated, boundary - 1, 3))
    assertTrue(TodayWidgetData.isRefreshStale(lastUpdated, boundary, 3))
  }

  @Test
  fun `next refresh chooses the earliest future boundary`() {
    assertEquals(
      1_500L,
      TodayWidgetData.earliestFutureRefreshAtMillis(
        1_000L,
        listOf(900L, 2_000L, 1_500L, 3_000L),
      ),
    )
    assertNull(
      TodayWidgetData.earliestFutureRefreshAtMillis(
        1_000L,
        listOf(500L, 1_000L),
      ),
    )
  }

  @Test
  fun `non-normal refresh presentation replaces date metadata`() {
    val stale =
      TodayWidgetData.RefreshPresentation(
        TodayWidgetData.RefreshPresentationState.STALE,
        "课表可能已过期",
      )
    val normal =
      TodayWidgetData.RefreshPresentation(
        TodayWidgetData.RefreshPresentationState.NORMAL,
        "10:32",
      )

    assertTrue(stale.replacesDateMetadata)
    assertFalse(normal.replacesDateMetadata)
  }

  @Test
  fun `covered cache without background polling timestamp is synchronized`() {
    val presentation =
      TodayWidgetData.idleRefreshPresentation(
        hasCoveredRequiredDate = true,
        hasAnyScheduleCache = true,
        isDebuggable = false,
        pollingEnabled = false,
        lastSuccessfulAt = null,
        nowMillis = 10_000L,
        suggestionDays = 3,
      )

    assertEquals(TodayWidgetData.RefreshPresentationState.NORMAL, presentation.state)
    assertEquals("", presentation.text)
  }

  @Test
  fun `one covered date keeps multi-day widget synchronized`() {
    val presentation =
      TodayWidgetData.idleRefreshPresentation(
        hasCoveredRequiredDate = true,
        hasAnyScheduleCache = true,
        isDebuggable = false,
        pollingEnabled = false,
        lastSuccessfulAt = null,
        nowMillis = 10_000L,
        suggestionDays = 3,
      )

    assertEquals(TodayWidgetData.RefreshPresentationState.NORMAL, presentation.state)
  }

  @Test
  fun `uncovered date with an older cache is stale instead of unsynchronized`() {
    val presentation =
      TodayWidgetData.idleRefreshPresentation(
        hasCoveredRequiredDate = false,
        hasAnyScheduleCache = true,
        isDebuggable = false,
        pollingEnabled = false,
        lastSuccessfulAt = null,
        nowMillis = 10_000L,
        suggestionDays = 3,
      )

    assertEquals(TodayWidgetData.RefreshPresentationState.STALE, presentation.state)
  }

  @Test
  fun `recently verified cache outside teaching week is normal`() {
    val presentation =
      TodayWidgetData.idleRefreshPresentation(
        hasCoveredRequiredDate = false,
        hasAnyScheduleCache = true,
        isDebuggable = false,
        pollingEnabled = false,
        lastSuccessfulAt = 9_000L,
        nowMillis = 10_000L,
        suggestionDays = 3,
      )

    assertEquals(TodayWidgetData.RefreshPresentationState.NORMAL, presentation.state)
  }

  @Test
  fun `no schedule cache remains unsynchronized`() {
    val presentation =
      TodayWidgetData.idleRefreshPresentation(
        hasCoveredRequiredDate = false,
        hasAnyScheduleCache = false,
        isDebuggable = false,
        pollingEnabled = false,
        lastSuccessfulAt = null,
        nowMillis = 10_000L,
        suggestionDays = 3,
      )

    assertEquals(TodayWidgetData.RefreshPresentationState.NEEDS_SYNC, presentation.state)
  }

  @Test
  fun `next course boundary includes both start and end`() {
    val clocks =
      mapOf(
        1 to (8 * 60 to 8 * 60 + 45),
        2 to (8 * 60 + 55 to 9 * 60 + 40),
        3 to (14 * 60 to 14 * 60 + 45),
      )
    val courses = listOf(listOf(1, 2), listOf(3))

    assertEquals(
      8 * 60,
      TodayWidgetData.nextCourseBoundaryMinuteOfDay(courses, clocks, 7 * 60 + 59),
    )
    assertEquals(
      9 * 60 + 40,
      TodayWidgetData.nextCourseBoundaryMinuteOfDay(courses, clocks, 8 * 60),
    )
    assertEquals(
      14 * 60,
      TodayWidgetData.nextCourseBoundaryMinuteOfDay(courses, clocks, 9 * 60 + 40),
    )
    assertEquals(
      14 * 60 + 45,
      TodayWidgetData.nextCourseBoundaryMinuteOfDay(courses, clocks, 14 * 60),
    )
  }

  @Test
  fun `missing or partial time map does not invent a boundary`() {
    assertNull(TodayWidgetData.sessionClockRange(listOf(1), emptyMap()))
    assertNull(
      TodayWidgetData.sessionClockRange(
        listOf(1, 2),
        mapOf(1 to (8 * 60 to 8 * 60 + 45)),
      ),
    )
    assertNull(
      TodayWidgetData.nextCourseBoundaryMinuteOfDay(
        listOf(listOf(1)),
        emptyMap(),
        7 * 60,
      ),
    )
  }

  @Test
  fun `course clock range uses first start and last end`() {
    val clocks =
      mapOf(
        1 to (8 * 60 to 8 * 60 + 45),
        2 to (8 * 60 + 55 to 9 * 60 + 40),
      )

    assertEquals(
      "08:00" to "09:40",
      TodayWidgetData.formatSessionClockRange(listOf(1, 2), clocks),
    )
    assertNull(TodayWidgetData.formatSessionClockRange(listOf(1, 3), clocks))
  }

  @Test
  fun `tiny course selection always chooses earliest remaining course`() {
    val later = courseItem("later", sortOrder = 5)
    val earlier = courseItem("earlier", sortOrder = 1)

    assertEquals(earlier, TodayWidgetData.selectNextCourse(listOf(later, earlier)))
    assertNull(TodayWidgetData.selectNextCourse(emptyList()))
  }

  @Test
  fun `visible course fingerprint changes when an ended course disappears`() {
    val course = courseItem("course-1", sortOrder = 1)
    val before = TodayWidgetData.visibleCoursesFingerprint(listOf(0 to listOf(course)))
    val same = TodayWidgetData.visibleCoursesFingerprint(listOf(0 to listOf(course.copy())))
    val after = TodayWidgetData.visibleCoursesFingerprint(listOf(0 to emptyList()))
    val timeChanged =
      TodayWidgetData.visibleCoursesFingerprint(
        listOf(0 to listOf(course.copy(startTime = "08:00", endTime = "09:40"))),
      )

    assertEquals(before, same)
    assertFalse(before == after)
    assertFalse(before == timeChanged)
  }

  @Test
  fun `day rollover is exactly midnight in Beijing`() {
    val originalTimeZone = TimeZone.getDefault()
    try {
      TimeZone.setDefault(TimeZone.getTimeZone("America/Los_Angeles"))
      val now = beijingCalendar(2026, Calendar.AUGUST, 22, 23, 59, 30)
      val refreshAt = TodayWidgetData.nextDayRefreshAtMillis(now.timeInMillis)
      val refresh =
        Calendar.getInstance(TimeZone.getTimeZone(TodayWidgetData.WIDGET_TIME_ZONE_ID)).apply {
          timeInMillis = refreshAt
        }

      assertEquals(2026, refresh.get(Calendar.YEAR))
      assertEquals(Calendar.AUGUST, refresh.get(Calendar.MONTH))
      assertEquals(23, refresh.get(Calendar.DAY_OF_MONTH))
      assertEquals(0, refresh.get(Calendar.HOUR_OF_DAY))
      assertEquals(0, refresh.get(Calendar.MINUTE))
      assertEquals(0, refresh.get(Calendar.SECOND))
    } finally {
      TimeZone.setDefault(originalTimeZone)
    }
  }

  @Test
  fun `stale today marker never overrides explicit date`() {
    val target = beijingCalendar(2026, Calendar.AUGUST, 23)

    assertFalse(
      TodayWidgetData.scheduleDayMarkersContainDate(
        listOf(TodayWidgetData.ScheduleDayMarker("2026-08-22", markedToday = true)),
        target,
      ),
    )
    assertFalse(
      TodayWidgetData.scheduleDayMarkersContainDate(
        listOf(TodayWidgetData.ScheduleDayMarker("", markedToday = true)),
        target,
      ),
    )
    assertTrue(
      TodayWidgetData.scheduleDayMarkersContainDate(
        listOf(TodayWidgetData.ScheduleDayMarker("2026-08-23", markedToday = false)),
        target,
      ),
    )
  }

  @Test
  fun `parsed week range covers dates between its endpoints`() {
    val target = beijingCalendar(2026, Calendar.AUGUST, 12)

    assertTrue(
      TodayWidgetData.scheduleDayMarkersContainDate(
        listOf(
          TodayWidgetData.ScheduleDayMarker("2026-08-10", markedToday = false),
          TodayWidgetData.ScheduleDayMarker("2026-08-16", markedToday = false),
        ),
        target,
      ),
    )
  }

  @Test
  fun `month day week range remains strict across year boundary`() {
    val inside = beijingCalendar(2026, Calendar.JANUARY, 2)
    val outside = beijingCalendar(2026, Calendar.JANUARY, 5)
    val markers =
      listOf(
        TodayWidgetData.ScheduleDayMarker("12-29", markedToday = true),
        TodayWidgetData.ScheduleDayMarker("01-04", markedToday = false),
      )

    assertTrue(TodayWidgetData.scheduleDayMarkersContainDate(markers, inside))
    assertFalse(TodayWidgetData.scheduleDayMarkersContainDate(markers, outside))
  }

  @Test
  fun `invalid calendar date is not treated as coverage`() {
    val target = beijingCalendar(2026, Calendar.FEBRUARY, 28)

    assertFalse(
      TodayWidgetData.scheduleDayMarkersContainDate(
        listOf(TodayWidgetData.ScheduleDayMarker("2026-02-31", markedToday = true)),
        target,
      ),
    )
    assertFalse(
      TodayWidgetData.scheduleDayMarkersContainDate(
        listOf(TodayWidgetData.ScheduleDayMarker("today=2026-02-28", markedToday = true)),
        target,
      ),
    )
  }

  private fun courseItem(
    key: String,
    sortOrder: Int,
  ): TodayWidgetData.CourseItem {
    return TodayWidgetData.CourseItem(
      eventId = "event-$key",
      courseKey = key,
      name = "软件工程",
      campus = "两江校区",
      classroom = "A101",
      teacher = "教师",
      periods = "第1-2节",
      indicatorColor = 0,
      sortOrder = sortOrder,
    )
  }
}
