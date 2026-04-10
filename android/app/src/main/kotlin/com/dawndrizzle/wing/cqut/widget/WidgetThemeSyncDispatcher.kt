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
    TodayListWidgetProvider.updateAll(context, resolution)
    TodayAndNextWidgetProvider.updateAll(context, resolution)
    TodayCourseWidgetProvider.updateAll(context, resolution)
    if (trigger == WidgetThemeTrigger.SYSTEM_THEME_CHANGED && resolution.mode == WidgetThemeMode.SYSTEM) {
      WidgetForceUpdatePusher.push(context)
    }
    WidgetAutoRefreshScheduler.schedule(context)
    if (resolution.shouldAnimate) {
      mainHandler.postDelayed(
        {
          WidgetTheme.commitTransition(context)
          val commitResolution = WidgetTheme.resolve(context, WidgetThemeTrigger.TRANSITION_COMMIT)
          TodayListWidgetProvider.updateAll(context, commitResolution)
          TodayAndNextWidgetProvider.updateAll(context, commitResolution)
          TodayCourseWidgetProvider.updateAll(context, commitResolution)
          WidgetAutoRefreshScheduler.schedule(context)
        },
        TRANSITION_DURATION_MS,
      )
    }
  }
}
