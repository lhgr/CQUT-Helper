import Foundation

// Only consumes Flutter's resolved calendar projection. Academic-calendar rules live in Dart.
struct WidgetSnapshot: Decodable {
  let schemaVersion: Int
  let generatedAt: Double
  let activeUserId: String
  let yearTerm: String
  let pinnedWeek: Int?
  let calendarProjection: CalendarProjection?
  let sessionClocks: [SessionClock]
  let courseColorMap: [String: Int]
  let themeMode: String
  let refresh: Refresh

  struct Refresh: Decodable {
    let state: String
    let lastSuccessfulAt: Double?
    let failure: String?
  }
  struct CalendarProjection: Decodable {
    let schemaVersion: Int
    let days: [Day]
    enum CodingKeys: String, CodingKey { case schemaVersion = "schema_version", days }
  }
  struct Day: Decodable {
    let date: String
    let kind: String
    let label: String?
    let sourceWeek: String?
    let sourceDate: String?
    let events: [Event]
    enum CodingKeys: String, CodingKey {
      case date, kind, label, events
      case sourceWeek = "source_week_num"
      case sourceDate = "source_date"
    }
  }
  struct SessionClock: Decodable {
    let sessionNum: Int
    let startTime: String
    let endTime: String
  }
  struct Event: Decodable {
    let eventName: String?
    let eventID: String?
    let address: String?
    let memberName: String?
    let sessionStart: String?
    let sessionLast: String?
    let sessionList: [String]?
    let colorIndex: Int?

    var sessions: [Int] {
      if let start = sessionStart.flatMap(Int.init), let count = sessionLast.flatMap(Int.init),
        start > 0, count > 0, count <= 1440, start <= 1440 - count
      { return Array(start..<(start + count)) }
      return (sessionList ?? []).compactMap(Int.init).filter { $0 > 0 }
    }
    var name: String {
      let value = (eventName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      return value.isEmpty ? "课程" : value
    }
    var colorKey: String {
      let value = (eventName ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      return value.isEmpty ? "未命名课程" : value
    }
    var location: String {
      let value = (address ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
      let lines = value.components(separatedBy: .newlines)
        .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
      if lines.count >= 2 { return lines.prefix(2).joined(separator: " · ") }
      if let campus = value.range(of: "校区") {
        let first = String(value[..<campus.upperBound])
        let room = value[campus.upperBound...].trimmingCharacters(in: CharacterSet(charactersIn: " -—－·•：:"))
        return room.isEmpty ? first : "\(first) · \(room)"
      }
      return value
    }
    var periods: String {
      if let start = sessionStart.flatMap(Int.init), let count = sessionLast.flatMap(Int.init),
        start > 0, count > 0, count <= 1440, start <= 1440 - count
      { return "第\(start)-\(start + count - 1)节" }
      return sessions.isEmpty ? "" : "第\(sessions.map(String.init).joined(separator: ","))节"
    }
  }

  static func decode(_ data: Data) throws -> WidgetSnapshot {
    let snapshot = try JSONDecoder().decode(WidgetSnapshot.self, from: data)
    guard snapshot.schemaVersion == 1,
      snapshot.calendarProjection == nil || snapshot.calendarProjection?.schemaVersion == 1
    else { throw SnapshotError.unsupportedVersion }
    return snapshot
  }

  func day(_ date: Date) -> Day? {
    let key = WidgetClock.dateKey(date)
    return calendarProjection?.days.first { $0.date == key }
  }

  func course(_ event: Event) -> WidgetCourse {
    let numbers = Array(Set(event.sessions)).sorted()
    let clocks = numbers.map { number in sessionClocks.first { $0.sessionNum == number } }
    let start = numbers.first.flatMap { first in
      sessionClocks.first { $0.sessionNum == first }.flatMap { WidgetClock.minute($0.startTime) }
    }
    let ranges = clocks.compactMap { clock -> (Int, Int)? in
      guard let clock = clock, let from = WidgetClock.minute(clock.startTime),
        let rawEnd = WidgetClock.minute(clock.endTime) else { return nil }
      return (from, rawEnd < from ? rawEnd + 1440 : rawEnd)
    }
    let complete = !numbers.isEmpty && ranges.count == numbers.count
    let from = complete ? ranges.map { $0.0 }.min() : nil
    let to = complete ? ranges.map { $0.1 }.max() : nil
    return WidgetCourse(event: event, startMinute: start,
      startTime: from.map(WidgetClock.time) ?? "", endTime: to.map(WidgetClock.time) ?? "",
      colorIndex: event.colorIndex ?? courseColorMap[event.colorKey] ?? Self.fallbackColor(event.colorKey))
  }

  func courses(on date: Date, now: Date) -> [WidgetCourse] {
    guard !activeUserId.isEmpty, refresh.state != "credential_invalid",
      let day = day(date), day.kind != "holiday", day.kind != "missing_source" else { return [] }
    let today = WidgetClock.calendar.isDate(date, inSameDayAs: now)
    let minute = WidgetClock.calendar.component(.hour, from: now) * 60
      + WidgetClock.calendar.component(.minute, from: now)
    return day.events.map(course).filter { !today || ($0.startMinute.map { minute < $0 } ?? true) }
      .sorted {
        let left = $0.event.sessions.min() ?? Int.max
        let right = $1.event.sessions.min() ?? Int.max
        return left == right ? $0.event.periods < $1.event.periods : left < right
      }
  }

  func presentation(now: Date, suggestionDays: Int) -> WidgetPresentation {
    if activeUserId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      return .init(state: "login", text: "请打开应用登录")
    }
    switch refresh.state {
    case "credential_invalid": return .init(state: "login", text: "登录已失效，请打开应用")
    case "loading":
      if now.timeIntervalSince1970 >= generatedAt / 1000 + 300 {
        return .init(state: "unconfirmed", text: "更新状态待确认，请打开应用")
      }
      return .init(state: "loading", text: "正在更新课表…")
    case "failed": return .init(state: "failed", text: "更新失败，请打开应用重试")
    default: break
    }
    if refresh.state == "needs_sync" || calendarProjection == nil {
      return .init(state: "needs_sync", text: "课表尚未同步，请打开应用")
    }
    if let at = refresh.lastSuccessfulAt,
      now.timeIntervalSince1970 * 1000 - at >= Double(WidgetOptions.normalizeDays(suggestionDays)) * 86400000
    { return .init(state: "stale", text: "课表可能已过期") }
    return .init(state: "normal", text: "")
  }

  func emptyText(on date: Date, now: Date) -> String {
    if let day = day(date) {
      if day.kind == "missing_source" { return "补课课表加载失败" }
      if day.kind == "holiday" {
        return (day.label ?? "").isEmpty ? "今日放假" : "今日放假 · \(day.label!)"
      }
      if WidgetClock.calendar.isDate(date, inSameDayAs: now) {
        return day.events.isEmpty ? "今天没有课程" : "今日无待上课程"
      }
      return "明天没有课程"
    }
    return calendarProjection == nil ? "课表尚未同步" : "该日期课表未获取"
  }

  // Java String.hashCode operates on UTF-16 code units, including surrogate pairs.
  static func fallbackColor(_ name: String) -> Int {
    let hash = name.utf16.reduce(Int32(0)) { ($0 &* 31) &+ Int32($1) }
    return Int(UInt32(bitPattern: hash) & 0x7fffffff) % 21
  }
}

struct WidgetCourse {
  let event: WidgetSnapshot.Event
  let startMinute: Int?
  let startTime: String
  let endTime: String
  let colorIndex: Int
}

struct WidgetPresentation {
  let state: String
  let text: String
}

enum SnapshotError: LocalizedError {
  case missingGroup, missingSnapshot, unsupportedVersion
  var errorDescription: String? {
    switch self {
    case .missingGroup: return "小组件暂不可用，请检查安装是否完整"
    case .missingSnapshot: return "请打开应用同步课表"
    case .unsupportedVersion: return "课表数据版本不支持，请打开应用同步"
    }
  }
}

enum WidgetSnapshotStore {
  static var groupIdentifier: String {
    Bundle.main.object(forInfoDictionaryKey: "CQUTWidgetAppGroup") as? String
      ?? "group.com.dawndrizzle.wing.cqut"
  }
  static func container() throws -> URL {
    guard let url = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: groupIdentifier)
    else { throw SnapshotError.missingGroup }
    return url
  }
  static func load() throws -> WidgetSnapshot {
    let file = try container().appendingPathComponent("widget_snapshot.json")
    guard FileManager.default.fileExists(atPath: file.path) else { throw SnapshotError.missingSnapshot }
    return try WidgetSnapshot.decode(Data(contentsOf: file))
  }
  static func write(_ json: String) throws {
    let data = Data(json.utf8)
    _ = try WidgetSnapshot.decode(data)
    try data.write(to: container().appendingPathComponent("widget_snapshot.json"), options: .atomic)
  }
}

enum WidgetClock {
  static var calendar: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Asia/Shanghai")!
    return calendar
  }
  static func dateKey(_ date: Date) -> String { format(date, "yyyy-MM-dd") }
  static func format(_ date: Date, _ pattern: String) -> String {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "zh_CN")
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = pattern
    return formatter.string(from: date)
  }
  static func parseDate(_ value: String) -> Date? {
    let formatter = DateFormatter()
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.calendar = calendar
    formatter.timeZone = calendar.timeZone
    formatter.dateFormat = "yyyy-MM-dd"
    formatter.isLenient = false
    guard let date = formatter.date(from: value), dateKey(date) == value else { return nil }
    return date
  }
  static func minute(_ value: String) -> Int? {
    let pattern = #"(\d{1,2})\s*[:：]\s*(\d{1,2})"#
    guard let regex = try? NSRegularExpression(pattern: pattern),
      let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)),
      let hours = Range(match.range(at: 1), in: value), let minutes = Range(match.range(at: 2), in: value),
      let hour = Int(value[hours]), let minute = Int(value[minutes]), hour < 24, minute < 60
    else { return nil }
    return hour * 60 + minute
  }
  static func time(_ minute: Int) -> String {
    String(format: "%02d:%02d", (minute % 1440) / 60, minute % 60)
  }
  static func day(_ now: Date, offset: Int) -> Date {
    calendar.date(byAdding: .day, value: offset, to: calendar.startOfDay(for: now))!
  }
  static func timelineDates(snapshot: WidgetSnapshot?, now: Date, suggestionDays: Int) -> [Date] {
    let end = now.addingTimeInterval(48 * 3600)
    var dates: Set<Date> = [now, end]
    for offset in 1...3 {
      let midnight = day(now, offset: offset)
      if midnight <= end { dates.insert(midnight) }
    }
    for day in snapshot?.calendarProjection?.days ?? [] where day.kind != "holiday" && day.kind != "missing_source" {
      guard let date = parseDate(day.date) else { continue }
      for event in day.events {
        guard let start = snapshot?.course(event).startMinute,
          let boundary = calendar.date(byAdding: .minute, value: start, to: date),
          boundary > now, boundary <= end else { continue }
        dates.insert(boundary)
      }
    }
    if let at = snapshot?.refresh.lastSuccessfulAt {
      let stale = Date(timeIntervalSince1970: at / 1000 + Double(WidgetOptions.normalizeDays(suggestionDays)) * 86400)
      if stale > now && stale <= end { dates.insert(stale) }
    }
    if let snapshot = snapshot, snapshot.refresh.state == "loading" {
      let expires = Date(timeIntervalSince1970: snapshot.generatedAt / 1000 + 300)
      if expires > now && expires <= end { dates.insert(expires) }
    }
    return dates.sorted()
  }
}

enum WidgetCourseLayout {
  static func capacity(contentHeight: Double, rowHeight: Double, courseCount: Int) -> Int {
    let room = Int(max(0, contentHeight + 6) / (rowHeight + 6))
    if courseCount <= room { return courseCount }
    // The denominator includes each row's 6-point spacing before the 14-point overflow label.
    return min(courseCount, Int(max(0, contentHeight - 14) / (rowHeight + 6)))
  }
}

struct WidgetOptions: Equatable {
  let dayOffset: Int
  let theme: String
  let refreshSuggestionDays: Int
  init(dayOffset: Int = 0, theme: String = "app", refreshSuggestionDays: Int = 3) {
    self.dayOffset = dayOffset == 1 ? 1 : 0
    self.theme = ["light", "dark"].contains(theme) ? theme : "app"
    self.refreshSuggestionDays = Self.normalizeDays(refreshSuggestionDays)
  }
  static func normalizeDays(_ value: Int) -> Int { value > 0 ? value : 3 }
  func toggleKey(kind: String) -> String {
    "widget-day|\(kind)|\(dayOffset)|\(theme)|\(refreshSuggestionDays)"
  }
}

enum WidgetDaySelection {
  static func effectiveOffset(kind: String, options: WidgetOptions, defaults: UserDefaults?) -> Int {
    guard let defaults = defaults, defaults.object(forKey: options.toggleKey(kind: kind)) != nil else {
      return options.dayOffset
    }
    return defaults.integer(forKey: options.toggleKey(kind: kind)) == 1 ? 1 : 0
  }
  static func toggle(kind: String, options: WidgetOptions, defaults: UserDefaults?) {
    let next = 1 - effectiveOffset(kind: kind, options: options, defaults: defaults)
    defaults?.set(next, forKey: options.toggleKey(kind: kind))
  }
}
