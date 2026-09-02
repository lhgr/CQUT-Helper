package com.dawndrizzle.wing.cqut.widgetbridge

import org.junit.Assert.assertEquals
import org.junit.Test

class WidgetBridgeDispatchPlanTest {
  @Test
  fun `ordinary refresh targets the shared auto refresh receiver`() {
    val plan = WidgetBridgeDispatchPlans.from(null, "schedule_refresh")

    assertEquals(WidgetBridgeDispatchPlans.AUTO_REFRESH_ACTION, plan.primaryAction)
    assertEquals(1, plan.fallbackTargets.size)
    assertEquals(
      "com.dawndrizzle.wing.cqut.widget.TodayCourseWidgetProvider",
      plan.fallbackTargets.single().receiverClassName,
    )
  }

  @Test
  fun `theme mode and init retain theme refresh semantics`() {
    listOf(
      WidgetBridgeDispatchPlans.from("dark", null),
      WidgetBridgeDispatchPlans.from(null, "app_theme_changed"),
      WidgetBridgeDispatchPlans.from(null, "init"),
    ).forEach { plan ->
      assertEquals(WidgetBridgeDispatchPlans.APP_THEME_REFRESH_ACTION, plan.primaryAction)
      assertEquals(5, plan.fallbackTargets.size)
      assertEquals(
        setOf(
          "com.dawndrizzle.wing.cqut.widget.TodayListWidgetProvider",
          "com.dawndrizzle.wing.cqut.widget.TodayAndNextWidgetProvider",
          "com.dawndrizzle.wing.cqut.widget.TodayCourseWidgetProvider",
          "com.dawndrizzle.wing.cqut.widget.TinyCourseWidgetProvider",
          "com.dawndrizzle.wing.cqut.widget.VerticalScheduleWidgetProvider",
        ),
        plan.fallbackTargets.map { it.receiverClassName }.toSet(),
      )
    }
  }
}
