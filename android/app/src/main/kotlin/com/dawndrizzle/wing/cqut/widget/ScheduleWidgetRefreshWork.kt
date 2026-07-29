package com.dawndrizzle.wing.cqut.widget

import android.content.Context
import androidx.work.Data
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import dev.fluttercommunity.workmanager.BackgroundWorker
import org.json.JSONObject

object ScheduleWidgetRefreshWork {
  private const val UNIQUE_WORK_NAME = "schedule_widget_manual_refresh"
  private const val DART_TASK_NAME = "schedule_notice_poll_task"
  private const val PREFS_NAME = "FlutterSharedPreferences"
  private const val FLUTTER_PREFIX = "flutter."
  private const val STATE_KEY_PREFIX = "${FLUTTER_PREFIX}schedule_widget_refresh_state_"
  private const val FAILURE_KEY_PREFIX = "${FLUTTER_PREFIX}schedule_widget_refresh_failure_"

  fun enqueue(context: Context) {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val account = prefs.getString("${FLUTTER_PREFIX}account", null)?.trim().orEmpty()
    if (account.isEmpty()) {
      WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.DATA_REFRESH)
      return
    }

    prefs
      .edit()
      .putString("$STATE_KEY_PREFIX$account", "loading")
      .remove("$FAILURE_KEY_PREFIX$account")
      .commit()
    WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.DATA_REFRESH)

    val payload =
      JSONObject()
        .put("trigger", "widget_manual")
        .put("logicalDateBjt", "")
        .toString()
    val workerInput =
      Data.Builder()
        .putString(BackgroundWorker.DART_TASK_KEY, DART_TASK_NAME)
        .putString(BackgroundWorker.PAYLOAD_KEY, payload)
        .putBoolean(BackgroundWorker.IS_IN_DEBUG_MODE_KEY, false)
        .build()
    val refreshRequest =
      OneTimeWorkRequestBuilder<BackgroundWorker>()
        .setInputData(workerInput)
        .build()
    val completionRequest =
      OneTimeWorkRequestBuilder<ScheduleWidgetRefreshCompletionWorker>().build()

    WorkManager
      .getInstance(context)
      .beginUniqueWork(
        UNIQUE_WORK_NAME,
        ExistingWorkPolicy.KEEP,
        refreshRequest,
      )
      .then(completionRequest)
      .enqueue()
  }
}

class ScheduleWidgetRefreshCompletionWorker(
  appContext: Context,
  workerParams: WorkerParameters,
) : Worker(appContext, workerParams) {
  override fun doWork(): Result {
    WidgetThemeSyncDispatcher.dispatch(
      applicationContext,
      WidgetThemeTrigger.DATA_REFRESH,
    )
    return Result.success()
  }
}
