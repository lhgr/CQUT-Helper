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
    WidgetRenderSnapshot.withSnapshot {
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
      updateWidgets(context, resolution, trigger, fullUpdate)
      WidgetNativeLog.info(context, "event=render_submitted at=${System.currentTimeMillis()}")
      WidgetRefreshCoordinator.recordRenderedState(context, renderedState)
      WidgetRefreshCoordinator.ensureScheduled(context, "theme_dispatch:$trigger")
      if (resolution.shouldAnimate) {
        mainHandler.postDelayed(
          {
            WidgetRenderSnapshot.withSnapshot {
              WidgetTheme.commitTransition(context)
              val commitResolution = WidgetTheme.resolve(context, WidgetThemeTrigger.TRANSITION_COMMIT)
              updateWidgets(
                context,
                commitResolution,
                WidgetThemeTrigger.TRANSITION_COMMIT,
                fullUpdate = true,
              )
              WidgetRefreshCoordinator.recordRenderedState(context)
              WidgetRefreshCoordinator.ensureScheduled(context, "theme_commit")
            }
          },
          TRANSITION_DURATION_MS,
        )
      }
    }
  }

  internal fun requiresFullUpdate(trigger: WidgetThemeTrigger): Boolean {
    return trigger != WidgetThemeTrigger.DATA_REFRESH
  }

  private fun updateWidgets(
    context: Context,
    resolution: WidgetThemeResolution,
    trigger: WidgetThemeTrigger,
    fullUpdate: Boolean,
  ) {
    WidgetRenderSnapshot.withSnapshot {
      if (!fullUpdate || trigger == WidgetThemeTrigger.DATA_REFRESH) {
        // A provider-only partial payload is delivered synchronously by
        // launchers that defer full RemoteViews containing collection
        // adapters. Apply list/empty visibility before a possible rebind so a
        // 1 -> 0 transition cannot leave the final cached row on screen.
        TodayListWidgetProvider.refreshAll(context, resolution)
        TodayAndNextWidgetProvider.refreshAll(context, resolution)
        TodayCourseWidgetProvider.updateRefreshPresentation(context, refreshData = true)
        VerticalScheduleWidgetProvider.refreshAll(context, resolution)
      }
      if (fullUpdate) {
        // Theme changes and collection identity changes still need a complete
        // RemoteViews rebind. The data-refresh visibility patch above protects
        // the screen while a launcher processes this potentially deferred work.
        TodayListWidgetProvider.updateAll(context, resolution)
        TodayAndNextWidgetProvider.updateAll(context, resolution)
        TodayCourseWidgetProvider.updateAll(context, resolution)
        VerticalScheduleWidgetProvider.updateAll(context, resolution)
      }
      TinyCourseWidgetProvider.updateAll(context, resolution)
    }
  }
}
