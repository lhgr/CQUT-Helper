package com.dawndrizzle.wing.cqut.widgetbridge

import org.junit.Assert.*
import org.junit.Test

class CourseAutoModePolicyTest {
  @Test fun delayedCleanupRestoresOnlyItsStillOwnedFinishedWindow() {
    val window = CourseModeInterval(10, 20)
    assertTrue(CourseAutoModePolicy.cleanupDue(true, "current", "current", window, 20, 20))
    // Exact-alarm permission is intentionally irrelevant to this restoration-only decision.
    assertTrue(CourseAutoModePolicy.cleanupDue(true, "current", "current", window, 20, 30))
    assertFalse(CourseAutoModePolicy.cleanupDue(true, "new", "old", window, 20, 30))
    assertFalse(CourseAutoModePolicy.cleanupDue(false, null, "old", null, 20, 30))
    assertFalse(CourseAutoModePolicy.cleanupDue(true, "current", "current", window, 20, 19))
    // A rebuilt overlapping window keeps capture ownership but replaces the cleanup deadline.
    assertFalse(CourseAutoModePolicy.cleanupDue(true, "current", "current", CourseModeInterval(10, 40), 20, 30))
    // A normal exact end has already cleared ownership, so its late backup is harmless.
    assertFalse(CourseAutoModePolicy.cleanupDue(false, null, "current", null, 20, 25))
  }

  @Test fun revokedLegacyPolicyKeepsRestoreOwnershipUntilRegrantOrUserChange() {
    val capturedPrevious = 1
    val appApplied = 2
    // Clearing the active course/cancelling does not discard this separate pending capture.
    assertEquals(CourseAutoModePolicy.PendingFilterAction.WAIT,
      CourseAutoModePolicy.pendingFilterAction(capturedPrevious, appApplied, 2, false))
    assertEquals(CourseAutoModePolicy.PendingFilterAction.RESTORE,
      CourseAutoModePolicy.pendingFilterAction(capturedPrevious, appApplied, 2, true))
    // A user change observed while access is missing releases ownership immediately.
    assertEquals(CourseAutoModePolicy.PendingFilterAction.DISCARD,
      CourseAutoModePolicy.pendingFilterAction(capturedPrevious, appApplied, 1, false))
    assertEquals(CourseAutoModePolicy.PendingFilterAction.DISCARD,
      CourseAutoModePolicy.pendingFilterAction(capturedPrevious, appApplied, 3, true))
    assertEquals(CourseAutoModePolicy.PendingFilterAction.DISCARD,
      CourseAutoModePolicy.pendingFilterAction(null, null, 2, true))
  }

  @Test fun mergesOverlappingAndTouchingWindowsButKeepsGaps() {
    assertEquals(listOf(CourseModeInterval(10, 40), CourseModeInterval(50, 60)), CourseAutoModePolicy.merge(listOf(
      CourseModeInterval(30, 40), CourseModeInterval(20, 30), CourseModeInterval(10, 25), CourseModeInterval(50, 60), CourseModeInterval(70, 70),
    )))
  }

  @Test fun boundariesAreStartInclusiveAndEndExclusive() {
    val intervals = listOf(CourseModeInterval(10, 20), CourseModeInterval(30, 40))
    assertNull(CourseAutoModePolicy.current(intervals, 9))
    assertEquals(intervals[0], CourseAutoModePolicy.current(intervals, 10))
    assertNull(CourseAutoModePolicy.current(intervals, 20))
    assertEquals(20L, CourseAutoModePolicy.nextBoundary(intervals, 10))
    assertEquals(30L, CourseAutoModePolicy.nextBoundary(intervals, 20))
    assertNull(CourseAutoModePolicy.nextBoundary(intervals, 40))
  }

  @Test fun rebuildingAnActiveWindowPreservesCapturedStateAndManualOverride() {
    assertTrue(CourseAutoModePolicy.preserveWindow("silent", "silent", CourseModeInterval(10, 30), CourseModeInterval(5, 40), 20))
    assertFalse(CourseAutoModePolicy.preserveWindow("silent", "dnd", CourseModeInterval(10, 30), CourseModeInterval(10, 30), 20))
    assertFalse(CourseAutoModePolicy.preserveWindow("silent", "silent", CourseModeInterval(10, 20), CourseModeInterval(30, 40), 35))
  }

  @Test fun restoreOnlyStillOwnedStateAndRespectUserChanges() {
    assertTrue(CourseAutoModePolicy.canRestore(true, false, 1, 0, 0))
    assertFalse(CourseAutoModePolicy.canRestore(true, false, 1, 0, 2))
    assertFalse(CourseAutoModePolicy.canRestore(true, true, 1, 0, 0))
    assertFalse(CourseAutoModePolicy.canRestore(false, false, 1, 0, 0))
  }

  @Test fun rebootAndClockChangeSelectTheCurrentWindowAndNextFutureBoundary() {
    val intervals = listOf(CourseModeInterval(10, 20), CourseModeInterval(30, 40))
    assertNull(CourseAutoModePolicy.current(intervals, 25))
    assertEquals(30L, CourseAutoModePolicy.nextBoundary(intervals, 25))
    assertFalse(CourseAutoModePolicy.preserveWindow("dnd", "dnd", intervals[0], intervals[1], 35))
    assertEquals(10L, CourseAutoModePolicy.nextBoundary(intervals, 5))
    assertNull(CourseAutoModePolicy.nextBoundary(emptyList(), 5))
    assertTrue(CourseAutoModePolicy.reapplyAfterBoot(true, false, "silent", "silent", intervals[0], intervals[0], 15))
    assertFalse(CourseAutoModePolicy.reapplyAfterBoot(true, true, "silent", "silent", intervals[0], intervals[0], 15))
    assertFalse(CourseAutoModePolicy.reapplyAfterBoot(true, false, "silent", "silent", intervals[0], intervals[1], 35))
    assertFalse(CourseAutoModePolicy.reapplyAfterBoot(true, false, "silent", "off", intervals[0], null, 15))
  }
}
