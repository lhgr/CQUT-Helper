package com.dawndrizzle.wing.cqut.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

/**
 * Opportunistic recovery for a process that is already alive.
 *
 * DATE_CHANGED is retained as a process-local secondary signal for Beijing
 * midnight. The central coalescer merges it with the boundary alarm.
 */
class WidgetRuntimeRecoveryReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val action = intent.action ?: return
    if (!isRuntimeRecoveryAction(action)) return
    if (!WidgetRefreshCoordinator.hasActiveWidgets(context)) return

    val nowMillis = System.currentTimeMillis()
    WidgetNativeLog.info(
      context,
      "event=runtime_recovery_received action=$action at=$nowMillis",
    )
    WidgetRefreshCoordinator.repairIfDue(context, "runtime:$action")
  }

  companion object {
    internal fun isRuntimeRecoveryAction(action: String): Boolean =
      action == Intent.ACTION_DATE_CHANGED
  }
}
