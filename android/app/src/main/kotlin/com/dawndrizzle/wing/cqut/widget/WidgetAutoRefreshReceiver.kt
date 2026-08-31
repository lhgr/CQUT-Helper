package com.dawndrizzle.wing.cqut.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class WidgetAutoRefreshReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val action = intent.action ?: return
    WidgetNativeLog.info(
      context,
      "event=broadcast_received action=$action at=${System.currentTimeMillis()}",
    )
    if (action == ACTION_APP_THEME_REFRESH) {
      WidgetForceUpdatePusher.pushTheme(context)
      WidgetRefreshCoordinator.ensureScheduled(context, "app_theme_refresh")
      return
    }
    if (action == ACTION_MANUAL_REFRESH_WATCHDOG) {
      ScheduleWidgetRefreshWork.handleWatchdog(
        context,
        intent.getStringExtra(EXTRA_REFRESH_ID).orEmpty(),
        intent.getStringExtra(EXTRA_ACCOUNT).orEmpty(),
      )
      return
    }
    if (!isDataRefreshAction(action)) return
    WidgetRefreshCoordinator.refreshAndRepair(context, "broadcast:$action")
  }

  companion object {
    const val ACTION_APP_THEME_REFRESH =
      "com.dawndrizzle.wing.cqut.widget.APP_THEME_REFRESH"
    const val ACTION_EXACT_ALARM_PERMISSION_STATE_CHANGED =
      "android.app.action.SCHEDULE_EXACT_ALARM_PERMISSION_STATE_CHANGED"
    const val ACTION_MANUAL_REFRESH_WATCHDOG =
      "com.dawndrizzle.wing.cqut.widget.MANUAL_REFRESH_WATCHDOG"
    const val EXTRA_REFRESH_ID = "refresh_id"
    const val EXTRA_ACCOUNT = "account"

    internal fun isDataRefreshAction(action: String): Boolean {
      return action == WidgetAutoRefreshScheduler.ACTION_AUTO_REFRESH ||
        action == Intent.ACTION_TIME_CHANGED ||
        action == Intent.ACTION_TIMEZONE_CHANGED ||
        action == Intent.ACTION_BOOT_COMPLETED ||
        action == Intent.ACTION_MY_PACKAGE_REPLACED ||
        action == ACTION_EXACT_ALARM_PERMISSION_STATE_CHANGED
    }
  }
}
