package com.dawndrizzle.wing.cqut.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent

object WidgetForceUpdatePusher {
  fun pushTheme(context: Context) {
    pushAction(
      context,
      TodayListWidgetProvider::class.java,
      TodayListWidgetProvider.ACTION_THEME_REFRESH,
    )
    pushAction(
      context,
      TodayAndNextWidgetProvider::class.java,
      TodayAndNextWidgetProvider.ACTION_THEME_REFRESH,
    )
    pushAction(
      context,
      TodayCourseWidgetProvider::class.java,
      TodayCourseWidgetProvider.ACTION_THEME_REFRESH,
    )
    pushAction(
      context,
      TinyCourseWidgetProvider::class.java,
      TinyCourseWidgetProvider.ACTION_THEME_REFRESH,
    )
    pushAction(
      context,
      VerticalScheduleWidgetProvider::class.java,
      VerticalScheduleWidgetProvider.ACTION_THEME_REFRESH,
    )
  }

  fun push(context: Context) {
    val manager = AppWidgetManager.getInstance(context)
    pushOne(
      context = context,
      manager = manager,
      provider = TodayListWidgetProvider::class.java,
      refreshAction = TodayListWidgetProvider.ACTION_REFRESH,
    )
    pushOne(
      context = context,
      manager = manager,
      provider = TodayAndNextWidgetProvider::class.java,
      refreshAction = TodayAndNextWidgetProvider.ACTION_REFRESH,
    )
    pushOne(
      context = context,
      manager = manager,
      provider = TodayCourseWidgetProvider::class.java,
      refreshAction = TodayCourseWidgetProvider.ACTION_REFRESH,
    )
    pushOne(
      context = context,
      manager = manager,
      provider = TinyCourseWidgetProvider::class.java,
      refreshAction = TinyCourseWidgetProvider.ACTION_REFRESH,
    )
    pushOne(
      context = context,
      manager = manager,
      provider = VerticalScheduleWidgetProvider::class.java,
      refreshAction = VerticalScheduleWidgetProvider.ACTION_REFRESH,
    )
  }

  private fun pushOne(
    context: Context,
    manager: AppWidgetManager,
    provider: Class<*>,
    refreshAction: String,
  ) {
    val ids = manager.getAppWidgetIds(ComponentName(context, provider))
    if (ids.isEmpty()) return
    val intent =
      Intent(AppWidgetManager.ACTION_APPWIDGET_UPDATE).apply {
        component = ComponentName(context, provider)
        putExtra(AppWidgetManager.EXTRA_APPWIDGET_IDS, ids)
      }
    context.sendBroadcast(intent)
    context.sendBroadcast(
      Intent(refreshAction).apply {
        component = ComponentName(context, provider)
      },
    )
  }

  private fun pushAction(
    context: Context,
    provider: Class<*>,
    action: String,
  ) {
    val manager = AppWidgetManager.getInstance(context)
    if (manager.getAppWidgetIds(ComponentName(context, provider)).isEmpty()) return
    context.sendBroadcast(
      Intent(action).apply {
        component = ComponentName(context, provider)
      },
    )
  }
}
