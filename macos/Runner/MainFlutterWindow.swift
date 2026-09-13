import Cocoa
import FlutterMacOS
import WidgetKit

class MainFlutterWindow: NSWindow {
  private static let appGroupId = "group.com.magisky.reschoolbeta"
  private static let dataKeys: Set<String> = [
    "widget_schedule_data", "widget_homework_data", "widget_grades_data",
    "widget_config", "widget_appearance"
  ]

  override func awakeFromNib() {
    let flutterViewController = FlutterViewController()
    let windowFrame = self.frame
    self.contentViewController = flutterViewController
    self.setFrame(windowFrame, display: true)
    RegisterGeneratedPlugins(registry: flutterViewController)

    let channel = FlutterMethodChannel(
      name: "com.magisky.reschoolbeta/widgets",
      binaryMessenger: flutterViewController.engine.binaryMessenger
    )
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "saveWidgetData":
        guard let args = call.arguments as? [String: Any],
              let key = args["key"] as? String, Self.dataKeys.contains(key),
              let data = args["data"] as? String else {
          result(FlutterError(code: "INVALID_ARGS", message: "Invalid widget key or data", details: nil))
          return
        }
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupId),
              let defaults = UserDefaults(suiteName: Self.appGroupId) else {
          result(FlutterError(code: "APP_GROUP_UNAVAILABLE", message: "Widget App Group is unavailable", details: nil))
          return
        }
        do {
          let directory = container.appendingPathComponent("Library/WidgetData")
          try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
          try data.write(to: directory.appendingPathComponent("\(key).json"), atomically: true, encoding: .utf8)
          defaults.set(data, forKey: key)
          result(true)
        } catch {
          result(FlutterError(code: "WIDGET_WRITE_FAILED", message: error.localizedDescription, details: nil))
        }
      case "reloadWidgets":
        if #available(macOS 11.0, *) { WidgetCenter.shared.reloadAllTimelines() }
        result(true)
      case "reloadWidget":
        guard let args = call.arguments as? [String: Any], let kind = args["kind"] as? String,
              ["ScheduleWidget", "HomeworkWidget", "GradesWidget"].contains(kind) else {
          result(FlutterError(code: "INVALID_ARGS", message: "Unknown widget kind", details: nil))
          return
        }
        if #available(macOS 11.0, *) { WidgetCenter.shared.reloadTimelines(ofKind: kind) }
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
    super.awakeFromNib()
  }
}
