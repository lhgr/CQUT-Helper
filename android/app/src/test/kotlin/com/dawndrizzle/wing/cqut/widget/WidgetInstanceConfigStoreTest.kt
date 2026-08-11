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

  @Test
  fun `refresh suggestion accepts positive custom days and repairs invalid values`() {
    assertEquals(1, WidgetInstanceConfigStore.normalizeRefreshSuggestionDays(1))
    assertEquals(12, WidgetInstanceConfigStore.normalizeRefreshSuggestionDays(12))
    assertEquals(3, WidgetInstanceConfigStore.normalizeRefreshSuggestionDays(0))
    assertEquals(3, WidgetInstanceConfigStore.normalizeRefreshSuggestionDays(-5))
  }
}
