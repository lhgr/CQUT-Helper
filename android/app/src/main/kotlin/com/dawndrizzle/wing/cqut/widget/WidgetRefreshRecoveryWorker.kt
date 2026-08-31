package com.dawndrizzle.wing.cqut.widget

import android.content.Context
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.PeriodicWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.Worker
import androidx.work.WorkerParameters
import java.util.concurrent.TimeUnit

/**
 * A permission-free, cache-only recovery path for missed widget alarms.
 *
 * WorkManager is intentionally not responsible for network synchronization or
 * starting Flutter. It only asks the existing native render pipeline to reload
 * cached rows, including time-sensitive filtering of completed courses.
 */
class WidgetRefreshRecoveryWorker(
  appContext: Context,
  workerParams: WorkerParameters,
) : Worker(appContext, workerParams) {
  override fun doWork(): Result {
    if (!WidgetRefreshCoordinator.hasActiveWidgets(applicationContext)) {
      WidgetRefreshCoordinator.cancelIfUnused(applicationContext, "recovery_worker_unused")
      return Result.success()
    }

    return try {
      val repaired =
        WidgetRefreshCoordinator.repairIfDue(applicationContext, "workmanager_recovery")
      if (repaired) {
        WidgetNativeLog.info(
          applicationContext,
          "event=recovery_worker_repaired at=${System.currentTimeMillis()}",
        )
      }
      Result.success()
    } catch (error: RuntimeException) {
      WidgetNativeLog.error(applicationContext, "event=recovery_worker_failed", error)
      Result.retry()
    }
  }
}

object WidgetRefreshRecoveryWork {
  internal const val UNIQUE_WORK_NAME = "WidgetRefreshRecovery_Periodic"
  internal const val INTERVAL_MINUTES = 15L
  @Volatile private var scheduledInProcess: Boolean? = null

  @Synchronized
  fun ensureScheduled(
    context: Context,
    reason: String,
  ) {
    if (scheduledInProcess == true) return
    val request =
      PeriodicWorkRequestBuilder<WidgetRefreshRecoveryWorker>(
        INTERVAL_MINUTES,
        TimeUnit.MINUTES,
      ).build()
    try {
      WorkManager.getInstance(context).enqueueUniquePeriodicWork(
        UNIQUE_WORK_NAME,
        ExistingPeriodicWorkPolicy.KEEP,
        request,
      )
      scheduledInProcess = true
      WidgetNativeLog.info(context, "event=recovery_worker_scheduled reason=$reason")
    } catch (error: RuntimeException) {
      WidgetNativeLog.error(
        context,
        "event=recovery_worker_schedule_failed reason=$reason",
        error,
      )
    }
  }

  @Synchronized
  fun cancel(
    context: Context,
    reason: String,
  ) {
    if (scheduledInProcess == false) return
    try {
      WorkManager.getInstance(context).cancelUniqueWork(UNIQUE_WORK_NAME)
      scheduledInProcess = false
      WidgetNativeLog.info(context, "event=recovery_worker_cancelled reason=$reason")
    } catch (error: RuntimeException) {
      WidgetNativeLog.error(
        context,
        "event=recovery_worker_cancel_failed reason=$reason",
        error,
      )
    }
  }
}
