package com.dawndrizzle.wing.cqut.widget

import org.junit.Assert.assertEquals
import org.junit.Test

class TinyCourseWidgetProviderTest {
  @Test
  fun `progress counts all remaining arrangements`() {
    assertEquals("剩余1项", TinyCourseWidgetProvider.courseProgressText(1))
    assertEquals("剩余2项", TinyCourseWidgetProvider.courseProgressText(2))
    assertEquals("剩余3项", TinyCourseWidgetProvider.courseProgressText(3))
  }

  @Test
  fun `course progress safely handles an empty count`() {
    assertEquals("", TinyCourseWidgetProvider.courseProgressText(0))
  }
}
