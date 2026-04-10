package com.dawndrizzle.wing.cqut.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

private const val ACTION_UI_MODE_CHANGED = "android.intent.action.UI_MODE_CHANGED"

class WidgetThemeChangedReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    val action = intent.action
    if (action != Intent.ACTION_CONFIGURATION_CHANGED && action != ACTION_UI_MODE_CHANGED) return
    Log.d("WidgetTheme", "WidgetThemeChangedReceiver action=$action")
    WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.SYSTEM_THEME_CHANGED)
  }
}

