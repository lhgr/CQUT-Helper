package com.dawndrizzle.wing.cqut.widgetbridge

internal data class CourseModeInterval(val startMillis: Long, val endMillis: Long)

/** Platform-free decisions used by the alarm receiver and every Flutter engine. */
internal object CourseAutoModePolicy {
  enum class PendingFilterAction { WAIT, RESTORE, DISCARD }
  fun merge(intervals: List<CourseModeInterval>): List<CourseModeInterval> {
    val sorted = intervals.filter { it.endMillis > it.startMillis }.sortedBy { it.startMillis }
    val result = mutableListOf<CourseModeInterval>()
    for (interval in sorted) {
      val previous = result.lastOrNull()
      if (previous != null && interval.startMillis <= previous.endMillis) {
        result[result.lastIndex] = CourseModeInterval(previous.startMillis, maxOf(previous.endMillis, interval.endMillis))
      } else result.add(interval)
    }
    return result
  }

  fun current(intervals: List<CourseModeInterval>, now: Long): CourseModeInterval? =
    intervals.firstOrNull { now >= it.startMillis && now < it.endMillis }

  fun nextBoundary(intervals: List<CourseModeInterval>, now: Long): Long? =
    intervals.asSequence().flatMap { sequenceOf(it.startMillis, it.endMillis) }.filter { it > now }.minOrNull()

  fun preserveWindow(oldMode: String?, mode: String, oldWindow: CourseModeInterval?, window: CourseModeInterval?, now: Long): Boolean =
    oldMode == mode && oldWindow != null && window != null &&
      now >= oldWindow.startMillis && now < oldWindow.endMillis &&
      now >= window.startMillis && now < window.endMillis

  fun canRestore(controlled: Boolean, manualOverride: Boolean, previous: Int?, applied: Int?, actual: Int): Boolean =
    controlled && !manualOverride && previous != null && applied != null && actual == applied

  fun reapplyAfterBoot(controlled: Boolean, manualOverride: Boolean, oldMode: String?, mode: String,
    oldWindow: CourseModeInterval?, window: CourseModeInterval?, now: Long): Boolean =
    controlled && !manualOverride && preserveWindow(oldMode, mode, oldWindow, window, now)

  fun pendingFilterAction(previous: Int?, applied: Int?, actual: Int, policyGranted: Boolean): PendingFilterAction = when {
    previous == null || applied == null || actual != applied -> PendingFilterAction.DISCARD
    policyGranted -> PendingFilterAction.RESTORE
    else -> PendingFilterAction.WAIT
  }

  fun cleanupDue(controlled: Boolean, token: String?, expectedToken: String?, window: CourseModeInterval?,
    expectedEnd: Long, now: Long): Boolean = controlled && token != null && token == expectedToken &&
    window != null && window.endMillis == expectedEnd && now >= expectedEnd
}
