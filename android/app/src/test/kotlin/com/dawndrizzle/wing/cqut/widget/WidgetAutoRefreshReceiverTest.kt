package com.dawndrizzle.wing.cqut.widget

import android.content.Intent
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WidgetAutoRefreshReceiverTest {
  @Test
  fun `alarm clock boot package replacement and exact permission changes refresh data`() {
    val actions =
      listOf(
        WidgetAutoRefreshScheduler.ACTION_AUTO_REFRESH,
        Intent.ACTION_TIME_CHANGED,
        Intent.ACTION_TIMEZONE_CHANGED,
        Intent.ACTION_BOOT_COMPLETED,
        Intent.ACTION_MY_PACKAGE_REPLACED,
        WidgetAutoRefreshReceiver.ACTION_EXACT_ALARM_PERMISSION_STATE_CHANGED,
      )

    actions.forEach { action ->
      assertTrue(WidgetAutoRefreshReceiver.isDataRefreshAction(action))
    }
  }

  @Test
  fun `restricted implicit screen user and date broadcasts are not relied upon`() {
    listOf(
      Intent.ACTION_SCREEN_ON,
      Intent.ACTION_USER_PRESENT,
      Intent.ACTION_DATE_CHANGED,
    ).forEach { action ->
      assertFalse(WidgetAutoRefreshReceiver.isDataRefreshAction(action))
    }
  }

  @Test
  fun `app theme bridge remains separate from data refresh actions`() {
    assertFalse(
      WidgetAutoRefreshReceiver.isDataRefreshAction(
        WidgetAutoRefreshReceiver.ACTION_APP_THEME_REFRESH,
      ),
    )
  }

  @Test
  fun `manual refresh watchdog remains separate from ordinary data actions`() {
    assertFalse(
      WidgetAutoRefreshReceiver.isDataRefreshAction(
        WidgetAutoRefreshReceiver.ACTION_MANUAL_REFRESH_WATCHDOG,
      ),
    )
  }
}
