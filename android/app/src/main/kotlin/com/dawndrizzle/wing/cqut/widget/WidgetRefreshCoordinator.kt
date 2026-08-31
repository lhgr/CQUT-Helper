package com.dawndrizzle.wing.cqut.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context

/**
 * Keeps every widget refresh entry point on the same repair path. Rendering
 * remains cache-only; network synchronization is still reserved for the
 * explicit manual-refresh job.
 */
object WidgetRefreshCoordinator {
  internal const val REFRESH_COALESCE_WINDOW_MILLIS = 2_000L
  private val refreshLock = Any()

  fun refreshAndRepair(
    context: Context,
    reason: String,
  ) {
    synchronized(refreshLock) {
      val current = WidgetRefreshRenderStateStore.capture(context)
      val previous = WidgetRefreshRenderStateStore.load(context)
      if (
        WidgetRefreshRenderStateStore.shouldCoalesce(
          previous,
          current,
          REFRESH_COALESCE_WINDOW_MILLIS,
        )
      ) {
        WidgetNativeLog.debug(context, "event=refresh_coalesced reason=$reason")
        ensureScheduled(context, reason)
        return
      }
      refreshAndRepair(context, reason, current, previous)
    }
  }

  /**
   * Uses any process start as a repair opportunity without redrawing on every
   * worker or service launch.
   */
  fun repairIfDue(
    context: Context,
    reason: String,
  ): Boolean {
    if (!hasActiveWidgets(context)) {
      cancelAll(context, reason)
      return false
    }
    synchronized(refreshLock) {
      val current = WidgetRefreshRenderStateStore.capture(context)
      val previous = WidgetRefreshRenderStateStore.load(context)
      if (WidgetRefreshRenderStateStore.shouldRefresh(previous, current)) {
        refreshAndRepair(context, reason, current, previous)
        return true
      }
      WidgetNativeLog.debug(
        context,
        "event=repair_not_due reason=$reason logicalDate=${current.logicalDate}",
      )
      ensureScheduled(context, reason)
      return false
    }
  }

  fun ensureScheduled(
    context: Context,
    reason: String,
  ) {
    if (!hasActiveWidgets(context)) {
      cancelAll(context, reason)
      return
    }
    WidgetAutoRefreshScheduler.schedule(context, reason)
    WidgetRefreshRecoveryWork.ensureScheduled(context, reason)
    WidgetRefreshHeartbeatJobService.retireIfNeeded(context, reason)
  }

  fun cancelIfUnused(
    context: Context,
    reason: String,
  ) {
    if (!hasActiveWidgets(context)) {
      cancelAll(context, reason)
    } else {
      ensureScheduled(context, reason)
    }
  }

  internal fun recordRenderedState(
    context: Context,
    state: WidgetRefreshRenderState? = null,
    persistLog: Boolean = true,
  ) {
    val renderedState = state ?: WidgetRefreshRenderStateStore.capture(context)
    WidgetRefreshRenderStateStore.save(context, renderedState)
    if (persistLog) {
      WidgetNativeLog.info(
        context,
        "event=render_state_saved logicalDate=${renderedState.logicalDate} " +
          "presentation=${renderedState.presentationSignature} " +
          "content=${renderedState.contentSignature}",
      )
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

  private fun refreshAndRepair(
    context: Context,
    reason: String,
    current: WidgetRefreshRenderState,
    previous: WidgetRefreshRenderState?,
  ) {
    val fullUpdate = WidgetRefreshRenderStateStore.shouldUseFullUpdate(previous, current)
    WidgetNativeLog.info(
      context,
      "event=refresh reason=$reason at=${System.currentTimeMillis()} full=$fullUpdate " +
        "previousDate=${previous?.logicalDate.orEmpty()} currentDate=${current.logicalDate} " +
        "previousPresentation=${previous?.presentationSignature.orEmpty()} " +
        "currentPresentation=${current.presentationSignature}",
    )
    WidgetThemeSyncDispatcher.dispatch(
      context,
      WidgetThemeTrigger.DATA_REFRESH,
      forceFullUpdate = fullUpdate,
      renderedState = current,
    )
  }

  private fun cancelAll(
    context: Context,
    reason: String,
  ) {
    WidgetAutoRefreshScheduler.cancel(context, reason)
    WidgetRefreshRecoveryWork.cancel(context, reason)
    WidgetRefreshHeartbeatJobService.cancel(context, reason)
    WidgetRefreshRenderStateStore.clear(context)
  }
}
