package com.dawndrizzle.wing.cqut.widget

import android.os.Build
import android.widget.RemoteViews

/**
 * Writes color actions that remain correct when a launcher re-applies the
 * existing RemoteViews after a system night-mode change.
 */
object WidgetRemoteViewsTheme {
  fun setColor(
    views: RemoteViews,
    viewId: Int,
    methodName: String,
    theme: WidgetThemeResolution,
    colorOf: (WidgetVisualPalette) -> Int,
  ) {
    val current = colorOf(theme.palette)
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.S) {
      views.setInt(viewId, methodName, current)
      return
    }

    val (notNight, night) =
      if (theme.mode == WidgetThemeMode.SYSTEM) {
        colorOf(systemPalette(dark = false)) to colorOf(systemPalette(dark = true))
      } else {
        current to current
      }
    views.setColorInt(viewId, methodName, notNight, night)
  }

  private fun systemPalette(dark: Boolean): WidgetVisualPalette =
    WidgetThemePolicy.ensureConsistent(
      WidgetThemePolicy.buildPalette(WidgetThemeMode.SYSTEM, dark),
    )
}
