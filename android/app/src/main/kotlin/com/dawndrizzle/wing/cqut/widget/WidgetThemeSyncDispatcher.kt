package com.dawndrizzle.wing.cqut.widget

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log

object WidgetThemeSyncDispatcher {
  private const val TRANSITION_DURATION_MS = 180L
  private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

  fun dispatch(context: Context, trigger: WidgetThemeTrigger) {
    val resolution = WidgetTheme.resolve(context, trigger)
    Log.d(
      "WidgetTheme",
      "dispatch trigger=$trigger mode=${resolution.mode} dark=${resolution.dark} signature=${resolution.signature}",
    )
    if (trigger == WidgetThemeTrigger.SYSTEM_THEME_CHANGED && resolution.mode != WidgetThemeMode.SYSTEM) {
      Log.d("WidgetTheme", "skip system changed because mode=${resolution.mode}")
      return
    }
    // Existing collection widgets already have their adapters and click
    // templates installed. Replacing the whole RemoteViews during an ordinary
    // refresh makes MIUI briefly recreate the list (visible as a dark/empty
    // frame), so patch presentation fields and notify the collections only.
    TodayListWidgetProvider.refreshAll(context, resolution)
    TodayAndNextWidgetProvider.refreshAll(context, resolution)
    TodayCourseWidgetProvider.updateAll(context, resolution)
    WidgetAutoRefreshScheduler.schedule(context)
    if (resolution.shouldAnimate) {
      mainHandler.postDelayed(
        {
          WidgetTheme.commitTransition(context)
          val commitResolution = WidgetTheme.resolve(context, WidgetThemeTrigger.TRANSITION_COMMIT)
          TodayListWidgetProvider.refreshAll(context, commitResolution)
          TodayAndNextWidgetProvider.refreshAll(context, commitResolution)
          TodayCourseWidgetProvider.updateAll(context, commitResolution)
          WidgetAutoRefreshScheduler.schedule(context)
        },
        TRANSITION_DURATION_MS,
      )
    }
  }
}
