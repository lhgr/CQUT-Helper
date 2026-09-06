package com.dawndrizzle.wing.cqut.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class WidgetRenderSnapshotTest {
  @Test
  fun `nested rendering keeps the same instant and session clocks`() {
    WidgetRenderSnapshot.withSnapshot(1000L) {
      WidgetRenderSnapshot.current.get()!!.sessionClocks = mapOf(1 to (480 to 525))
      WidgetRenderSnapshot.withSnapshot(2000L) {
        assertEquals(1000L, WidgetRenderSnapshot.nowMillis())
        assertEquals(480 to 525, WidgetRenderSnapshot.current.get()!!.sessionClocks!![1])
      }
    }
    assertNull(WidgetRenderSnapshot.current.get())
    WidgetRenderSnapshot.withSnapshot(3000L) {
      assertEquals(3000L, WidgetRenderSnapshot.nowMillis())
      assertNull(WidgetRenderSnapshot.current.get()!!.sessionClocks)
    }
  }

  @Test
  fun `failed renders release the snapshot`() {
    try {
      WidgetRenderSnapshot.withSnapshot(1000L) { error("render failed") }
    } catch (_: IllegalStateException) {
      // The next recovery must use fresh data even after a render failure.
    }
    assertNull(WidgetRenderSnapshot.current.get())
  }
}
