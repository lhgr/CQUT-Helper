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
import org.json.JSONObject
import java.util.UUID

object ScheduleWidgetRefreshWork {
  private const val UNIQUE_WORK_NAME = "schedule_widget_manual_refresh"
  private const val DART_TASK_NAME = "schedule_notice_poll_task"
  private const val PREFS_NAME = "FlutterSharedPreferences"
  private const val LEASE_PREFS_NAME = "ScheduleWidgetManualRefresh"
  private const val FLUTTER_PREFIX = "flutter."
  private const val STATE_KEY_PREFIX = "${FLUTTER_PREFIX}schedule_widget_refresh_state_"
  private const val FAILURE_KEY_PREFIX = "${FLUTTER_PREFIX}schedule_widget_refresh_failure_"
  private const val TOKEN_KEY_PREFIX = "${FLUTTER_PREFIX}schedule_widget_refresh_token_"
  private const val LEASE_TOKEN_KEY = "active_token"
  private const val LEASE_STARTED_AT_KEY = "active_started_at"
  private const val LEASE_TIMEOUT_MS = 15L * 60 * 1000
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
      TodayCourseWidgetProvider.updateRefreshPresentation(context, intArrayOf(appWidgetId))
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

    val contentFingerprint = TodayWidgetData.loadDisplayedScheduleFingerprint(context)
    val payload =
      JSONObject()
        .put("trigger", "widget_manual")
        .put("logicalDateBjt", "")
        .put("refreshId", refreshId)
        .toString()
    val workerInput =
      Data.Builder()
        .putString(BackgroundWorker.DART_TASK_KEY, DART_TASK_NAME)
        .putString(BackgroundWorker.PAYLOAD_KEY, payload)
        .build()
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

    try {
      WorkManager
        .getInstance(context)
        .beginUniqueWork(
          UNIQUE_WORK_NAME,
          ExistingWorkPolicy.REPLACE,
          refreshRequest,
        )
        .then(completionRequest)
        .enqueue()
      Log.i(
        TAG,
        "event=enqueued widgetId=$appWidgetId refreshId=$refreshId " +
          "workId=${refreshRequest.id} completionId=${completionRequest.id}",
      )
    } catch (error: RuntimeException) {
      clearLease(context, refreshId)
      prefs
        .edit()
        .putString("$STATE_KEY_PREFIX$account", "failed")
        .putString("$FAILURE_KEY_PREFIX$account", "generic")
        .remove("$TOKEN_KEY_PREFIX$account")
        .commit()
      TodayCourseWidgetProvider.updateRefreshPresentation(context, intArrayOf(appWidgetId))
      Log.e(TAG, "event=enqueue_failed widgetId=$appWidgetId refreshId=$refreshId", error)
    }
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
}

class ScheduleWidgetRefreshCompletionWorker(
  appContext: Context,
  workerParams: WorkerParameters,
) : Worker(appContext, workerParams) {
  override fun doWork(): Result {
    val refreshId = inputData.getString("refresh_id").orEmpty()
    val account = inputData.getString("account").orEmpty()
    if (!ScheduleWidgetRefreshWork.isCurrentLease(applicationContext, refreshId)) {
      Log.i("WidgetManualRefresh", "event=completion_ignored refreshId=$refreshId reason=stale")
      return Result.success()
    }

    val prefs =
      applicationContext.getSharedPreferences("FlutterSharedPreferences", Context.MODE_PRIVATE)
    val stateKey = "flutter.schedule_widget_refresh_state_$account"
    if (account.isNotBlank() && prefs.getString(stateKey, "idle") == "loading") {
      prefs
        .edit()
        .putString(stateKey, "failed")
        .putString("flutter.schedule_widget_refresh_failure_$account", "generic")
        .commit()
      Log.w(
        "WidgetManualRefresh",
        "event=state_repaired refreshId=$refreshId from=loading to=failed",
      )
    }

    val previousFingerprint = inputData.getString("content_fingerprint")
    try {
      TodayCourseWidgetProvider.completeManualRefresh(
        applicationContext,
        previousFingerprint,
        refreshId,
      )
    } finally {
      ScheduleWidgetRefreshWork.clearLease(applicationContext, refreshId)
      if (account.isNotBlank()) {
        prefs.edit().remove("flutter.schedule_widget_refresh_token_$account").commit()
      }
    }
    return Result.success()
  }
}
