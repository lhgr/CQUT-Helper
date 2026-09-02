package com.dawndrizzle.wing.cqut.widget

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log

object WidgetThemeSyncDispatcher {
  private const val TRANSITION_DURATION_MS = 180L
  private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

  internal fun dispatch(
    context: Context,
    trigger: WidgetThemeTrigger,
    forceFullUpdate: Boolean = false,
    renderedState: WidgetRefreshRenderState? = null,
  ) {
    val resolution = WidgetTheme.resolve(context, trigger)
    Log.d(
      "WidgetTheme",
      "dispatch trigger=$trigger mode=${resolution.mode} dark=${resolution.dark} signature=${resolution.signature}",
    )
    if (trigger == WidgetThemeTrigger.SYSTEM_THEME_CHANGED && resolution.mode != WidgetThemeMode.SYSTEM) {
      Log.d("WidgetTheme", "skip system changed because mode=${resolution.mode}")
      return
    }
    val fullUpdate = forceFullUpdate || requiresFullUpdate(trigger)
    WidgetNativeLog.info(
      context,
      "event=render_dispatched trigger=$trigger mode=${if (fullUpdate) "full" else "partial"}",
    )
    updateWidgets(context, resolution, fullUpdate)
    WidgetRefreshCoordinator.recordRenderedState(context, renderedState)
    WidgetRefreshCoordinator.ensureScheduled(context, "theme_dispatch:$trigger")
    if (resolution.shouldAnimate) {
      mainHandler.postDelayed(
        {
          WidgetTheme.commitTransition(context)
          val commitResolution = WidgetTheme.resolve(context, WidgetThemeTrigger.TRANSITION_COMMIT)
          updateWidgets(context, commitResolution, fullUpdate = true)
          WidgetRefreshCoordinator.recordRenderedState(context)
          WidgetRefreshCoordinator.ensureScheduled(context, "theme_commit")
        },
        TRANSITION_DURATION_MS,
      )
    }
  }

  internal fun requiresFullUpdate(trigger: WidgetThemeTrigger): Boolean {
    return trigger != WidgetThemeTrigger.DATA_REFRESH
  }

  private fun updateWidgets(
    context: Context,
    resolution: WidgetThemeResolution,
    fullUpdate: Boolean,
  ) {
    if (fullUpdate) {
      // Theme changes need a complete RemoteViews rebind. Several launchers
      // retain background resources during partial updates, making FOLLOW_APP
      // appear pinned to the theme used when the widget was placed.
      TodayListWidgetProvider.updateAll(context, resolution)
      TodayAndNextWidgetProvider.updateAll(context, resolution)
      VerticalScheduleWidgetProvider.updateAll(context, resolution)
    } else {
      // Ordinary data refreshes keep their collection adapters and click
      // templates to avoid a dark/empty frame on MIUI.
      TodayListWidgetProvider.refreshAll(context, resolution)
      TodayAndNextWidgetProvider.refreshAll(context, resolution)
      VerticalScheduleWidgetProvider.refreshAll(context, resolution)
    }
    TodayCourseWidgetProvider.updateAll(context, resolution)
    TinyCourseWidgetProvider.updateAll(context, resolution)
  }
}
