package com.dawndrizzle.wing.cqut.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build

internal enum class WidgetAlarmScheduleMode {
  EXACT_ALLOW_WHILE_IDLE,
  EXACT,
  INEXACT_ALLOW_WHILE_IDLE,
  INEXACT,
}

object WidgetAutoRefreshScheduler {
  const val ACTION_AUTO_REFRESH = "com.dawndrizzle.wing.cqut.widget.AUTO_REFRESH"
  private const val REQUEST_CODE = 9017

  fun schedule(context: Context) {
    val triggerAt = TodayWidgetData.nextRefreshAtMillis(context) ?: return
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
    val pendingIntent = pendingIntent(context)
    val canScheduleExact =
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        try {
          alarmManager.canScheduleExactAlarms()
        } catch (_: RuntimeException) {
          false
        }
      } else {
        true
      }
    val mode = resolveScheduleMode(Build.VERSION.SDK_INT, canScheduleExact)
    try {
      scheduleWithMode(alarmManager, triggerAt, pendingIntent, mode)
    } catch (_: SecurityException) {
      // Exact-alarm access can be revoked between the capability check and
      // the call. Preserve eventual refresh through the permission-free path.
      scheduleWithMode(
        alarmManager,
        triggerAt,
        pendingIntent,
        resolveInexactFallbackMode(Build.VERSION.SDK_INT),
      )
    }
  }

  internal fun resolveScheduleMode(
    sdkInt: Int,
    canScheduleExact: Boolean,
  ): WidgetAlarmScheduleMode {
    return when {
      sdkInt >= Build.VERSION_CODES.S && canScheduleExact ->
        WidgetAlarmScheduleMode.EXACT_ALLOW_WHILE_IDLE
      sdkInt >= Build.VERSION_CODES.S -> WidgetAlarmScheduleMode.INEXACT_ALLOW_WHILE_IDLE
      sdkInt >= Build.VERSION_CODES.M -> WidgetAlarmScheduleMode.EXACT_ALLOW_WHILE_IDLE
      sdkInt >= Build.VERSION_CODES.KITKAT -> WidgetAlarmScheduleMode.EXACT
      else -> WidgetAlarmScheduleMode.INEXACT
    }
  }

  private fun resolveInexactFallbackMode(sdkInt: Int): WidgetAlarmScheduleMode {
    return if (sdkInt >= Build.VERSION_CODES.M) {
      WidgetAlarmScheduleMode.INEXACT_ALLOW_WHILE_IDLE
    } else {
      WidgetAlarmScheduleMode.INEXACT
    }
  }

  private fun scheduleWithMode(
    alarmManager: AlarmManager,
    triggerAt: Long,
    pendingIntent: PendingIntent,
    mode: WidgetAlarmScheduleMode,
  ) {
    when (mode) {
      WidgetAlarmScheduleMode.EXACT_ALLOW_WHILE_IDLE ->
        alarmManager.setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
      WidgetAlarmScheduleMode.EXACT ->
        alarmManager.setExact(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
      WidgetAlarmScheduleMode.INEXACT_ALLOW_WHILE_IDLE ->
        alarmManager.setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
      WidgetAlarmScheduleMode.INEXACT ->
        alarmManager.set(AlarmManager.RTC_WAKEUP, triggerAt, pendingIntent)
    }
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
