package com.dawndrizzle.wing.cqut.widget

import org.junit.Assert.assertEquals
import org.junit.Test

class WidgetInstanceConfigStoreTest {
  @Test
  fun `unknown theme falls back to following app`() {
    assertEquals(
      WidgetInstanceTheme.FOLLOW_APP,
      WidgetInstanceTheme.parse("legacy-value"),
    )
  }

  @Test
  fun `theme values are parsed independently`() {
    assertEquals(
      WidgetInstanceTheme.LIGHT,
      WidgetInstanceTheme.parse(WidgetInstanceTheme.LIGHT.name),
    )
    assertEquals(
      WidgetInstanceTheme.DARK,
      WidgetInstanceTheme.parse(WidgetInstanceTheme.DARK.name),
    )
  }

  @Test
  fun `day offset is constrained to today and tomorrow`() {
    assertEquals(0, WidgetInstanceConfigStore.normalizeDayOffset(-1))
    assertEquals(0, WidgetInstanceConfigStore.normalizeDayOffset(0))
    assertEquals(1, WidgetInstanceConfigStore.normalizeDayOffset(1))
    assertEquals(1, WidgetInstanceConfigStore.normalizeDayOffset(8))
  }
}
