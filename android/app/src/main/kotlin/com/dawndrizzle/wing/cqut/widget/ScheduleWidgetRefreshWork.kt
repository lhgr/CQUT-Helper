package com.dawndrizzle.wing.cqut.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.util.Log
import java.util.UUID

object ScheduleWidgetRefreshWork {
  private const val PREFS_NAME = "FlutterSharedPreferences"
  private const val LEASE_PREFS_NAME = "ScheduleWidgetManualRefresh"
  private const val FLUTTER_PREFIX = "flutter."
  private const val STATE_KEY_PREFIX = "${FLUTTER_PREFIX}schedule_widget_refresh_state_"
  private const val FAILURE_KEY_PREFIX = "${FLUTTER_PREFIX}schedule_widget_refresh_failure_"
  private const val TOKEN_KEY_PREFIX = "${FLUTTER_PREFIX}schedule_widget_refresh_token_"
  private const val LEASE_TOKEN_KEY = "active_token"
  private const val LEASE_STARTED_AT_KEY = "active_started_at"
  private const val LEASE_TIMEOUT_MS = 15L * 60 * 1000
  private const val WATCHDOG_REQUEST_CODE = 0x43515744
  private const val TAG = "WidgetManualRefresh"

  @Synchronized
  fun enqueue(context: Context, appWidgetId: Int) {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val account = prefs.getString("${FLUTTER_PREFIX}account", null)?.trim().orEmpty()
    if (account.isEmpty()) {
      Log.i(TAG, "event=click_rejected reason=missing_account widgetId=$appWidgetId")
      updateAllRefreshPresentations(context, refreshData = true)
      return
    }

    val now = System.currentTimeMillis()
    val leasePrefs = context.getSharedPreferences(LEASE_PREFS_NAME, Context.MODE_PRIVATE)
    val activeToken = leasePrefs.getString(LEASE_TOKEN_KEY, null)
    val activeStartedAt = leasePrefs.getLong(LEASE_STARTED_AT_KEY, 0L)
    if (!shouldAcceptClick(activeToken, activeStartedAt, now)) {
      Log.i(
        TAG,
        "event=click_deduplicated widgetId=$appWidgetId refreshId=$activeToken",
      )
      return
    }

    val refreshId = UUID.randomUUID().toString()
    leasePrefs
      .edit()
      .putString(LEASE_TOKEN_KEY, refreshId)
      .putLong(LEASE_STARTED_AT_KEY, now)
      .commit()
    prefs
      .edit()
      .putString("$STATE_KEY_PREFIX$account", "loading")
      .remove("$FAILURE_KEY_PREFIX$account")
      .putString("$TOKEN_KEY_PREFIX$account", refreshId)
      .commit()
    updateAllRefreshPresentations(context, refreshData = true)

    val contentFingerprint = TodayWidgetData.loadDisplayedScheduleFingerprint(context)
    try {
      // A stable JobService avoids WorkManager toggling its RescheduleReceiver
      // for every widget click. Some MIUI/HyperOS launchers respond to that
      // package-component change by redrawing the app icon and making it flash.
      scheduleWatchdog(context, refreshId, account)
      check(
        ScheduleWidgetManualRefreshJobService.schedule(
          context = context,
          refreshId = refreshId,
          account = account,
          contentFingerprint = contentFingerprint,
        ),
      ) { "manual widget refresh job was rejected" }
      Log.i(
        TAG,
        "event=job_scheduled widgetId=$appWidgetId refreshId=$refreshId",
      )
    } catch (error: RuntimeException) {
      ScheduleWidgetManualRefreshJobService.cancel(context)
      cancelWatchdog(context)
      clearLease(context, refreshId)
      prefs
        .edit()
        .putString("$STATE_KEY_PREFIX$account", "failed")
        .putString("$FAILURE_KEY_PREFIX$account", "generic")
        .remove("$TOKEN_KEY_PREFIX$account")
        .commit()
      updateAllRefreshPresentations(context, refreshData = true)
      Log.e(TAG, "event=enqueue_failed widgetId=$appWidgetId refreshId=$refreshId", error)
    }
  }

  fun updateAllRefreshPresentations(
    context: Context,
    refreshData: Boolean = false,
  ) {
    TodayListWidgetProvider.updateRefreshPresentation(context, refreshData = refreshData)
    TodayAndNextWidgetProvider.updateRefreshPresentation(context, refreshData = refreshData)
    TodayCourseWidgetProvider.updateRefreshPresentation(context, refreshData = refreshData)
  }

  internal fun shouldAcceptClick(
    activeToken: String?,
    activeStartedAt: Long,
    now: Long,
  ): Boolean {
    if (activeToken.isNullOrBlank()) return true
    return activeStartedAt <= 0L || now - activeStartedAt >= LEASE_TIMEOUT_MS
  }

  internal fun isCurrentLease(context: Context, refreshId: String): Boolean {
    if (refreshId.isBlank()) return false
    return context
      .getSharedPreferences(LEASE_PREFS_NAME, Context.MODE_PRIVATE)
      .getString(LEASE_TOKEN_KEY, null) == refreshId
  }

  internal fun clearLease(context: Context, refreshId: String) {
    val leasePrefs = context.getSharedPreferences(LEASE_PREFS_NAME, Context.MODE_PRIVATE)
    if (leasePrefs.getString(LEASE_TOKEN_KEY, null) != refreshId) return
    leasePrefs.edit().remove(LEASE_TOKEN_KEY).remove(LEASE_STARTED_AT_KEY).commit()
  }

  internal fun cancelWatchdog(context: Context) {
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager ?: return
    alarmManager.cancel(watchdogPendingIntent(context, "", ""))
  }

  private fun scheduleWatchdog(
    context: Context,
    refreshId: String,
    account: String,
  ) {
    val alarmManager = context.getSystemService(Context.ALARM_SERVICE) as? AlarmManager
      ?: throw IllegalStateException("AlarmManager unavailable")
    val triggerAt = SystemClock.elapsedRealtime() + LEASE_TIMEOUT_MS
    val pendingIntent = watchdogPendingIntent(context, refreshId, account)
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
      alarmManager.setAndAllowWhileIdle(
        AlarmManager.ELAPSED_REALTIME_WAKEUP,
        triggerAt,
        pendingIntent,
      )
    } else {
      alarmManager.set(AlarmManager.ELAPSED_REALTIME_WAKEUP, triggerAt, pendingIntent)
    }
  }

  private fun watchdogPendingIntent(
    context: Context,
    refreshId: String,
    account: String,
  ): PendingIntent {
    val intent =
      Intent(context, WidgetAutoRefreshReceiver::class.java).apply {
        action = WidgetAutoRefreshReceiver.ACTION_MANUAL_REFRESH_WATCHDOG
        putExtra(WidgetAutoRefreshReceiver.EXTRA_REFRESH_ID, refreshId)
        putExtra(WidgetAutoRefreshReceiver.EXTRA_ACCOUNT, account)
      }
    return PendingIntent.getBroadcast(
      context,
      WATCHDOG_REQUEST_CODE,
      intent,
      PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
    )
  }

  /**
   * Finalizes a refresh under the same monitor used by [enqueue]. This keeps a
   * late completion from clearing the lease, token, or watchdog belonging to a
   * newer click that replaced it after the timeout.
   */
  @Synchronized
  internal fun completeIfCurrent(
    context: Context,
    refreshId: String,
    account: String,
    previousFingerprint: String?,
  ): Boolean {
    if (!isCurrentLease(context, refreshId)) return false
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val stateKey = "$STATE_KEY_PREFIX$account"
    if (
      account.isNotBlank() &&
        prefs.getString("$TOKEN_KEY_PREFIX$account", null) == refreshId &&
        prefs.getString(stateKey, "idle") == "loading"
    ) {
      prefs
        .edit()
        .putString(stateKey, "failed")
        .putString("$FAILURE_KEY_PREFIX$account", "generic")
        .commit()
      Log.w(TAG, "event=state_repaired refreshId=$refreshId from=loading to=failed")
    }

    try {
      TodayCourseWidgetProvider.completeManualRefresh(
        context,
        previousFingerprint,
        refreshId,
      )
    } finally {
      cancelWatchdog(context)
      clearLease(context, refreshId)
      if (
        account.isNotBlank() &&
          prefs.getString("$TOKEN_KEY_PREFIX$account", null) == refreshId
      ) {
        prefs.edit().remove("$TOKEN_KEY_PREFIX$account").commit()
      }
    }
    return true
  }

  /** Performs the watchdog state transition atomically with click enqueue. */
  @Synchronized
  internal fun recoverIfCurrent(
    context: Context,
    refreshId: String,
    account: String,
  ): Boolean {
    if (!isCurrentLease(context, refreshId)) return false
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val stateKey = "$STATE_KEY_PREFIX$account"
    if (
      account.isNotBlank() &&
        prefs.getString("$TOKEN_KEY_PREFIX$account", null) == refreshId &&
        prefs.getString(stateKey, "idle") == "loading"
    ) {
      prefs
        .edit()
        .putString(stateKey, "failed")
        .putString("$FAILURE_KEY_PREFIX$account", "generic")
        .commit()
      Log.w(TAG, "event=watchdog_recovered refreshId=$refreshId from=loading to=failed")
    }
    // Keep the expired token and lease until the worker finishes or a new
    // click replaces them. [shouldAcceptClick] already permits retry after the
    // timeout, while retaining ownership lets an unusually slow successful
    // worker clear the watchdog failure and immediately redraw the widget.
    return true
  }

  fun handleWatchdog(
    context: Context,
    refreshId: String,
    account: String,
  ) {
    if (!recoverIfCurrent(context, refreshId, account)) return
    updateAllRefreshPresentations(context, refreshData = true)
    WidgetAutoRefreshScheduler.schedule(context)
  }

}
