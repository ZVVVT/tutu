import UIKit
import Flutter
import UniformTypeIdentifiers

@UIApplicationMain
class AppDelegate: FlutterAppDelegate, UIDocumentPickerDelegate {

  private var flutterResult: FlutterResult?
  private var currentAccessedURL: URL?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    let controller : FlutterViewController = window?.rootViewController as! FlutterViewController
    let channel = FlutterMethodChannel(name: "io.tutu/bookmarks", binaryMessenger: controller.binaryMessenger)

    channel.setMethodCallHandler { [weak self] call, result in
      guard let self = self else { return }
      switch call.method {
      case "pickFolder":
        self.pickFolder(result: result)
      case "restoreBookmark":
        self.restoreBookmark(result: result)
      case "releaseBookmark":
        self.releaseBookmark(result: result)
      default:
        result(FlutterMethodNotImplemented)
      }
    }

    GeneratedPluginRegistrant.register(with: self)
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - Pick folder and save bookmark
  private func pickFolder(result: @escaping FlutterResult) {
    flutterResult = result
    let picker = UIDocumentPickerViewController(forOpeningContentTypes: [UTType.folder], asCopy: false)
    picker.delegate = self
    picker.allowsMultipleSelection = false
    window?.rootViewController?.present(picker, animated: true)
  }

  func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
    guard let url = urls.first else { flutterResult?(nil); flutterResult = nil; return }
    let _ = url.startAccessingSecurityScopedResource()
    defer { url.stopAccessingSecurityScopedResource() }

    do {
      // 持久化安全书签
      let data = try url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
      UserDefaults.standard.set(data, forKey: "rootFolderBookmark")
      // 由 Flutter 负责稍后重新打开一次（会真正 startAccess）
      flutterResult?(["path": url.path])
    } catch {
      flutterResult?(FlutterError(code: "BOOKMARK_ERROR", message: error.localizedDescription, details: nil))
    }
    flutterResult = nil
  }

  // MARK: - Restore & hold access for scanning
  private func restoreBookmark(result: @escaping FlutterResult) {
    guard let data = UserDefaults.standard.data(forKey: "rootFolderBookmark") else {
      result(nil); return
    }
    var stale = false
    do {
      let url = try URL(resolvingBookmarkData: data, options: [.withSecurityScope], relativeTo: nil, bookmarkDataIsStale: &stale)
      if stale {
        // 书签过期需要用户重新选择
        result(FlutterError(code: "BOOKMARK_STALE", message: "Bookmark is stale", details: nil))
        return
      }
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
