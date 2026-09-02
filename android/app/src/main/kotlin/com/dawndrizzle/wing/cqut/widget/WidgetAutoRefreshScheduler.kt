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

internal data class WidgetAlarmScheduleKey(
  val triggerAtMillis: Long,
  val mode: WidgetAlarmScheduleMode,
)

object WidgetAutoRefreshScheduler {
  const val ACTION_AUTO_REFRESH = "com.dawndrizzle.wing.cqut.widget.AUTO_REFRESH"
  private const val REQUEST_CODE = 9017
  private var lastScheduledKey: WidgetAlarmScheduleKey? = null
  private var cancellationCheckedInProcess = false

  @Synchronized
  fun schedule(
    context: Context,
    reason: String = "unspecified",
  ): Boolean {
    val target = TodayWidgetData.nextRefreshTarget(context) ?: return false
    val triggerAt = target.atMillis
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
      ?: run {
        WidgetNativeLog.error(context, "event=alarm_unavailable reason=$reason")
        return false
      }
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
    val scheduleKey = WidgetAlarmScheduleKey(triggerAt, mode)
    if (lastScheduledKey == scheduleKey) {
      WidgetNativeLog.debug(
        context,
        "event=alarm_schedule_unchanged reason=$reason triggerAt=$triggerAt mode=$mode",
      )
      return true
    }
    return try {
      scheduleWithMode(alarmManager, triggerAt, pendingIntent, mode)
      lastScheduledKey = scheduleKey
      cancellationCheckedInProcess = false
      WidgetNativeLog.info(
        context,
        "event=alarm_scheduled reason=$reason triggerAt=$triggerAt " +
          "targetKind=${target.kind} mode=$mode",
      )
      true
    } catch (error: SecurityException) {
      // Exact-alarm access can be revoked between the capability check and
      // the call. Preserve eventual refresh through the permission-free path.
      val fallbackMode = resolveInexactFallbackMode(Build.VERSION.SDK_INT)
      try {
        scheduleWithMode(alarmManager, triggerAt, pendingIntent, fallbackMode)
        lastScheduledKey = WidgetAlarmScheduleKey(triggerAt, fallbackMode)
        cancellationCheckedInProcess = false
        WidgetNativeLog.warn(
          context,
          "event=alarm_fallback reason=$reason triggerAt=$triggerAt " +
            "targetKind=${target.kind} mode=$fallbackMode",
          error,
        )
        true
      } catch (fallbackError: RuntimeException) {
        WidgetNativeLog.error(
          context,
          "event=alarm_schedule_failed reason=$reason",
          fallbackError,
        )
        false
      }
    } catch (error: RuntimeException) {
      WidgetNativeLog.error(context, "event=alarm_schedule_failed reason=$reason", error)
      false
    }
  }

  @Synchronized
  fun cancel(
    context: Context,
    reason: String = "unspecified",
  ) {
    if (lastScheduledKey == null && cancellationCheckedInProcess) return
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
    try {
      alarmManager.cancel(pendingIntent(context))
      lastScheduledKey = null
      cancellationCheckedInProcess = true
      WidgetNativeLog.info(context, "event=alarm_cancelled reason=$reason")
    } catch (error: RuntimeException) {
      WidgetNativeLog.error(context, "event=alarm_cancel_failed reason=$reason", error)
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

  internal fun resolveInexactFallbackMode(sdkInt: Int): WidgetAlarmScheduleMode {
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
