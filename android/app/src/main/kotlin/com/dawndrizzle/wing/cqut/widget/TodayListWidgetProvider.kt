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
    WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.INITIALIZATION)
  }

  override fun onReceive(context: Context, intent: Intent) {
    super.onReceive(context, intent)
    if (intent.action == ACTION_REFRESH) {
      WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.DATA_REFRESH)
    }
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
