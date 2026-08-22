package com.dawndrizzle.wing.cqut.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class WidgetAutoRefreshReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val action = intent.action ?: return
    if (action == ACTION_APP_THEME_REFRESH) {
      WidgetForceUpdatePusher.pushTheme(context)
      WidgetAutoRefreshScheduler.schedule(context)
      return
    }
    if (!isDataRefreshAction(action)) return
    WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.DATA_REFRESH)
  }

  companion object {
    const val ACTION_APP_THEME_REFRESH =
      "com.dawndrizzle.wing.cqut.widget.APP_THEME_REFRESH"
    const val ACTION_EXACT_ALARM_PERMISSION_STATE_CHANGED =
      "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED"

    internal fun isDataRefreshAction(action: String): Boolean {
      return action == WidgetAutoRefreshScheduler.ACTION_AUTO_REFRESH ||
        action == Intent.ACTION_DATE_CHANGED ||
        action == Intent.ACTION_TIME_CHANGED ||
        action == Intent.ACTION_TIMEZONE_CHANGED ||
        action == Intent.ACTION_SCREEN_ON ||
        action == Intent.ACTION_USER_PRESENT ||
        action == Intent.ACTION_BOOT_COMPLETED ||
        action == Intent.ACTION_MY_PACKAGE_REPLACED ||
        action == ACTION_EXACT_ALARM_PERMISSION_STATE_CHANGED
    }
  }
}
