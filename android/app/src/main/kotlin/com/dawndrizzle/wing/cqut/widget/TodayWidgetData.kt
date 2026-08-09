package com.dawndrizzle.wing.cqut.widget

import android.content.Context
import android.content.pm.ApplicationInfo
import android.text.format.DateUtils
import org.json.JSONArray
import org.json.JSONObject
import java.text.SimpleDateFormat
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

  private const val PREFS_NAME = "FlutterSharedPreferences"
  private const val FLUTTER_PREFIX = "flutter."
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
  private const val STALE_AFTER_MILLIS = 72L * 60 * 60 * 1000
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

  fun loadHeader(context: Context): Header {
    val calendar = Calendar.getInstance()
    val dateFormat = SimpleDateFormat("M.d", Locale.CHINA)
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
    val calendar = Calendar.getInstance()
    val dateFormat = SimpleDateFormat("M.d", Locale.CHINA)
    val targetCal = Calendar.getInstance().apply { add(Calendar.DAY_OF_YEAR, dayOffset) }
    val targetWeekDay = toMondayBasedWeekday(targetCal)

    val defaultDateText = dateFormat.format(targetCal.time)
    val defaultWeekText = "周${toChineseWeekday(targetWeekDay)}"

    return Header(
      scheduleName = "课表",
      dateText = defaultDateText,
      weekText = defaultWeekText,
    )
  }

  fun loadWeekCountText(context: Context): String {
    val data = loadScheduleJsonObject(context) ?: return ""
    if (!scheduleContainsSystemDate(data)) return ""
    val week = data.optString("weekNum", "")
    if (week.isBlank()) return ""
    return "第${week}周"
  }

  fun loadRefreshPresentation(context: Context): RefreshPresentation {
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

    // Keep manual refresh directly reachable while exercising widget behavior
    // from a debug build. Release builds continue to use the real sync age.
    val isDebuggable =
      context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0
    if (isDebuggable) {
      return RefreshPresentation(
        RefreshPresentationState.NEEDS_SYNC,
        "调试模式：点右上角刷新",
      )
    }

    val lastSuccessfulAt =
      prefs
        .getString("$KEY_LAST_SUCCESSFUL_REFRESH_AT_PREFIX$account", null)
        ?.let(::parseIso8601Millis)
        ?: migrateLegacyRefreshAt(context, prefs, account)
    val pollingEnabled = prefs.getBoolean(KEY_BACKGROUND_POLLING_ENABLED, false)
    if (!pollingEnabled && lastSuccessfulAt == null) {
      return RefreshPresentation(
        RefreshPresentationState.NEEDS_SYNC,
        "课表尚未同步",
      )
    }
    if (!pollingEnabled &&
      lastSuccessfulAt != null &&
      System.currentTimeMillis() - lastSuccessfulAt > STALE_AFTER_MILLIS
    ) {
      return RefreshPresentation(
        RefreshPresentationState.STALE,
        "课表可能已过期",
      )
    }
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
            .atZone(java.time.ZoneId.systemDefault())
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
        ).parse(normalized)?.time
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

  private fun formatLastUpdated(timestamp: Long): String {
    val now = Calendar.getInstance()
    val at = Calendar.getInstance().apply { timeInMillis = timestamp }
    val prefix =
      if (now.get(Calendar.YEAR) == at.get(Calendar.YEAR) &&
        now.get(Calendar.DAY_OF_YEAR) == at.get(Calendar.DAY_OF_YEAR)
      ) {
        "今天"
      } else {
        SimpleDateFormat("M.d ", Locale.CHINA).format(at.time)
      }
    return "$prefix${SimpleDateFormat("HH:mm", Locale.CHINA).format(at.time)}更新"
  }

  fun loadCoursesByDayOffset(context: Context, dayOffset: Int): List<CourseItem> {
    val data = loadScheduleJsonObject(context)
    if (data == null) return emptyList()
    if (!scheduleContainsSystemDate(data)) return emptyList()
    val baseWeekDay = toMondayBasedWeekday(Calendar.getInstance())

    val rawTarget = baseWeekDay + dayOffset
    var targetWeekDay = rawTarget
    var targetData = data

    if (rawTarget > 7 && dayOffset > 0) {
      targetWeekDay = rawTarget - 7
      targetData = loadNextWeekScheduleJsonObject(context) ?: return emptyList()
    } else if (rawTarget < 1 && dayOffset < 0) {
      targetWeekDay = rawTarget + 7
      targetData = loadPrevWeekScheduleJsonObject(context) ?: return emptyList()
    }
    val targetDate =
      Calendar.getInstance().apply {
        add(Calendar.DAY_OF_YEAR, dayOffset)
      }
    if (!scheduleContainsDate(targetData, targetDate)) return emptyList()

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
    val data =
      loadScheduleJsonObject(context) ?: return DayScheduleAvailability.MISSING_CACHE
    if (!scheduleContainsSystemDate(data)) {
      return DayScheduleAvailability.OUTSIDE_TEACHING_WEEK
    }
    val rawTarget = toMondayBasedWeekday(Calendar.getInstance()) + dayOffset
    val targetData =
      when {
        rawTarget > 7 && dayOffset > 0 ->
          loadNextWeekScheduleJsonObject(context)
            ?: return DayScheduleAvailability.MISSING_CACHE
        rawTarget < 1 && dayOffset < 0 ->
          loadPrevWeekScheduleJsonObject(context)
            ?: return DayScheduleAvailability.MISSING_CACHE
        else -> data
      }
    val targetDate =
      Calendar.getInstance().apply {
        add(Calendar.DAY_OF_YEAR, dayOffset)
      }
    return if (scheduleContainsDate(targetData, targetDate)) {
      DayScheduleAvailability.COVERED
    } else {
      DayScheduleAvailability.OUTSIDE_TEACHING_WEEK
    }
  }

  fun nextRefreshAtMillis(context: Context): Long? {
    val now = System.currentTimeMillis()
    val candidates = mutableListOf<Long>()
    candidates.add(nextDayRefreshAtMillis())
    val nextCourseStart = nextCourseStartAtMillisToday(context)
    if (nextCourseStart != null && nextCourseStart > now) {
      candidates.add(nextCourseStart)
    }
    return candidates.filter { it > now }.minOrNull()
  }

  private fun scheduleContainsSystemDate(data: JSONObject): Boolean {
    return scheduleContainsDate(data, Calendar.getInstance())
  }

  private fun scheduleContainsDate(data: JSONObject, targetDate: Calendar): Boolean {
    val weekDayList = data.optJSONArray("weekDayList")
    if (weekDayList == null || weekDayList.length() == 0) {
      val events = data.optJSONArray("eventList")
      return events != null && events.length() > 0
    }
    for (i in 0 until weekDayList.length()) {
      val d = weekDayList.optJSONObject(i) ?: continue
      val weekDate = d.optString("weekDate", "")
      if (d.optBoolean("today", false) &&
        isSameCalendarDate(targetDate, Calendar.getInstance())
      ) {
        return true
      }
      if (weekDate.isBlank()) return true
      if (isSameAsDate(weekDate, targetDate)) return true
    }
    return false
  }

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
    val data = loadScheduleJsonObject(context) ?: return emptyList()
    val todayWeekDay = toMondayBasedWeekday(Calendar.getInstance()).toString()

    return loadCoursesByWeekdayFromSchedule(context, data, todayWeekDay)
  }

  private data class TodayInfo(
    val weekDay: String,
    val dateText: String,
    val weekText: String,
  )

  private fun loadTodayWeekDayAndDate(context: Context): TodayInfo? {
    val data = loadScheduleJsonObject(context) ?: return null
    return loadTodayWeekDayAndDateFromSchedule(data)
  }

  private fun loadTodayWeekDayAndDateFromSchedule(data: JSONObject): TodayInfo? {
    val weekDayList = data.optJSONArray("weekDayList") ?: return null
    for (i in 0 until weekDayList.length()) {
      val d = weekDayList.optJSONObject(i) ?: continue
      if (!d.optBoolean("today", false)) continue

      val weekDay = d.optString("weekDay", "")
      val weekDate = d.optString("weekDate", "")
      if (weekDate.isNotBlank() && !isSameAsSystemDate(weekDate)) continue
      val computedWeekDay = mondayBasedWeekdayFromWeekDateText(weekDate)
      val weekText =
        when {
          computedWeekDay != null -> "周${toChineseWeekday(computedWeekDay)}"
          weekDay.isNotBlank() -> "周${toChineseWeekday(weekDay.toIntOrNull() ?: 1)}"
          else -> ""
        }

      val dateText =
        if (weekDate.isNotBlank()) {
          weekDate
        } else {
          ""
        }

      if (weekDay.isBlank() && dateText.isBlank()) return null
      val normalizedWeekDay =
        when {
          computedWeekDay != null -> computedWeekDay.toString()
          weekDay.isNotBlank() -> weekDay
          else -> ""
        }
      return TodayInfo(weekDay = normalizedWeekDay, dateText = dateText, weekText = weekText)
    }
    return null
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

  private fun isSameAsSystemDate(weekDateText: String): Boolean {
    return isSameAsDate(weekDateText, Calendar.getInstance())
  }

  private fun isSameAsDate(weekDateText: String, targetDate: Calendar): Boolean {
    val md = extractMonthDay(weekDateText) ?: return false
    val targetMonth = targetDate.get(Calendar.MONTH) + 1
    val targetDay = targetDate.get(Calendar.DAY_OF_MONTH)
    return md.first == targetMonth && md.second == targetDay
  }

  private fun isSameCalendarDate(first: Calendar, second: Calendar): Boolean {
    return first.get(Calendar.YEAR) == second.get(Calendar.YEAR) &&
      first.get(Calendar.DAY_OF_YEAR) == second.get(Calendar.DAY_OF_YEAR)
  }

  private fun mondayBasedWeekdayFromWeekDateText(weekDateText: String): Int? {
    val md = extractMonthDay(weekDateText) ?: return null
    val calNow = Calendar.getInstance()
    val nowYear = calNow.get(Calendar.YEAR)
    val nowMonth = calNow.get(Calendar.MONTH) + 1
    val nowDay = calNow.get(Calendar.DAY_OF_MONTH)

    val base = Calendar.getInstance().apply {
      set(Calendar.YEAR, nowYear)
      set(Calendar.MONTH, md.first - 1)
      set(Calendar.DAY_OF_MONTH, md.second)
      set(Calendar.HOUR_OF_DAY, 0)
      set(Calendar.MINUTE, 0)
      set(Calendar.SECOND, 0)
      set(Calendar.MILLISECOND, 0)
    }

    val nowDate = Calendar.getInstance().apply {
      set(Calendar.YEAR, nowYear)
      set(Calendar.MONTH, nowMonth - 1)
      set(Calendar.DAY_OF_MONTH, nowDay)
      set(Calendar.HOUR_OF_DAY, 0)
      set(Calendar.MINUTE, 0)
      set(Calendar.SECOND, 0)
      set(Calendar.MILLISECOND, 0)
    }

    val diffDays = ((base.timeInMillis - nowDate.timeInMillis) / (24L * 60 * 60 * 1000)).toInt()
    if (kotlin.math.abs(diffDays) > 183) {
      val adjustedYear = if (diffDays > 0) nowYear - 1 else nowYear + 1
      base.set(Calendar.YEAR, adjustedYear)
    }

    return toMondayBasedWeekday(base)
  }

  private fun extractMonthDay(raw: String): Pair<Int, Int>? {
    val s = raw.trim()
    if (s.isEmpty()) return null

    val nums = Regex("""\d{1,4}""").findAll(s).map { it.value }.toList()
    if (nums.size < 2) return null

    val month: Int
    val day: Int
    if (nums[0].length == 4 && nums.size >= 3) {
      month = nums[1].toIntOrNull() ?: return null
      day = nums[2].toIntOrNull() ?: return null
    } else {
      month = nums[0].toIntOrNull() ?: return null
      day = nums[1].toIntOrNull() ?: return null
    }

    if (month !in 1..12) return null
    if (day !in 1..31) return null
    return month to day
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

    val todayWeekDay = toMondayBasedWeekday(Calendar.getInstance()).toString()
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
      if (sessionNums.isEmpty()) continue
      var maxEndMinute: Int? = null
      var hasInvalidSession = false
      for (sessionNum in sessionNums) {
        val clock = sessionClockMap[sessionNum]
        if (clock == null) {
          hasInvalidSession = true
          break
        }
        if (maxEndMinute == null || clock.second > maxEndMinute!!) {
          maxEndMinute = clock.second
        }
      }
      if (hasInvalidSession || maxEndMinute == null) continue
      if (maxEndMinute <= nowMinutes) {
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

  private fun nextCourseStartAtMillisToday(context: Context): Long? {
    val data = loadScheduleJsonObject(context) ?: return null
    if (!scheduleContainsSystemDate(data)) return null
    val sessionClockMap = loadSessionClockMap(context)
    if (sessionClockMap.isEmpty()) return null

    val events = data.optJSONArray("eventList") ?: return null
    val todayWeekDay = toMondayBasedWeekday(Calendar.getInstance()).toString()
    val now = System.currentTimeMillis()
    var best: Long? = null

    for (i in 0 until events.length()) {
      val event = events.optJSONObject(i) ?: continue
      if (event.optString("weekDay", "") != todayWeekDay) continue
      val sessionNums = sessionNumbersOfEvent(event)
      if (sessionNums.isEmpty()) continue
      val minStartMinute =
        sessionNums
          .mapNotNull { sessionClockMap[it]?.first }
          .minOrNull() ?: continue
      val startAt = minuteOfDayToMillis(minStartMinute)
      if (startAt > now && (best == null || startAt < best!!)) {
        best = startAt
      }
    }
    return best
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

  private fun currentMinuteOfDay(): Int {
    val c = Calendar.getInstance()
    return c.get(Calendar.HOUR_OF_DAY) * 60 + c.get(Calendar.MINUTE)
  }

  private fun minuteOfDayToMillis(minuteOfDay: Int): Long {
    val cal = Calendar.getInstance().apply {
      set(Calendar.HOUR_OF_DAY, minuteOfDay / 60)
      set(Calendar.MINUTE, minuteOfDay % 60)
      set(Calendar.SECOND, 0)
      set(Calendar.MILLISECOND, 0)
    }
    return cal.timeInMillis
  }

  private fun nextDayRefreshAtMillis(): Long {
    val cal = Calendar.getInstance().apply {
      add(Calendar.DAY_OF_YEAR, 1)
      set(Calendar.HOUR_OF_DAY, 0)
      set(Calendar.MINUTE, 1)
      set(Calendar.SECOND, 0)
      set(Calendar.MILLISECOND, 0)
    }
    return cal.timeInMillis
  }
}
