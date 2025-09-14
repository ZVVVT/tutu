import UIKit
import Flutter

@UIApplicationMain
class AppDelegate: FlutterAppDelegate, UIDocumentPickerDelegate {

  private var flutterResult: FlutterResult?
  private var currentAccessedURL: URL?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    let controller = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "io.tutu/bookmarks", binaryMessenger: controller.binaryMessenger)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "pickFolder":       self.pickFolder(result: result)
      case "restoreBookmark":  self.restoreBookmark(result: result)
      case "releaseBookmark":  self.releaseBookmark(result: result)
      default: result(FlutterMethodNotImplemented)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Pick folder and save bookmark (iOS 11+)
  private func pickFolder(result: @escaping FlutterResult) {
    flutterResult = result
    let picker = UIDocumentPickerViewController(documentTypes: ["public.folder"], in: .open)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    if #available(iOS 14.0, *) { picker.shouldShowFileExtensions = true }
    window?.rootViewController?.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else { flutterResult?(nil); flutterResult = nil; return }
    let ok = url.startAccessingSecurityScopedResource()
    defer { if ok { url.stopAccessingSecurityScopedResource() } }

    do {
      let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
      UserDefaults.standard.set(data, forKey: "rootFolderBookmark")
      flutterResult?(["path": url.path])
    } catch {
      flutterResult?(FlutterError(code: "BOOKMARK_ERROR", message: error.localizedDescription, details: nil))
    }
    flutterResult = nil
  }

  // MARK: - Restore & release
  private func restoreBookmark(result: @escaping FlutterResult) {
    guard let data = UserDefaults.standard.data(forKey: "rootFolderBookmark") else { result(nil); return }
    var stale = false
    do {
      let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
      if stale { result(FlutterError(code: "BOOKMARK_STALE", message: "Bookmark is stale", details: nil)); return }
      if url.startAccessingSecurityScopedResource() {
        currentAccessedURL = url
        result(url.path)
      } else {
        result(FlutterError(code: "START_ACCESS_FAIL", message: "Failed to start security scope", details: nil))
      }
    } catch {
      result(FlutterError(code: "RESTORE_ERROR", message: error.localizedDescription, details: nil))
    }
  }

  private func releaseBookmark(result: @escaping FlutterResult) {
    if let u = currentAccessedURL {
      u.stopAccessingSecurityScopedResource()
      currentAccessedURL = nil
    }
    result(true)
  }
}
