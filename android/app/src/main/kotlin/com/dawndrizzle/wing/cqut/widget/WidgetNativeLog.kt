package com.dawndrizzle.wing.cqut.widget

import android.content.Context
import android.util.Log
import com.dawndrizzle.wing.cqut.widgetbridge.CqutDiagnostics

/** Normal events are breadcrumbs; only actionable failures reach bounded storage. */
internal object WidgetNativeLog {
  private const val DEFAULT_TAG = "WidgetRefresh"

  fun <T> withOperation(name: String, operationId: String? = null, action: () -> T): T = CqutDiagnostics.withOperation(name, operationId, action)

  fun debug(context: Context, message: String, tag: String = DEFAULT_TAG) {
    Log.d(tag, message)
    CqutDiagnostics.record(context, "debug", tag, message)
  }

  fun info(context: Context, message: String, tag: String = DEFAULT_TAG) {
    Log.i(tag, message)
    CqutDiagnostics.record(context, "info", tag, message)
  }

  fun warn(context: Context, message: String, error: Throwable? = null, tag: String = DEFAULT_TAG) {
    if (error == null) Log.w(tag, message) else Log.w(tag, message, error)
    CqutDiagnostics.record(context, "warn", tag, message, error)
  }

  fun error(context: Context, message: String, error: Throwable? = null, tag: String = DEFAULT_TAG) {
    if (error == null) Log.e(tag, message) else Log.e(tag, message, error)
    CqutDiagnostics.record(context, "error", tag, message, error)
  }
}
