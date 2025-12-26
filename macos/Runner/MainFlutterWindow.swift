import Cocoa
import FlutterMacOS
import WidgetKit

class MainFlutterWindow: NSWindow {
  private static let appGroupId = "group.com.magisky.reschoolbeta"

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)

    RegisterGeneratedPlugins(registry: flutterViewController)

    Self.checkAppGroupAvailability()

    let channel = FlutterMethodChannel(
      name: "com.magisky.reschoolbeta/widgets",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )

    channel.setMethodCallHandler { (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "saveWidgetData":
        guard let args = call.arguments as? [String: Any],
              let key = args["key"] as? String,
              let data = args["data"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing key or data", details: nil))
          return
        }

        let userDefaults = UserDefaults(suiteName: Self.appGroupId)
        if userDefaults != nil {
          userDefaults?.set(data, forKey: key)
          userDefaults?.synchronize()
          print("[Widget] Saved to App Group UserDefaults for key: \(key), length: \(data.count)")
        } else {
          print("[Widget] WARNING: App Group UserDefaults is nil!")
        }

        Self.saveToFile(key: key, data: data)

        result(true)

      case "reloadWidgets":
        if #available(macOS 11.0, *) {
          WidgetCenter.shared.reloadAllTimelines()
          print("[Widget] Reloaded all timelines")
        }
        result(true)

      case "reloadWidget":
        guard let args = call.arguments as? [String: Any],
              let kind = args["kind"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Missing kind", details: nil))
          return
        }
        if #available(macOS 11.0, *) {
          WidgetCenter.shared.reloadTimelines(ofKind: kind)
          print("[Widget] Reloaded timeline for: \(kind)")
        }
        result(true)

      default:
        result(FlutterMethodNotImplemented)
      }
    }

    super.awakeFromNib()
  }

  private static func checkAppGroupAvailability() {
    if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
      print("[Widget] App Group container available at: \(containerURL.path)")
    } else {
      print("[Widget] WARNING: App Group container NOT available!")
      print("[Widget] This usually means the app is not properly signed with provisioning profile.")
      print("[Widget] Try running from Xcode instead of 'flutter run'.")
    }

    if let defaults = UserDefaults(suiteName: appGroupId) {
      defaults.set("test", forKey: "widget_test_key")
      defaults.synchronize()
      if defaults.string(forKey: "widget_test_key") == "test" {
        print("[Widget] App Group UserDefaults is working")
        defaults.removeObject(forKey: "widget_test_key")
      } else {
        print("[Widget] WARNING: App Group UserDefaults write/read failed!")
      }
    } else {
      print("[Widget] WARNING: Could not create UserDefaults with App Group!")
    }
  }

  private static func getSharedDataDirectory() -> URL? {
    if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
      let dataDir = containerURL.appendingPathComponent("Library/WidgetData")
      try? FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
      return dataDir
    }

    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    if let appSupport = appSupport {
      let sharedDir = appSupport.appendingPathComponent("ReSchoolWidgets")
      try? FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)
      print("[Widget] Using fallback directory: \(sharedDir.path)")
      return sharedDir
    }

    return nil
  }

  private static func saveToFile(key: String, data: String) {
    guard let dataDir = getSharedDataDirectory() else {
      print("[Widget] ERROR: Could not get shared data directory")
      return
    }

    let fileURL = dataDir.appendingPathComponent("\(key).json")
    do {
      try data.write(to: fileURL, atomically: true, encoding: .utf8)
      print("[Widget] Saved to file: \(fileURL.path)")
    } catch {
      print("[Widget] ERROR saving to file: \(error)")
    }
  }
}