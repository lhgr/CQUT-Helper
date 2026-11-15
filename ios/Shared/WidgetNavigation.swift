import Foundation

struct WidgetNavigation: Equatable {
  let date: String
  let action: String
  let eventID: String?
  let eventName: String?
  let itemKind: String
  let examKey: String?

  init?(url: URL) {
    guard url.scheme?.lowercased() == "cqut", url.host?.lowercased() == "widget",
      let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
    let items = components.queryItems ?? []
    func value(_ name: String) -> String? { items.first { $0.name == name }?.value }
    guard let date = value("date"), WidgetClock.parseDate(date) != nil else { return nil }
    let action = value("action") ?? "open"
    guard ["open", "sync"].contains(action) else { return nil }
    self.date = date
    self.action = action
    eventID = value("eventId").flatMap { $0.isEmpty ? nil : $0 }
    eventName = value("eventName").flatMap { $0.isEmpty ? nil : $0 }
    itemKind = value("itemKind") ?? "course"
    examKey = value("examKey").flatMap { $0.isEmpty ? nil : $0 }
  }

  func arguments(now: Date = Date()) -> [String: Any] {
    let target = WidgetClock.parseDate(date)!
    let offset = WidgetClock.calendar.dateComponents([.day],
      from: WidgetClock.calendar.startOfDay(for: now), to: target).day ?? 0
    var result: [String: Any] = ["date": date, "action": action, "dayOffset": offset]
    result["itemKind"] = itemKind
    if let examKey = examKey { result["examKey"] = examKey }
    if let eventID = eventID { result["eventId"] = eventID }
    if let eventName = eventName { result["eventName"] = eventName }
    return result
  }
}
