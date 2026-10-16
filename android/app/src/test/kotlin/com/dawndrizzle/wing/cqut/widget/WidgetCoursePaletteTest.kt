package com.dawndrizzle.wing.cqut.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class WidgetCoursePaletteTest {
  @Test
  fun `all schedule colors are available without wrapping at the old eleven color boundary`() {
    assertEquals(21, WidgetCoursePalette.size)
    val light = (0 until WidgetCoursePalette.size)
      .map { WidgetCoursePalette.colorsAt(it, dark = false) }
    assertEquals(21, light.map { it.background }.toSet().size)
    assertEquals(21, light.map { it.accent }.toSet().size)
    assertEquals(0xFFE6F4FF.toInt(), light[0].background)
    assertEquals(0xFF1473A3.toInt(), light[0].accent)
    assertEquals(0xFFE6E6FF.toInt(), light[11].background)
    assertEquals(0xFF1426A3.toInt(), light[11].accent)
    assertEquals(0xFFF2F4FD.toInt(), light[20].background)
    assertEquals(0xFF152EAC.toInt(), light[20].accent)
    assertNotEquals(light[0], light[11])
    assertEquals(light[20], WidgetCoursePalette.colorsAt(41, dark = false))
  }

  @Test
  fun `dark backgrounds use schedule HSL lightness and saturation`() {
    assertEquals(0xFF1E3648.toInt(), WidgetCoursePalette.colorsAt(0, dark = true).background)
    assertEquals(0xFF48301E.toInt(), WidgetCoursePalette.colorsAt(1, dark = true).background)
    assertEquals(0xFF1E4843.toInt(), WidgetCoursePalette.colorsAt(2, dark = true).background)
    assertEquals(0xFFAED6EA.toInt(), WidgetCoursePalette.colorsAt(0, dark = true).accent)
  }

  @Test
  fun `event customization precedes persisted course assignment and fallback`() {
    assertEquals(19, TodayWidgetData.resolveColorIndex(19, 3, "编译原理"))
    assertEquals(17, TodayWidgetData.resolveColorIndex(null, 17, "编译原理"))
    val fallback = TodayWidgetData.resolveColorIndex(null, null, "编译原理")
    assertEquals(3, fallback)
    assertEquals(4, TodayWidgetData.resolveColorIndex(null, null, "📚程序设计"))
    assertEquals(4, TodayWidgetData.resolveColorIndex(null, null, ""))
    assertTrue(fallback in 0 until WidgetCoursePalette.size)
    assertEquals(
      WidgetCoursePalette.colorsAt(19, dark = false),
      WidgetCoursePalette.colorsAt(
        TodayWidgetData.resolveColorIndex(19, 3, "编译原理"),
        dark = false,
      ),
    )
  }
}
