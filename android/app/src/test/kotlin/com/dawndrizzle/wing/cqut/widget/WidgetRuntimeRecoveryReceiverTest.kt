package com.dawndrizzle.wing.cqut.widget

import android.content.Intent
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WidgetRuntimeRecoveryReceiverTest {
  @Test
  fun `only date changes are process local recovery actions`() {
    assertTrue(WidgetRuntimeRecoveryReceiver.isRuntimeRecoveryAction(Intent.ACTION_DATE_CHANGED))
    assertFalse(WidgetRuntimeRecoveryReceiver.isRuntimeRecoveryAction(Intent.ACTION_SCREEN_ON))
    assertFalse(WidgetRuntimeRecoveryReceiver.isRuntimeRecoveryAction(Intent.ACTION_USER_PRESENT))
    assertFalse(
      WidgetRuntimeRecoveryReceiver.isRuntimeRecoveryAction(Intent.ACTION_TIMEZONE_CHANGED),
    )
  }
}
