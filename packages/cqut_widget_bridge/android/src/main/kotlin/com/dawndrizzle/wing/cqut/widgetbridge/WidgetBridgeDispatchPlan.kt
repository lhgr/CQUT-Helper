package com.dawndrizzle.wing.cqut.widgetbridge

internal data class WidgetBroadcastTarget(
  val receiverClassName: String,
  val action: String,
)

internal data class WidgetBridgeDispatchPlan(
  val primaryAction: String,
  val fallbackTargets: List<WidgetBroadcastTarget>,
)

internal object WidgetBridgeDispatchPlans {
  const val AUTO_REFRESH_ACTION = "com.dawndrizzle.wing.cqut.widget.AUTO_REFRESH"
  const val APP_THEME_REFRESH_ACTION =
    "com.dawndrizzle.wing.cqut.widget.APP_THEME_REFRESH"
  const val AUTO_REFRESH_RECEIVER =
    "com.dawndrizzle.wing.cqut.widget.WidgetAutoRefreshReceiver"

  private const val TODAY_LIST_PROVIDER =
    "com.dawndrizzle.wing.cqut.widget.TodayListWidgetProvider"
  private const val TODAY_AND_NEXT_PROVIDER =
    "com.dawndrizzle.wing.cqut.widget.TodayAndNextWidgetProvider"
  private const val TODAY_COURSE_PROVIDER =
    "com.dawndrizzle.wing.cqut.widget.TodayCourseWidgetProvider"
  private const val TINY_COURSE_PROVIDER =
    "com.dawndrizzle.wing.cqut.widget.TinyCourseWidgetProvider"
  private const val VERTICAL_SCHEDULE_PROVIDER =
    "com.dawndrizzle.wing.cqut.widget.VerticalScheduleWidgetProvider"

  private const val TODAY_LIST_THEME_ACTION =
    "com.dawndrizzle.wing.cqut.widget.TODAY_LIST_THEME_REFRESH"
  private const val TODAY_AND_NEXT_THEME_ACTION =
    "com.dawndrizzle.wing.cqut.widget.TODAY_AND_NEXT_THEME_REFRESH"
  private const val TODAY_COURSE_THEME_ACTION =
    "com.dawndrizzle.wing.cqut.widget.TODAY_COURSE_THEME_REFRESH"
  private const val TINY_COURSE_THEME_ACTION =
    "com.dawndrizzle.wing.cqut.widget.TINY_COURSE_THEME_REFRESH"
  private const val VERTICAL_SCHEDULE_THEME_ACTION =
    "com.dawndrizzle.wing.cqut.widget.VERTICAL_SCHEDULE_THEME_REFRESH"
  private const val TODAY_COURSE_DATA_ACTION =
    "com.dawndrizzle.wing.cqut.widget.TODAY_COURSE_REFRESH"

  fun from(themeMode: String?, trigger: String?): WidgetBridgeDispatchPlan {
    val isThemeRefresh =
      !themeMode.isNullOrBlank() || trigger == "app_theme_changed" || trigger == "init"
    return if (isThemeRefresh) {
      WidgetBridgeDispatchPlan(
        primaryAction = APP_THEME_REFRESH_ACTION,
        fallbackTargets =
          listOf(
            WidgetBroadcastTarget(TODAY_LIST_PROVIDER, TODAY_LIST_THEME_ACTION),
            WidgetBroadcastTarget(TODAY_AND_NEXT_PROVIDER, TODAY_AND_NEXT_THEME_ACTION),
            WidgetBroadcastTarget(TODAY_COURSE_PROVIDER, TODAY_COURSE_THEME_ACTION),
            WidgetBroadcastTarget(TINY_COURSE_PROVIDER, TINY_COURSE_THEME_ACTION),
            WidgetBroadcastTarget(VERTICAL_SCHEDULE_PROVIDER, VERTICAL_SCHEDULE_THEME_ACTION),
          ),
      )
    } else {
      // The day-view provider's data action delegates to the shared dispatcher,
      // so a single fallback broadcast refreshes every widget family.
      WidgetBridgeDispatchPlan(
        primaryAction = AUTO_REFRESH_ACTION,
        fallbackTargets =
          listOf(
            WidgetBroadcastTarget(TODAY_COURSE_PROVIDER, TODAY_COURSE_DATA_ACTION),
          ),
      )
    }
  }
}
