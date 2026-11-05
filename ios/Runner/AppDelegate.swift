import Flutter
import UIKit
import UniformTypeIdentifiers
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private let documents = DocumentPickerBridge()

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    guard let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "CqutNativeChannels") else {
      return
    }
    let documentsChannel = FlutterMethodChannel(
      name: "cqut/documents", binaryMessenger: registrar.messenger())
    documentsChannel.setMethodCallHandler { [weak self] call, result in
      DispatchQueue.main.async {
        self?.documents.handle(call, result: result)
      }
    }
  }
}

private final class DocumentPickerBridge: NSObject, UIDocumentPickerDelegate,
  UIAdaptivePresentationControllerDelegate
{
  private var pendingResult: FlutterResult?
  private var temporaryDirectory: URL?
  private var isImporting = false
  private var isCompletingSelection = false
  private var activePicker: UIDocumentPickerViewController?
  private var operationID = UUID()

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard ["createTextDocument", "openTextDocument", "exportFile"].contains(call.method) else {
      result(FlutterMethodNotImplemented)
      return
    }
    guard pendingResult == nil else {
      result(FlutterError(code: "document_busy", message: "已有文件选择操作正在进行", details: nil))
      return
    }
    guard let arguments = call.arguments as? [String: Any] else {
      result(FlutterError(code: "invalid_arguments", message: "缺少文件参数", details: nil))
      return
    }
    guard let presenter = activePresenter(), presenter.viewIfLoaded?.window != nil else {
      result(FlutterError(code: "document_unavailable", message: "无法显示文件选择器", details: nil))
      return
    }

    pendingResult = result
    operationID = UUID()
    isImporting = call.method == "openTextDocument"
    isCompletingSelection = false
    do {
      let picker: UIDocumentPickerViewController
      if isImporting {
        let mimeType = arguments["mimeType"] as? String ?? "application/json"
        let contentType = UTType(mimeType: mimeType) ?? .text
        picker = UIDocumentPickerViewController(forOpeningContentTypes: [contentType], asCopy: false)
      } else {
        guard let fileName = arguments["fileName"] as? String,
          !fileName.isEmpty, (fileName as NSString).lastPathComponent == fileName
        else {
          finish(FlutterError(code: "invalid_arguments", message: "文件名无效", details: nil))
          return
        }
        let directory = FileManager.default.temporaryDirectory
          .appendingPathComponent("cqut-documents-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        temporaryDirectory = directory
        let file = directory.appendingPathComponent(fileName)
        if call.method == "createTextDocument" {
          guard let content = arguments["content"] as? String else {
            finish(FlutterError(code: "invalid_arguments", message: "缺少文件内容", details: nil))
            return
          }
          try content.write(to: file, atomically: true, encoding: .utf8)
        } else {
          guard let path = arguments["path"] as? String, !path.isEmpty else {
            finish(FlutterError(code: "invalid_arguments", message: "缺少源文件路径", details: nil))
            return
          }
          try FileManager.default.copyItem(at: URL(fileURLWithPath: path), to: file)
        }
        picker = UIDocumentPickerViewController(forExporting: [file], asCopy: true)
      }
      picker.delegate = self
      picker.allowsMultipleSelection = false
      picker.presentationController?.delegate = self
      activePicker = picker
      presenter.present(picker, animated: true)
    } catch {
      finish(FlutterError(code: "document_error", message: error.localizedDescription, details: nil))
    }
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard controller === activePicker, !isCompletingSelection else { return }
    let operation = operationID
    guard let url = urls.first else {
      finish(nil, operation: operation)
      return
    }
    isCompletingSelection = true
    guard isImporting else {
      finish(url.absoluteString, operation: operation)
      return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      let accessing = url.startAccessingSecurityScopedResource()
      defer { if accessing { url.stopAccessingSecurityScopedResource() } }
      var coordinationError: NSError?
      var readResult: Any?
      NSFileCoordinator(filePresenter: nil).coordinate(readingItemAt: url, options: [], error: &coordinationError) { readableURL in
        do {
          readResult = try String(contentsOf: readableURL, encoding: .utf8)
        } catch {
          readResult = FlutterError(code: "document_read_error", message: error.localizedDescription, details: nil)
        }
      }
      if let error = coordinationError {
        readResult = FlutterError(code: "document_read_error", message: error.localizedDescription, details: nil)
      }
      let value = readResult
      DispatchQueue.main.async {
        self.finish(value, operation: operation)
      }
    }
  }

  func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
    guard controller === activePicker, !isCompletingSelection else { return }
    let operation = operationID
    finish(nil, operation: operation)
  }

  func presentationControllerDidDismiss(_ presentationController: UIPresentationController) {
    guard presentationController.presentedViewController === activePicker, !isCompletingSelection else { return }
    finish(nil)
  }

  private func finish(_ value: Any?, operation: UUID? = nil) {
    if let operation = operation, operation != operationID { return }
    let result = pendingResult
    pendingResult = nil
    activePicker = nil
    if let directory = temporaryDirectory {
      try? FileManager.default.removeItem(at: directory)
    }
    temporaryDirectory = nil
    result?(value)
  }

  private func activePresenter() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    let scene = scenes.first { $0.activationState == .foregroundActive }
    var controller = scene?.windows.first { $0.isKeyWindow }?.rootViewController
    while let presented = controller?.presentedViewController { controller = presented }
    guard !(controller is UIDocumentPickerViewController),
      controller?.isBeingDismissed == false,
      controller?.isBeingPresented == false
    else { return nil }
    return controller
  }
}
