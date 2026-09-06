package com.dawndrizzle.wing.cqut.widget

import android.content.Intent
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WidgetRuntimeRecoveryReceiverTest {
  @Test
  fun `date changes and unlocks repair widgets while the process is alive`() {
    assertTrue(WidgetRuntimeRecoveryReceiver.isRuntimeRecoveryAction(Intent.ACTION_DATE_CHANGED))
    assertFalse(WidgetRuntimeRecoveryReceiver.isRuntimeRecoveryAction(Intent.ACTION_SCREEN_ON))
    assertTrue(WidgetRuntimeRecoveryReceiver.isRuntimeRecoveryAction(Intent.ACTION_USER_PRESENT))
    assertFalse(
      WidgetRuntimeRecoveryReceiver.isRuntimeRecoveryAction(Intent.ACTION_TIMEZONE_CHANGED),
    )
  }
}
