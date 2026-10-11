package com.dawndrizzle.wing.cqut.widgetbridge

import android.app.AlarmManager
import android.app.AutomaticZenRule
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioManager
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import android.service.notification.Condition
import org.json.JSONArray
import org.json.JSONObject
import java.util.UUID

/** All entry points share this monitor; snapshots are committed before alarms or OS changes. */
internal object CourseAutoMode {
  private const val PREFERENCES = "cqut_course_auto_mode"
  private const val SNAPSHOT = "snapshot"
  private const val ALARM_ACTION = "com.dawndrizzle.wing.cqut.COURSE_MODE_BOUNDARY"
  private const val CLEANUP_ACTION = "com.dawndrizzle.wing.cqut.COURSE_MODE_CLEANUP"
  private const val RULE_STATUS_ACTION = "android.app.action.AUTOMATIC_ZEN_RULE_STATUS_CHANGED"
  private const val RINGER_ACTION = "android.media.RINGER_MODE_CHANGED"
  private var listening = false

  private data class State(
    var mode: String = "off",
    var intervals: List<CourseModeInterval> = emptyList(),
    var windowMode: String? = null,
    var window: CourseModeInterval? = null,
    var windowToken: String? = null,
    var controlled: Boolean = false,
    var applying: Boolean = false,
    var manual: Boolean = false,
    var previous: Int? = null,
    var applied: Int? = null,
    var ruleId: String? = null,
    var ruleResetPending: Boolean = false,
    var pendingFilterPrevious: Int? = null,
    var pendingFilterApplied: Int? = null,
    var status: String? = null,
  )

  @Synchronized
  fun initialize(context: Context) {
    if (!listening) {
      val filter = IntentFilter().apply {
        addAction(RINGER_ACTION)
        addAction(NotificationManager.ACTION_INTERRUPTION_FILTER_CHANGED)
        addAction(NotificationManager.ACTION_NOTIFICATION_POLICY_ACCESS_GRANTED_CHANGED)
        addAction(RULE_STATUS_ACTION)
      }
      if (Build.VERSION.SDK_INT >= 33) context.applicationContext.registerReceiver(CourseAutoModeReceiver(), filter, Context.RECEIVER_EXPORTED)
      else context.applicationContext.registerReceiver(CourseAutoModeReceiver(), filter)
      listening = true
    }
    reconcile(context, read(context))
  }

  @Synchronized
  fun replace(context: Context, mode: String, rawIntervals: List<CourseModeInterval>) {
    require(mode in setOf("off", "dnd", "silent")) { "Invalid auto mode" }
    val state = read(context)
    state.mode = mode
    state.intervals = if (mode == "off") emptyList() else CourseAutoModePolicy.merge(rawIntervals)
    write(context, state)
    reconcile(context, state, throwOnError = true)
  }

  @Synchronized
  fun cancel(context: Context) {
    val state = read(context)
    state.mode = "off"
    state.intervals = emptyList()
    write(context, state)
    reconcile(context, state, throwOnError = true)
  }

  @Synchronized
  fun receive(context: Context, intent: Intent) {
    val state = read(context)
    if (intent.action == CLEANUP_ACTION) {
      cleanup(context, state, intent)
      return
    }
    if (intent.action == Intent.ACTION_BOOT_COMPLETED) {
      val now = System.currentTimeMillis()
      val current = CourseAutoModePolicy.current(state.intervals, now)
      if (exactGranted(context) && notifications(context).isNotificationPolicyAccessGranted &&
        CourseAutoModePolicy.reapplyAfterBoot(state.controlled, state.manual, state.windowMode, state.mode, state.window, current, now)) {
        // A reboot resets device state. Reapply the same window without recapturing its original
        // state; a previously observed user override remains authoritative across reboot.
        reapplyAfterBoot(context, state)
      }
    }
    if (intent.action == RULE_STATUS_ACTION && intent.getStringExtra("android.app.extra.AUTOMATIC_ZEN_RULE_ID") == state.ruleId) {
      // API 35+ explicitly reports snooze. Older releases protect overrides in the system rule.
      if (intent.getIntExtra("android.app.extra.AUTOMATIC_ZEN_RULE_STATUS", -1) in setOf(2, 3, 4, 5) && state.controlled) {
        state.manual = true
        write(context, state)
      }
    }
    if (intent.action == RINGER_ACTION && state.windowMode == "silent" && state.controlled &&
      audio(context).ringerMode != state.applied) {
      state.manual = true
      write(context, state)
    }
    reconcile(context, state)
  }

  private fun cleanup(context: Context, state: State, intent: Intent) {
    if (!CourseAutoModePolicy.cleanupDue(state.controlled, state.windowToken, intent.getStringExtra("windowToken"),
      state.window, intent.getLongExtra("windowEnd", Long.MIN_VALUE), System.currentTimeMillis())) return
    // This is deliberately restoration-only: missing exact access must never start another
    // course or install a replacement automatic plan from this delayed cleanup alarm.
    observeManual(context, state)
    try {
      restore(context, state)
      clearWindow(context, state)
      state.status = when {
        state.mode == "off" -> null
        !notifications(context).isNotificationPolicyAccessGranted -> "未生效：需要勿扰权限"
        !exactGranted(context) -> "未生效：需要精确闹钟权限"
        else -> "等待上课"
      }
      write(context, state)
    } catch (error: Exception) {
      // Policy revocation can prevent ringer restoration. Retain ownership for regrant.
      state.status = "未生效：需要勿扰权限"
      write(context, state)
      record(context, "cleanup_restore", error)
    }
  }

  private fun reapplyAfterBoot(context: Context, state: State) {
    state.applying = true
    write(context, state)
    when {
      state.windowMode == "silent" -> {
        audio(context).ringerMode = AudioManager.RINGER_MODE_SILENT
        check(audio(context).ringerMode == AudioManager.RINGER_MODE_SILENT) { "Device did not apply silent mode after boot" }
      }
      Build.VERSION.SDK_INT >= 29 -> {
        val manager = notifications(context)
        val rule = state.ruleId?.let { manager.getAutomaticZenRule(it) }
        if (rule == null || !rule.isEnabled) state.manual = true
        else manager.setAutomaticZenRuleState(state.ruleId!!, condition(context, Condition.STATE_TRUE))
      }
      else -> notifications(context).setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)
    }
    state.applying = false
    write(context, state)
  }

  @Synchronized
  fun status(context: Context): Map<String, Any?> {
    val state = read(context)
    reconcile(context, state)
    val notifications = notifications(context)
    return mapOf(
      "supported" to true,
      "notificationGranted" to notifications.areNotificationsEnabled(),
      "exactAlarmGranted" to exactGranted(context),
      "dndGranted" to notifications.isNotificationPolicyAccessGranted,
      "batteryOptimizationIgnored" to context.getSystemService(PowerManager::class.java).isIgnoringBatteryOptimizations(context.packageName),
      "autoModeActive" to (state.controlled && !state.applying && !state.manual && exactGranted(context) &&
        notifications.isNotificationPolicyAccessGranted && currentlyApplied(context, state)),
      "autoModeStatus" to state.status,
    )
  }

  fun openSettings(context: Context, kind: String): Boolean {
    val packageUri = Uri.parse("package:${context.packageName}")
    val intent = when (kind) {
      "notifications" -> if (Build.VERSION.SDK_INT >= 26) Intent(Settings.ACTION_APP_NOTIFICATION_SETTINGS).putExtra(Settings.EXTRA_APP_PACKAGE, context.packageName)
        else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri)
      "exactAlarm" -> if (Build.VERSION.SDK_INT >= 31) Intent(Settings.ACTION_REQUEST_SCHEDULE_EXACT_ALARM, packageUri)
        else Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri)
      "dnd" -> Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
      "appDetails" -> Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, packageUri)
      else -> return false
    }
    return try { context.startActivity(intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)); true }
    catch (error: Exception) { record(context, "open_settings_$kind", error); false }
  }

  private fun reconcile(context: Context, state: State, throwOnError: Boolean = false) {
    cancelAlarm(context)
    val now = System.currentTimeMillis()
    val window = if (state.mode == "off") null else CourseAutoModePolicy.current(state.intervals, now)
    val permitted = exactGranted(context) && notifications(context).isNotificationPolicyAccessGranted
    try {
      restorePendingFilter(context, state)
      if (state.ruleResetPending && Build.VERSION.SDK_INT >= 29 && notifications(context).isNotificationPolicyAccessGranted) {
        state.ruleId?.let { notifications(context).setAutomaticZenRuleState(it, condition(context, Condition.STATE_FALSE)) }
        state.ruleResetPending = false
        write(context, state)
      }
      observeManual(context, state)
      val preserve = permitted && !state.applying && CourseAutoModePolicy.preserveWindow(state.windowMode, state.mode, state.window, window, now)
      if (!preserve) {
        restore(context, state)
        clearWindow(context, state)
      }
      when {
        state.mode == "off" -> state.status = null
        !exactGranted(context) -> state.status = "未生效：需要精确闹钟权限"
        !notifications(context).isNotificationPolicyAccessGranted -> state.status = "未生效：需要勿扰权限"
        window == null -> state.status = "等待上课"
        preserve -> {
          state.window = window
          state.status = if (state.manual) "本时段已手动调整" else "上课期间已${if (state.mode == "dnd") "开启勿扰" else "静音"}"
        }
        else -> activate(context, state, window)
      }
      write(context, state)
      if (state.controlled) state.window?.let { scheduleCleanup(context, state, it.endMillis) }
      if (state.mode != "off" && permitted) CourseAutoModePolicy.nextBoundary(state.intervals, now)?.let { schedule(context, it) }
    } catch (error: Exception) {
      // If applying a setting or scheduling its end failed, roll back immediately. If rollback
      // itself fails, retain the captured ownership so the next entry point can retry it.
      state.applying = true
      try {
        restore(context, state)
        clearWindow(context, state)
      } catch (restoreError: Exception) {
        record(context, "rollback_${state.mode}", restoreError)
      }
      state.status = when {
        !notifications(context).isNotificationPolicyAccessGranted -> "未生效：需要勿扰权限"
        !exactGranted(context) -> "未生效：需要精确闹钟权限"
        else -> "未生效：系统设置失败"
      }
      write(context, state)
      record(context, "reconcile_${state.mode}", error)
      if (throwOnError) throw error
    }
  }

  private fun activate(context: Context, state: State, window: CourseModeInterval) {
    state.window = window
    state.windowToken = UUID.randomUUID().toString()
    state.windowMode = state.mode
    state.manual = false
    when {
      state.mode == "silent" -> {
        state.previous = audio(context).ringerMode
        state.applied = AudioManager.RINGER_MODE_SILENT
        state.controlled = true
        state.applying = true
        write(context, state)
        audio(context).ringerMode = AudioManager.RINGER_MODE_SILENT
        check(audio(context).ringerMode == AudioManager.RINGER_MODE_SILENT) { "Device did not apply silent mode" }
      }
      Build.VERSION.SDK_INT >= 29 -> {
        val manager = notifications(context)
        var ruleId = state.ruleId
        val existing = ruleId?.let { manager.getAutomaticZenRule(it) }
        if (existing != null && !existing.isEnabled) {
          state.manual = true
          state.status = "未生效：课程勿扰规则已停用"
          return
        }
        if (existing == null) {
          val activity = context.packageManager.getLaunchIntentForPackage(context.packageName)?.component
            ?: throw IllegalStateException("App launch component unavailable")
          ruleId = manager.addAutomaticZenRule(AutomaticZenRule(
            "课程自动勿扰", null, activity, conditionUri(context), null,
            NotificationManager.INTERRUPTION_FILTER_PRIORITY, true,
          )) ?: throw IllegalStateException("Cannot create course DND rule")
          state.ruleId = ruleId
        }
        state.controlled = true
        state.applying = true
        write(context, state)
        manager.setAutomaticZenRuleState(ruleId!!, condition(context, Condition.STATE_TRUE))
      }
      else -> {
        state.previous = notifications(context).currentInterruptionFilter
        state.applied = NotificationManager.INTERRUPTION_FILTER_PRIORITY
        state.controlled = true
        state.applying = true
        write(context, state)
        notifications(context).setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_PRIORITY)
      }
    }
    state.applying = false
    state.status = "上课期间已${if (state.mode == "dnd") "开启勿扰" else "静音"}"
  }

  private fun observeManual(context: Context, state: State) {
    if (!state.controlled || state.applying || state.manual) return
    val changed = when {
      state.windowMode == "silent" -> audio(context).ringerMode != state.applied
      Build.VERSION.SDK_INT >= 29 && notifications(context).isNotificationPolicyAccessGranted -> {
        val manager = notifications(context)
        val rule = state.ruleId?.let { manager.getAutomaticZenRule(it) }
        rule == null || !rule.isEnabled || (Build.VERSION.SDK_INT >= 35 && manager.getAutomaticZenRuleState(state.ruleId!!) == Condition.STATE_FALSE)
      }
      state.windowMode == "dnd" && Build.VERSION.SDK_INT < 29 -> notifications(context).currentInterruptionFilter != state.applied
      else -> false
    }
    if (changed) { state.manual = true; write(context, state) }
  }

  private fun restore(context: Context, state: State) {
    if (!state.controlled) return
    when {
      state.windowMode == "silent" -> {
        val actual = audio(context).ringerMode
        if (CourseAutoModePolicy.canRestore(state.controlled, state.manual, state.previous, state.applied, actual)) audio(context).ringerMode = state.previous!!
      }
      state.windowMode == "dnd" && Build.VERSION.SDK_INT >= 29 -> {
        // FALSE ends only our rule, and also clears snooze for its next natural cycle.
        if (notifications(context).isNotificationPolicyAccessGranted) state.ruleId?.let {
          notifications(context).setAutomaticZenRuleState(it, condition(context, Condition.STATE_FALSE))
        } else if (state.ruleId != null) {
          // Reset after access is granted again, including when the schedule was cancelled.
          state.ruleResetPending = true
        }
      }
      state.windowMode == "dnd" -> {
        val actual = notifications(context).currentInterruptionFilter
        if (CourseAutoModePolicy.canRestore(state.controlled, state.manual, state.previous, state.applied, actual)) {
          if (notifications(context).isNotificationPolicyAccessGranted) notifications(context).setInterruptionFilter(state.previous!!)
          else {
            // API 24–28 controls the global filter. Keep its ownership across revoked access,
            // independently of the course window, so cancellation can finish after regrant.
            state.pendingFilterPrevious = state.previous
            state.pendingFilterApplied = state.applied
          }
        }
      }
    }
  }

  private fun restorePendingFilter(context: Context, state: State) {
    if (Build.VERSION.SDK_INT >= 29 || state.pendingFilterPrevious == null) return
    val manager = notifications(context)
    when (CourseAutoModePolicy.pendingFilterAction(state.pendingFilterPrevious, state.pendingFilterApplied,
      manager.currentInterruptionFilter, manager.isNotificationPolicyAccessGranted)) {
      CourseAutoModePolicy.PendingFilterAction.WAIT -> return
      CourseAutoModePolicy.PendingFilterAction.RESTORE -> manager.setInterruptionFilter(state.pendingFilterPrevious!!)
      CourseAutoModePolicy.PendingFilterAction.DISCARD -> Unit
    }
    state.pendingFilterPrevious = null
    state.pendingFilterApplied = null
    write(context, state)
  }

  private fun clearWindow(context: Context, state: State) {
    cancelCleanup(context)
    state.window = null
    state.windowToken = null
    state.windowMode = null
    state.controlled = false
    state.applying = false
    state.manual = false
    state.previous = null
    state.applied = null
  }

  private fun currentlyApplied(context: Context, state: State): Boolean = when {
    state.windowMode == "silent" -> audio(context).ringerMode == state.applied
    state.windowMode == "dnd" && Build.VERSION.SDK_INT >= 35 -> state.ruleId?.let {
      notifications(context).getAutomaticZenRuleState(it) == Condition.STATE_TRUE
    } ?: false
    state.windowMode == "dnd" -> notifications(context).currentInterruptionFilter != NotificationManager.INTERRUPTION_FILTER_ALL
    else -> false
  }

  private fun notifications(context: Context) = context.getSystemService(NotificationManager::class.java)
  private fun audio(context: Context) = context.getSystemService(AudioManager::class.java)
  private fun exactGranted(context: Context) = Build.VERSION.SDK_INT < 31 || context.getSystemService(AlarmManager::class.java).canScheduleExactAlarms()
  private fun conditionUri(context: Context) = Uri.parse("condition://${context.packageName}/course_auto_mode")
  private fun condition(context: Context, value: Int) = Condition(conditionUri(context), "课程自动勿扰", value)
  private fun alarmIntent(context: Context) = PendingIntent.getBroadcast(context, 67031,
    Intent(context, CourseAutoModeReceiver::class.java).setAction(ALARM_ACTION), PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
  private fun cancelAlarm(context: Context) { context.getSystemService(AlarmManager::class.java).cancel(alarmIntent(context)) }
  private fun schedule(context: Context, boundary: Long) {
    context.getSystemService(AlarmManager::class.java).setExactAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, boundary, alarmIntent(context))
  }
  private fun cleanupIntent(context: Context, state: State? = null, end: Long = 0L) = PendingIntent.getBroadcast(context, 67032,
    Intent(context, CourseAutoModeReceiver::class.java).setAction(CLEANUP_ACTION)
      .putExtra("windowToken", state?.windowToken).putExtra("windowEnd", end),
    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE)
  private fun cancelCleanup(context: Context) { context.getSystemService(AlarmManager::class.java).cancel(cleanupIntent(context)) }
  private fun scheduleCleanup(context: Context, state: State, end: Long) {
    // Distinct identity survives SCHEDULE_EXACT_ALARM revocation, which removes exact alarms.
    // Reusing it replaces an earlier end when the active window is rebuilt.
    context.getSystemService(AlarmManager::class.java).setAndAllowWhileIdle(AlarmManager.RTC_WAKEUP, end, cleanupIntent(context, state, end))
  }

  private fun read(context: Context): State {
    val raw = context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).getString(SNAPSHOT, null) ?: return State()
    val json = JSONObject(raw)
    val intervals = json.optJSONArray("intervals") ?: JSONArray()
    return State(
      mode = json.optString("mode", "off"),
      intervals = (0 until intervals.length()).map { val interval = intervals.getJSONObject(it); CourseModeInterval(interval.getLong("start"), interval.getLong("end")) },
      windowMode = json.optString("windowMode").takeIf { it.isNotEmpty() },
      window = if (json.has("windowStart")) CourseModeInterval(json.getLong("windowStart"), json.getLong("windowEnd")) else null,
      windowToken = json.optString("windowToken").takeIf { it.isNotEmpty() },
      controlled = json.optBoolean("controlled"), applying = json.optBoolean("applying"), manual = json.optBoolean("manual"),
      previous = if (json.has("previous")) json.getInt("previous") else null,
      applied = if (json.has("applied")) json.getInt("applied") else null,
      ruleId = json.optString("ruleId").takeIf { it.isNotEmpty() },
      ruleResetPending = json.optBoolean("ruleResetPending"),
      pendingFilterPrevious = if (json.has("pendingFilterPrevious")) json.getInt("pendingFilterPrevious") else null,
      pendingFilterApplied = if (json.has("pendingFilterApplied")) json.getInt("pendingFilterApplied") else null,
      status = json.optString("status").takeIf { it.isNotEmpty() },
    )
  }

  private fun write(context: Context, state: State) {
    val json = JSONObject().put("mode", state.mode).put("intervals", JSONArray(state.intervals.map {
      JSONObject().put("start", it.startMillis).put("end", it.endMillis)
    })).put("windowMode", state.windowMode).put("controlled", state.controlled).put("applying", state.applying).put("manual", state.manual)
      .put("windowToken", state.windowToken)
      .put("previous", state.previous).put("applied", state.applied).put("ruleId", state.ruleId).put("ruleResetPending", state.ruleResetPending).put("status", state.status)
      .put("pendingFilterPrevious", state.pendingFilterPrevious).put("pendingFilterApplied", state.pendingFilterApplied)
    state.window?.let { json.put("windowStart", it.startMillis).put("windowEnd", it.endMillis) }
    check(context.getSharedPreferences(PREFERENCES, Context.MODE_PRIVATE).edit().putString(SNAPSHOT, json.toString()).commit()) { "Cannot persist auto mode state" }
  }

  private fun record(context: Context, operation: String, error: Exception) {
    CqutDiagnostics.record(context, "error", "CourseAutoMode", "event=$operation", error)
  }
}

class CourseAutoModeReceiver : BroadcastReceiver() {
  override fun onReceive(context: Context, intent: Intent) {
    try { CourseAutoMode.receive(context.applicationContext, intent) }
    catch (error: Exception) { CqutDiagnostics.record(context, "error", "CourseAutoMode", "event=receiver action=${intent.action}", error) }
  }
}
