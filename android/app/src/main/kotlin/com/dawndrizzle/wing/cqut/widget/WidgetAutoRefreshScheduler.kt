package com.dawndrizzle.wing.cqut.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent

object WidgetAutoRefreshScheduler {
  const val ACTION_AUTO_REFRESH = "com.dawndrizzle.wing.cqut.widget.AUTO_REFRESH"
  private const val REQUEST_CODE = 9017

  fun schedule(context: Context) {
    val triggerAt = TodayWidgetData.nextRefreshAtMillis(context) ?: return
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
    val pendingIntent = pendingIntent(context)
    alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
  }

  private fun pendingIntent(context: Context): PendingIntent {
    val intent =
      Intent(context, WidgetAutoRefreshReceiver::class.java).apply {
        action = ACTION_AUTO_REFRESH
      }
    return PendingIntent.getBroadcast(
      context,
      REQUEST_CODE,
      intent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
  }
}
