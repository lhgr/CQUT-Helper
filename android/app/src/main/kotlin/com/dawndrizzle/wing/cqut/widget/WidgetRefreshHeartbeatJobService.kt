package com.dawndrizzle.wing.cqut.widget

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.util.Log

/**
 * A lightweight, cache-only repair loop for launchers that drop AppWidget
 * periodic callbacks or a one-shot AlarmManager delivery. This service never
 * starts Flutter and never performs network work.
 */
class WidgetRefreshHeartbeatJobService : JobService() {
  override fun onStartJob(params: JobParameters): Boolean {
    Log.i(TAG, "event=heartbeat_started at=${System.currentTimeMillis()}")
    var succeeded = true
    try {
      WidgetRefreshCoordinator.refreshAndRepair(applicationContext, "heartbeat")
    } catch (error: RuntimeException) {
      succeeded = false
      Log.e(TAG, "event=heartbeat_failed", error)
    }
    Log.i(TAG, "event=heartbeat_completed success=$succeeded at=${System.currentTimeMillis()}")
    return false
  }

  override fun onStopJob(params: JobParameters): Boolean {
    Log.w(TAG, "event=heartbeat_stopped at=${System.currentTimeMillis()}")
    return true
  }

  companion object {
    private const val TAG = "WidgetRefresh"
    internal const val JOB_ID = 0x43515748
    internal const val INTERVAL_MILLIS = 15L * 60 * 1000

    fun ensureScheduled(
      context: Context,
      reason: String,
    ): Boolean {
      val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler
        ?: run {
          Log.e(TAG, "event=heartbeat_unavailable reason=$reason")
          return false
        }
      val pendingIds =
        try {
          scheduler.allPendingJobs.map { it.id }
        } catch (error: RuntimeException) {
          Log.w(TAG, "event=heartbeat_pending_query_failed reason=$reason", error)
          emptyList()
        }
      if (hasPendingJob(pendingIds)) return true
      val job =
        JobInfo.Builder(
          JOB_ID,
          ComponentName(context, WidgetRefreshHeartbeatJobService::class.java),
        )
          .setPeriodic(INTERVAL_MILLIS)
          .setPersisted(true)
          .build()
      return try {
        val scheduled = scheduler.schedule(job) == JobScheduler.RESULT_SUCCESS
        Log.i(TAG, "event=heartbeat_scheduled reason=$reason success=$scheduled")
        scheduled
      } catch (error: RuntimeException) {
        Log.e(TAG, "event=heartbeat_schedule_failed reason=$reason", error)
        false
      }
    }

    fun cancel(
      context: Context,
      reason: String,
    ) {
      val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler
      try {
        scheduler?.cancel(JOB_ID)
        Log.i(TAG, "event=heartbeat_cancelled reason=$reason")
      } catch (error: RuntimeException) {
        Log.e(TAG, "event=heartbeat_cancel_failed reason=$reason", error)
      }
    }

    internal fun hasPendingJob(jobIds: List<Int>): Boolean = JOB_ID in jobIds
  }
}
