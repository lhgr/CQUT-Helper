package com.dawndrizzle.wing.cqut

import android.app.Application
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Build
import android.os.Handler
import android.os.Looper
import com.dawndrizzle.wing.cqut.widget.WidgetRefreshCoordinator
import com.dawndrizzle.wing.cqut.widget.WidgetNativeLog
import com.dawndrizzle.wing.cqut.widget.WidgetRuntimeRecoveryReceiver

/**
 * Makes any legitimate process start an opportunity to repair stale widgets.
 * The coordinator only redraws when the Beijing logical date or refresh
 * presentation changed, so unrelated background work stays lightweight.
 */
class CqutApplication : Application() {
  private val runtimeRecoveryReceiver = WidgetRuntimeRecoveryReceiver()

  override fun onCreate() {
    super.onCreate()
    WidgetNativeLog.info(
      applicationContext,
      "event=process_started at=${System.currentTimeMillis()}",
    )
    registerRuntimeRecoveryReceiver()
    Handler(Looper.getMainLooper()).post {
      try {
        WidgetRefreshCoordinator.repairIfDue(applicationContext, "process_start")
      } catch (error: RuntimeException) {
        // Widget repair must never prevent Flutter or a background component
        // from starting.
        WidgetNativeLog.error(
          applicationContext,
          "event=process_start_repair_failed",
          error,
        )
      }
    }
  }

  private fun registerRuntimeRecoveryReceiver() {
    val filter = IntentFilter().apply {
      addAction(Intent.ACTION_DATE_CHANGED)
    }
    try {
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        registerReceiver(runtimeRecoveryReceiver, filter, Context.RECEIVER_EXPORTED)
      } else {
        @Suppress("DEPRECATION")
        registerReceiver(runtimeRecoveryReceiver, filter)
      }
      WidgetNativeLog.debug(applicationContext, "event=runtime_recovery_registered")
    } catch (error: RuntimeException) {
      WidgetNativeLog.error(
        applicationContext,
        "event=runtime_recovery_register_failed",
        error,
      )
    }
  }
}
