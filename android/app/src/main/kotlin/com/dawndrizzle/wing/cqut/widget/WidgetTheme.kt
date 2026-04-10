package com.dawndrizzle.wing.cqut.widget

import android.content.Context
import android.content.res.Configuration

object WidgetTheme {
  private const val PREFS_STATE = "WidgetThemeState"
  private const val KEY_LAST_SIGNATURE = "last_signature"
  private const val KEY_LAST_DARK = "last_dark"
  private const val KEY_PENDING = "transition_pending"
  private const val FLUTTER_PREFS = "FlutterSharedPreferences"
  private const val FLUTTER_THEME_MODE_KEY = "flutter.theme_mode"

  fun resolve(context: Context, trigger: WidgetThemeTrigger): WidgetThemeResolution {
    val prefs = context.getSharedPreferences(PREFS_STATE, Context.MODE_PRIVATE)
    val lastSignature = prefs.getString(KEY_LAST_SIGNATURE, null)
    val lastDark =
      if (prefs.contains(KEY_LAST_DARK)) prefs.getBoolean(KEY_LAST_DARK, false) else null
    val pending = prefs.getBoolean(KEY_PENDING, false)

    val mode = WidgetThemePolicy.parseMode(readThemeMode(context))
    val dark = WidgetThemePolicy.resolveDark(mode, isSystemDark(context), pending, lastDark)
    val signature = WidgetThemePolicy.signature(mode, dark)
    val shouldAnimate = WidgetThemePolicy.shouldAnimate(trigger, lastSignature, signature)
    val palette = WidgetThemePolicy.ensureConsistent(WidgetThemePolicy.buildPalette(mode, dark))

    prefs.edit()
      .putString(KEY_LAST_SIGNATURE, signature)
      .putBoolean(KEY_LAST_DARK, dark)
      .putBoolean(KEY_PENDING, shouldAnimate)
      .apply()

    return WidgetThemeResolution(
      mode = mode,
      dark = dark,
      palette = palette,
      signature = signature,
      shouldAnimate = shouldAnimate,
    )
  }

  fun commitTransition(context: Context) {
    val prefs = context.getSharedPreferences(PREFS_STATE, Context.MODE_PRIVATE)
    prefs.edit().putBoolean(KEY_PENDING, false).apply()
  }

  private fun readThemeMode(context: Context): String? {
    val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
    return prefs.getString(FLUTTER_THEME_MODE_KEY, null)
  }

  private fun isSystemDark(context: Context): Boolean {
    val nightModeFlags = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK
    return nightModeFlags == Configuration.UI_MODE_NIGHT_YES
  }
}
