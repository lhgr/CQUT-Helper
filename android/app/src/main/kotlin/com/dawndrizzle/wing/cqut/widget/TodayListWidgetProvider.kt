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

private const val ACTION_UI_MODE_CHANGED = "android.intent.action.UI_MODE_CHANGED"
private const val ACTION_APPWIDGET_UPDATE_OPTIONS = "android.appwidget.action.APPWIDGET_UPDATE_OPTIONS"

class TodayListWidgetProvider : AppWidgetProvider() {
  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray,
  ) {
    val theme = WidgetTheme.resolve(context, WidgetThemeTrigger.INITIALIZATION)
    if (ScheduleWidgetRefreshWork.shouldSuppressProviderUpdate(context)) {
      refreshAppWidgets(context, appWidgetManager, appWidgetIds, theme)
    } else {
      updateAppWidgets(context, appWidgetManager, appWidgetIds, theme)
    }
    WidgetAutoRefreshScheduler.schedule(context)
  }

  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    when (intent.action) {
      ACTION_REFRESH -> refreshAll(context)
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
      Intent.ACTION_CONFIGURATION_CHANGED ->
        WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.SYSTEM_THEME_CHANGED)
      ACTION_UI_MODE_CHANGED ->
        WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.SYSTEM_THEME_CHANGED)
      ACTION_APPWIDGET_UPDATE_OPTIONS ->
        WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.SYSTEM_THEME_CHANGED)
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
    const val ACTION_REFRESH = "com.dawndrizzle.wing.cqut.widget.TODAY_LIST_REFRESH"
    const val ACTION_MANUAL_REFRESH =
      "com.dawndrizzle.wing.cqut.widget.TODAY_LIST_MANUAL_REFRESH"

    fun updateAll(context: Context, theme: WidgetThemeResolution? = null) {
      val appWidgetManager = AppWidgetManager.getInstance(context)
      val ids =
        appWidgetManager.getAppWidgetIds(ComponentName(context, TodayListWidgetProvider::class.java))
      updateAppWidgets(context, appWidgetManager, ids, theme)
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
            ComponentName(context, TodayListWidgetProvider::class.java),
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
        val views = RemoteViews(context.packageName, R.layout.widget_today_list)
        bindPresentation(context, views, appWidgetId, resolvedTheme)
        appWidgetManager.partiallyUpdateAppWidget(appWidgetId, views)
        if (refreshData) {
          appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.lv_course)
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
      val views = RemoteViews(context.packageName, R.layout.widget_today_list)
      bindPresentation(context, views, appWidgetId, theme)
      val dayOffset = WidgetInstanceConfigStore.load(context, appWidgetId).dayOffset

      val svcIntent = Intent(context, CourseListWidgetService::class.java).apply {
        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        putExtra(CourseListWidgetService.EXTRA_DAY_OFFSET, dayOffset)
        data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME) + "#$dayOffset")
      }
      views.setRemoteAdapter(R.id.lv_course, svcIntent)
      views.setEmptyView(R.id.lv_course, R.id.empty)

      val rootPendingIntent =
        WidgetNavigationPendingIntent.create(context, appWidgetId, dayOffset, false)
      val coursePendingIntent =
        WidgetNavigationPendingIntent.create(context, appWidgetId, dayOffset, true)
      if (rootPendingIntent != null) {
        views.setOnClickPendingIntent(R.id.widget_root, rootPendingIntent)
        views.setOnClickPendingIntent(R.id.rl_title, rootPendingIntent)
        views.setOnClickPendingIntent(R.id.empty, rootPendingIntent)
      }
      if (coursePendingIntent != null) {
        views.setPendingIntentTemplate(R.id.lv_course, coursePendingIntent)
      }

      appWidgetManager.updateAppWidget(appWidgetId, views)
      appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.lv_course)
    }

    private fun bindPresentation(
      context: Context,
      views: RemoteViews,
      appWidgetId: Int,
      theme: WidgetThemeResolution,
    ) {
      val palette = theme.palette
      views.setInt(R.id.widget_card, "setBackgroundResource", palette.backgroundRes)
      views.setTextColor(R.id.tv_schedule_name, palette.primaryText)
      views.setTextColor(R.id.tv_date, palette.secondaryText)
      views.setTextColor(R.id.tv_week, palette.accent)
      views.setTextColor(R.id.empty, palette.secondaryText)
      views.setTextColor(R.id.tv_sync_status, palette.secondaryText)
      views.setInt(R.id.iv_refresh, "setColorFilter", palette.icon)
      views.setInt(R.id.theme_transition_overlay, "setBackgroundColor", palette.transitionOverlay)
      views.setViewVisibility(
        R.id.theme_transition_overlay,
        if (theme.shouldAnimate) android.view.View.VISIBLE else android.view.View.GONE,
      )

      val dayOffset = WidgetInstanceConfigStore.load(context, appWidgetId).dayOffset
      val header = TodayWidgetData.loadHeaderByDayOffset(context, dayOffset)
      views.setTextViewText(R.id.tv_schedule_name, header.scheduleName)
      views.setTextViewText(R.id.tv_date, header.dateText)
      views.setTextViewText(R.id.tv_week, header.weekText)
      views.setTextViewText(R.id.empty, TodayWidgetData.loadEmptyStateText(context, dayOffset))

      val refreshPresentation = TodayWidgetData.loadRefreshPresentation(context, appWidgetId)
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
        Intent(context, TodayListWidgetProvider::class.java).apply {
          action = ACTION_MANUAL_REFRESH
          putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
          data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME) + "#manual-refresh-$appWidgetId")
        }
      val manualRefreshPendingIntent =
        PendingIntent.getBroadcast(
          context,
          appWidgetId + 20000,
          manualRefreshIntent,
          PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
      val refreshPendingIntent =
        if (
          refreshPresentation.state ==
            TodayWidgetData.RefreshPresentationState.CREDENTIAL_INVALID
        ) {
          WidgetNavigationPendingIntent.create(context, appWidgetId, dayOffset, false)
        } else {
          manualRefreshPendingIntent
        }
      if (refreshPendingIntent != null) {
        views.setOnClickPendingIntent(R.id.iv_refresh, refreshPendingIntent)
      }
    }
  }
}
