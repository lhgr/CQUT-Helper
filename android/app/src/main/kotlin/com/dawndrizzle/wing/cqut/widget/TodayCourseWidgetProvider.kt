package com.dawndrizzle.wing.cqut.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import android.widget.RemoteViews
import com.dawndrizzle.wing.cqut.R

internal enum class TodayCourseHeaderAction {
  TOGGLE_DAY,
  MANUAL_REFRESH,
  OPEN_APP,
}

class TodayCourseWidgetProvider : AppWidgetProvider() {
  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray,
  ) {
    val theme = WidgetTheme.resolve(context, WidgetThemeTrigger.DATA_REFRESH)
    updateAppWidgets(context, appWidgetManager, appWidgetIds, theme)
    WidgetAutoRefreshScheduler.schedule(context)
  }

  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    when (intent.action) {
      ACTION_REFRESH -> WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.DATA_REFRESH)
      ACTION_THEME_REFRESH -> updateTheme(context)
      ACTION_MANUAL_REFRESH -> {
        val appWidgetId =
          intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
          ScheduleWidgetRefreshWork.enqueue(context, appWidgetId)
        }
      }
      ACTION_TOGGLE_DAY -> {
        val appWidgetId =
          intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
          toggleDayOffset(context, appWidgetId)
        } else {
          WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.DATA_REFRESH)
        }
      }
    }
  }

  override fun onAppWidgetOptionsChanged(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetId: Int,
    newOptions: android.os.Bundle,
  ) {
    super.onAppWidgetOptionsChanged(context, appWidgetManager, appWidgetId, newOptions)
    updateOne(context, appWidgetId)
  }

  override fun onDeleted(
    context: Context,
    appWidgetIds: IntArray,
  ) {
    WidgetInstanceConfigStore.delete(context, appWidgetIds)
    super.onDeleted(context, appWidgetIds)
  }

  companion object {
    const val ACTION_REFRESH = "com.dawndrizzle.wing.cqut.widget.TODAY_COURSE_REFRESH"
    const val ACTION_THEME_REFRESH =
      "com.dawndrizzle.wing.cqut.widget.TODAY_COURSE_THEME_REFRESH"
    const val ACTION_TOGGLE_DAY = "com.dawndrizzle.wing.cqut.widget.TODAY_COURSE_TOGGLE_DAY"
    const val ACTION_MANUAL_REFRESH =
      "com.dawndrizzle.wing.cqut.widget.TODAY_COURSE_MANUAL_REFRESH"
    fun updateAll(context: Context, theme: WidgetThemeResolution? = null) {
      val appWidgetManager = AppWidgetManager.getInstance(context)
      val ids =
        appWidgetManager.getAppWidgetIds(ComponentName(context, TodayCourseWidgetProvider::class.java))
      updateAppWidgets(context, appWidgetManager, ids, theme)
    }

    fun updateTheme(
      context: Context,
      appWidgetIds: IntArray? = null,
    ) {
      // Full RemoteViews containing a legacy ListView adapter are delivered
      // through updateAppWidgetDeferred(). HyperOS may never request that
      // deferred payload, so patch visual fields directly and refresh rows
      // through the collection callback instead.
      updateRefreshPresentation(context, appWidgetIds = appWidgetIds, refreshData = true)
    }

    private fun updateAppWidgets(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      theme: WidgetThemeResolution? = null,
    ) {
      val fallbackTheme = theme ?: WidgetTheme.resolve(context, WidgetThemeTrigger.DATA_REFRESH)
      for (appWidgetId in appWidgetIds) {
        val resolvedTheme =
          WidgetInstanceConfigStore.resolveTheme(context, appWidgetId, fallbackTheme)
        updateAppWidget(context, appWidgetManager, appWidgetId, resolvedTheme)
      }
    }

    fun updateOne(
      context: Context,
      appWidgetId: Int,
    ) {
      val appWidgetManager = AppWidgetManager.getInstance(context)
      val fallbackTheme = WidgetTheme.resolve(context, WidgetThemeTrigger.DATA_REFRESH)
      val theme = WidgetInstanceConfigStore.resolveTheme(context, appWidgetId, fallbackTheme)
      updateAppWidget(context, appWidgetManager, appWidgetId, theme)
    }

    fun updateRefreshPresentation(
      context: Context,
      appWidgetIds: IntArray? = null,
      refreshData: Boolean = false,
    ) {
      val appWidgetManager = AppWidgetManager.getInstance(context)
      val ids =
        appWidgetIds
          ?: appWidgetManager.getAppWidgetIds(
            ComponentName(context, TodayCourseWidgetProvider::class.java),
          )
      val fallbackTheme = WidgetTheme.resolve(context, WidgetThemeTrigger.DATA_REFRESH)
      for (appWidgetId in ids) {
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) continue
        val views = RemoteViews(context.packageName, R.layout.widget_today_course)
        val theme = WidgetInstanceConfigStore.resolveTheme(context, appWidgetId, fallbackTheme)
        bindTheme(views, theme)
        val dayOffset = getDayOffset(context, appWidgetId)
        // MIUI may reapply the partial RemoteViews from its layout defaults.
        // Include every non-collection field so a status-only patch cannot
        // surface stale header text from another widget instance.
        val header = TodayWidgetData.loadHeaderByDayOffset(context, dayOffset)
        val weekCount = TodayWidgetData.loadWeekCountText(context, dayOffset)
        views.setTextViewText(R.id.tv_schedule_name, header.scheduleName)
        views.setTextViewText(R.id.tv_date, header.dateText)
        views.setTextViewText(
          R.id.tv_week_count,
          if (weekCount.isNotBlank()) " | $weekCount    " else " | ",
        )
        views.setTextViewText(R.id.tv_week, header.weekText)
        views.setTextViewText(
          R.id.empty_text,
          TodayWidgetData.loadEmptyStateText(context, dayOffset),
        )
        val refreshPresentation = TodayWidgetData.loadRefreshPresentation(context, appWidgetId)
        bindRefreshPresentation(
          context,
          views,
          appWidgetId,
          dayOffset,
          refreshPresentation,
        )
        appWidgetManager.partiallyUpdateAppWidget(appWidgetId, views)
        if (refreshData) {
          appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.lv_course)
        }
      }
    }

    fun completeManualRefresh(
      context: Context,
      previousContentFingerprint: String? = null,
      refreshId: String = "",
    ) {
      val refreshPresentation = TodayWidgetData.loadRefreshPresentation(context)
      val currentContentFingerprint = TodayWidgetData.loadDisplayedScheduleFingerprint(context)
      val refreshSucceeded =
        refreshPresentation.state == TodayWidgetData.RefreshPresentationState.NORMAL ||
          (
            context.applicationInfo.flags and android.content.pm.ApplicationInfo.FLAG_DEBUGGABLE != 0 &&
              refreshPresentation.state == TodayWidgetData.RefreshPresentationState.NEEDS_SYNC
          )
      val refreshData =
        shouldRefreshData(
          refreshSucceeded,
          previousContentFingerprint,
          currentContentFingerprint,
        )
      val contentChanged =
        previousContentFingerprint == null ||
          previousContentFingerprint != currentContentFingerprint
      Log.i(
        "WidgetManualRefresh",
        "event=completion refreshId=$refreshId state=${refreshPresentation.state} " +
          "contentChanged=$contentChanged refreshData=$refreshData",
      )
      // The visible rows are time-dependent even when the schedule JSON is
      // unchanged. A completed refresh must therefore reload the collection so
      // courses that ended while the worker was running disappear immediately.
      ScheduleWidgetRefreshWork.updateAllRefreshPresentations(context, refreshData)
      WidgetAutoRefreshScheduler.schedule(context)
    }

    internal fun shouldRefreshData(
      refreshSucceeded: Boolean,
      previousContentFingerprint: String?,
      currentContentFingerprint: String,
    ): Boolean {
      // Keep the fingerprint parameters for diagnostics and binary-compatible
      // tests, but freshness is not purely content based: elapsed time changes
      // which courses should be visible.
      return refreshSucceeded
    }

    internal fun headerActionFor(
      state: TodayWidgetData.RefreshPresentationState,
    ): TodayCourseHeaderAction {
      return when (state) {
        TodayWidgetData.RefreshPresentationState.NORMAL -> TodayCourseHeaderAction.TOGGLE_DAY
        TodayWidgetData.RefreshPresentationState.CREDENTIAL_INVALID ->
          TodayCourseHeaderAction.OPEN_APP
        TodayWidgetData.RefreshPresentationState.NEEDS_SYNC,
        TodayWidgetData.RefreshPresentationState.STALE,
        TodayWidgetData.RefreshPresentationState.LOADING,
        TodayWidgetData.RefreshPresentationState.FAILED,
        -> TodayCourseHeaderAction.MANUAL_REFRESH
      }
    }

    private fun updateAppWidget(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetId: Int,
      theme: WidgetThemeResolution,
    ) {
      val views = RemoteViews(context.packageName, R.layout.widget_today_course)

      // Keep the background on the containers instead of a full-size
      // ImageView. Some launchers briefly clear ImageView content while
      // reapplying RemoteViews, which presents as a black flash.
      bindTheme(views, theme)

      val dayOffset = getDayOffset(context, appWidgetId)
      val header = TodayWidgetData.loadHeaderByDayOffset(context, dayOffset)
      val weekCount = TodayWidgetData.loadWeekCountText(context, dayOffset)
      views.setTextViewText(R.id.tv_schedule_name, header.scheduleName)
      views.setTextViewText(R.id.tv_date, header.dateText)
      val weekCountPart = if (weekCount.isNotBlank()) " | $weekCount    " else " | "
      views.setTextViewText(R.id.tv_week_count, weekCountPart)
      views.setTextViewText(R.id.tv_week, header.weekText)
      views.setTextViewText(
        R.id.empty_text,
        TodayWidgetData.loadEmptyStateText(context, dayOffset),
      )
      val refreshPresentation = TodayWidgetData.loadRefreshPresentation(context, appWidgetId)
      views.setTextViewText(R.id.tv_sync_status, refreshPresentation.text)
      views.setViewVisibility(
        R.id.tv_sync_status,
        if (refreshPresentation.text.isBlank()) android.view.View.GONE else android.view.View.VISIBLE,
      )

      val svcIntent = Intent(context, CourseListWidgetService::class.java).apply {
        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        putExtra(CourseListWidgetService.EXTRA_DAY_OFFSET, dayOffset)
        putExtra(CourseListWidgetService.EXTRA_FOLLOW_WIDGET_DAY_OFFSET, true)
        putExtra(CourseListWidgetService.EXTRA_ADD_FIRST_ITEM_TOP_SPACING, true)
        data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME) + "#$dayOffset")
      }
      views.setRemoteAdapter(R.id.lv_course, svcIntent)
      views.setEmptyView(R.id.lv_course, android.R.id.empty)

      views.setFloat(R.id.iv_next, "setRotation", if (dayOffset == 0) 180f else 0f)
      val toggleIntent =
        Intent(context, TodayCourseWidgetProvider::class.java).apply {
          action = ACTION_TOGGLE_DAY
          putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
          data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME) + "#toggle-$appWidgetId")
        }
      val togglePendingIntent =
        PendingIntent.getBroadcast(
          context,
          appWidgetId,
          toggleIntent,
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
      val rootPendingIntent =
        WidgetNavigationPendingIntent.create(
          context,
          appWidgetId,
          dayOffset,
          false,
        )
      val coursePendingIntent =
        WidgetNavigationPendingIntent.create(
          context,
          appWidgetId,
          dayOffset,
          true,
        )
      // Clear click actions written by earlier app versions. RemoteViews can
      // be reapplied without resetting omitted listeners, so merely no longer
      // binding these ancestors is insufficient for existing widgets.
      views.setOnClickPendingIntent(R.id.widget_root, null)
      views.setOnClickPendingIntent(R.id.rl_appwidget, null)
      views.setOnClickPendingIntent(R.id.rl_title, null)
      if (rootPendingIntent != null) {
        // Keep the arrow as a sibling of the only clickable header region.
        // Clickable ancestors are flattened by some launchers and can steal
        // taps from the child PendingIntent.
        views.setOnClickPendingIntent(R.id.header_text, rootPendingIntent)
        views.setOnClickPendingIntent(android.R.id.empty, rootPendingIntent)
      }
      if (coursePendingIntent != null) {
        views.setPendingIntentTemplate(R.id.lv_course, coursePendingIntent)
      }
      // Bind the contextual action after the independent header/empty-state
      // navigation actions so later partial refreshes keep the intended PendingIntent.
      bindRefreshPresentation(
        context,
        views,
        appWidgetId,
        dayOffset,
        refreshPresentation,
        togglePendingIntent,
      )

      appWidgetManager.updateAppWidget(appWidgetId, views)
      appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.lv_course)
    }

    private fun bindTheme(
      views: RemoteViews,
      theme: WidgetThemeResolution,
    ) {
      val palette = theme.palette
      views.setInt(R.id.widget_root, "setBackgroundResource", palette.imageBackgroundRes)
      views.setInt(R.id.widget_card, "setBackgroundResource", palette.imageBackgroundRes)
      WidgetRemoteViewsTheme.setColor(views, R.id.tv_schedule_name, "setTextColor", theme) {
        it.primaryText
      }
      WidgetRemoteViewsTheme.setColor(views, R.id.tv_date, "setTextColor", theme) {
        it.primaryText
      }
      WidgetRemoteViewsTheme.setColor(views, R.id.tv_week_count, "setTextColor", theme) {
        it.secondaryText
      }
      WidgetRemoteViewsTheme.setColor(views, R.id.tv_week, "setTextColor", theme) { it.accent }
      WidgetRemoteViewsTheme.setColor(views, R.id.empty_text, "setTextColor", theme) {
        it.secondaryText
      }
      WidgetRemoteViewsTheme.setColor(views, R.id.tv_sync_status, "setTextColor", theme) {
        it.secondaryText
      }
      WidgetRemoteViewsTheme.setColor(views, R.id.iv_next, "setColorFilter", theme) { it.icon }
      WidgetRemoteViewsTheme.setColor(
        views,
        R.id.theme_transition_overlay,
        "setBackgroundColor",
        theme,
      ) { it.transitionOverlay }
      views.setViewVisibility(
        R.id.theme_transition_overlay,
        if (theme.shouldAnimate) android.view.View.VISIBLE else android.view.View.GONE,
      )
    }

    private fun bindRefreshPresentation(
      context: Context,
      views: RemoteViews,
      appWidgetId: Int,
      dayOffset: Int,
      refreshPresentation: TodayWidgetData.RefreshPresentation,
      existingTogglePendingIntent: PendingIntent? = null,
    ) {
      views.setTextViewText(R.id.tv_sync_status, refreshPresentation.text)
      views.setViewVisibility(
        R.id.tv_sync_status,
        if (refreshPresentation.text.isBlank()) android.view.View.GONE else android.view.View.VISIBLE,
      )
      val isLoading =
        refreshPresentation.state == TodayWidgetData.RefreshPresentationState.LOADING
      val headerAction = headerActionFor(refreshPresentation.state)
      views.setImageViewResource(
        R.id.iv_next,
        if (headerAction == TodayCourseHeaderAction.TOGGLE_DAY) {
          R.drawable.ic_back
        } else {
          android.R.drawable.ic_popup_sync
        },
      )
      views.setFloat(
        R.id.iv_next,
        "setRotation",
        if (headerAction == TodayCourseHeaderAction.TOGGLE_DAY && dayOffset == 0) 180f else 0f,
      )
      views.setBoolean(R.id.iv_next, "setEnabled", !isLoading)

      val manualRefreshIntent =
        Intent(context, TodayCourseWidgetProvider::class.java).apply {
          action = ACTION_MANUAL_REFRESH
          putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
          data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME) + "#refresh-$appWidgetId")
        }
      val manualRefreshPendingIntent =
        PendingIntent.getBroadcast(
          context,
          appWidgetId + 10000,
          manualRefreshIntent,
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
      val togglePendingIntent =
        existingTogglePendingIntent
          ?: PendingIntent.getBroadcast(
            context,
            appWidgetId,
            Intent(context, TodayCourseWidgetProvider::class.java).apply {
              action = ACTION_TOGGLE_DAY
              putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
              data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME) + "#toggle-$appWidgetId")
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
          )
      when (headerAction) {
        TodayCourseHeaderAction.TOGGLE_DAY ->
          views.setOnClickPendingIntent(R.id.iv_next, togglePendingIntent)
        TodayCourseHeaderAction.MANUAL_REFRESH ->
          views.setOnClickPendingIntent(R.id.iv_next, manualRefreshPendingIntent)
        TodayCourseHeaderAction.OPEN_APP ->
          WidgetNavigationPendingIntent.create(context, appWidgetId, dayOffset, false)?.let {
            views.setOnClickPendingIntent(R.id.iv_next, it)
          }
      }
    }

    private fun getDayOffset(context: Context, appWidgetId: Int): Int {
      return WidgetInstanceConfigStore.load(context, appWidgetId).dayOffset
    }

    private fun toggleDayOffset(context: Context, appWidgetId: Int) {
      val current = WidgetInstanceConfigStore.load(context, appWidgetId).dayOffset
      val next = if (current == 0) 1 else 0
      WidgetInstanceConfigStore.saveDayOffset(context, appWidgetId, next)

      // Rebinding the legacy ListView in a full update lets launchers deliver
      // rapid toggles out of order. Patch the header/action immediately and
      // make the existing factory reload the latest persisted day instead.
      updateRefreshPresentation(context, intArrayOf(appWidgetId), refreshData = true)
      WidgetAutoRefreshScheduler.schedule(context)
    }
  }
}
