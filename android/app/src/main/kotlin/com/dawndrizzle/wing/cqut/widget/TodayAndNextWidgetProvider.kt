package com.dawndrizzle.wing.cqut.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.widget.RemoteViews
import com.dawndrizzle.wing.cqut.R

class TodayAndNextWidgetProvider : AppWidgetProvider() {
  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray,
  ) {
    val theme = WidgetTheme.resolve(context, WidgetThemeTrigger.DATA_REFRESH)
    updateAppWidgets(context, appWidgetManager, appWidgetIds, theme)
    WidgetRefreshCoordinator.ensureScheduled(context, "today_and_next_update")
  }

  override fun onEnabled(context: Context) {
    super.onEnabled(context)
    WidgetRefreshCoordinator.ensureScheduled(context, "today_and_next_enabled")
  }

  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    when (intent.action) {
      ACTION_REFRESH -> WidgetRefreshCoordinator.refreshAndRepair(context, "today_and_next_action")
      ACTION_THEME_REFRESH -> {
        updateTheme(context)
        WidgetRefreshCoordinator.ensureScheduled(context, "today_and_next_theme")
      }
      ACTION_MANUAL_REFRESH -> {
        val appWidgetId =
          intent.getIntExtra(
            AppWidgetManager.EXTRA_APPWIDGET_ID,
            AppWidgetManager.INVALID_APPWIDGET_ID,
          )
        if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
          ScheduleWidgetRefreshWork.enqueue(context, appWidgetId)
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
    WidgetRefreshCoordinator.ensureScheduled(context, "today_and_next_options")
  }

  override fun onDeleted(
    context: Context,
    appWidgetIds: IntArray,
  ) {
    WidgetInstanceConfigStore.delete(context, appWidgetIds)
    super.onDeleted(context, appWidgetIds)
    WidgetRefreshCoordinator.cancelIfUnused(context, "today_and_next_deleted")
  }

  override fun onDisabled(context: Context) {
    super.onDisabled(context)
    WidgetRefreshCoordinator.cancelIfUnused(context, "today_and_next_disabled")
  }

  companion object {
    const val ACTION_REFRESH = "com.dawndrizzle.wing.cqut.widget.TODAY_AND_NEXT_REFRESH"
    const val ACTION_THEME_REFRESH =
      "com.dawndrizzle.wing.cqut.widget.TODAY_AND_NEXT_THEME_REFRESH"
    const val ACTION_MANUAL_REFRESH =
      "com.dawndrizzle.wing.cqut.widget.TODAY_AND_NEXT_MANUAL_REFRESH"

    fun updateAll(context: Context, theme: WidgetThemeResolution? = null) {
      val appWidgetManager = AppWidgetManager.getInstance(context)
      val ids =
        appWidgetManager.getAppWidgetIds(ComponentName(context, TodayAndNextWidgetProvider::class.java))
      updateAppWidgets(context, appWidgetManager, ids, theme)
    }

    fun updateTheme(
      context: Context,
      appWidgetIds: IntArray? = null,
    ) {
      // Keep both legacy ListView adapters out of the theme payload. HyperOS
      // otherwise defers the full update and can leave this widget on its
      // previous palette indefinitely.
      updateRefreshPresentation(context, appWidgetIds = appWidgetIds, refreshData = true)
    }

    fun refreshAll(context: Context, theme: WidgetThemeResolution? = null) {
      updateRefreshPresentation(context, theme = theme, refreshData = true)
    }

    fun updateRefreshPresentation(
      context: Context,
      appWidgetIds: IntArray? = null,
      theme: WidgetThemeResolution? = null,
      refreshData: Boolean = false,
    ) {
      val appWidgetManager = AppWidgetManager.getInstance(context)
      val ids =
        appWidgetIds
          ?: appWidgetManager.getAppWidgetIds(
            ComponentName(context, TodayAndNextWidgetProvider::class.java),
          )
      refreshAppWidgets(context, appWidgetManager, ids, theme, refreshData)
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

    private fun refreshAppWidgets(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      theme: WidgetThemeResolution? = null,
      refreshData: Boolean = false,
    ) {
      val fallbackTheme = theme ?: WidgetTheme.resolve(context, WidgetThemeTrigger.DATA_REFRESH)
      for (appWidgetId in appWidgetIds) {
        val resolvedTheme =
          WidgetInstanceConfigStore.resolveTheme(context, appWidgetId, fallbackTheme)
        val views = RemoteViews(context.packageName, R.layout.widget_today_and_next)
        bindPresentation(context, views, appWidgetId, resolvedTheme)
        appWidgetManager.partiallyUpdateAppWidget(appWidgetId, views)
        if (refreshData) {
          appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.lv_course)
          appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.lv_course_next_day)
        }
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

    private fun updateAppWidget(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetId: Int,
      theme: WidgetThemeResolution,
    ) {
      val views = RemoteViews(context.packageName, R.layout.widget_today_and_next)
      bindPresentation(context, views, appWidgetId, theme)

      val todayIntent = Intent(context, CourseListWidgetService::class.java).apply {
        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        putExtra(CourseListWidgetService.EXTRA_DAY_OFFSET, 0)
        data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME) + "#today")
      }
      val nextIntent = Intent(context, CourseListWidgetService::class.java).apply {
        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        putExtra(CourseListWidgetService.EXTRA_DAY_OFFSET, 1)
        data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME) + "#next")
      }
      views.setRemoteAdapter(R.id.lv_course, todayIntent)
      views.setRemoteAdapter(R.id.lv_course_next_day, nextIntent)
      views.setEmptyView(R.id.lv_course, R.id.empty)
      views.setEmptyView(R.id.lv_course_next_day, R.id.empty_next_day)

      val rootPendingIntent =
        WidgetNavigationPendingIntent.create(context, appWidgetId, 0, false)
      val todayCoursePendingIntent =
        WidgetNavigationPendingIntent.create(context, appWidgetId, 0, true)
      val nextCoursePendingIntent =
        WidgetNavigationPendingIntent.create(context, appWidgetId, 1, true)
      if (rootPendingIntent != null) {
        views.setOnClickPendingIntent(R.id.widget_root, rootPendingIntent)
        views.setOnClickPendingIntent(R.id.rl_title, rootPendingIntent)
        views.setOnClickPendingIntent(R.id.empty, rootPendingIntent)
        views.setOnClickPendingIntent(R.id.empty_next_day, rootPendingIntent)
      }
      if (todayCoursePendingIntent != null) {
        views.setPendingIntentTemplate(R.id.lv_course, todayCoursePendingIntent)
      }
      if (nextCoursePendingIntent != null) {
        views.setPendingIntentTemplate(
          R.id.lv_course_next_day,
          nextCoursePendingIntent,
        )
      }

      appWidgetManager.updateAppWidget(appWidgetId, views)
      appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.lv_course)
      appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.lv_course_next_day)
    }

    private fun bindPresentation(
      context: Context,
      views: RemoteViews,
      appWidgetId: Int,
      theme: WidgetThemeResolution,
    ) {
      val palette = theme.palette
      views.setInt(R.id.widget_card, "setBackgroundResource", palette.backgroundRes)
      WidgetRemoteViewsTheme.setColor(views, R.id.tv_schedule_name, "setTextColor", theme) {
        it.primaryText
      }
      WidgetRemoteViewsTheme.setColor(views, R.id.tv_date, "setTextColor", theme) {
        it.secondaryText
      }
      WidgetRemoteViewsTheme.setColor(views, R.id.tv_week, "setTextColor", theme) { it.accent }
      WidgetRemoteViewsTheme.setColor(views, R.id.tv_week_count, "setTextColor", theme) {
        it.secondaryText
      }
      WidgetRemoteViewsTheme.setColor(views, R.id.empty, "setTextColor", theme) {
        it.secondaryText
      }
      WidgetRemoteViewsTheme.setColor(views, R.id.empty_next_day, "setTextColor", theme) {
        it.secondaryText
      }
      WidgetRemoteViewsTheme.setColor(views, R.id.tv_sync_status, "setTextColor", theme) {
        it.secondaryText
      }
      WidgetRemoteViewsTheme.setColor(views, R.id.iv_refresh, "setColorFilter", theme) { it.icon }
      WidgetRemoteViewsTheme.setColor(views, R.id.vertical_divider, "setBackgroundColor", theme) {
        it.divider
      }
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

      val header = TodayWidgetData.loadHeader(context)
      views.setTextViewText(R.id.tv_schedule_name, header.scheduleName)
      views.setTextViewText(R.id.tv_date, header.dateText)
      views.setTextViewText(R.id.tv_week, header.weekText)
      views.setTextViewText(R.id.tv_week_count, TodayWidgetData.loadWeekCountText(context))
      views.setTextViewText(R.id.empty, TodayWidgetData.loadEmptyStateText(context, 0))
      views.setTextViewText(R.id.empty_next_day, TodayWidgetData.loadEmptyStateText(context, 1))

      val refreshPresentation =
        TodayWidgetData.loadRefreshPresentation(
          context,
          appWidgetId,
          requiredDayOffsets = intArrayOf(0, 1),
        )
      val dateVisibility =
        if (refreshPresentation.replacesDateMetadata) {
          android.view.View.GONE
        } else {
          android.view.View.VISIBLE
        }
      views.setViewVisibility(R.id.tv_date, dateVisibility)
      views.setViewVisibility(R.id.tv_week_count, dateVisibility)
      views.setViewVisibility(R.id.tv_week, dateVisibility)
      views.setTextViewText(R.id.tv_sync_status, refreshPresentation.text)
      views.setViewVisibility(
        R.id.tv_sync_status,
        if (refreshPresentation.text.isBlank()) android.view.View.GONE else android.view.View.VISIBLE,
      )
      val isLoading =
        refreshPresentation.state == TodayWidgetData.RefreshPresentationState.LOADING
      val showRefreshAction = refreshPresentation.usesRefreshAction || isLoading
      views.setViewVisibility(
        R.id.iv_refresh,
        if (showRefreshAction) android.view.View.VISIBLE else android.view.View.GONE,
      )
      views.setBoolean(R.id.iv_refresh, "setEnabled", !isLoading)
      val manualRefreshIntent =
        Intent(context, TodayAndNextWidgetProvider::class.java).apply {
          action = ACTION_MANUAL_REFRESH
          putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
          data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME) + "#manual-refresh-$appWidgetId")
        }
      val manualRefreshPendingIntent =
        PendingIntent.getBroadcast(
          context,
          appWidgetId + 30000,
          manualRefreshIntent,
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
      val refreshPendingIntent =
        if (
          refreshPresentation.state ==
            TodayWidgetData.RefreshPresentationState.CREDENTIAL_INVALID
        ) {
          WidgetNavigationPendingIntent.create(context, appWidgetId, 0, false)
        } else {
          manualRefreshPendingIntent
        }
      if (refreshPendingIntent != null) {
        views.setOnClickPendingIntent(R.id.iv_refresh, refreshPendingIntent)
      }
    }
  }
}
