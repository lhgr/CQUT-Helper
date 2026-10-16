package com.dawndrizzle.wing.cqut.widget

import kotlin.math.abs
import kotlin.math.roundToInt

/** Course card colors shared by every native widget, in the same order as ScheduleCourseCardTheme. */
internal object WidgetCoursePalette {
  internal data class Colors(val background: Int, val accent: Int)

  private val lightBackgrounds = intArrayOf(
    0xFFE6F4FF.toInt(), 0xFFFDEBDD.toInt(), 0xFFDEFBF7.toInt(),
    0xFFEEEDFF.toInt(), 0xFFFCEBCD.toInt(), 0xFFFFEFF0.toInt(),
    0xFFFFEEF8.toInt(), 0xFFE2F9F3.toInt(), 0xFFFFF9C9.toInt(),
    0xFFFAEDFF.toInt(), 0xFFF4F2FD.toInt(), 0xFFE6E6FF.toInt(),
    0xFFEEFDDD.toInt(), 0xFFEADEFB.toInt(), 0xFFFFEFED.toInt(),
    0xFFCDF2FC.toInt(), 0xFFEFFFFF.toInt(), 0xFFEEFFFF.toInt(),
    0xFFF9F5E2.toInt(), 0xFFEDF0FF.toInt(), 0xFFF2F4FD.toInt(),
  )

  private val lightAccents = intArrayOf(
    0xFF1473A3.toInt(), 0xFFAC3E15.toInt(), 0xFF0F7B78.toInt(),
    0xFF621EA4.toInt(), 0xFF915D12.toInt(), 0xFFAC1522.toInt(),
    0xFFAC152C.toInt(), 0xFF0F7A7B.toInt(), 0xFF846C10.toInt(),
    0xFF781CA6.toInt(), 0xFF3215AC.toInt(), 0xFF1426A3.toInt(),
    0xFF80AC15.toInt(), 0xFF480F7B.toInt(), 0xFFA4671E.toInt(),
    0xFF127B91.toInt(), 0xFF15ACA8.toInt(), 0xFF1568AC.toInt(),
    0xFF717B0F.toInt(), 0xFF1C3CA6.toInt(), 0xFF152EAC.toInt(),
  )

  private val darkBackgrounds = lightBackgrounds.map { recolorHsl(it, 0.42, 0.20) }
  private val darkAccents = lightAccents.map { recolorHsl(it, 0.58, 0.80) }

  val size: Int get() = lightBackgrounds.size

  fun colorsAt(index: Int, dark: Boolean): Colors {
    val safeIndex = Math.floorMod(index, size)
    return if (dark) {
      Colors(darkBackgrounds[safeIndex], darkAccents[safeIndex])
    } else {
      Colors(lightBackgrounds[safeIndex], lightAccents[safeIndex])
    }
  }

  // Matches HSLColor.fromColor(...).withSaturation(...).withLightness(...).toColor()
  // used by ScheduleCourseCardTheme.dark(), including channel rounding.
  private fun recolorHsl(color: Int, saturation: Double, lightness: Double): Int {
    val r = ((color ushr 16) and 0xFF) / 255.0
    val g = ((color ushr 8) and 0xFF) / 255.0
    val b = (color and 0xFF) / 255.0
    val maximum = maxOf(r, g, b)
    val minimum = minOf(r, g, b)
    val delta = maximum - minimum
    val hue = when {
      delta == 0.0 -> 0.0
      maximum == r -> 60.0 * (((g - b) / delta) % 6.0)
      maximum == g -> 60.0 * ((b - r) / delta + 2.0)
      else -> 60.0 * ((r - g) / delta + 4.0)
    }.let { if (it < 0.0) it + 360.0 else it }

    val chroma = (1.0 - abs(2.0 * lightness - 1.0)) * saturation
    val secondary = chroma * (1.0 - abs((hue / 60.0) % 2.0 - 1.0))
    val match = lightness - chroma / 2.0
    val (red, green, blue) = when {
      hue < 60.0 -> Triple(chroma, secondary, 0.0)
      hue < 120.0 -> Triple(secondary, chroma, 0.0)
      hue < 180.0 -> Triple(0.0, chroma, secondary)
      hue < 240.0 -> Triple(0.0, secondary, chroma)
      hue < 300.0 -> Triple(secondary, 0.0, chroma)
      else -> Triple(chroma, 0.0, secondary)
    }
    return (0xFF shl 24) or
      (((red + match) * 255.0).roundToInt().coerceIn(0, 255) shl 16) or
      (((green + match) * 255.0).roundToInt().coerceIn(0, 255) shl 8) or
      ((blue + match) * 255.0).roundToInt().coerceIn(0, 255)
  }
}
