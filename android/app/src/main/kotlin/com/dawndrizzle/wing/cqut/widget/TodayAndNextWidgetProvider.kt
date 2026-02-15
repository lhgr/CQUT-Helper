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
    updateAppWidgets(context, appWidgetManager, appWidgetIds)
  }

  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    if (intent.action == ACTION_REFRESH) {
      updateAll(context)
    }
  }

  companion object {
    const val ACTION_REFRESH = "com.dawndrizzle.wing.cqut.widget.TODAY_AND_NEXT_REFRESH"

    fun updateAll(context: Context) {
      val appWidgetManager = AppWidgetManager.getInstance(context)
      val ids =
        appWidgetManager.getAppWidgetIds(ComponentName(context, TodayAndNextWidgetProvider::class.java))
      updateAppWidgets(context, appWidgetManager, ids)
    }

    private fun updateAppWidgets(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetIds: IntArray,
    ) {
      for (appWidgetId in appWidgetIds) {
        updateAppWidget(context, appWidgetManager, appWidgetId)
      }
    }

    private fun updateAppWidget(
      context: Context,
      appWidgetManager: AppWidgetManager,
      appWidgetId: Int,
    ) {
      val views = RemoteViews(context.packageName, R.layout.widget_today_and_next)

      when (WidgetTheme.mode(context)) {
        WidgetTheme.Mode.DARK -> {
          views.setInt(R.id.widget_card, "setBackgroundResource", R.drawable.widget_bg_dark)
          views.setTextColor(R.id.tv_schedule_name, WidgetTheme.primaryTextColor(true))
          views.setTextColor(R.id.tv_date, WidgetTheme.secondaryTextColor(true))
          views.setTextColor(R.id.tv_week_count, WidgetTheme.secondaryTextColor(true))
          views.setTextColor(R.id.tv_week, WidgetTheme.accentColor())
          views.setTextColor(R.id.empty, WidgetTheme.secondaryTextColor(true))
          views.setTextColor(R.id.empty_next_day, WidgetTheme.secondaryTextColor(true))
        }
        WidgetTheme.Mode.LIGHT -> {
          views.setInt(R.id.widget_card, "setBackgroundResource", R.drawable.widget_bg)
          views.setTextColor(R.id.tv_schedule_name, WidgetTheme.primaryTextColor(false))
          views.setTextColor(R.id.tv_date, WidgetTheme.secondaryTextColor(false))
          views.setTextColor(R.id.tv_week_count, WidgetTheme.secondaryTextColor(false))
          views.setTextColor(R.id.tv_week, WidgetTheme.accentColor())
          views.setTextColor(R.id.empty, WidgetTheme.secondaryTextColor(false))
          views.setTextColor(R.id.empty_next_day, WidgetTheme.secondaryTextColor(false))
        }
        WidgetTheme.Mode.SYSTEM -> {
        }
      }

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
