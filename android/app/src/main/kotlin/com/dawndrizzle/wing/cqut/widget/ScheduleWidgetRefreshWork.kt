package com.dawndrizzle.wing.cqut.widget

import android.app.AlarmManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.SystemClock
import android.provider.Settings
import java.util.UUID

internal enum class WidgetManualRefreshRecovery {
  NONE,
  TIMED_OUT,
  REBOOTED,
}

object ScheduleWidgetRefreshWork {
  private const val PREFS_NAME = "FlutterSharedPreferences"
  private const val LEASE_PREFS_NAME = "ScheduleWidgetManualRefresh"
  private const val FLUTTER_PREFIX = "flutter."
  private const val STATE_KEY_PREFIX = "${FLUTTER_PREFIX}schedule_widget_refresh_state_"
  private const val FAILURE_KEY_PREFIX = "${FLUTTER_PREFIX}schedule_widget_refresh_failure_"
  private const val TOKEN_KEY_PREFIX = "${FLUTTER_PREFIX}schedule_widget_refresh_token_"
  private const val LEASE_TOKEN_KEY = "active_token"
  private const val LEASE_STARTED_AT_KEY = "active_started_at"
  private const val LEASE_ACCOUNT_KEY = "active_account"
  private const val LEASE_BOOT_COUNT_KEY = "active_boot_count"
  private const val LEASE_TIMEOUT_MS = 15L * 60 * 1000
  private const val WATCHDOG_REQUEST_CODE = 0x43515744
  private const val TAG = "WidgetManualRefresh"
  private var leaseCreatedInProcess: String? = null

  @Synchronized
  fun enqueue(context: Context, appWidgetId: Int) {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val account = prefs.getString("${FLUTTER_PREFIX}account", null)?.trim().orEmpty()
    if (account.isEmpty()) {
      WidgetNativeLog.info(
        context,
        "event=click_rejected reason=missing_account widgetId=$appWidgetId",
        tag = TAG,
      )
      updateAllRefreshPresentations(context, refreshData = true)
      return
    }

    val now = System.currentTimeMillis()
    val leasePrefs = context.getSharedPreferences(LEASE_PREFS_NAME, Context.MODE_PRIVATE)
    val activeToken = leasePrefs.getString(LEASE_TOKEN_KEY, null)
    val activeStartedAt = leasePrefs.getLong(LEASE_STARTED_AT_KEY, 0L)
    if (!shouldAcceptClick(activeToken, activeStartedAt, now)) {
      WidgetNativeLog.info(
        context,
        "event=click_deduplicated widgetId=$appWidgetId refreshId=$activeToken",
        tag = TAG,
      )
      return
    }

    val refreshId = UUID.randomUUID().toString()
    leaseCreatedInProcess = refreshId
    leasePrefs
      .edit()
      .putString(LEASE_TOKEN_KEY, refreshId)
      .putLong(LEASE_STARTED_AT_KEY, now)
      .putString(LEASE_ACCOUNT_KEY, account)
      .putInt(LEASE_BOOT_COUNT_KEY, bootCount(context) ?: -1)
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
      WidgetNativeLog.info(
        context,
        "event=job_scheduled widgetId=$appWidgetId refreshId=$refreshId",
        tag = TAG,
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
      WidgetNativeLog.error(
        context,
        "event=enqueue_failed widgetId=$appWidgetId refreshId=$refreshId",
        error,
        tag = TAG,
      )
    }
  }

  fun updateAllRefreshPresentations(
    context: Context,
    refreshData: Boolean = false,
  ) {
    TodayListWidgetProvider.updateRefreshPresentation(context, refreshData = refreshData)
    TodayAndNextWidgetProvider.updateRefreshPresentation(context, refreshData = refreshData)
    TodayCourseWidgetProvider.updateRefreshPresentation(context, refreshData = refreshData)
    VerticalScheduleWidgetProvider.updateRefreshPresentation(context, refreshData = refreshData)
    TinyCourseWidgetProvider.updateRefreshPresentation(context)
    WidgetRefreshCoordinator.ensureScheduled(context, "manual_refresh_presentation")
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
    leasePrefs.edit()
      .remove(LEASE_TOKEN_KEY)
      .remove(LEASE_STARTED_AT_KEY)
      .remove(LEASE_ACCOUNT_KEY)
      .remove(LEASE_BOOT_COUNT_KEY)
      .commit()
    if (leaseCreatedInProcess == refreshId) leaseCreatedInProcess = null
  }

  private fun bootCount(context: Context): Int? = try {
    // Reading the key also works on systems where BOOT_COUNT is unavailable:
    // a missing setting is represented by null, never by a new boot.
    Settings.Global.getInt(context.contentResolver, "boot_count", -1).takeIf { it >= 0 }
  } catch (_: RuntimeException) {
    null
  }

  internal fun recoveryFor(
    refreshId: String?,
    accountToken: String?,
    state: String?,
    startedAt: Long,
    leaseBootCount: Int?,
    currentBootCount: Int?,
    bootCompleted: Boolean,
    createdInProcess: Boolean,
    now: Long,
  ): WidgetManualRefreshRecovery {
    if (refreshId.isNullOrBlank() || accountToken != refreshId || state != "loading") {
      return WidgetManualRefreshRecovery.NONE
    }
    val differentBoot = leaseBootCount != null && currentBootCount != null &&
      leaseBootCount != currentBootCount
    val bootWithoutGeneration = bootCompleted && !createdInProcess &&
      (leaseBootCount == null || currentBootCount == null)
    if (differentBoot || bootWithoutGeneration) return WidgetManualRefreshRecovery.REBOOTED
    return if (shouldAcceptClick(refreshId, startedAt, now)) {
      WidgetManualRefreshRecovery.TIMED_OUT
    } else {
      WidgetManualRefreshRecovery.NONE
    }
  }

  /** Repairs persisted loading before the coordinator acquires its render lock. */
  @Synchronized
  internal fun recoverInterruptedRefresh(
    context: Context,
    bootCompleted: Boolean = false,
  ): Boolean {
    val leasePrefs = context.getSharedPreferences(LEASE_PREFS_NAME, Context.MODE_PRIVATE)
    val refreshId = leasePrefs.getString(LEASE_TOKEN_KEY, null) ?: return false
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val account = leasePrefs.getString(LEASE_ACCOUNT_KEY, null)
      ?: prefs.getString("${FLUTTER_PREFIX}account", null)?.trim().orEmpty()
    if (account.isBlank()) return false
    val recovery = recoveryFor(
      refreshId = refreshId,
      accountToken = prefs.getString("$TOKEN_KEY_PREFIX$account", null),
      state = prefs.getString("$STATE_KEY_PREFIX$account", null),
      startedAt = leasePrefs.getLong(LEASE_STARTED_AT_KEY, 0L),
      leaseBootCount = leasePrefs.getInt(LEASE_BOOT_COUNT_KEY, -1).takeIf { it >= 0 },
      currentBootCount = bootCount(context),
      bootCompleted = bootCompleted,
      createdInProcess = leaseCreatedInProcess == refreshId,
      now = System.currentTimeMillis(),
    )
    if (recovery == WidgetManualRefreshRecovery.NONE) return false
    // enqueue and completion hold this same monitor. A superseded token must
    // never fail or release the task that replaced it.
    if (!recoverIfCurrent(context, refreshId, account)) return false
    if (recovery == WidgetManualRefreshRecovery.REBOOTED) {
      cancelWatchdog(context)
      clearLease(context, refreshId)
      if (prefs.getString("$TOKEN_KEY_PREFIX$account", null) == refreshId) {
        prefs.edit().remove("$TOKEN_KEY_PREFIX$account").commit()
      }
    }
    // Timed-out work retains its token so a late successful Dart result can
    // still clear the failure, exactly as with the existing watchdog.
    WidgetNativeLog.info(
      context,
      "event=interrupted_refresh_recovered refreshId=$refreshId kind=$recovery",
      tag = TAG,
    )
    return true
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
      WidgetNativeLog.warn(
        context,
        "event=state_repaired refreshId=$refreshId from=loading to=failed",
        tag = TAG,
      )
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
      WidgetNativeLog.warn(
        context,
        "event=watchdog_recovered refreshId=$refreshId from=loading to=failed",
        tag = TAG,
      )
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
  }

}
