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

class TodayListWidgetProvider : AppWidgetProvider() {
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
    const val ACTION_REFRESH = "com.dawndrizzle.wing.cqut.widget.TODAY_LIST_REFRESH"

    fun updateAll(context: Context) {
      val appWidgetManager = AppWidgetManager.getInstance(context)
      val ids =
        appWidgetManager.getAppWidgetIds(ComponentName(context, TodayListWidgetProvider::class.java))
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
      val views = RemoteViews(context.packageName, R.layout.widget_today_list)

      val dark = WidgetTheme.isDark(context)
      views.setInt(
        R.id.widget_card,
        "setBackgroundResource",
        if (dark) R.drawable.widget_bg_dark else R.drawable.widget_bg,
      )
      views.setTextColor(R.id.tv_schedule_name, WidgetTheme.primaryTextColor(dark))
      views.setTextColor(R.id.tv_date, WidgetTheme.secondaryTextColor(dark))
      views.setTextColor(R.id.tv_week, WidgetTheme.accentColor())
      views.setTextColor(R.id.empty, WidgetTheme.secondaryTextColor(dark))

      val header = TodayWidgetData.loadHeader(context)
      views.setTextViewText(R.id.tv_schedule_name, header.scheduleName)
      views.setTextViewText(R.id.tv_date, header.dateText)
      views.setTextViewText(R.id.tv_week, header.weekText)

      val svcIntent = Intent(context, CourseListWidgetService::class.java).apply {
        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        putExtra(CourseListWidgetService.EXTRA_DAY_OFFSET, 0)
        data = Uri.parse(toUri(Intent.URI_INTENT_SCHEME))
      }
      views.setRemoteAdapter(R.id.lv_course, svcIntent)
      views.setEmptyView(R.id.lv_course, R.id.empty)

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
        views.setPendingIntentTemplate(R.id.lv_course, pendingIntent)
      }

      appWidgetManager.updateAppWidget(appWidgetId, views)
      appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.lv_course)
    }
  }
}
