package com.dawndrizzle.wing.cqut.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

private const val ACTION_UI_MODE_CHANGED = "android.intent.action.UI_MODE_CHANGED"

class WidgetAutoRefreshReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val action = intent.action ?: return
    val shouldRefresh =
      action == WidgetAutoRefreshScheduler.ACTION_AUTO_REFRESH ||
        action == Intent.ACTION_DATE_CHANGED ||
        action == Intent.ACTION_TIME_CHANGED ||
        action == Intent.ACTION_TIMEZONE_CHANGED ||
        action == Intent.ACTION_SCREEN_ON ||
        action == Intent.ACTION_USER_PRESENT ||
        action == ACTION_UI_MODE_CHANGED
    if (!shouldRefresh) return
    WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.DATA_REFRESH)
  }
}
