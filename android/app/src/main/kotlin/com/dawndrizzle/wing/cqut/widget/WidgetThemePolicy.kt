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
      "light", "ThemeMode.light" -> WidgetThemeMode.LIGHT
      "dark", "ThemeMode.dark" -> WidgetThemeMode.DARK
      "system", "ThemeMode.system" -> WidgetThemeMode.SYSTEM
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
      WidgetThemeMode.SYSTEM -> systemDark
    }
  }

  fun buildPalette(mode: WidgetThemeMode, dark: Boolean): WidgetVisualPalette {
    if (mode == WidgetThemeMode.SYSTEM) {
      return WidgetVisualPalette(
        mode = mode,
        dark = dark,
        backgroundRes = com.dawndrizzle.wing.cqut.R.drawable.widget_bg,
        backgroundColor = if (dark) 0xFF232A35.toInt() else 0xFFFFFFFF.toInt(),
        itemBackgroundRes = com.dawndrizzle.wing.cqut.R.drawable.widget_item_bg,
        imageBackgroundRes = com.dawndrizzle.wing.cqut.R.drawable.widget_bg,
        primaryText = if (dark) 0xFFF4F6FA.toInt() else 0xFF172238.toInt(),
        secondaryText = if (dark) 0xFFB7C1D0.toInt() else 0xFF5D6B82.toInt(),
        accent = if (dark) 0xFFA8BCFF.toInt() else 0xFF3856A6.toInt(),
        divider = if (dark) 0xFF3A4658.toInt() else 0xFFDCE3ED.toInt(),
        border = if (dark) 0x33FFFFFF.toInt() else 0x1A111111.toInt(),
        icon = if (dark) 0xFFB7C1D0.toInt() else 0xFF5D6B82.toInt(),
        transitionOverlay = if (dark) 0x33FFFFFF.toInt() else 0x22000000.toInt(),
      )
    }
    return if (dark) {
      WidgetVisualPalette(
        mode = mode,
        dark = true,
        backgroundRes = com.dawndrizzle.wing.cqut.R.drawable.widget_bg_dark,
        backgroundColor = 0xFF232A35.toInt(),
        itemBackgroundRes = com.dawndrizzle.wing.cqut.R.drawable.widget_item_bg_dark,
        imageBackgroundRes = com.dawndrizzle.wing.cqut.R.drawable.widget_bg_dark,
        primaryText = 0xFFF4F6FA.toInt(),
        secondaryText = 0xFFB7C1D0.toInt(),
        accent = 0xFFA8BCFF.toInt(),
        divider = 0xFF3A4658.toInt(),
        border = 0x33FFFFFF.toInt(),
        icon = 0xFFB7C1D0.toInt(),
        transitionOverlay = 0x33FFFFFF.toInt(),
      )
    } else {
      WidgetVisualPalette(
        mode = mode,
        dark = false,
        backgroundRes = com.dawndrizzle.wing.cqut.R.drawable.widget_bg_light,
        backgroundColor = 0xFFFFFFFF.toInt(),
        itemBackgroundRes = com.dawndrizzle.wing.cqut.R.drawable.widget_item_bg_light,
        imageBackgroundRes = com.dawndrizzle.wing.cqut.R.drawable.widget_bg_light,
        primaryText = 0xFF172238.toInt(),
        secondaryText = 0xFF5D6B82.toInt(),
        accent = 0xFF3856A6.toInt(),
        divider = 0xFFDCE3ED.toInt(),
        border = 0x1A111111.toInt(),
        icon = 0xFF5D6B82.toInt(),
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
