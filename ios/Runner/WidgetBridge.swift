import Flutter
import UIKit
import WidgetKit

final class WidgetBridge {
  static let shared = WidgetBridge()
  private var navigationChannel: FlutterMethodChannel?
  private var pendingNavigation: WidgetNavigation?
  private var dartReady = false
  private var lastDelivery: (url: String, time: TimeInterval)?

  func register(messenger: FlutterBinaryMessenger) {
    let widget = FlutterMethodChannel(name: "cqut/widget", binaryMessenger: messenger)
    widget.setMethodCallHandler { call, result in
      guard call.method == "updateTodayWidget" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let arguments = call.arguments as? [String: Any],
        let json = arguments["snapshotJson"] as? String else {
        result(FlutterError(code: "invalid_arguments", message: "缺少小组件快照", details: nil))
        return
      }
      do {
        try WidgetSnapshotStore.write(json)
        WidgetCenter.shared.reloadAllTimelines()
        result(nil)
      } catch {
        result(FlutterError(code: "widget_snapshot_error", message: error.localizedDescription, details: nil))
      }
    }
    let navigation = FlutterMethodChannel(name: "cqut/navigation", binaryMessenger: messenger)
    navigationChannel = navigation
    dartReady = false
    navigation.setMethodCallHandler { [weak self] call, result in
      guard call.method == "getInitialWidgetNavigation" else {
        result(FlutterMethodNotImplemented)
        return
      }
      self?.dartReady = true
      let initial = self?.pendingNavigation
      self?.pendingNavigation = nil
      result(initial?.arguments())
    }
  }

  @discardableResult
  func receive(_ url: URL) -> Bool {
    guard let navigation = WidgetNavigation(url: url) else { return false }
    let now = Date().timeIntervalSince1970
    // UIKit can forward one activation through both application and scene delegates.
    if let last = lastDelivery, last.url == url.absoluteString, now - last.time < 1 { return true }
    lastDelivery = (url.absoluteString, now)
    if dartReady, let channel = navigationChannel {
      channel.invokeMethod("widgetNavigation", arguments: navigation.arguments())
    } else {
      pendingNavigation = navigation
    }
    return true
  }
}
