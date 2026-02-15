package com.dawndrizzle.wing.cqut.widget

import android.content.Context
import android.content.res.Configuration

object WidgetTheme {
  private const val PREFS_NAME = "FlutterSharedPreferences"
  private const val FLUTTER_PREFIX = "flutter."
  private const val KEY_THEME_MODE = "${FLUTTER_PREFIX}theme_mode"

  fun isDark(context: Context): Boolean {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    return when (prefs.getString(KEY_THEME_MODE, null)) {
      "ThemeMode.dark" -> true
      "ThemeMode.light" -> false
      else -> isSystemDark(context)
    }
  }

  private fun isSystemDark(context: Context): Boolean {
    val nightModeFlags = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
    return nightModeFlags == Configuration.UI_MODE_NIGHT_YES
  }

  fun primaryTextColor(dark: Boolean): Int = if (dark) 0xFFFFFFFF.toInt() else 0xFF111111.toInt()

  fun secondaryTextColor(dark: Boolean): Int = if (dark) 0xFFB0B0B0.toInt() else 0xFF666666.toInt()

  fun accentColor(): Int = 0xFF3F51B5.toInt()
}
