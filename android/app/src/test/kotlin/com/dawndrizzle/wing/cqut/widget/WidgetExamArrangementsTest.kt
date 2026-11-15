package com.dawndrizzle.wing.cqut.widget

import java.time.OffsetDateTime
import org.junit.Assert.*
import org.junit.Test

class WidgetExamArrangementsTest {
  private fun at(clock: String) = OffsetDateTime.parse("2026-11-15T$clock:00+08:00").toInstant().toEpochMilli()
  private fun exam(key: String = "exam-1", start: String = "09:00", end: String = "11:00") =
    TodayWidgetData.ExamItem(key, "考试科目", "原始考试时间", "校区", "楼栋", "101", at(start), at(end))
  private fun course(minute: Int?) = TodayWidgetData.CourseItem(
    "course-1", "course", "课程", "", "", "", "第1节", 0, 1, startMinuteOfDay = minute,
  )

  @Test fun `exams survive missing course data until exact end and keep real date`() {
    assertEquals(1, TodayWidgetData.mergeArrangements(emptyList(), listOf(exam()), "2026-11-15", at("10:00")).size)
    assertTrue(TodayWidgetData.mergeArrangements(emptyList(), listOf(exam()), "2026-11-16", at("10:00")).isEmpty())
    assertTrue(TodayWidgetData.mergeArrangements(emptyList(), listOf(exam()), "2026-11-15", at("11:00")).isEmpty())
    val row = TodayWidgetData.mergeArrangements(emptyList(), listOf(exam()), "2026-11-15", at("09:00")).single()
    assertEquals("考试中 · 09:00–11:00", row.periods)
    assertTrue(row.isOngoingExam)
    assertEquals("exam", row.kind)
    assertEquals("exam-1", row.examKey)
  }

  @Test fun `clockless courses follow timed rows and tiny prefers ongoing exam`() {
    WidgetRenderSnapshot.withSnapshot(at("10:00")) {
      val rows = TodayWidgetData.mergeArrangements(listOf(course(null), course(630)), listOf(exam()), "2026-11-15")
      assertEquals(listOf("exam", "course", "course"), rows.map { it.kind })
      assertNull(rows.last().startMinuteOfDay)
      assertEquals("exam", TodayWidgetData.selectNextCourse(rows)?.kind)
    }
  }

  @Test fun `exam boundaries advance from start to end and navigation survives collection template`() {
    assertEquals(at("09:00"), TodayWidgetData.nextExamBoundary(listOf(exam()), at("08:00")))
    assertEquals(at("11:00"), TodayWidgetData.nextExamBoundary(listOf(exam()), at("09:00")))
    assertNull(TodayWidgetData.nextExamBoundary(listOf(exam()), at("11:00")))
    val row = TodayWidgetData.mergeArrangements(emptyList(), listOf(exam()), "2026-11-15", at("10:00")).single()
    val day = TodayWidgetData.CourseDay("2026-11-15", 0, listOf(row))
    val template = WidgetNavigationPendingIntent.navigationExtras(0, "2026-11-16", mutableForCollection = true)
    val extras = day.navigationExtras(row) + template
    assertEquals("exam", extras["itemKind"])
    assertEquals("exam-1", extras["examKey"])
    assertEquals("2026-11-15", extras["widgetDate"])
  }

  @Test fun `exam changes invalidate visible rows without changing course identity`() {
    val rows = TodayWidgetData.mergeArrangements(listOf(course(600)), listOf(exam()), "2026-11-15", at("08:00"))
    val changed = rows.map { if (it.kind == "exam") it.copy(examKey = "exam-2") else it }
    assertNotEquals(TodayWidgetData.visibleCoursesFingerprint(listOf(0 to rows)), TodayWidgetData.visibleCoursesFingerprint(listOf(0 to changed)))
    assertEquals("course-1", rows.first { it.kind == "course" }.eventId)
  }

  @Test fun `offset and fractional ISO values share an instant and overnight exams last until end`() {
    assertEquals(at("09:00"), TodayWidgetData.parseIso8601Millis("2026-11-15T01:00:00.000Z"))
    assertEquals(at("09:00"), TodayWidgetData.parseIso8601Millis("2026-11-15T09:00:00+08:00"))
    assertNull(TodayWidgetData.parseIso8601Millis("invalid"))
    val overnight = exam().copy(startAtMillis = at("23:00") - 86400000, endAtMillis = at("01:00"))
    assertEquals(1, TodayWidgetData.mergeArrangements(emptyList(), listOf(overnight), "2026-11-15", at("00:30")).size)
    assertTrue(TodayWidgetData.mergeArrangements(emptyList(), listOf(overnight), "2026-11-15", at("01:00")).isEmpty())
  }
}
