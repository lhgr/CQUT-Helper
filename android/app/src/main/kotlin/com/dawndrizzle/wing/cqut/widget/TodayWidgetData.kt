package com.dawndrizzle.wing.cqut.widget

import android.content.Context
import android.content.pm.ApplicationInfo
import android.text.format.DateUtils
import android.util.Log
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
import java.security.MessageDigest
import java.util.Calendar
import java.util.Locale

object TodayWidgetData {
  enum class DayScheduleAvailability {
    COVERED,
    OUTSIDE_TEACHING_WEEK,
    MISSING_CACHE,
  }

  enum class RefreshPresentationState {
    NORMAL,
    NEEDS_SYNC,
    STALE,
    LOADING,
    FAILED,
    CREDENTIAL_INVALID,
  }

  data class RefreshPresentation(
    val state: RefreshPresentationState,
    val text: String,
  ) {
    val usesRefreshAction: Boolean
      get() =
        state == RefreshPresentationState.NEEDS_SYNC ||
          state == RefreshPresentationState.STALE ||
          state == RefreshPresentationState.FAILED

    val replacesDateMetadata: Boolean
      get() = state != RefreshPresentationState.NORMAL
  }

  data class Header(
    val scheduleName: String,
    val dateText: String,
    val weekText: String,
  )

  data class CourseItem(
    val eventId: String?,
    val courseKey: String,
    val name: String,
    val campus: String,
    val classroom: String,
    val teacher: String,
    val periods: String,
    val indicatorColor: Int,
    val sortOrder: Int,
  )

  internal data class ScheduleDayMarker(
    val weekDate: String,
    val markedToday: Boolean,
  )

  private data class ParsedScheduleDate(
    val year: Int?,
    val month: Int,
    val day: Int,
  )

  private const val PREFS_NAME = "FlutterSharedPreferences"
  private const val FLUTTER_PREFIX = "flutter."
  internal const val WIDGET_TIME_ZONE_ID = "Asia/Shanghai"
  private val WIDGET_TIME_ZONE = java.util.TimeZone.getTimeZone(WIDGET_TIME_ZONE_ID)
  private const val KEY_WIDGET_WEEK_PREFIX = "${FLUTTER_PREFIX}schedule_widget_week_"
  private const val KEY_WIDGET_TERM_PREFIX = "${FLUTTER_PREFIX}schedule_widget_term_"
  private const val KEY_LAST_WEEK_PREFIX = "${FLUTTER_PREFIX}schedule_last_week_"
  private const val KEY_LAST_TERM_PREFIX = "${FLUTTER_PREFIX}schedule_last_term_"
  private const val KEY_TIME_INFO_CACHE = "${FLUTTER_PREFIX}schedule_time_info_cache_v1"
  private const val KEY_COURSE_COLOR_MAP_PREFIX = "${FLUTTER_PREFIX}schedule_course_color_map_v1_"
  private const val KEY_BACKGROUND_POLLING_ENABLED =
    "${FLUTTER_PREFIX}schedule_background_polling_enabled"
  private const val KEY_LAST_SUCCESSFUL_REFRESH_AT_PREFIX =
    "${FLUTTER_PREFIX}schedule_last_successful_refresh_at_"
  private const val KEY_WIDGET_REFRESH_STATE_PREFIX =
    "${FLUTTER_PREFIX}schedule_widget_refresh_state_"
  private const val KEY_WIDGET_REFRESH_FAILURE_PREFIX =
    "${FLUTTER_PREFIX}schedule_widget_refresh_failure_"
  private const val MILLIS_PER_DAY = 24L * 60 * 60 * 1000
  private const val ANONYMOUS_SCOPE = "anonymous"
  private val COURSE_TITLE_COLORS =
    intArrayOf(
      0xFF1473A3.toInt(),
      0xFFAC3E15.toInt(),
      0xFF0F7B78.toInt(),
      0xFF621EA4.toInt(),
      0xFF915D12.toInt(),
      0xFFAC1522.toInt(),
      0xFFAC152C.toInt(),
      0xFF0F7A7B.toInt(),
      0xFF846C10.toInt(),
      0xFF781CA6.toInt(),
      0xFF3215AC.toInt(),
    )

  private fun widgetCalendar(
    timeInMillis: Long = System.currentTimeMillis(),
  ): Calendar =
    Calendar.getInstance(WIDGET_TIME_ZONE).apply {
      this.timeInMillis = timeInMillis
    }

  private fun widgetDateFormat(pattern: String): SimpleDateFormat =
    SimpleDateFormat(pattern, Locale.CHINA).apply {
      timeZone = WIDGET_TIME_ZONE
    }

  fun loadHeader(context: Context): Header {
    val calendar = widgetCalendar()
    val dateFormat = widgetDateFormat("M.d")
    val defaultDateText = dateFormat.format(calendar.time)
    val defaultWeekText = "周${toChineseWeekday(toMondayBasedWeekday(calendar))}"

    val today = loadTodayWeekDayAndDate(context)
    return Header(
      scheduleName = "课表",
      dateText = today?.dateText ?: defaultDateText,
      weekText = today?.weekText ?: defaultWeekText,
    )
  }

  fun loadHeaderByDayOffset(context: Context, dayOffset: Int): Header {
    val dateFormat = widgetDateFormat("M.d")
    val targetCal = widgetCalendar().apply { add(Calendar.DAY_OF_YEAR, dayOffset) }
    val targetWeekDay = toMondayBasedWeekday(targetCal)

    val defaultDateText = dateFormat.format(targetCal.time)
    val defaultWeekText = "周${toChineseWeekday(targetWeekDay)}"

    return Header(
      scheduleName = "课表",
      dateText = defaultDateText,
      weekText = defaultWeekText,
    )
  }

  fun loadWeekCountText(context: Context, dayOffset: Int = 0): String {
    val targetDate = widgetCalendar().apply { add(Calendar.DAY_OF_YEAR, dayOffset) }
    val data = loadScheduleJsonObjectForDate(context, targetDate) ?: return ""
    val week = data.optString("weekNum", "")
    if (week.isBlank()) return ""
    return "第${week}周"
  }

  fun loadRefreshPresentation(
    context: Context,
    appWidgetId: Int = android.appwidget.AppWidgetManager.INVALID_APPWIDGET_ID,
    requiredDayOffsets: IntArray? = null,
  ): RefreshPresentation {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val account =
      prefs.getString("${FLUTTER_PREFIX}account", null)?.trim().orEmpty()
    if (account.isEmpty()) {
      return RefreshPresentation(
        RefreshPresentationState.CREDENTIAL_INVALID,
        "请打开应用登录",
      )
    }

    val refreshState =
      prefs.getString("$KEY_WIDGET_REFRESH_STATE_PREFIX$account", "idle")
    val failure =
      prefs.getString("$KEY_WIDGET_REFRESH_FAILURE_PREFIX$account", null)
    if (refreshState == "loading") {
      return RefreshPresentation(
        RefreshPresentationState.LOADING,
        "正在更新课表…",
      )
    }
    if (refreshState == "failed") {
      return if (failure == "credentialInvalid") {
        RefreshPresentation(
          RefreshPresentationState.CREDENTIAL_INVALID,
          "登录已失效，请打开应用",
        )
      } else {
        RefreshPresentation(
          RefreshPresentationState.FAILED,
          "更新失败，点右上角重试",
        )
      }
    }

    val offsets =
      requiredDayOffsets
        ?: intArrayOf(
          if (appWidgetId == android.appwidget.AppWidgetManager.INVALID_APPWIDGET_ID) {
            0
          } else {
            WidgetInstanceConfigStore.load(context, appWidgetId).dayOffset
          },
        )
    val scheduleCandidates = loadScheduleJsonObjects(context)
    val hasCoveredRequiredDate =
      offsets.any { dayOffset ->
        val targetDate = widgetCalendar().apply { add(Calendar.DAY_OF_YEAR, dayOffset) }
        scheduleCandidates.any { scheduleContainsDate(it, targetDate) }
      }
    val isDebuggable =
      context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
    val lastSuccessfulAt =
      prefs
        .getString("$KEY_LAST_SUCCESSFUL_REFRESH_AT_PREFIX$account", null)
        ?.let(::parseIso8601Millis)
        ?: migrateLegacyRefreshAt(context, prefs, account)
    val pollingEnabled = prefs.getBoolean(KEY_BACKGROUND_POLLING_ENABLED, false)
    val presentation = idleRefreshPresentation(
      hasCoveredRequiredDate = hasCoveredRequiredDate,
      hasAnyScheduleCache = scheduleCandidates.isNotEmpty(),
      isDebuggable = isDebuggable,
      pollingEnabled = pollingEnabled,
      lastSuccessfulAt = lastSuccessfulAt,
      nowMillis = System.currentTimeMillis(),
      suggestionDays = WidgetInstanceConfigStore.load(context, appWidgetId).refreshSuggestionDays,
    )
    val refreshAgeMillis =
      lastSuccessfulAt?.let { (System.currentTimeMillis() - it).coerceAtLeast(0L) }
    Log.i(
      "WidgetScheduleState",
      "offsets=${offsets.joinToString()} covered=$hasCoveredRequiredDate " +
        "cacheCount=${scheduleCandidates.size} polling=$pollingEnabled " +
        "refreshAgeMs=${refreshAgeMillis ?: -1L} state=${presentation.state}",
    )
    return presentation
  }

  internal fun idleRefreshPresentation(
    hasCoveredRequiredDate: Boolean,
    hasAnyScheduleCache: Boolean,
    isDebuggable: Boolean,
    pollingEnabled: Boolean,
    lastSuccessfulAt: Long?,
    nowMillis: Long,
    suggestionDays: Int,
  ): RefreshPresentation {
    if (!hasCoveredRequiredDate) {
      if (!hasAnyScheduleCache) {
        return RefreshPresentation(
          RefreshPresentationState.NEEDS_SYNC,
          "课表尚未同步，点右上角刷新",
        )
      }
      val cacheWasVerifiedRecently =
        lastSuccessfulAt != null &&
          !isRefreshStale(lastSuccessfulAt, nowMillis, suggestionDays)
      if (!cacheWasVerifiedRecently) {
        return RefreshPresentation(
          RefreshPresentationState.STALE,
          "课表可能已过期，点右上角刷新",
        )
      }
      // A recent successful server response that does not cover the requested
      // date is authoritative evidence of a holiday/non-teaching week, not a
      // stale cache. Let the day-level empty state explain that condition.
    }

    // Keep manual refresh directly reachable while exercising widget behavior
    // from a debug build. Release builds continue to use the real sync age.
    if (isDebuggable) {
      return RefreshPresentation(
        RefreshPresentationState.NEEDS_SYNC,
        "调试模式：点右上角刷新",
      )
    }

    if (!pollingEnabled &&
      lastSuccessfulAt != null &&
      isRefreshStale(lastSuccessfulAt, nowMillis, suggestionDays)
    ) {
      return RefreshPresentation(
        RefreshPresentationState.STALE,
        "课表可能已过期",
      )
    }

    // A matching, parseable cache is already synchronized data. Background
    // polling is optional, so the absence of its success timestamp must not
    // turn a populated widget into a permanent "not synchronized" state.
    return RefreshPresentation(
      RefreshPresentationState.NORMAL,
      lastSuccessfulAt?.let(::formatLastUpdated).orEmpty(),
    )
  }

  private fun parseIso8601Millis(raw: String): Long? {
    return try {
      if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.O) {
        val hasOffset =
          raw.endsWith("Z") || Regex("""[+-]\d{2}:\d{2}$""").containsMatchIn(raw)
        if (hasOffset) {
          java.time.OffsetDateTime.parse(raw).toInstant().toEpochMilli()
        } else {
          java.time.LocalDateTime
            .parse(raw)
            .atZone(java.time.ZoneId.of(WIDGET_TIME_ZONE_ID))
            .toInstant()
            .toEpochMilli()
        }
      } else {
        val hasOffset =
          raw.endsWith("Z") || Regex("""[+-]\d{2}:\d{2}$""").containsMatchIn(raw)
        val normalized =
          if (hasOffset) {
            raw.replace("Z", "+0000")
              .replace(Regex("""([+-]\d{2}):(\d{2})$"""), "$1$2")
          } else {
            raw
          }
        SimpleDateFormat(
          if (hasOffset) "yyyy-MM-dd'T'HH:mm:ss.SSSZ" else "yyyy-MM-dd'T'HH:mm:ss.SSS",
          Locale.US,
        ).apply {
          if (!hasOffset) timeZone = WIDGET_TIME_ZONE
        }.parse(normalized)?.time
      }
    } catch (_: Exception) {
      null
    }
  }

  private fun migrateLegacyRefreshAt(
    context: Context,
    prefs: android.content.SharedPreferences,
    account: String,
  ): Long? {
    val schedule = loadScheduleJsonObject(context) ?: return null
    if (!schedule.has("weekDayList") && !schedule.has("eventList")) return null

    val term =
      prefs.getString("$KEY_WIDGET_TERM_PREFIX$account", null)?.takeIf { it.isNotBlank() }
        ?: prefs.getString("$KEY_LAST_TERM_PREFIX$account", null)?.takeIf { it.isNotBlank() }
        ?: return null
    val week =
      prefs.getString("$KEY_WIDGET_WEEK_PREFIX$account", null)?.takeIf { it.isNotBlank() }
        ?: prefs.getString("$KEY_LAST_WEEK_PREFIX$account", null)?.takeIf { it.isNotBlank() }
        ?: return null

    val legacyFetchAt =
      try {
        prefs.getLong("${FLUTTER_PREFIX}schedule_fetch_at_${account}_${term}_$week", 0L)
      } catch (_: ClassCastException) {
        0L
      }
    val backgroundPollAt =
      prefs
        .getString("${FLUTTER_PREFIX}schedule_background_poll_last_success_at", null)
        ?.let(::parseIso8601Millis)
        ?: 0L
    val migratedAt =
      maxOf(legacyFetchAt, backgroundPollAt).takeIf { it > 0L }
        ?: if (scheduleContainsSystemDate(schedule)) {
          System.currentTimeMillis()
        } else {
          return null
        }
    val migratedText =
      SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss.SSS'Z'", Locale.US)
        .apply { timeZone = java.util.TimeZone.getTimeZone("UTC") }
        .format(java.util.Date(migratedAt))
    prefs
      .edit()
      .putString("$KEY_LAST_SUCCESSFUL_REFRESH_AT_PREFIX$account", migratedText)
      .apply()
    return migratedAt
  }

  internal fun formatLastUpdated(
    timestamp: Long,
    nowMillis: Long = System.currentTimeMillis(),
  ): String {
    val now = widgetCalendar(nowMillis)
    val at = widgetCalendar(timestamp)
    if (isSameCalendarDate(now, at)) {
      return widgetDateFormat("HH:mm").format(at.time)
    }
    return "${calendarDayDistance(now, at)}天前"
  }

  internal fun isRefreshStale(
    lastSuccessfulAt: Long,
    nowMillis: Long,
    suggestionDays: Int,
  ): Boolean {
    val normalizedDays = WidgetInstanceConfigStore.normalizeRefreshSuggestionDays(suggestionDays)
    return nowMillis - lastSuccessfulAt > normalizedDays.toLong() * MILLIS_PER_DAY
  }

  private fun calendarDayDistance(
    now: Calendar,
    at: Calendar,
  ): Long {
    fun localDateAsUtcMillis(calendar: Calendar): Long =
      Calendar.getInstance(java.util.TimeZone.getTimeZone("UTC")).run {
        clear()
        set(
          calendar.get(Calendar.YEAR),
          calendar.get(Calendar.MONTH),
          calendar.get(Calendar.DAY_OF_MONTH),
        )
        timeInMillis
      }
    return ((localDateAsUtcMillis(now) - localDateAsUtcMillis(at)) / MILLIS_PER_DAY)
      .coerceAtLeast(0L)
  }

  fun loadCoursesByDayOffset(context: Context, dayOffset: Int): List<CourseItem> {
    val targetDate =
      widgetCalendar().apply {
        add(Calendar.DAY_OF_YEAR, dayOffset)
      }
    val targetData = loadScheduleJsonObjectForDate(context, targetDate) ?: return emptyList()
    val targetWeekDay = toMondayBasedWeekday(targetDate)

    val courses =
      loadCoursesByWeekdayFromSchedule(
        context,
        targetData,
        targetWeekDay.coerceIn(1, 7).toString(),
      )
    if (dayOffset != 0) return courses
    return filterEndedCourses(context, targetData, courses)
  }

  fun loadEmptyStateText(context: Context, dayOffset: Int): String {
    return emptyStateTextFor(loadDayScheduleAvailability(context, dayOffset))
  }

  internal fun emptyStateTextFor(availability: DayScheduleAvailability): String {
    return when (availability) {
      DayScheduleAvailability.COVERED -> "暂无课程"
      DayScheduleAvailability.OUTSIDE_TEACHING_WEEK -> "当前不在教学周"
      DayScheduleAvailability.MISSING_CACHE -> "课表尚未同步"
    }
  }

  private fun loadDayScheduleAvailability(
    context: Context,
    dayOffset: Int,
  ): DayScheduleAvailability {
    val targetDate =
      widgetCalendar().apply {
        add(Calendar.DAY_OF_YEAR, dayOffset)
      }
    if (loadScheduleJsonObjectForDate(context, targetDate) != null) {
      return DayScheduleAvailability.COVERED
    }
    return if (loadScheduleJsonObjects(context).isEmpty()) {
      DayScheduleAvailability.MISSING_CACHE
    } else {
      DayScheduleAvailability.OUTSIDE_TEACHING_WEEK
    }
  }

  fun nextRefreshAtMillis(context: Context): Long? {
    val now = System.currentTimeMillis()
    val candidates = mutableListOf<Long>()
    candidates.add(nextDayRefreshAtMillis(now))
    val nextCourseBoundary = nextCourseBoundaryAtMillisToday(context, now)
    if (nextCourseBoundary != null && nextCourseBoundary > now) {
      candidates.add(nextCourseBoundary)
    }
    return candidates.filter { it > now }.minOrNull()
  }

  private fun scheduleContainsSystemDate(data: JSONObject): Boolean {
    return scheduleContainsDate(data, widgetCalendar())
  }

  private fun scheduleContainsDate(data: JSONObject, targetDate: Calendar): Boolean {
    val weekDayList = data.optJSONArray("weekDayList")
    if (weekDayList == null || weekDayList.length() == 0) {
      return false
    }
    val markers = ArrayList<ScheduleDayMarker>(weekDayList.length())
    for (i in 0 until weekDayList.length()) {
      val d = weekDayList.optJSONObject(i) ?: continue
      markers.add(
        ScheduleDayMarker(
          weekDate = d.optString("weekDate", ""),
          markedToday = d.optBoolean("today", false),
        ),
      )
    }
    return scheduleDayMarkersContainDate(
      markers,
      targetDate = targetDate,
    )
  }

  internal fun scheduleDayMarkersContainDate(
    markers: List<ScheduleDayMarker>,
    targetDate: Calendar,
  ): Boolean {
    val targetDay =
      createScheduleCalendar(
        targetDate.get(Calendar.YEAR),
        targetDate.get(Calendar.MONTH) + 1,
        targetDate.get(Calendar.DAY_OF_MONTH),
      ) ?: return false
    var firstDayMillis: Long? = null
    var lastDayMillis: Long? = null
    for (marker in markers) {
      val parsed = extractScheduleDate(marker.weekDate) ?: continue
      val parsedDay = resolveScheduleDate(parsed, targetDate) ?: continue
      val millis = parsedDay.timeInMillis
      if (firstDayMillis == null || millis < firstDayMillis!!) firstDayMillis = millis
      if (lastDayMillis == null || millis > lastDayMillis!!) lastDayMillis = millis
    }
    // The backend's `today` bit belongs to the fetch instant and can remain
    // stale in a cached week. Only a parseable range containing the target is
    // authoritative, matching ScheduleDate.dataCoversDate on the Dart side.
    val first = firstDayMillis ?: return false
    val last = lastDayMillis ?: return false
    return targetDay.timeInMillis in first..last
  }

  private fun loadScheduleJsonObjectForDate(
    context: Context,
    targetDate: Calendar,
  ): JSONObject? {
    return loadScheduleJsonObjects(context).firstOrNull { scheduleContainsDate(it, targetDate) }
  }

  private fun loadScheduleJsonObjects(context: Context): List<JSONObject> =
    listOfNotNull(
      loadScheduleJsonObject(context),
      loadPrevWeekScheduleJsonObject(context),
      loadNextWeekScheduleJsonObject(context),
    )

  private fun loadNextWeekScheduleJsonObject(context: Context): JSONObject? {
    return loadOffsetWeekScheduleJsonObject(context, offsetWeeks = 1)
  }

  private fun loadPrevWeekScheduleJsonObject(context: Context): JSONObject? {
    return loadOffsetWeekScheduleJsonObject(context, offsetWeeks = -1)
  }

  private fun loadOffsetWeekScheduleJsonObject(context: Context, offsetWeeks: Int): JSONObject? {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val userId = prefs.getString("${FLUTTER_PREFIX}account", null)?.takeIf { it.isNotBlank() } ?: return null
    val baseTerm =
      prefs.getString("$KEY_WIDGET_TERM_PREFIX$userId", null)?.takeIf { it.isNotBlank() }
        ?: prefs.getString("$KEY_LAST_TERM_PREFIX$userId", null)?.takeIf { it.isNotBlank() }
        ?: return null
    val baseWeekStr =
      prefs.getString("$KEY_WIDGET_WEEK_PREFIX$userId", null)?.takeIf { it.isNotBlank() }
        ?: prefs.getString("$KEY_LAST_WEEK_PREFIX$userId", null)?.takeIf { it.isNotBlank() }
        ?: return null
    val baseWeek = baseWeekStr.toIntOrNull() ?: return null

    val targetWeek = (baseWeek + offsetWeeks).toString()
    val scheduleKey = "${FLUTTER_PREFIX}schedule_${userId}_${baseTerm}_$targetWeek"
    val jsonStr = prefs.getString(scheduleKey, null) ?: return null
    return try {
      JSONObject(jsonStr)
    } catch (_: Exception) {
      null
    }
  }

  fun loadCoursesByWeekdayFromSchedule(context: Context, data: JSONObject, weekDay: String): List<CourseItem> {
    val events = data.optJSONArray("eventList") ?: return emptyList()
    val courseColorMap = loadCourseColorIndexMap(context)
    val result = ArrayList<CourseItem>(events.length())

    for (i in 0 until events.length()) {
      val e = events.optJSONObject(i) ?: continue
      val eWeekDay = e.optString("weekDay", "")
      if (eWeekDay != weekDay) continue

      val rawName = e.optString("eventName", "")
      val courseKey = buildCourseColorKey(rawName)
      val name = rawName.ifBlank { "课程" }
      val location = e.optString("address", "").trim()
      val (campus, classroom) = splitCampusAndClassroom(location)
      val teacher = e.optString("memberName", "").ifBlank { " " }

      val start = e.optInt("sessionStart", -1)
      val last = e.optInt("sessionLast", -1)
      val periods =
        if (start > 0 && last > 0) {
          val end = start + last - 1
          "第$start-${end}节"
        } else {
          val arr = e.optJSONArray("sessionList")
          if (arr != null && arr.length() > 0) {
            "第${joinIntArray(arr)}节"
          } else {
            ""
          }
        }
      val sortOrder =
        when {
          start > 0 -> start
          else -> minSessionStart(e.optJSONArray("sessionList")) ?: Int.MAX_VALUE
        }

      val eventId = e.optString("eventID", "").ifBlank { null }
      val colorIndex = courseColorMap[courseKey] ?: fallbackColorIndex(courseKey)
      result.add(
        CourseItem(
          eventId = eventId,
          courseKey = courseKey,
          name = name,
          campus = campus,
          classroom = classroom,
          teacher = teacher,
          periods = periods,
          indicatorColor = colorByIndex(colorIndex),
          sortOrder = sortOrder,
        ),
      )
    }

    result.sortWith(compareBy<CourseItem> { it.sortOrder }.thenBy { it.periods })
    return result
  }

  fun loadTodayCourses(context: Context): List<CourseItem> {
    return loadCoursesByDayOffset(context, 0)
  }

  private data class TodayInfo(
    val weekDay: String,
    val dateText: String,
    val weekText: String,
  )

  private fun loadTodayWeekDayAndDate(context: Context): TodayInfo? {
    val targetDate = widgetCalendar()
    val data = loadScheduleJsonObjectForDate(context, targetDate) ?: return null
    return loadTodayWeekDayAndDateFromSchedule(data, targetDate)
  }

  private fun loadTodayWeekDayAndDateFromSchedule(
    data: JSONObject,
    targetDate: Calendar,
  ): TodayInfo? {
    val weekDayList = data.optJSONArray("weekDayList") ?: return null
    for (i in 0 until weekDayList.length()) {
      val d = weekDayList.optJSONObject(i) ?: continue
      val weekDay = d.optString("weekDay", "")
      val weekDate = d.optString("weekDate", "")
      if (weekDate.isNotBlank() && isSameAsDate(weekDate, targetDate)) {
        return todayInfoFromScheduleDay(weekDay, weekDate)
      }
    }
    // A weekday without a date cannot prove that this cached week covers the
    // target. The caller will use a clock-derived Beijing date as a safe header.
    return null
  }

  private fun todayInfoFromScheduleDay(
    weekDay: String,
    weekDate: String,
  ): TodayInfo? {
    val computedWeekDay = mondayBasedWeekdayFromWeekDateText(weekDate)
    val normalizedWeekDay = computedWeekDay?.toString() ?: weekDay
    if (normalizedWeekDay.isBlank() && weekDate.isBlank()) return null
    val weekText =
      normalizedWeekDay
        .toIntOrNull()
        ?.let { "周${toChineseWeekday(it)}" }
        .orEmpty()
    return TodayInfo(
      weekDay = normalizedWeekDay,
      dateText = weekDate,
      weekText = weekText,
    )
  }

  fun loadScheduleJsonObject(context: Context): JSONObject? {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val userId = prefs.getString("${FLUTTER_PREFIX}account", null)?.takeIf { it.isNotBlank() } ?: return null

    val term =
      prefs.getString("$KEY_WIDGET_TERM_PREFIX$userId", null)?.takeIf { it.isNotBlank() }
        ?: prefs.getString("$KEY_LAST_TERM_PREFIX$userId", null)?.takeIf { it.isNotBlank() }
        ?: return null
    val week =
      prefs.getString("$KEY_WIDGET_WEEK_PREFIX$userId", null)?.takeIf { it.isNotBlank() }
        ?: prefs.getString("$KEY_LAST_WEEK_PREFIX$userId", null)?.takeIf { it.isNotBlank() }
        ?: return null

    val scheduleKey = "${FLUTTER_PREFIX}schedule_${userId}_${term}_$week"
    val jsonStr = prefs.getString(scheduleKey, null) ?: return null

    return try {
      JSONObject(jsonStr)
    } catch (_: Exception) {
      null
    }
  }

  fun loadDisplayedScheduleFingerprint(context: Context): String {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val account = prefs.getString("${FLUTTER_PREFIX}account", null)?.trim().orEmpty()
    val term =
      prefs.getString("$KEY_WIDGET_TERM_PREFIX$account", null)?.trim().orEmpty()
        .ifBlank { prefs.getString("$KEY_LAST_TERM_PREFIX$account", null)?.trim().orEmpty() }
    val week =
      prefs.getString("$KEY_WIDGET_WEEK_PREFIX$account", null)?.trim().orEmpty()
        .ifBlank { prefs.getString("$KEY_LAST_WEEK_PREFIX$account", null)?.trim().orEmpty() }
    val scheduleJson =
      if (account.isNotBlank() && term.isNotBlank() && week.isNotBlank()) {
        prefs.getString("${FLUTTER_PREFIX}schedule_${account}_${term}_$week", null)
      } else {
        null
      }
    return displayedScheduleFingerprint(account, term, week, scheduleJson)
  }

  internal fun displayedScheduleFingerprint(
    account: String,
    term: String,
    week: String,
    scheduleJson: String?,
  ): String {
    val bytes = "$account\u0000$term\u0000$week\u0000${scheduleJson.orEmpty()}".toByteArray()
    return MessageDigest
      .getInstance("SHA-256")
      .digest(bytes)
      .joinToString("") { "%02x".format(it) }
  }

  private fun isSameAsDate(weekDateText: String, targetDate: Calendar): Boolean {
    val parsed = extractScheduleDate(weekDateText) ?: return false
    return isSameAsDate(parsed, targetDate)
  }

  private fun isSameAsDate(
    parsed: ParsedScheduleDate,
    targetDate: Calendar,
  ): Boolean {
    if (parsed.year != null && parsed.year != targetDate.get(Calendar.YEAR)) return false
    return parsed.month == targetDate.get(Calendar.MONTH) + 1 &&
      parsed.day == targetDate.get(Calendar.DAY_OF_MONTH)
  }

  private fun isSameCalendarDate(first: Calendar, second: Calendar): Boolean {
    return first.get(Calendar.YEAR) == second.get(Calendar.YEAR) &&
      first.get(Calendar.DAY_OF_YEAR) == second.get(Calendar.DAY_OF_YEAR)
  }

  private fun mondayBasedWeekdayFromWeekDateText(weekDateText: String): Int? {
    val parsed = extractScheduleDate(weekDateText) ?: return null
    val calNow = widgetCalendar()
    val nowYear = calNow.get(Calendar.YEAR)
    val nowMonth = calNow.get(Calendar.MONTH) + 1
    val nowDay = calNow.get(Calendar.DAY_OF_MONTH)

    val base = widgetCalendar().apply {
      set(Calendar.YEAR, parsed.year ?: nowYear)
      set(Calendar.MONTH, parsed.month - 1)
      set(Calendar.DAY_OF_MONTH, parsed.day)
      set(Calendar.HOUR_OF_DAY, 0)
      set(Calendar.MINUTE, 0)
      set(Calendar.SECOND, 0)
      set(Calendar.MILLISECOND, 0)
    }

    val nowDate = widgetCalendar().apply {
      set(Calendar.YEAR, nowYear)
      set(Calendar.MONTH, nowMonth - 1)
      set(Calendar.DAY_OF_MONTH, nowDay)
      set(Calendar.HOUR_OF_DAY, 0)
      set(Calendar.MINUTE, 0)
      set(Calendar.SECOND, 0)
      set(Calendar.MILLISECOND, 0)
    }

    val diffDays = ((base.timeInMillis - nowDate.timeInMillis) / MILLIS_PER_DAY).toInt()
    if (parsed.year == null && kotlin.math.abs(diffDays) > 183) {
      val adjustedYear = if (diffDays > 0) nowYear - 1 else nowYear + 1
      base.set(Calendar.YEAR, adjustedYear)
    }

    return toMondayBasedWeekday(base)
  }

  private fun extractScheduleDate(raw: String): ParsedScheduleDate? {
    val s = raw.trim()
    if (s.isEmpty()) return null

    val normalized = s.replace('/', '-').replace('.', '-')
    val fullDate = Regex("""^(\d{4})-(\d{1,2})-(\d{1,2})$""").matchEntire(normalized)
    val monthDay = Regex("""^(\d{1,2})-(\d{1,2})$""").matchEntire(normalized)
    val year = fullDate?.groupValues?.get(1)?.toIntOrNull()
    val month =
      (fullDate?.groupValues?.get(2) ?: monthDay?.groupValues?.get(1))
        ?.toIntOrNull() ?: return null
    val day =
      (fullDate?.groupValues?.get(3) ?: monthDay?.groupValues?.get(2))
        ?.toIntOrNull() ?: return null

    val parsed = ParsedScheduleDate(year = year, month = month, day = day)
    val validationYear = year ?: 2000
    if (validationYear !in 1..9999) return null
    if (createScheduleCalendar(validationYear, month, day) == null) return null
    return parsed
  }

  private fun resolveScheduleDate(
    parsed: ParsedScheduleDate,
    reference: Calendar,
  ): Calendar? {
    parsed.year?.let { return createScheduleCalendar(it, parsed.month, parsed.day) }

    val referenceYear = reference.get(Calendar.YEAR)
    var candidate = createScheduleCalendar(referenceYear, parsed.month, parsed.day) ?: return null
    val referenceDay =
      createScheduleCalendar(
        referenceYear,
        reference.get(Calendar.MONTH) + 1,
        reference.get(Calendar.DAY_OF_MONTH),
      ) ?: return null
    val diffDays = (candidate.timeInMillis - referenceDay.timeInMillis) / MILLIS_PER_DAY
    if (kotlin.math.abs(diffDays) > 183L) {
      val adjustedYear = if (diffDays > 0L) referenceYear - 1 else referenceYear + 1
      candidate = createScheduleCalendar(adjustedYear, parsed.month, parsed.day) ?: return null
    }
    return candidate
  }

  private fun createScheduleCalendar(
    year: Int,
    month: Int,
    day: Int,
  ): Calendar? {
    if (year !in 1..9999 || month !in 1..12 || day !in 1..31) return null
    val calendar =
      Calendar.getInstance(WIDGET_TIME_ZONE).apply {
        isLenient = false
        clear()
        set(year, month - 1, day, 0, 0, 0)
        set(Calendar.MILLISECOND, 0)
      }
    return try {
      calendar.timeInMillis
      calendar
    } catch (_: IllegalArgumentException) {
      null
    }
  }

  private fun toMondayBasedWeekday(calendar: Calendar): Int {
    val dayOfWeek = calendar.get(Calendar.DAY_OF_WEEK)
    return (dayOfWeek + 5) % 7 + 1
  }

  private fun toChineseWeekday(mondayBased: Int): String {
    return when (mondayBased) {
      1 -> "一"
      2 -> "二"
      3 -> "三"
      4 -> "四"
      5 -> "五"
      6 -> "六"
      7 -> "日"
      else -> "一"
    }
  }

  private fun joinIntArray(arr: JSONArray): String {
    val sb = StringBuilder()
    for (i in 0 until arr.length()) {
      val v = arr.optInt(i, -1)
      if (v <= 0) continue
      if (sb.isNotEmpty()) sb.append(",")
      sb.append(v)
    }
    return sb.toString()
  }

  private fun minSessionStart(arr: JSONArray?): Int? {
    if (arr == null || arr.length() == 0) return null
    var min: Int? = null
    for (i in 0 until arr.length()) {
      val v = arr.optInt(i, -1)
      if (v <= 0) continue
      if (min == null || v < min) min = v
    }
    return min
  }

  private fun splitCampusAndClassroom(raw: String): Pair<String, String> {
    val s = raw.trim()
    if (s.isBlank()) return " " to " "

    val lines = s.split("\n").map { it.trim() }.filter { it.isNotBlank() }
    if (lines.size >= 2) {
      return lines[0] to lines[1]
    }

    val campusIdx = s.indexOf("校区")
    if (campusIdx >= 0) {
      val campus = s.substring(0, campusIdx + 2).trim().ifBlank { " " }
      val classroom =
        s.substring(campusIdx + 2)
          .trim()
          .trimStart(' ', '-', '—', '－', '·', '•', '：', ':')
          .ifBlank { " " }
      return campus to classroom
    }

    val wsParts = s.split(Regex("\\s+"), limit = 2)
    if (wsParts.size == 2) {
      val campus = wsParts[0].trim().ifBlank { " " }
      val classroom = wsParts[1].trim().ifBlank { " " }
      return campus to classroom
    }

    val splitChars = charArrayOf('-', '—', '－', '·', '•', '|', '/', '\\')
    for (i in 1 until s.length - 1) {
      if (splitChars.contains(s[i])) {
        val campus = s.substring(0, i).trim().ifBlank { " " }
        val classroom = s.substring(i + 1).trim().ifBlank { " " }
        return campus to classroom
      }
    }

    return " " to s.ifBlank { " " }
  }

  private fun loadCourseColorIndexMap(context: Context): Map<String, Int> {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val account = prefs.getString("${FLUTTER_PREFIX}account", null)?.trim().orEmpty().ifEmpty { ANONYMOUS_SCOPE }
    val term =
      prefs.getString("$KEY_WIDGET_TERM_PREFIX$account", null)?.takeIf { it.isNotBlank() }
        ?: prefs.getString("$KEY_LAST_TERM_PREFIX$account", null)?.takeIf { it.isNotBlank() }
        ?: return emptyMap()
    val raw = prefs.getString("$KEY_COURSE_COLOR_MAP_PREFIX$account|$term", null) ?: return emptyMap()
    return try {
      val obj = JSONObject(raw)
      val result = HashMap<String, Int>(obj.length())
      val keys = obj.keys()
      while (keys.hasNext()) {
        val key = keys.next()
        result[key] = obj.optInt(key, 0)
      }
      result
    } catch (_: Exception) {
      emptyMap()
    }
  }

  private fun buildCourseColorKey(eventName: String): String {
    val normalized = eventName.trim()
    return if (normalized.isEmpty()) "未命名课程" else normalized
  }

  private fun fallbackColorIndex(courseKey: String): Int {
    if (COURSE_TITLE_COLORS.isEmpty()) return 0
    return (courseKey.hashCode().ushr(1)) % COURSE_TITLE_COLORS.size
  }

  private fun colorByIndex(index: Int): Int {
    if (COURSE_TITLE_COLORS.isEmpty()) return 0xFF3F51B5.toInt()
    val safeIndex = ((index % COURSE_TITLE_COLORS.size) + COURSE_TITLE_COLORS.size) % COURSE_TITLE_COLORS.size
    return COURSE_TITLE_COLORS[safeIndex]
  }

  private fun filterEndedCourses(
    context: Context,
    schedule: JSONObject,
    courses: List<CourseItem>,
  ): List<CourseItem> {
    if (courses.isEmpty()) return courses
    val sessionClockMap = loadSessionClockMap(context)
    if (sessionClockMap.isEmpty()) return courses

    val todayWeekDay = toMondayBasedWeekday(widgetCalendar()).toString()
    val nowMinutes = currentMinuteOfDay()
    return filterEndedCoursesByClockMap(schedule, courses, sessionClockMap, todayWeekDay, nowMinutes)
  }

  internal fun filterEndedCoursesByClockMap(
    schedule: JSONObject,
    courses: List<CourseItem>,
    sessionClockMap: Map<Int, Pair<Int, Int>>,
    targetWeekDay: String,
    nowMinutes: Int,
  ): List<CourseItem> {
    if (courses.isEmpty()) return courses
    if (sessionClockMap.isEmpty()) return courses
    if (nowMinutes < 0) return courses

    val events = schedule.optJSONArray("eventList") ?: return courses
    val endedEventIds = HashSet<String>()
    val endedFallbackKeys = HashSet<String>()

    for (i in 0 until events.length()) {
      val event = events.optJSONObject(i) ?: continue
      if (event.optString("weekDay", "") != targetWeekDay) continue
      val eventId = event.optString("eventID", "").trim()
      val sessionNums = sessionNumbersOfEvent(event)
      val clockRange = sessionClockRange(sessionNums, sessionClockMap) ?: continue
      if (clockRange.second <= nowMinutes) {
        if (eventId.isNotEmpty()) {
          endedEventIds.add(eventId)
        } else {
          val fallbackKey = fallbackCourseKey(event, sessionNums)
          if (fallbackKey != null) endedFallbackKeys.add(fallbackKey)
        }
      }
    }
    if (endedEventIds.isEmpty() && endedFallbackKeys.isEmpty()) return courses
    return courses.filterNot { item ->
      val eventId = item.eventId?.trim().orEmpty()
      if (eventId.isNotEmpty()) {
        endedEventIds.contains(eventId)
      } else {
        val fallbackKey = fallbackCourseKey(item.name, item.periods)
        fallbackKey != null && endedFallbackKeys.contains(fallbackKey)
      }
    }
  }

  private fun fallbackCourseKey(event: JSONObject, sessionNums: List<Int>): String? {
    val name = event.optString("eventName", "").ifBlank { "课程" }
    val periods = periodsTextFromSessionNumbers(sessionNums) ?: return null
    return fallbackCourseKey(name, periods)
  }

  private fun fallbackCourseKey(name: String, periods: String): String? {
    val normalizedName = name.trim().ifBlank { "课程" }
    val normalizedPeriods = periods.trim()
    if (normalizedPeriods.isEmpty()) return null
    return "$normalizedName|$normalizedPeriods"
  }

  private fun periodsTextFromSessionNumbers(sessionNums: List<Int>): String? {
    if (sessionNums.isEmpty()) return null
    val nums = sessionNums.filter { it > 0 }.distinct().sorted()
    if (nums.isEmpty()) return null
    val isContinuous = nums.last() - nums.first() + 1 == nums.size
    return if (isContinuous && nums.size > 1) {
      "第${nums.first()}-${nums.last()}节"
    } else if (nums.size == 1) {
      "第${nums.first()}-${nums.first()}节"
    } else {
      "第${nums.joinToString(",")}节"
    }
  }

  private fun nextCourseBoundaryAtMillisToday(
    context: Context,
    nowMillis: Long,
  ): Long? {
    val nowCalendar = widgetCalendar(nowMillis)
    val data = loadScheduleJsonObjectForDate(context, nowCalendar) ?: return null
    val sessionClockMap = loadSessionClockMap(context)
    if (sessionClockMap.isEmpty()) return null

    val events = data.optJSONArray("eventList") ?: return null
    val todayWeekDay = toMondayBasedWeekday(nowCalendar).toString()
    val sessionGroups = ArrayList<List<Int>>()

    for (i in 0 until events.length()) {
      val event = events.optJSONObject(i) ?: continue
      if (event.optString("weekDay", "") != todayWeekDay) continue
      val sessionNums = sessionNumbersOfEvent(event)
      if (sessionNums.isNotEmpty()) sessionGroups.add(sessionNums)
    }
    val nextBoundaryMinute =
      nextCourseBoundaryMinuteOfDay(
        sessionGroups,
        sessionClockMap,
        currentMinuteOfDay(nowCalendar),
      ) ?: return null
    return minuteOfDayToMillis(nextBoundaryMinute, nowCalendar)
  }

  internal fun nextCourseBoundaryMinuteOfDay(
    sessionGroups: List<List<Int>>,
    sessionClockMap: Map<Int, Pair<Int, Int>>,
    nowMinutes: Int,
  ): Int? {
    if (sessionGroups.isEmpty() || sessionClockMap.isEmpty() || nowMinutes < 0) return null
    var best: Int? = null
    for (sessionNums in sessionGroups) {
      val range = sessionClockRange(sessionNums, sessionClockMap) ?: continue
      for (boundary in intArrayOf(range.first, range.second)) {
        if (boundary > nowMinutes && (best == null || boundary < best!!)) {
          best = boundary
        }
      }
    }
    return best
  }

  internal fun sessionClockRange(
    sessionNums: List<Int>,
    sessionClockMap: Map<Int, Pair<Int, Int>>,
  ): Pair<Int, Int>? {
    val normalized = sessionNums.filter { it > 0 }.distinct()
    if (normalized.isEmpty() || sessionClockMap.isEmpty()) return null
    var minStart: Int? = null
    var maxEnd: Int? = null
    for (sessionNum in normalized) {
      val clock = sessionClockMap[sessionNum] ?: return null
      if (clock.first !in 0 until 24 * 60 || clock.second < clock.first) return null
      if (minStart == null || clock.first < minStart!!) minStart = clock.first
      if (maxEnd == null || clock.second > maxEnd!!) maxEnd = clock.second
    }
    return minStart?.let { start -> maxEnd?.let { end -> start to end } }
  }

  private fun loadSessionClockMap(context: Context): Map<Int, Pair<Int, Int>> {
    val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
    val raw = prefs.getString(KEY_TIME_INFO_CACHE, null)
    if (raw.isNullOrBlank()) return emptyMap()
    return try {
      val decoded = JSONObject(raw)
      val items = decoded.optJSONArray("items") ?: return emptyMap()
      val result = HashMap<Int, Pair<Int, Int>>(items.length())
      for (i in 0 until items.length()) {
        val item = items.optJSONObject(i) ?: continue
        val sessionNum = item.optInt("sessionNum", -1)
        if (sessionNum <= 0) continue
        val start = parseTimeToMinute(item.optString("startTime", "")) ?: continue
        val endRaw = parseTimeToMinute(item.optString("endTime", "")) ?: continue
        val end = if (endRaw < start) endRaw + 24 * 60 else endRaw
        result[sessionNum] = start to end
      }
      result
    } catch (_: Exception) {
      emptyMap()
    }
  }

  private fun parseTimeToMinute(raw: String): Int? {
    val m = Regex("""(\d{1,2})\s*[:：]\s*(\d{1,2})""").find(raw.trim()) ?: return null
    val hour = m.groupValues[1].toIntOrNull() ?: return null
    val minute = m.groupValues[2].toIntOrNull() ?: return null
    if (hour !in 0..23 || minute !in 0..59) return null
    return hour * 60 + minute
  }

  private fun sessionNumbersOfEvent(event: JSONObject): List<Int> {
    val start = event.optInt("sessionStart", -1)
    val last = event.optInt("sessionLast", -1)
    if (start > 0 && last > 0) {
      val end = start + last - 1
      return (start..end).toList()
    }
    val arr = event.optJSONArray("sessionList") ?: return emptyList()
    val result = ArrayList<Int>(arr.length())
    for (i in 0 until arr.length()) {
      val n = arr.optInt(i, -1)
      if (n > 0) result.add(n)
    }
    return result
  }

  private fun currentMinuteOfDay(calendar: Calendar = widgetCalendar()): Int {
    return calendar.get(Calendar.HOUR_OF_DAY) * 60 + calendar.get(Calendar.MINUTE)
  }

  private fun minuteOfDayToMillis(
    minuteOfDay: Int,
    baseDate: Calendar,
  ): Long {
    val cal = (baseDate.clone() as Calendar).apply {
      set(Calendar.HOUR_OF_DAY, 0)
      set(Calendar.MINUTE, 0)
      set(Calendar.SECOND, 0)
      set(Calendar.MILLISECOND, 0)
      add(Calendar.MINUTE, minuteOfDay)
    }
    return cal.timeInMillis
  }

  internal fun nextDayRefreshAtMillis(nowMillis: Long): Long {
    val cal = widgetCalendar(nowMillis).apply {
      add(Calendar.DAY_OF_YEAR, 1)
      set(Calendar.HOUR_OF_DAY, 0)
      set(Calendar.MINUTE, 0)
      set(Calendar.SECOND, 0)
      set(Calendar.MILLISECOND, 0)
    }
    return cal.timeInMillis
  }
}
