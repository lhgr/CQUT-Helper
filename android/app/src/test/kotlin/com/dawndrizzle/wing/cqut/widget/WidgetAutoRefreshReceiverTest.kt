package com.dawndrizzle.wing.cqut.widget

import android.content.Intent
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WidgetAutoRefreshReceiverTest {
  @Test
  fun `alarm boot package replacement and exact permission changes refresh data`() {
    val actions =
      listOf(
        WidgetAutoRefreshScheduler.ACTION_AUTO_REFRESH,
        Intent.ACTION_BOOT_COMPLETED,
        Intent.ACTION_MY_PACKAGE_REPLACED,
        WidgetAutoRefreshReceiver.ACTION_EXACT_ALARM_PERMISSION_STATE_CHANGED,
      )

    actions.forEach { action ->
      assertTrue(WidgetAutoRefreshReceiver.isDataRefreshAction(action))
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
}
