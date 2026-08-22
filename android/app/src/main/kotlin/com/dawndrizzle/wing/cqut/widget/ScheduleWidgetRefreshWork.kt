package com.dawndrizzle.wing.cqut.widget

import android.content.Context
import android.util.Log
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import dev.fluttercommunity.workmanager.BackgroundWorker
import dev.fluttercommunity.workmanager.buildTaskInputData
import java.util.UUID
import java.util.concurrent.TimeUnit

object ScheduleWidgetRefreshWork {
  private const val UNIQUE_WORK_NAME = "schedule_widget_manual_refresh"
  private const val WATCHDOG_WORK_NAME = "schedule_widget_manual_refresh_watchdog"
  private const val DART_TASK_NAME = "schedule_notice_poll_task"
  private const val PREFS_NAME = "FlutterSharedPreferences"
  private const val LEASE_PREFS_NAME = "ScheduleWidgetManualRefresh"
  private const val FLUTTER_PREFIX = "flutter."
  private const val STATE_KEY_PREFIX = "${FLUTTER_PREFIX}schedule_widget_refresh_state_"
  private const val FAILURE_KEY_PREFIX = "${FLUTTER_PREFIX}schedule_widget_refresh_failure_"
  private const val TOKEN_KEY_PREFIX = "${FLUTTER_PREFIX}schedule_widget_refresh_token_"
  private const val LEASE_TOKEN_KEY = "active_token"
  private const val LEASE_STARTED_AT_KEY = "active_started_at"
  private const val LAST_REQUESTED_AT_KEY = "last_requested_at"
  private const val LEASE_TIMEOUT_MS = 15L * 60 * 1000
  private const val PROVIDER_UPDATE_SUPPRESSION_MS = 10L * 1000
  private const val INPUT_REFRESH_ID = "refresh_id"
  private const val INPUT_ACCOUNT = "account"
  private const val INPUT_CONTENT_FINGERPRINT = "content_fingerprint"
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
      .putLong(LAST_REQUESTED_AT_KEY, now)
      .commit()
    prefs
      .edit()
      .putString("$STATE_KEY_PREFIX$account", "loading")
      .remove("$FAILURE_KEY_PREFIX$account")
      .putString("$TOKEN_KEY_PREFIX$account", refreshId)
      .commit()
    updateAllRefreshPresentations(context, refreshData = true)

    val contentFingerprint = TodayWidgetData.loadDisplayedScheduleFingerprint(context)
    // workmanager 0.10 stores each Dart input under a payload_ key. Building
    // the Data through the plugin keeps the native click path aligned with
    // Workmanager.registerOneOffTask instead of using the removed 0.6 JSON
    // envelope, which 0.10 silently decodes as an empty input map.
    val workerInput = buildWorkerInput(refreshId)
    val refreshRequest =
      OneTimeWorkRequestBuilder<BackgroundWorker>()
        .setInputData(workerInput)
        .build()
    val completionRequest =
      OneTimeWorkRequestBuilder<ScheduleWidgetRefreshCompletionWorker>()
        .setInputData(
          Data.Builder()
            .putString(INPUT_REFRESH_ID, refreshId)
            .putString(INPUT_ACCOUNT, account)
            .putString(INPUT_CONTENT_FINGERPRINT, contentFingerprint)
            .build(),
        )
        .build()
    val watchdogRequest =
      OneTimeWorkRequestBuilder<ScheduleWidgetRefreshWatchdogWorker>()
        .setInitialDelay(LEASE_TIMEOUT_MS, TimeUnit.MILLISECONDS)
        .setInputData(
          Data.Builder()
            .putString(INPUT_REFRESH_ID, refreshId)
            .putString(INPUT_ACCOUNT, account)
            .build(),
        )
        .build()

    try {
      val workManager = WorkManager.getInstance(context)
      workManager
        .beginUniqueWork(
          UNIQUE_WORK_NAME,
          ExistingWorkPolicy.REPLACE,
          refreshRequest,
        )
        .then(completionRequest)
        .enqueue()
      // A dependent worker is skipped when its prerequisite fails or is
      // cancelled. Keep an independent watchdog so the widget cannot remain
      // indefinitely stuck in the disabled "loading" presentation.
      workManager.enqueueUniqueWork(
        WATCHDOG_WORK_NAME,
        ExistingWorkPolicy.REPLACE,
        watchdogRequest,
      )
      Log.i(
        TAG,
        "event=enqueued widgetId=$appWidgetId refreshId=$refreshId " +
          "workId=${refreshRequest.id} completionId=${completionRequest.id}",
      )
    } catch (error: RuntimeException) {
      runCatching {
        WorkManager.getInstance(context).apply {
          cancelUniqueWork(UNIQUE_WORK_NAME)
          cancelUniqueWork(WATCHDOG_WORK_NAME)
        }
      }
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

  internal fun buildWorkerInput(refreshId: String): Data {
    return buildTaskInputData(
      dartTask = DART_TASK_NAME,
      payload =
        mapOf(
          "trigger" to "widget_manual",
          "logicalDateBjt" to "",
          "refreshId" to refreshId,
        ),
      uniqueName = UNIQUE_WORK_NAME,
    )
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
    WorkManager.getInstance(context).cancelUniqueWork(WATCHDOG_WORK_NAME)
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

  fun shouldSuppressProviderUpdate(context: Context): Boolean {
    val lastRequestedAt =
      context
        .getSharedPreferences(LEASE_PREFS_NAME, Context.MODE_PRIVATE)
        .getLong(LAST_REQUESTED_AT_KEY, 0L)
    return shouldSuppressProviderUpdate(lastRequestedAt, System.currentTimeMillis())
  }

  internal fun shouldSuppressProviderUpdate(
    lastRequestedAt: Long,
    now: Long,
  ): Boolean {
    if (lastRequestedAt <= 0L || now < lastRequestedAt) return false
    return now - lastRequestedAt < PROVIDER_UPDATE_SUPPRESSION_MS
  }
}

class ScheduleWidgetRefreshCompletionWorker(
  appContext: Context,
  workerParams: WorkerParameters,
) : Worker(appContext, workerParams) {
  override fun doWork(): Result {
    val refreshId = inputData.getString("refresh_id").orEmpty()
    val account = inputData.getString("account").orEmpty()
    val completed =
      ScheduleWidgetRefreshWork.completeIfCurrent(
        applicationContext,
        refreshId,
        account,
        inputData.getString("content_fingerprint"),
      )
    if (!completed) {
      Log.i("WidgetManualRefresh", "event=completion_ignored refreshId=$refreshId reason=stale")
    }
    return Result.success()
  }
}

class ScheduleWidgetRefreshWatchdogWorker(
  appContext: Context,
  workerParams: WorkerParameters,
) : Worker(appContext, workerParams) {
  override fun doWork(): Result {
    val refreshId = inputData.getString("refresh_id").orEmpty()
    val account = inputData.getString("account").orEmpty()
    if (!ScheduleWidgetRefreshWork.recoverIfCurrent(applicationContext, refreshId, account)) {
      return Result.success()
    }
    ScheduleWidgetRefreshWork.updateAllRefreshPresentations(
      applicationContext,
      refreshData = true,
    )
    WidgetAutoRefreshScheduler.schedule(applicationContext)
    return Result.success()
  }
}
