package com.dawndrizzle.wing.cqut.widget

import android.app.job.JobInfo
import android.app.job.JobParameters
import android.app.job.JobScheduler
import android.app.job.JobService
import android.content.ComponentName
import android.content.Context
import android.os.Handler
import android.os.Looper
import android.os.PersistableBundle
import dev.fluttercommunity.workmanager.SharedPreferenceHelper
import dev.fluttercommunity.workmanager.pigeon.WorkmanagerFlutterApi
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.view.FlutterCallbackInformation

/**
 * Runs a user-requested widget refresh without enqueuing temporary WorkManager
 * records. WorkManager enables/disables its reschedule receiver as its queue
 * changes; some launchers treat that as an app-package change and visibly
 * redraw the launcher icon. A permanently declared JobService has no such
 * component-state transition.
 */
class ScheduleWidgetManualRefreshJobService : JobService() {
  private val mainHandler by lazy { Handler(Looper.getMainLooper()) }
  private var activeParameters: JobParameters? = null
  private var engine: FlutterEngine? = null

  override fun onStartJob(params: JobParameters): Boolean {
    activeParameters = params
    startDartRefresh(params)
    return true
  }

  override fun onStopJob(params: JobParameters): Boolean {
    if (activeParameters === params) {
      activeParameters = null
      destroyEngine()
      completeNativeRefresh(params, taskReportedSuccess = false)
    }
    // Manual clicks should surface failure and let the user retry rather than
    // allowing JobScheduler to repeat an obsolete refresh token.
    return false
  }

  override fun onDestroy() {
    destroyEngine()
    super.onDestroy()
  }

  private fun startDartRefresh(params: JobParameters) {
    try {
      val flutterLoader = FlutterInjector.instance().flutterLoader()
      if (!flutterLoader.initialized()) {
        flutterLoader.startInitialization(applicationContext)
      }
      flutterLoader.ensureInitializationCompleteAsync(
        applicationContext,
        null,
        mainHandler,
      ) {
        if (activeParameters !== params) return@ensureInitializationCompleteAsync
        launchDartCallback(params, flutterLoader.findAppBundlePath())
      }
    } catch (error: RuntimeException) {
      WidgetNativeLog.error(applicationContext, "event=engine_initialization_failed", error, TAG)
      finishJob(params, taskReportedSuccess = false)
    }
  }

  private fun launchDartCallback(
    params: JobParameters,
    dartBundlePath: String,
  ) {
    try {
      val callbackHandle = SharedPreferenceHelper.getCallbackHandle(applicationContext)
      val callbackInfo = FlutterCallbackInformation.lookupCallbackInformation(callbackHandle)
      if (callbackInfo == null) {
        WidgetNativeLog.error(
          applicationContext,
          "event=callback_lookup_failed handle=$callbackHandle",
          tag = TAG,
        )
        finishJob(params, taskReportedSuccess = false)
        return
      }

      val localEngine = FlutterEngine(applicationContext)
      engine = localEngine
      val flutterApi = WorkmanagerFlutterApi(localEngine.dartExecutor.binaryMessenger)
      localEngine.dartExecutor.executeDartCallback(
        DartExecutor.DartCallback(
          applicationContext.assets,
          dartBundlePath,
          callbackInfo,
        ),
      )
      flutterApi.backgroundChannelInitialized { initialized ->
        runOnMain {
          if (activeParameters !== params) return@runOnMain
          if (initialized.isFailure) {
            WidgetNativeLog.error(
              applicationContext,
              "event=background_channel_failed",
              initialized.exceptionOrNull(),
              TAG,
            )
            finishJob(params, taskReportedSuccess = false)
            return@runOnMain
          }
          flutterApi.executeTask(
            DART_TASK_NAME,
            buildTaskPayload(params.extras.getString(EXTRA_REFRESH_ID).orEmpty()),
          ) { result ->
            runOnMain {
              if (result.isFailure) {
                WidgetNativeLog.error(
                  applicationContext,
                  "event=dart_task_failed",
                  result.exceptionOrNull(),
                  TAG,
                )
              }
              finishJob(params, taskReportedSuccess = result.getOrNull() == true)
            }
          }
        }
      }
    } catch (error: RuntimeException) {
      WidgetNativeLog.error(applicationContext, "event=dart_launch_failed", error, TAG)
      finishJob(params, taskReportedSuccess = false)
    }
  }

  private fun finishJob(
    params: JobParameters,
    taskReportedSuccess: Boolean,
  ) {
    if (activeParameters !== params) return
    activeParameters = null
    destroyEngine()
    completeNativeRefresh(params, taskReportedSuccess)
    jobFinished(params, false)
  }

  private fun completeNativeRefresh(
    params: JobParameters,
    taskReportedSuccess: Boolean,
  ) {
    val refreshId = params.extras.getString(EXTRA_REFRESH_ID).orEmpty()
    val completed =
      ScheduleWidgetRefreshWork.completeIfCurrent(
        context = applicationContext,
        refreshId = refreshId,
        account = params.extras.getString(EXTRA_ACCOUNT).orEmpty(),
        previousFingerprint = params.extras.getString(EXTRA_CONTENT_FINGERPRINT),
      )
    WidgetNativeLog.info(
      applicationContext,
      "event=job_completed refreshId=$refreshId dartSuccess=$taskReportedSuccess current=$completed",
      tag = TAG,
    )
  }

  private fun destroyEngine() {
    engine?.destroy()
    engine = null
  }

  private fun runOnMain(block: () -> Unit) {
    if (Looper.myLooper() == Looper.getMainLooper()) {
      block()
    } else {
      mainHandler.post(block)
    }
  }

  companion object {
    private const val TAG = "WidgetManualRefresh"
    private const val JOB_ID = 0x43515554
    private const val DART_TASK_NAME = "schedule_notice_poll_task"
    internal const val EXTRA_REFRESH_ID = "refresh_id"
    internal const val EXTRA_ACCOUNT = "account"
    internal const val EXTRA_CONTENT_FINGERPRINT = "content_fingerprint"

    fun schedule(
      context: Context,
      refreshId: String,
      account: String,
      contentFingerprint: String,
    ): Boolean {
      val scheduler =
        context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler
          ?: return false
      val extras =
        PersistableBundle().apply {
          putString(EXTRA_REFRESH_ID, refreshId)
          putString(EXTRA_ACCOUNT, account)
          putString(EXTRA_CONTENT_FINGERPRINT, contentFingerprint)
        }
      val job =
        JobInfo.Builder(
          JOB_ID,
          ComponentName(context, ScheduleWidgetManualRefreshJobService::class.java),
        )
          .setOverrideDeadline(0L)
          .setExtras(extras)
          .build()
      return scheduler.schedule(job) == JobScheduler.RESULT_SUCCESS
    }

    fun cancel(context: Context) {
      val scheduler = context.getSystemService(Context.JOB_SCHEDULER_SERVICE) as? JobScheduler
      scheduler?.cancel(JOB_ID)
    }

    internal fun buildTaskPayload(refreshId: String): Map<String?, Any?> =
      mapOf(
        "trigger" to "widget_manual",
        "logicalDateBjt" to "",
        "refreshId" to refreshId,
      )
  }
}
