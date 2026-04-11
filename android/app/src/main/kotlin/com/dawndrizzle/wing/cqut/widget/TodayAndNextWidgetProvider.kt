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

class TodayAndNextWidgetProvider : AppWidgetProvider() {
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

  companion object {
    const val ACTION_REFRESH = "com.dawndrizzle.wing.cqut.widget.TODAY_AND_NEXT_REFRESH"

    fun updateAll(context: Context, theme: WidgetThemeResolution? = null) {
      val appWidgetManager = AppWidgetManager.getInstance(context)
      val ids =
        appWidgetManager.getAppWidgetIds(ComponentName(context, TodayAndNextWidgetProvider::class.java))
      updateAppWidgets(context, appWidgetManager, ids, theme)
    }

    private fun updateAppWidgets(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
      theme: WidgetThemeResolution? = null,
    ) {
      val resolvedTheme = theme ?: WidgetTheme.resolve(context, WidgetThemeTrigger.DATA_REFRESH)
      for (appWidgetId in appWidgetIds) {
        updateAppWidget(context, appWidgetManager, appWidgetId, resolvedTheme)
      }
    }

    private fun updateAppWidget(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetId: Int,
      theme: WidgetThemeResolution,
    ) {
      val views = RemoteViews(context.packageName, R.layout.widget_today_and_next)

      val palette = theme.palette
      views.setInt(
        R.id.widget_card,
        "setBackgroundResource",
        palette.backgroundRes,
      )
      views.setTextColor(R.id.tv_schedule_name, palette.primaryText)
      views.setTextColor(R.id.tv_date, palette.secondaryText)
      views.setTextColor(R.id.tv_week, palette.accent)
      views.setTextColor(R.id.tv_week_count, palette.secondaryText)
      views.setTextColor(R.id.empty, palette.secondaryText)
      views.setTextColor(R.id.empty_next_day, palette.secondaryText)
      views.setInt(R.id.vertical_divider, "setBackgroundColor", palette.divider)
      views.setInt(R.id.theme_transition_overlay, "setBackgroundColor", palette.transitionOverlay)
      views.setViewVisibility(
        R.id.theme_transition_overlay,
        if (theme.shouldAnimate) android.view.View.VISIBLE else android.view.View.GONE,
      )

      val header = TodayWidgetData.loadHeader(context)
      val weekCount = TodayWidgetData.loadWeekCountText(context)
      views.setTextViewText(R.id.tv_schedule_name, header.scheduleName)
      views.setTextViewText(R.id.tv_date, header.dateText)
      views.setTextViewText(R.id.tv_week, header.weekText)
      views.setTextViewText(R.id.tv_week_count, weekCount)

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

      val launchIntent = context.packageManager.getLaunchIntentForPackage(context.packageName)
      if (launchIntent != null) {
        val pendingIntent =
          PendingIntent.getActivity(
            context,
            0,
            launchIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
          )
        views.setOnClickPendingIntent(R.id.widget_root, pendingIntent)
        views.setOnClickPendingIntent(R.id.rl_title, pendingIntent)
        views.setOnClickPendingIntent(R.id.empty, pendingIntent)
        views.setOnClickPendingIntent(R.id.empty_next_day, pendingIntent)
        views.setPendingIntentTemplate(R.id.lv_course, pendingIntent)
        views.setPendingIntentTemplate(R.id.lv_course_next_day, pendingIntent)
      }

      appWidgetManager.updateAppWidget(appWidgetId, views)
      appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.lv_course)
      appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.lv_course_next_day)
    }
  }
}
