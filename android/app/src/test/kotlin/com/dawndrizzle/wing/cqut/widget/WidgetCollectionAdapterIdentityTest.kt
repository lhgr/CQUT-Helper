package com.dawndrizzle.wing.cqut.widget

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

class WidgetCollectionAdapterIdentityTest {
  @Test
  fun `adapter identity remains stable within one Beijing calendar day`() {
    val morning = Instant.parse("2026-08-28T00:00:00Z").toEpochMilli()
    val evening = Instant.parse("2026-08-28T15:59:59Z").toEpochMilli()

    assertEquals(
      WidgetCollectionAdapterIdentity.dataUri("today-list", 7, 0, morning),
      WidgetCollectionAdapterIdentity.dataUri("today-list", 7, 0, evening),
    )
  }

  @Test
  fun `adapter identity changes at Beijing midnight`() {
    val beforeMidnight = Instant.parse("2026-08-28T15:59:59Z").toEpochMilli()
    val atMidnight = Instant.parse("2026-08-28T16:00:00Z").toEpochMilli()

    val before = WidgetCollectionAdapterIdentity.dataUri("today-course", 7, 0, beforeMidnight)
    val after = WidgetCollectionAdapterIdentity.dataUri("today-course", 7, 0, atMidnight)

    assertNotEquals(before, after)
    assertTrue(before.endsWith("/2026-08-28"))
    assertTrue(after.endsWith("/2026-08-29"))
  }

  @Test
  fun `tomorrow adapter identity contains its resolved calendar date`() {
    val now = Instant.parse("2026-08-28T15:59:59Z").toEpochMilli()

    assertTrue(
      WidgetCollectionAdapterIdentity
        .dataUri("today-and-next", 11, 1, now)
        .endsWith("/1/2026-08-29"),
    )
  }
}
