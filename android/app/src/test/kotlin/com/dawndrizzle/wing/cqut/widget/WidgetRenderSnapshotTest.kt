package com.dawndrizzle.wing.cqut.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
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

  @Test
  fun `nested renders reuse a projection and the next render decodes again`() {
    val projection = TodayWidgetData.CalendarProjection(false, emptyMap())
    var decodes = 0
    val decode = { decodes++; projection }
    WidgetRenderSnapshot.withSnapshot(1000L) {
      assertSame(projection, WidgetRenderSnapshot.current.get()!!.loadCalendarProjection("first", decode))
      WidgetRenderSnapshot.withSnapshot(2000L) {
        assertSame(projection, WidgetRenderSnapshot.current.get()!!.loadCalendarProjection("first", decode))
      }
      assertEquals(1, decodes)
    }
    WidgetRenderSnapshot.withSnapshot(3000L) {
      WidgetRenderSnapshot.current.get()!!.loadCalendarProjection("first", decode)
      assertEquals(2, decodes)
    }
  }

  @Test
  fun `changed preference contents replace the projection in the same render`() {
    val first = TodayWidgetData.CalendarProjection(false, emptyMap())
    val refreshed = TodayWidgetData.CalendarProjection(true, emptyMap())
    WidgetRenderSnapshot.withSnapshot {
      val snapshot = WidgetRenderSnapshot.current.get()!!
      assertSame(first, snapshot.loadCalendarProjection("first") { first })
      assertSame(refreshed, snapshot.loadCalendarProjection("refreshed") { refreshed })
      assertSame(refreshed, snapshot.loadCalendarProjection("refreshed") { error("decoded twice") })
    }
  }

  @Test
  fun `invalid projection is only decoded once until its contents change`() {
    var decodes = 0
    val refreshed = TodayWidgetData.CalendarProjection(true, emptyMap())
    WidgetRenderSnapshot.withSnapshot {
      val snapshot = WidgetRenderSnapshot.current.get()!!
      repeat(2) {
        assertNull(snapshot.loadCalendarProjection("invalid") { decodes++; null })
      }
      assertEquals(1, decodes)
      assertSame(refreshed, snapshot.loadCalendarProjection("refreshed") { refreshed })
    }
  }

  @Test
  fun `collection threads use independent projections`() {
    val parentProjection = TodayWidgetData.CalendarProjection(false, emptyMap())
    val collectionProjection = TodayWidgetData.CalendarProjection(true, emptyMap())
    var collectionResult: TodayWidgetData.CalendarProjection? = null
    WidgetRenderSnapshot.withSnapshot(1000L) {
      val snapshot = WidgetRenderSnapshot.current.get()!!
      snapshot.loadCalendarProjection("first") { parentProjection }
      val collectionThread = Thread {
        WidgetRenderSnapshot.withSnapshot(2000L) {
          collectionResult = WidgetRenderSnapshot.current.get()!!
            .loadCalendarProjection("first") { collectionProjection }
        }
      }
      collectionThread.start()
      collectionThread.join()
      assertSame(collectionProjection, collectionResult)
      assertSame(parentProjection, snapshot.loadCalendarProjection("first") { error("decoded twice") })
    }
  }
}
