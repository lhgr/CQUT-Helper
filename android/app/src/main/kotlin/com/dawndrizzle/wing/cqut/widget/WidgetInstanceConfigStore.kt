package com.dawndrizzle.wing.cqut.widget

import android.appwidget.AppWidgetManager
import android.content.Context
import android.content.SharedPreferences

enum class WidgetInstanceTheme {
  FOLLOW_APP,
  LIGHT,
  DARK,
  ;

  companion object {
    fun parse(raw: String?): WidgetInstanceTheme =
      entries.firstOrNull { it.name == raw } ?: FOLLOW_APP
  }
}

data class WidgetInstanceConfig(
  val theme: WidgetInstanceTheme = WidgetInstanceTheme.FOLLOW_APP,
  val dayOffset: Int = 0,
  val refreshSuggestionDays: Int = WidgetInstanceConfigStore.DEFAULT_REFRESH_SUGGESTION_DAYS,
)

object WidgetInstanceConfigStore {
  private const val PREFS_NAME = "ScheduleWidgetInstanceConfig"
  private const val LEGACY_DAY_PREFS_NAME = "TodayCourseWidgetPrefs"
  private const val KEY_THEME_PREFIX = "theme_"
  private const val KEY_DAY_OFFSET_PREFIX = "day_offset_"
  private const val KEY_REFRESH_SUGGESTION_DAYS_PREFIX = "refresh_suggestion_days_"
  private const val KEY_CONFIGURED_PREFIX = "configured_"
  const val DEFAULT_REFRESH_SUGGESTION_DAYS = 3

  fun normalizeDayOffset(value: Int): Int = value.coerceIn(0, 1)

  fun normalizeRefreshSuggestionDays(value: Int): Int =
    if (value > 0) value else DEFAULT_REFRESH_SUGGESTION_DAYS

  fun load(
    context: Context,
    appWidgetId: Int,
  ): WidgetInstanceConfig {
    if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) {
      return WidgetInstanceConfig()
    }
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val dayKey = "$KEY_DAY_OFFSET_PREFIX$appWidgetId"
    val dayOffset =
      if (prefs.contains(dayKey)) {
        prefs.getInt(dayKey, 0)
      } else {
        val legacyPrefs =
          context.getSharedPreferences(LEGACY_DAY_PREFS_NAME, Context.MODE_PRIVATE)
        val legacyKey = "dayOffset_$appWidgetId"
        val migrated = legacyPrefs.getInt(legacyKey, 0)
        if (legacyPrefs.contains(legacyKey)) {
          prefs.edit().putInt(dayKey, normalizeDayOffset(migrated)).apply()
          legacyPrefs.edit().remove(legacyKey).apply()
        }
        migrated
      }
    return WidgetInstanceConfig(
      theme = WidgetInstanceTheme.parse(prefs.getString("$KEY_THEME_PREFIX$appWidgetId", null)),
      dayOffset = normalizeDayOffset(dayOffset),
      refreshSuggestionDays =
        normalizeRefreshSuggestionDays(
          prefs.getInt(
            "$KEY_REFRESH_SUGGESTION_DAYS_PREFIX$appWidgetId",
            DEFAULT_REFRESH_SUGGESTION_DAYS,
          ),
        ),
    )
  }

  fun save(
    context: Context,
    appWidgetId: Int,
    config: WidgetInstanceConfig,
  ) {
    if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return
    configEditor(context, appWidgetId, config).apply()
  }

  fun saveImmediately(
    context: Context,
    appWidgetId: Int,
    config: WidgetInstanceConfig,
  ): Boolean {
    if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return false
    return configEditor(context, appWidgetId, config).commit()
  }

  private fun configEditor(
    context: Context,
    appWidgetId: Int,
    config: WidgetInstanceConfig,
  ): SharedPreferences.Editor {
    return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
      .edit()
      .putString("$KEY_THEME_PREFIX$appWidgetId", config.theme.name)
      .putInt("$KEY_DAY_OFFSET_PREFIX$appWidgetId", normalizeDayOffset(config.dayOffset))
      .putInt(
        "$KEY_REFRESH_SUGGESTION_DAYS_PREFIX$appWidgetId",
        normalizeRefreshSuggestionDays(config.refreshSuggestionDays),
      )
      .putBoolean("$KEY_CONFIGURED_PREFIX$appWidgetId", true)
  }

  fun isConfigured(
    context: Context,
    appWidgetId: Int,
  ): Boolean {
    return context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
      .getBoolean("$KEY_CONFIGURED_PREFIX$appWidgetId", false)
  }

  fun saveDayOffset(
    context: Context,
    appWidgetId: Int,
    dayOffset: Int,
  ) {
    val current = load(context, appWidgetId)
    save(context, appWidgetId, current.copy(dayOffset = normalizeDayOffset(dayOffset)))
  }

  fun delete(
    context: Context,
    appWidgetIds: IntArray,
  ) {
    val editor = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE).edit()
    val legacyEditor =
      context.getSharedPreferences(LEGACY_DAY_PREFS_NAME, Context.MODE_PRIVATE).edit()
    appWidgetIds.forEach { appWidgetId ->
      editor.remove("$KEY_THEME_PREFIX$appWidgetId")
      editor.remove("$KEY_DAY_OFFSET_PREFIX$appWidgetId")
      editor.remove("$KEY_REFRESH_SUGGESTION_DAYS_PREFIX$appWidgetId")
      editor.remove("$KEY_CONFIGURED_PREFIX$appWidgetId")
      legacyEditor.remove("dayOffset_$appWidgetId")
    }
    editor.apply()
    legacyEditor.apply()
  }

  fun resolveTheme(
    context: Context,
    appWidgetId: Int,
    fallback: WidgetThemeResolution? = null,
  ): WidgetThemeResolution {
    return when (load(context, appWidgetId).theme) {
      WidgetInstanceTheme.FOLLOW_APP ->
        fallback ?: WidgetTheme.resolve(context, WidgetThemeTrigger.DATA_REFRESH)
      WidgetInstanceTheme.LIGHT -> fixedTheme(WidgetThemeMode.LIGHT, dark = false)
      WidgetInstanceTheme.DARK -> fixedTheme(WidgetThemeMode.DARK, dark = true)
    }
  }

  private fun fixedTheme(
    mode: WidgetThemeMode,
    dark: Boolean,
  ): WidgetThemeResolution {
    return WidgetThemeResolution(
      mode = mode,
      dark = dark,
      palette = WidgetThemePolicy.ensureConsistent(WidgetThemePolicy.buildPalette(mode, dark)),
      signature = WidgetThemePolicy.signature(mode, dark),
      shouldAnimate = false,
    )
  }
}
