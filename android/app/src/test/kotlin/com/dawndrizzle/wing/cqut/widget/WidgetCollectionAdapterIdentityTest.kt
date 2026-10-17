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
      WidgetCollectionAdapterIdentity.dataUri("today-list", 7, 0, "LIGHT|false", morning),
      WidgetCollectionAdapterIdentity.dataUri("today-list", 7, 0, "LIGHT|false", evening),
    )
  }

  @Test
  fun `adapter identity changes when visible collection content changes`() {
    val now = Instant.parse("2026-08-28T08:00:00Z").toEpochMilli()

    val before =
      WidgetCollectionAdapterIdentity.dataUri(
        "today-list",
        7,
        0,
        "LIGHT|false",
        contentFingerprint = "courses-before",
        nowMillis = now,
      )
    val after =
      WidgetCollectionAdapterIdentity.dataUri(
        "today-list",
        7,
        0,
        "LIGHT|false",
        contentFingerprint = "courses-after",
        nowMillis = now,
      )

    assertNotEquals(before, after)
    assertTrue(before.contains("/courses-before/"))
    assertTrue(after.contains("/courses-after/"))
  }

  @Test
  fun `adapter identity changes with app and system theme but stays stable otherwise`() {
    val now = Instant.parse("2026-08-28T08:00:00Z").toEpochMilli()
    val light = WidgetCollectionAdapterIdentity.dataUri(
      "today-list", 7, 0, "LIGHT|false", now, "same-courses",
    )
    val dark = WidgetCollectionAdapterIdentity.dataUri(
      "today-list", 7, 0, "DARK|true", now, "same-courses",
    )
    val systemLight = WidgetCollectionAdapterIdentity.dataUri(
      "today-list", 7, 0, "SYSTEM|false", now, "same-courses",
    )
    val systemDark = WidgetCollectionAdapterIdentity.dataUri(
      "today-list", 7, 0, "SYSTEM|true", now, "same-courses",
    )

    assertNotEquals(light, dark)
    assertNotEquals(systemLight, systemDark)
    assertEquals(light, WidgetCollectionAdapterIdentity.dataUri(
      "today-list", 7, 0, "LIGHT|false", now, "same-courses",
    ))
    assertTrue(dark.contains("/DARK-true/same-courses/"))
  }

  @Test
  fun `adapter identity changes at Beijing midnight`() {
    val beforeMidnight = Instant.parse("2026-08-28T15:59:59Z").toEpochMilli()
    val atMidnight = Instant.parse("2026-08-28T16:00:00Z").toEpochMilli()

    val before = WidgetCollectionAdapterIdentity.dataUri("today-course", 7, 0, "LIGHT|false", beforeMidnight)
    val after = WidgetCollectionAdapterIdentity.dataUri("today-course", 7, 0, "LIGHT|false", atMidnight)

    assertNotEquals(before, after)
    assertTrue(before.endsWith("/LIGHT-false/empty/2026-08-28"))
    assertTrue(after.endsWith("/LIGHT-false/empty/2026-08-29"))
  }

  @Test
  fun `tomorrow adapter identity contains its resolved calendar date`() {
    val now = Instant.parse("2026-08-28T15:59:59Z").toEpochMilli()

    assertTrue(
      WidgetCollectionAdapterIdentity
        .dataUri("today-and-next", 11, 1, "LIGHT|false", now)
        .endsWith("/1/LIGHT-false/empty/2026-08-29"),
    )
  }
}
