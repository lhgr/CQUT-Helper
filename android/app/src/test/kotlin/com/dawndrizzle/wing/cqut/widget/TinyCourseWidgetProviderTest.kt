package com.dawndrizzle.wing.cqut.widget

import org.junit.Assert.assertEquals
import org.junit.Test

class TinyCourseWidgetProviderTest {
  @Test
  fun `course progress excludes the displayed course`() {
    assertEquals("今日最后一节", TinyCourseWidgetProvider.courseProgressText(1))
    assertEquals("后续1节", TinyCourseWidgetProvider.courseProgressText(2))
    assertEquals("后续2节", TinyCourseWidgetProvider.courseProgressText(3))
  }

  @Test
  fun `course progress safely handles an empty count`() {
    assertEquals("", TinyCourseWidgetProvider.courseProgressText(0))
  }
}
