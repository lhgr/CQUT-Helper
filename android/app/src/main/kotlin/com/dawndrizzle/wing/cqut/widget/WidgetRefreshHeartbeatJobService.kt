package com.dawndrizzle.wing.cqut.widget

import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.Context

/**
 * Compatibility shell for a persisted v0.3.0 JobScheduler heartbeat.
 * New builds retire the job and use AlarmManager plus WorkManager instead.
 */
class WidgetRefreshHeartbeatJobService : JobService() {
  override fun onStartJob(params: JobParameters): Boolean {
    WidgetNativeLog.info(
      applicationContext,
      "event=legacy_heartbeat_started at=${System.currentTimeMillis()}",
    )
    var succeeded = true
    try {
      WidgetRefreshCoordinator.repairIfDue(applicationContext, "legacy_heartbeat")
    } catch (error: RuntimeException) {
      succeeded = false
      WidgetNativeLog.error(applicationContext, "event=legacy_heartbeat_failed", error)
    }
    WidgetNativeLog.info(
      applicationContext,
      "event=legacy_heartbeat_completed success=$succeeded at=${System.currentTimeMillis()}",
    )
    return false
  }

  override fun onStopJob(params: JobParameters): Boolean {
    WidgetNativeLog.warn(
      applicationContext,
      "event=legacy_heartbeat_stopped at=${System.currentTimeMillis()}",
    )
    return false
  }

  companion object {
    private const val PREFS_NAME = "WidgetRefreshHeartbeat"
    private const val KEY_SCHEDULED_INTERVAL_MILLIS = "scheduled_interval_millis"
    private const val KEY_RETIRED = "retired"
    internal const val JOB_ID = 0x43515748

    fun retireIfNeeded(
      context: Context,
      reason: String,
    ) {
      val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
      if (prefs.getBoolean(KEY_RETIRED, false)) return
      val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler
      try {
        scheduler?.cancel(JOB_ID)
        prefs
          .edit()
          .remove(KEY_SCHEDULED_INTERVAL_MILLIS)
          .putBoolean(KEY_RETIRED, true)
          .apply()
        WidgetNativeLog.info(
          context,
          "event=legacy_heartbeat_retired reason=$reason",
        )
      } catch (error: RuntimeException) {
        WidgetNativeLog.error(
          context,
          "event=legacy_heartbeat_retire_failed reason=$reason",
          error,
        )
      }
    }

    fun cancel(
      context: Context,
      reason: String,
    ) {
      val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler
      try {
        scheduler?.cancel(JOB_ID)
        context
          .getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
          .edit()
          .remove(KEY_SCHEDULED_INTERVAL_MILLIS)
          .putBoolean(KEY_RETIRED, true)
          .apply()
        WidgetNativeLog.info(context, "event=heartbeat_cancelled reason=$reason")
      } catch (error: RuntimeException) {
        WidgetNativeLog.error(context, "event=heartbeat_cancel_failed reason=$reason", error)
      }
    }
  }
}
