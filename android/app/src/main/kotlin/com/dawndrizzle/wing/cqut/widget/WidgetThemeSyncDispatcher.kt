package com.dawndrizzle.wing.cqut.widget

import android.content.Context
import android.os.Handler
import android.os.Looper

object WidgetThemeSyncDispatcher {
  private const val TRANSITION_DURATION_MS = 180L
  private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

  fun dispatch(context: Context, trigger: WidgetThemeTrigger) {
    val appContext = context.applicationContext
    val resolution = WidgetTheme.resolve(appContext, trigger)
    TodayListWidgetProvider.updateAll(appContext, resolution)
    TodayAndNextWidgetProvider.updateAll(appContext, resolution)
    TodayCourseWidgetProvider.updateAll(appContext, resolution)
    WidgetAutoRefreshScheduler.schedule(appContext)
    if (resolution.shouldAnimate) {
      mainHandler.postDelayed(
        {
          WidgetTheme.commitTransition(appContext)
          val commitResolution = WidgetTheme.resolve(appContext, WidgetThemeTrigger.TRANSITION_COMMIT)
          TodayListWidgetProvider.updateAll(appContext, commitResolution)
          TodayAndNextWidgetProvider.updateAll(appContext, commitResolution)
          TodayCourseWidgetProvider.updateAll(appContext, commitResolution)
          WidgetAutoRefreshScheduler.schedule(appContext)
        },
        TRANSITION_DURATION_MS,
      )
    }
  }
}
