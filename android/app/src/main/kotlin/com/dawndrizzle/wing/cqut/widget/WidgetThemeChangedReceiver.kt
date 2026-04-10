package com.dawndrizzle.wing.cqut.widget

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent

class WidgetThemeChangedReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    if (intent.action != Intent.ACTION_CONFIGURATION_CHANGED) return
    WidgetThemeSyncDispatcher.dispatch(context, WidgetThemeTrigger.SYSTEM_THEME_CHANGED)
  }
}

