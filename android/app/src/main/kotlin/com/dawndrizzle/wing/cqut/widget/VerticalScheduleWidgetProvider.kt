package com.dawndrizzle.wing.cqut.widget

import android.app.PendingIntent
import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProvider
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.view.View
import android.widget.RemoteViews
import com.dawndrizzle.wing.cqut.R

class VerticalScheduleWidgetProvider : AppWidgetProvider() {
  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray,
  ) {
    val theme = WidgetTheme.resolve(context, WidgetThemeTrigger.DATA_REFRESH)
    updateAppWidgets(context, appWidgetManager, appWidgetIds, theme)
    WidgetRefreshCoordinator.ensureScheduled(context, "vertical_schedule_update")
  }

  override fun onEnabled(context: Context) {
    super.onEnabled(context)
    WidgetRefreshCoordinator.ensureScheduled(context, "vertical_schedule_enabled")
  }

  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    when (intent.action) {
      ACTION_REFRESH -> WidgetRefreshCoordinator.refreshAndRepair(context, "vertical_schedule_action")
      ACTION_THEME_REFRESH -> {
        updateTheme(context)
        WidgetRefreshCoordinator.ensureScheduled(context, "vertical_schedule_theme")
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
    WidgetRefreshCoordinator.ensureScheduled(context, "vertical_schedule_options")
  }

  override fun onDeleted(context: Context, appWidgetIds: IntArray) {
    WidgetInstanceConfigStore.delete(context, appWidgetIds)
    super.onDeleted(context, appWidgetIds)
    WidgetRefreshCoordinator.cancelIfUnused(context, "vertical_schedule_deleted")
  }

  override fun onDisabled(context: Context) {
    super.onDisabled(context)
    WidgetRefreshCoordinator.cancelIfUnused(context, "vertical_schedule_disabled")
  }

  companion object {
    const val ACTION_REFRESH = "com.dawndrizzle.wing.cqut.widget.VERTICAL_SCHEDULE_REFRESH"
    const val ACTION_THEME_REFRESH =
      "com.dawndrizzle.wing.cqut.widget.VERTICAL_SCHEDULE_THEME_REFRESH"
    const val ACTION_MANUAL_REFRESH =
      "com.dawndrizzle.wing.cqut.widget.VERTICAL_SCHEDULE_MANUAL_REFRESH"

    fun updateAll(context: Context, theme: WidgetThemeResolution? = null) {
      val manager = AppWidgetManager.getInstance(context)
      val ids =
        manager.getAppWidgetIds(ComponentName(context, VerticalScheduleWidgetProvider::class.java))
      updateAppWidgets(context, manager, ids, theme)
    }

    fun updateTheme(context: Context, appWidgetIds: IntArray? = null) {
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
      val manager = AppWidgetManager.getInstance(context)
      val ids =
        appWidgetIds
          ?: manager.getAppWidgetIds(
            ComponentName(context, VerticalScheduleWidgetProvider::class.java),
          )
      refreshAppWidgets(context, manager, ids, theme, refreshData)
    }

    fun updateOne(context: Context, appWidgetId: Int) {
      val manager = AppWidgetManager.getInstance(context)
      val fallback = WidgetTheme.resolve(context, WidgetThemeTrigger.DATA_REFRESH)
      val theme = WidgetInstanceConfigStore.resolveTheme(context, appWidgetId, fallback)
      updateAppWidget(context, manager, appWidgetId, theme)
    }

    private fun updateAppWidgets(
      context: Context,
      manager: AppWidgetManager,
      appWidgetIds: IntArray,
      theme: WidgetThemeResolution? = null,
    ) {
      val fallback = theme ?: WidgetTheme.resolve(context, WidgetThemeTrigger.DATA_REFRESH)
      for (appWidgetId in appWidgetIds) {
        val resolved = WidgetInstanceConfigStore.resolveTheme(context, appWidgetId, fallback)
        updateAppWidget(context, manager, appWidgetId, resolved)
      }
    }

    private fun refreshAppWidgets(
      context: Context,
      manager: AppWidgetManager,
      appWidgetIds: IntArray,
      theme: WidgetThemeResolution? = null,
      refreshData: Boolean = false,
    ) {
      val fallback = theme ?: WidgetTheme.resolve(context, WidgetThemeTrigger.DATA_REFRESH)
      for (appWidgetId in appWidgetIds) {
        val resolved = WidgetInstanceConfigStore.resolveTheme(context, appWidgetId, fallback)
        val views = RemoteViews(context.packageName, R.layout.widget_vertical_schedule)
        bindPresentation(context, views, appWidgetId, resolved)
        manager.partiallyUpdateAppWidget(appWidgetId, views)
        if (refreshData) {
          manager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.lv_course)
        }
      }
    }

    private fun updateAppWidget(
      context: Context,
      manager: AppWidgetManager,
      appWidgetId: Int,
      theme: WidgetThemeResolution,
    ) {
      val views = RemoteViews(context.packageName, R.layout.widget_vertical_schedule)
      bindPresentation(context, views, appWidgetId, theme)
      val dayOffset = WidgetInstanceConfigStore.load(context, appWidgetId).dayOffset
      val serviceIntent = Intent(context, VerticalCourseListWidgetService::class.java).apply {
        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        putExtra(VerticalCourseListWidgetService.EXTRA_DAY_OFFSET, dayOffset)
        data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME) + "#vertical-$appWidgetId-$dayOffset")
      }
      views.setRemoteAdapter(R.id.lv_course, serviceIntent)
      views.setEmptyView(R.id.lv_course, R.id.empty)

      val rootIntent = WidgetNavigationPendingIntent.create(context, appWidgetId, dayOffset, false)
      val courseIntent = WidgetNavigationPendingIntent.create(context, appWidgetId, dayOffset, true)
      if (rootIntent != null) {
        views.setOnClickPendingIntent(R.id.widget_root, null)
        views.setOnClickPendingIntent(R.id.rl_title, null)
        views.setOnClickPendingIntent(R.id.header_text, rootIntent)
        views.setOnClickPendingIntent(R.id.empty, rootIntent)
      }
      if (courseIntent != null) {
        views.setPendingIntentTemplate(R.id.lv_course, courseIntent)
      }
      manager.updateAppWidget(appWidgetId, views)
      manager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.lv_course)
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
      WidgetRemoteViewsTheme.setColor(views, R.id.tv_sync_status, "setTextColor", theme) {
        it.secondaryText
      }
      WidgetRemoteViewsTheme.setColor(views, R.id.tv_course_count, "setTextColor", theme) {
        it.secondaryText
      }
      WidgetRemoteViewsTheme.setColor(views, R.id.tv_date, "setTextColor", theme) {
        it.secondaryText
      }
      WidgetRemoteViewsTheme.setColor(views, R.id.tv_week, "setTextColor", theme) { it.accent }
      WidgetRemoteViewsTheme.setColor(views, R.id.empty, "setTextColor", theme) {
        it.secondaryText
      }
      WidgetRemoteViewsTheme.setColor(views, R.id.iv_refresh, "setColorFilter", theme) {
        it.icon
      }
      WidgetRemoteViewsTheme.setColor(
        views,
        R.id.theme_transition_overlay,
        "setBackgroundColor",
        theme,
      ) { it.transitionOverlay }
      views.setViewVisibility(
        R.id.theme_transition_overlay,
        if (theme.shouldAnimate) View.VISIBLE else View.GONE,
      )

      val config = WidgetInstanceConfigStore.load(context, appWidgetId)
      val dayOffset = config.dayOffset
      val header = TodayWidgetData.loadHeaderByDayOffset(context, dayOffset)
      val weekCount = TodayWidgetData.loadWeekCountText(context, dayOffset)
      views.setTextViewText(
        R.id.tv_schedule_name,
        listOf(header.scheduleName, weekCount).filter { it.isNotBlank() }.joinToString(" · "),
      )
      views.setTextViewText(R.id.tv_date, header.dateText)
      views.setTextViewText(R.id.tv_week, header.weekText)
      views.setTextViewText(R.id.empty, TodayWidgetData.loadEmptyStateText(context, dayOffset))
      val courseCount = TodayWidgetData.loadCoursesByDayOffset(context, dayOffset).size
      views.setTextViewText(
        R.id.tv_course_count,
        courseCountText(dayOffset, courseCount),
      )

      val refresh = TodayWidgetData.loadRefreshPresentation(context, appWidgetId)
      val metadataVisibility = View.VISIBLE
      views.setViewVisibility(R.id.tv_date, metadataVisibility)
      views.setViewVisibility(R.id.tv_week, metadataVisibility)
      views.setViewVisibility(R.id.tv_course_count, metadataVisibility)
      views.setTextViewText(R.id.tv_sync_status, refresh.text)
      views.setViewVisibility(
        R.id.tv_sync_status,
        if (refresh.text.isBlank()) View.GONE else View.VISIBLE,
      )
      val isLoading = refresh.state == TodayWidgetData.RefreshPresentationState.LOADING
      views.setViewVisibility(R.id.iv_refresh, if (refresh.showsRefreshButton) android.view.View.VISIBLE else android.view.View.GONE)
      views.setBoolean(R.id.iv_refresh, "setEnabled", !isLoading)
      views.setImageViewResource(R.id.iv_refresh, R.drawable.ic_widget_refresh)
      views.setContentDescription(R.id.iv_refresh, refreshActionDescription(refresh))

      val manualRefreshIntent =
        Intent(context, VerticalScheduleWidgetProvider::class.java).apply {
          action = ACTION_MANUAL_REFRESH
          putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
          data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME) + "#manual-refresh-$appWidgetId")
        }
      val manualRefreshPendingIntent =
        PendingIntent.getBroadcast(
          context,
          appWidgetId + 40000,
          manualRefreshIntent,
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
      val refreshIntent =
        if (refresh.state == TodayWidgetData.RefreshPresentationState.CREDENTIAL_INVALID) {
          WidgetNavigationPendingIntent.create(context, appWidgetId, dayOffset, false)
        } else {
          manualRefreshPendingIntent
        }
      if (refreshIntent != null) {
        views.setOnClickPendingIntent(R.id.iv_refresh, refreshIntent)
      }
    }

    internal fun courseCountText(dayOffset: Int, courseCount: Int): String {
      return when {
        courseCount <= 0 -> ""
        WidgetInstanceConfigStore.normalizeDayOffset(dayOffset) == 0 -> "剩余${courseCount}节"
        else -> "共${courseCount}节"
      }
    }
  }
}
