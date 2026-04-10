package com.dawndrizzle.wing.cqut.widget

enum class WidgetThemeMode {
  SYSTEM,
  LIGHT,
  DARK,
}

enum class WidgetThemeTrigger {
  INITIALIZATION,
  APP_THEME_CHANGED,
  SYSTEM_THEME_CHANGED,
  DATA_REFRESH,
  TRANSITION_COMMIT,
}

data class WidgetVisualPalette(
  val mode: WidgetThemeMode,
  val dark: Boolean,
  val backgroundRes: Int,
  val backgroundColor: Int,
  val itemBackgroundRes: Int,
  val imageBackgroundRes: Int,
  val primaryText: Int,
  val secondaryText: Int,
  val accent: Int,
  val divider: Int,
  val border: Int,
  val icon: Int,
  val transitionOverlay: Int,
)

data class WidgetThemeResolution(
  val mode: WidgetThemeMode,
  val dark: Boolean,
  val palette: WidgetVisualPalette,
  val signature: String,
  val shouldAnimate: Boolean,
)

object WidgetThemePolicy {
  fun parseMode(raw: String?): WidgetThemeMode {
    return when (raw?.trim()) {
      "ThemeMode.light" -> WidgetThemeMode.LIGHT
      "ThemeMode.dark" -> WidgetThemeMode.DARK
      else -> WidgetThemeMode.SYSTEM
    }
  }

  fun resolveDark(
    mode: WidgetThemeMode,
    systemDark: Boolean,
    transitionPending: Boolean,
    lastDark: Boolean?,
  ): Boolean {
    return when (mode) {
      WidgetThemeMode.DARK -> true
      WidgetThemeMode.LIGHT -> false
      WidgetThemeMode.SYSTEM -> {
        if (transitionPending && lastDark != null) {
          lastDark
        } else {
          systemDark
        }
      }
    }
  }

  fun buildPalette(mode: WidgetThemeMode, dark: Boolean): WidgetVisualPalette {
    return if (dark) {
      WidgetVisualPalette(
        mode = mode,
        dark = true,
        backgroundRes = com.dawndrizzle.wing.cqut.R.drawable.widget_bg_dark,
        backgroundColor = 0xFF1E1E1E.toInt(),
        itemBackgroundRes = com.dawndrizzle.wing.cqut.R.drawable.widget_item_bg_dark,
        imageBackgroundRes = com.dawndrizzle.wing.cqut.R.drawable.appwidget_bg_dark,
        primaryText = 0xFFFFFFFF.toInt(),
        secondaryText = 0xFFB0B0B0.toInt(),
        accent = 0xFF3F51B5.toInt(),
        divider = 0x33FFFFFF.toInt(),
        border = 0x33FFFFFF.toInt(),
        icon = 0xFFE0E0E0.toInt(),
        transitionOverlay = 0x33FFFFFF.toInt(),
      )
    } else {
      WidgetVisualPalette(
        mode = mode,
        dark = false,
        backgroundRes = com.dawndrizzle.wing.cqut.R.drawable.widget_bg,
        backgroundColor = 0xFFFFFFFF.toInt(),
        itemBackgroundRes = com.dawndrizzle.wing.cqut.R.drawable.widget_item_bg,
        imageBackgroundRes = com.dawndrizzle.wing.cqut.R.drawable.appwidget_bg,
        primaryText = 0xFF111111.toInt(),
        secondaryText = 0xFF666666.toInt(),
        accent = 0xFF3F51B5.toInt(),
        divider = 0x1A111111.toInt(),
        border = 0x1A111111.toInt(),
        icon = 0xFF666666.toInt(),
        transitionOverlay = 0x22000000.toInt(),
      )
    }
  }

  fun validateConsistency(palette: WidgetVisualPalette): Boolean {
    val bgLight = isLightColor(palette.backgroundColor)
    val primaryLight = isLightColor(palette.primaryText)
    val secondaryLight = isLightColor(palette.secondaryText)
    val iconLight = isLightColor(palette.icon)
    val borderLight = isLightColor(palette.border)
    return if (palette.dark) {
      !bgLight && primaryLight && secondaryLight && iconLight && borderLight
    } else {
      bgLight && !primaryLight && !secondaryLight && !iconLight && !borderLight
    }
  }

  fun ensureConsistent(palette: WidgetVisualPalette): WidgetVisualPalette {
    if (validateConsistency(palette)) return palette
    return buildPalette(palette.mode, palette.dark)
  }

  fun shouldAnimate(
    trigger: WidgetThemeTrigger,
    lastSignature: String?,
    currentSignature: String,
  ): Boolean {
    if (trigger == WidgetThemeTrigger.TRANSITION_COMMIT) return false
    if (lastSignature.isNullOrBlank()) {
      return trigger == WidgetThemeTrigger.INITIALIZATION
    }
    if (lastSignature == currentSignature) return false
    return trigger == WidgetThemeTrigger.INITIALIZATION ||
      trigger == WidgetThemeTrigger.APP_THEME_CHANGED ||
      trigger == WidgetThemeTrigger.SYSTEM_THEME_CHANGED
  }

  fun signature(mode: WidgetThemeMode, dark: Boolean): String = "${mode.name}|$dark"

  private fun isLightColor(color: Int): Boolean {
    val r = (color shr 16) and 0xFF
    val g = (color shr 8) and 0xFF
    val b = color and 0xFF
    val luminance = (0.299 * r + 0.587 * g + 0.114 * b) / 255.0
    return luminance >= 0.58
  }
}
