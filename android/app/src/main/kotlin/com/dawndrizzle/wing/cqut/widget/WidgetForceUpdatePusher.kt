package com.dawndrizzle.wing.cqut.widget

import android.appwidget.AppWidgetManager
import android.content.ComponentName
import android.content.Context
import android.content.Intent

object WidgetForceUpdatePusher {
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
}
