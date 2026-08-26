package com.dawndrizzle.wing.cqut.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.util.Log

/**
 * Keeps every widget refresh entry point on the same repair path. Rendering
 * remains cache-only; network synchronization is still reserved for the
 * explicit manual-refresh job.
 */
object WidgetRefreshCoordinator {
  private const val TAG = "WidgetRefresh"

  fun refreshAndRepair(
    context: Context,
    reason: String,
  ) {
    Log.i(TAG, "event=refresh reason=$reason at=${System.currentTimeMillis()}")
    WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.DATA_REFRESH)
  }

  fun ensureScheduled(
    context: Context,
    reason: String,
  ) {
    if (!hasActiveWidgets(context)) {
      WidgetAutoRefreshScheduler.cancel(context, reason)
      WidgetRefreshHeartbeatJobService.cancel(context, reason)
      return
    }
    WidgetAutoRefreshScheduler.schedule(context, reason)
    WidgetRefreshHeartbeatJobService.ensureScheduled(context, reason)
  }

  fun cancelIfUnused(
    context: Context,
    reason: String,
  ) {
    if (!hasActiveWidgets(context)) {
      WidgetAutoRefreshScheduler.cancel(context, reason)
      WidgetRefreshHeartbeatJobService.cancel(context, reason)
    } else {
      ensureScheduled(context, reason)
    }
  }

  fun hasActiveWidgets(context: Context): Boolean = activeWidgetIds(context).isNotEmpty()

  fun activeWidgetIds(context: Context): IntArray {
    val manager = AppWidgetManager.getInstance(context)
    return activeWidgetIds(
      manager.getAppWidgetIds(ComponentName(context, TodayListWidgetProvider::class.java)),
      manager.getAppWidgetIds(ComponentName(context, TodayAndNextWidgetProvider::class.java)),
      manager.getAppWidgetIds(ComponentName(context, TodayCourseWidgetProvider::class.java)),
    )
  }

  internal fun activeWidgetIds(vararg groups: IntArray): IntArray =
    groups
      .asSequence()
      .flatMap { it.asSequence() }
      .filter { it != AppWidgetManager.INVALID_APPWIDGET_ID }
      .distinct()
      .toList()
      .toIntArray()
}
