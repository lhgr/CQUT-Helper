package com.dawndrizzle.wing.cqut.widget

import java.time.Instant
import java.util.TimeZone
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WidgetNavigationPendingIntentTest {
  private val beforeMidnight = Instant.parse("2026-12-31T15:59:59Z").toEpochMilli()
  private val afterMidnight = Instant.parse("2026-12-31T16:00:00Z").toEpochMilli()

  private fun course() = TodayWidgetData.CourseItem(
    eventId = "course-before-midnight", courseKey = "课程", name = "课程",
    campus = "校区", classroom = "101", teacher = "教师", periods = "第1节",
    colorIndex = 0, sortOrder = 1, startMinuteOfDay = 480,
  )

  @Test
  fun `all navigation identities change across Beijing midnight`() {
    for (target in listOf("root", "course", "tiny-course")) {
      val oldDate = TodayWidgetData.dateForDayOffset(1, beforeMidnight)
      val newDate = TodayWidgetData.dateForDayOffset(1, afterMidnight)
      assertEquals("2027-01-01", oldDate)
      assertEquals("2027-01-02", newDate)
      assertNotEquals(
        WidgetNavigationPendingIntent.dataUri(7, 1, oldDate, target),
        WidgetNavigationPendingIntent.dataUri(7, 1, newDate, target),
      )
    }
  }

  @Test
  fun `root and tiny clicks preserve the date on the rendered calendar`() {
    val date = TodayWidgetData.dateForDayOffset(0, beforeMidnight)
    val root = WidgetNavigationPendingIntent.navigationExtras(0, date)
    val tiny = WidgetNavigationPendingIntent.navigationExtras(
      0, date, eventName = "课程", eventId = "course-before-midnight",
    )
    assertEquals("2026-12-31", root[WidgetNavigationPendingIntent.EXTRA_DATE])
    assertEquals(date, tiny[WidgetNavigationPendingIntent.EXTRA_DATE])
    assertEquals("course-before-midnight", tiny[WidgetNavigationPendingIntent.EXTRA_EVENT_ID])
  }

  @Test
  fun `old rows and new templates retain the row date and course together`() {
    val rowDay = TodayWidgetData.courseDayFor(1, listOf(course()), beforeMidnight)
    val newTemplate = WidgetNavigationPendingIntent.navigationExtras(
      1, TodayWidgetData.dateForDayOffset(1, afterMidnight), mutableForCollection = true,
    )
    assertFalse(newTemplate.containsKey(WidgetNavigationPendingIntent.EXTRA_DATE))
    // Android's base template extras take precedence over fill-in extras.
    val navigation = rowDay.navigationExtras(rowDay.courses.single()) + newTemplate
    assertEquals("2027-01-01", navigation[WidgetNavigationPendingIntent.EXTRA_DATE])
    assertEquals("course-before-midnight", navigation[WidgetNavigationPendingIntent.EXTRA_EVENT_ID])
    assertTrue(navigation[WidgetNavigationPendingIntent.EXTRA_OPEN_TODAY] == true)
  }

  @Test
  fun `new rows and old templates still navigate to the newly loaded date`() {
    val oldTemplate = WidgetNavigationPendingIntent.navigationExtras(
      1, TodayWidgetData.dateForDayOffset(1, beforeMidnight), mutableForCollection = true,
    )
    val rowDay = TodayWidgetData.courseDayFor(1, listOf(course()), afterMidnight)
    val navigation = rowDay.navigationExtras(rowDay.courses.single()) + oldTemplate
    assertEquals("2027-01-02", navigation[WidgetNavigationPendingIntent.EXTRA_DATE])
    assertEquals("course-before-midnight", navigation[WidgetNavigationPendingIntent.EXTRA_EVENT_ID])
  }

  @Test
  fun `date and filtered rows use one captured instant despite later rendering`() {
    val originalZone = TimeZone.getDefault()
    try {
      TimeZone.setDefault(TimeZone.getTimeZone("America/Los_Angeles"))
      val rowDay = WidgetRenderSnapshot.withSnapshot(beforeMidnight) {
        TodayWidgetData.courseDayFor(1, listOf(course()))
      }
      WidgetRenderSnapshot.withSnapshot(afterMidnight) {
        assertEquals("2027-01-01", rowDay.date)
        assertEquals("2027-01-01", rowDay.navigationExtras(rowDay.courses.single())[WidgetNavigationPendingIntent.EXTRA_DATE])
        assertEquals("2027-01-02", TodayWidgetData.dateForDayOffset(1))
      }
    } finally {
      TimeZone.setDefault(originalZone)
    }
  }
}
