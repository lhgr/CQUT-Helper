import XCTest
@testable import Runner

final class WidgetSnapshotTests: XCTestCase {
  private func snapshot(state: String = "normal", user: String = "student",
    lastSuccessfulAt: Double? = nil, kind: String = "normal",
    events: [[String: Any]] = [], clocks: [[String: Any]] = [], schema: Int = 1,
    generatedAt: Double? = nil, label: String = "", exams: [[String: Any]] = [], projectionPresent: Bool = true
  ) throws -> WidgetSnapshot {
    var json: [String: Any] = [
      "schemaVersion": schema,
      "generatedAt": generatedAt ?? WidgetClock.parseDate("2026-11-05")!.timeIntervalSince1970 * 1000,
      "activeUserId": user,
      "yearTerm": "2026-2027-1", "pinnedWeek": 1,
      "calendarProjection": ["schema_version": 1, "days": [
        ["date": "2026-11-05", "kind": kind, "label": label, "events": events]
      ]],
      "sessionClocks": clocks, "courseColorMap": ["高等数学": 7], "themeMode": "system",
      "exams": exams, "examRefresh": ["state": "normal", "lastSuccessfulAt": NSNull()],
      "refresh": ["state": state, "lastSuccessfulAt": lastSuccessfulAt.map { $0 as Any } ?? NSNull(),
        "failure": NSNull()]
    ]
    if !projectionPresent { json.removeValue(forKey: "calendarProjection") }
    return try WidgetSnapshot.decode(JSONSerialization.data(withJSONObject: json))
  }

  func testSnapshotVersionAndRefreshStates() throws {
    let now = WidgetClock.parseDate("2026-11-05")!
    XCTAssertThrowsError(try snapshot(schema: 2))
    XCTAssertEqual(try snapshot(user: "").presentation(now: now, suggestionDays: 3).state, "login")
    XCTAssertEqual(try snapshot(state: "credential_invalid").presentation(now: now, suggestionDays: 3).state, "login")
    XCTAssertEqual(try snapshot(state: "loading").presentation(now: now, suggestionDays: 3).state, "loading")
    XCTAssertEqual(try snapshot(state: "failed").presentation(now: now, suggestionDays: 3).state, "failed")
    XCTAssertEqual(try snapshot(state: "needs_sync").presentation(now: now, suggestionDays: 3).state, "needs_sync")
    let successful = now.addingTimeInterval(-3 * 86400).timeIntervalSince1970 * 1000
    XCTAssertEqual(try snapshot(lastSuccessfulAt: successful).presentation(now: now, suggestionDays: 3).state, "stale")
  }

  func testIndependentExamsSurviveHolidayMissingCourseAndCourseCredentialFailureUntilEnd() throws {
    let exam: [String: Any] = ["key": "exam-key", "course_name": "考试科目", "time_text": "考试时间",
      "campus": "校区", "building": "楼栋", "room": "101",
      "start_at": "2026-11-05T09:00:00+08:00", "end_at": "2026-11-05T03:00:00.000Z"]
    let date = WidgetClock.parseDate("2026-11-05")!
    let during = date.addingTimeInterval(10 * 3600)
    for kind in ["holiday", "missing_source", "normal"] {
      let data = try snapshot(state: "credential_invalid", kind: kind, exams: [exam])
      let item = try XCTUnwrap(data.courses(on: date, now: during).first)
      XCTAssertEqual(item.kind, "exam")
      XCTAssertEqual(item.examKey, "exam-key")
      XCTAssertTrue(item.isOngoing)
      XCTAssertEqual(item.examDisplayText, "考试中 · 09:00–11:00")
      XCTAssertNotEqual(data.presentation(now: during, suggestionDays: 3).state, "login")
      XCTAssertTrue(data.courses(on: date, now: date.addingTimeInterval(11 * 3600)).isEmpty)
      XCTAssertTrue(data.courses(on: date.addingTimeInterval(86400), now: during).isEmpty)
      let dates = WidgetClock.timelineDates(snapshot: data, now: date, suggestionDays: 3)
      XCTAssertTrue(dates.contains(date.addingTimeInterval(9 * 3600)))
      XCTAssertTrue(dates.contains(date.addingTimeInterval(11 * 3600)))
    }
    XCTAssertTrue(try snapshot(user: "", exams: [exam]).courses(on: date, now: during).isEmpty)
    XCTAssertEqual(try snapshot(exams: [exam], projectionPresent: false).courses(on: date, now: during).count, 1)
    var overnight = exam
    overnight["start_at"] = "2026-11-04T23:00:00+08:00"
    overnight["end_at"] = "2026-11-05T01:00:00+08:00"
    let overnightData = try snapshot(exams: [overnight])
    XCTAssertEqual(overnightData.courses(on: date, now: date.addingTimeInterval(1800)).count, 1)
    XCTAssertTrue(overnightData.courses(on: date, now: date.addingTimeInterval(3600)).isEmpty)
  }

  func testExamNavigationPreservesIndependentIdentity() throws {
    let navigation = try XCTUnwrap(WidgetNavigation(url: URL(string:
      "cqut://widget?date=2026-11-05&action=open&itemKind=exam&examKey=exam-key")!))
    XCTAssertEqual(navigation.arguments()["itemKind"] as? String, "exam")
    XCTAssertEqual(navigation.arguments()["examKey"] as? String, "exam-key")
    XCTAssertNil(navigation.arguments()["eventId"])
  }

  func testStartedFilteringClockFallbackAndFinalColorPrecedence() throws {
    let event: [String: Any] = ["eventName": "高等数学", "sessionStart": "1", "sessionLast": "2",
      "address": "两江校区\n第三教学楼301"]
    let clocks: [[String: Any]] = [
      ["sessionNum": 1, "startTime": "08:00", "endTime": "08:45"],
      ["sessionNum": 2, "startTime": "08:55", "endTime": "09:40"]
    ]
    let date = WidgetClock.parseDate("2026-11-05")!
    let data = try snapshot(events: [event], clocks: clocks)
    XCTAssertEqual(data.courses(on: date, now: date.addingTimeInterval(7 * 3600)).count, 1)
    XCTAssertTrue(data.courses(on: date, now: date.addingTimeInterval(8 * 3600)).isEmpty)
    let tomorrowView = data.courses(on: date, now: date.addingTimeInterval(-86400)).first!
    XCTAssertEqual(tomorrowView.startTime, "08:00")
    XCTAssertEqual(tomorrowView.endTime, "09:40")
    XCTAssertEqual(tomorrowView.colorIndex, 7)
    XCTAssertEqual(tomorrowView.event.location, "两江校区 · 第三教学楼301")
    var final = event
    final["colorIndex"] = 20
    let finalData = try snapshot(events: [final], clocks: clocks)
    XCTAssertEqual(finalData.courses(on: date, now: date).first?.colorIndex, 20)
    let incomplete = try snapshot(events: [event], clocks: Array(clocks.suffix(1)))
    let fallback = incomplete.courses(on: date, now: date.addingTimeInterval(10 * 3600)).first!
    XCTAssertNil(fallback.startMinute)
    XCTAssertEqual(fallback.startTime, "")
    XCTAssertEqual(fallback.event.periods, "第1-2节")
  }

  func testCalendarKindsAndUncoveredDate() throws {
    let date = WidgetClock.parseDate("2026-11-05")!
    XCTAssertEqual(try snapshot(kind: "missing_source").emptyText(on: date, now: date), "补课课表加载失败")
    XCTAssertEqual(try snapshot(kind: "holiday").emptyText(on: date, now: date), "放假")
    XCTAssertEqual(try snapshot(kind: "holiday", label: " 校庆 ")
      .emptyText(on: date, now: date.addingTimeInterval(-86400)), "放假 · 校庆")
    XCTAssertEqual(try snapshot().emptyText(on: date, now: date), "今天没有安排")
    XCTAssertEqual(try snapshot().emptyText(on: date.addingTimeInterval(86400), now: date), "该日期课表未获取")
  }

  func testTimelineContainsStartsMidnightsAndStaleBoundaryWithin48Hours() throws {
    let now = WidgetClock.parseDate("2026-11-05")!
    let data = try snapshot(lastSuccessfulAt: now.addingTimeInterval(-2.5 * 86400).timeIntervalSince1970 * 1000,
      events: [["eventName": "课程", "sessionStart": "1", "sessionLast": "1"]],
      clocks: [["sessionNum": 1, "startTime": "08:00", "endTime": "08:45"]])
    let dates = WidgetClock.timelineDates(snapshot: data, now: now, suggestionDays: 3)
    XCTAssertTrue(dates.contains(now.addingTimeInterval(8 * 3600)))
    XCTAssertTrue(dates.contains(now.addingTimeInterval(12 * 3600)))
    XCTAssertTrue(dates.contains(now.addingTimeInterval(24 * 3600)))
    XCTAssertEqual(dates.last, now.addingTimeInterval(48 * 3600))
    XCTAssertEqual(dates, Array(Set(dates)).sorted())
  }

  func testLoadingStateExpiresWithoutReportingFailureAndSchedulesBoundary() throws {
    let now = WidgetClock.parseDate("2026-11-05")!
    let data = try snapshot(state: "loading", generatedAt: now.timeIntervalSince1970 * 1000)
    XCTAssertEqual(data.presentation(now: now.addingTimeInterval(299), suggestionDays: 3).state, "loading")
    let expired = data.presentation(now: now.addingTimeInterval(300), suggestionDays: 3)
    XCTAssertEqual(expired.state, "unconfirmed")
    XCTAssertEqual(expired.text, "更新状态待确认，请打开应用")
    XCTAssertTrue(WidgetClock.timelineDates(snapshot: data, now: now, suggestionDays: 3)
      .contains(now.addingTimeInterval(300)))
  }

  func testMediumLayoutShowsCourseAlongsideOverflowAndRefreshStatus() {
    // iOS 17 medium height 169, system margins 16 each. Refresh status replaces header metadata.
    let content = 169.0 - 32 - 39 - 8
    let dualContent = content - 15 - 6
    XCTAssertGreaterThanOrEqual(WidgetCourseLayout.capacity(contentHeight: content, rowHeight: 42, courseCount: 4), 1)
    XCTAssertGreaterThanOrEqual(WidgetCourseLayout.capacity(contentHeight: dualContent, rowHeight: 42, courseCount: 4), 1)
    XCTAssertEqual(WidgetCourseLayout.capacity(contentHeight: 42, rowHeight: 42, courseCount: 1), 1)
    XCTAssertEqual(WidgetCourseLayout.capacity(contentHeight: 62, rowHeight: 42, courseCount: 4), 1)
  }

  func testWidgetURLUsesActualDateAndPreservesCourseIdentity() {
    let url = URL(string: "cqut://widget?date=2026-11-05&action=sync&eventId=a%26b&eventName=%E9%AB%98%E7%AD%89%E6%95%B0%E5%AD%A6")!
    let navigation = WidgetNavigation(url: url)!
    XCTAssertEqual(navigation.action, "sync")
    XCTAssertEqual(navigation.eventID, "a&b")
    XCTAssertEqual(navigation.eventName, "高等数学")
    XCTAssertEqual(navigation.arguments(now: WidgetClock.parseDate("2026-11-04")!)["dayOffset"] as? Int, 1)
    XCTAssertNil(WidgetNavigation(url: URL(string: "cqut://widget?date=2026-02-30")!))
    XCTAssertNil(WidgetNavigation(url: URL(string: "cqut://widget?date=2026-11-05&action=delete")!))
  }

  func testToggleSynchronizesIdenticalConfigurationsAndSeparatesOtherSettings() {
    let name = "cqut-widget-test-\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: name)!
    defer { defaults.removePersistentDomain(forName: name) }
    let options = WidgetOptions()
    XCTAssertEqual(WidgetOptions(refreshSuggestionDays: 0).refreshSuggestionDays, 3)
    XCTAssertEqual(WidgetDaySelection.effectiveOffset(kind: "today_course", options: options, defaults: defaults), 0)
    WidgetDaySelection.toggle(kind: "today_course", options: options, defaults: defaults)
    XCTAssertEqual(WidgetDaySelection.effectiveOffset(kind: "today_course", options: WidgetOptions(), defaults: defaults), 1)
    XCTAssertEqual(WidgetDaySelection.effectiveOffset(kind: "today_list", options: options, defaults: defaults), 0)
    XCTAssertEqual(WidgetDaySelection.effectiveOffset(kind: "today_course", options: WidgetOptions(theme: "dark"), defaults: defaults), 0)
    WidgetDaySelection.toggle(kind: "today_course", options: options, defaults: defaults)
    XCTAssertEqual(WidgetDaySelection.effectiveOffset(kind: "today_course", options: options, defaults: defaults), 0)
  }
}
