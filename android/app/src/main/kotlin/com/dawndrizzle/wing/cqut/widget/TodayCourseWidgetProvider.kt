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

class TodayCourseWidgetProvider : AppWidgetProvider() {
  override fun onUpdate(
    context: Context,
    appWidgetManager: AppWidgetManager,
    appWidgetIds: IntArray,
  ) {
    updateAppWidgets(context, appWidgetManager, appWidgetIds)
  }

  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    when (intent.action) {
      ACTION_REFRESH -> updateAll(context)
      ACTION_TOGGLE_DAY -> {
        val appWidgetId =
          intent.getIntExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, AppWidgetManager.INVALID_APPWIDGET_ID)
        if (appWidgetId != AppWidgetManager.INVALID_APPWIDGET_ID) {
          toggleDayOffset(context, appWidgetId)
        } else {
          updateAll(context)
        }
      }
    }
  }

  companion object {
    const val ACTION_REFRESH = "com.dawndrizzle.wing.cqut.widget.TODAY_COURSE_REFRESH"
    const val ACTION_TOGGLE_DAY = "com.dawndrizzle.wing.cqut.widget.TODAY_COURSE_TOGGLE_DAY"
    private const val PREFS_NAME = "TodayCourseWidgetPrefs"

    fun updateAll(context: Context) {
      val appWidgetManager = AppWidgetManager.getInstance(context)
      val ids =
        appWidgetManager.getAppWidgetIds(ComponentName(context, TodayCourseWidgetProvider::class.java))
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
      val views = RemoteViews(context.packageName, R.layout.widget_today_course)

      val dark = WidgetTheme.isDark(context)
      views.setImageViewResource(R.id.iv_appwidget, if (dark) R.drawable.appwidget_bg_dark else R.drawable.appwidget_bg)
      views.setInt(R.id.tv_schedule_name, "setTextColor", WidgetTheme.primaryTextColor(dark))
      views.setInt(R.id.tv_date, "setTextColor", WidgetTheme.primaryTextColor(dark))
      views.setInt(R.id.tv_week_count, "setTextColor", WidgetTheme.secondaryTextColor(dark))
      views.setInt(R.id.tv_week, "setTextColor", WidgetTheme.accentColor())
      views.setInt(R.id.empty_text, "setTextColor", WidgetTheme.secondaryTextColor(dark))

      val dayOffset = getDayOffset(context, appWidgetId)
      val header = TodayWidgetData.loadHeaderByDayOffset(context, dayOffset)
      val weekCount = TodayWidgetData.loadWeekCountText(context)
      views.setTextViewText(R.id.tv_schedule_name, header.scheduleName)
      views.setTextViewText(R.id.tv_date, header.dateText)
      val weekCountPart = if (weekCount.isNotBlank()) " | $weekCount    " else " | "
      views.setTextViewText(R.id.tv_week_count, weekCountPart)
      views.setTextViewText(R.id.tv_week, header.weekText)

      val svcIntent = Intent(context, CourseListWidgetService::class.java).apply {
        putExtra(AppWidgetManager.EXTRA_APPWIDGET_ID, appWidgetId)
        putExtra(CourseListWidgetService.EXTRA_DAY_OFFSET, dayOffset)
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
      views.setOnClickPendingIntent(R.id.iv_next, togglePendingIntent)

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
        views.setOnClickPendingIntent(R.id.rl_appwidget, pendingIntent)
        views.setOnClickPendingIntent(R.id.rl_title, pendingIntent)
        views.setOnClickPendingIntent(android.R.id.empty, pendingIntent)
        views.setPendingIntentTemplate(R.id.lv_course, pendingIntent)
      }

      appWidgetManager.updateAppWidget(appWidgetId, views)
      appWidgetManager.notifyAppWidgetViewDataChanged(appWidgetId, R.id.lv_course)
    }

    private fun getDayOffset(context: Context, appWidgetId: Int): Int {
      val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
      return prefs.getInt("dayOffset_$appWidgetId", 0).coerceIn(0, 1)
    }

    private fun toggleDayOffset(context: Context, appWidgetId: Int) {
      val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
      val current = prefs.getInt("dayOffset_$appWidgetId", 0).coerceIn(0, 1)
      val next = if (current == 0) 1 else 0
      prefs.edit().putInt("dayOffset_$appWidgetId", next).apply()

      val appWidgetManager = AppWidgetManager.getInstance(context)
      updateAppWidget(context, appWidgetManager, appWidgetId)
    }
  }
}
