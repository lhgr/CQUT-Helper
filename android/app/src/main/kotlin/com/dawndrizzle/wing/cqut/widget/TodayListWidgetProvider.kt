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
    WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.INITIALIZATION)
  }

  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    when (intent.action) {
      ACTION_REFRESH -> WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.DATA_REFRESH)
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
    WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.SYSTEM_THEME_CHANGED)
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

    fun updateAll(context: Context, theme: WidgetThemeResolution? = null) {
      val appWidgetManager = AppWidgetManager.getInstance(context)
      val ids =
        appWidgetManager.getAppWidgetIds(ComponentName(context, TodayListWidgetProvider::class.java))
      updateAppWidgets(context, appWidgetManager, ids, theme)
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

    private fun updateAppWidget(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetId: Int,
      theme: WidgetThemeResolution,
    ) {
      val views = RemoteViews(context.packageName, R.layout.widget_today_list)

      val palette = theme.palette
      views.setInt(
        R.id.widget_card,
        "setBackgroundResource",
        palette.backgroundRes,
      )
      views.setTextColor(R.id.tv_schedule_name, palette.primaryText)
      views.setTextColor(R.id.tv_date, palette.secondaryText)
      views.setTextColor(R.id.tv_week, palette.accent)
      views.setTextColor(R.id.empty, palette.secondaryText)
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
      views.setTextViewText(
        R.id.empty,
        TodayWidgetData.loadEmptyStateText(context, dayOffset),
      )

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
  }
}
