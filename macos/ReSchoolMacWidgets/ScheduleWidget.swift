import WidgetKit
import SwiftUI

struct ScheduleEntry: TimelineEntry {
    let date: Date
    let scheduleData: WidgetScheduleData
}

struct WidgetScheduleData: Decodable, Hashable {
    let date: String
    let lessons: [WidgetLesson]
    let lastUpdated: String

    static var empty: WidgetScheduleData {
        WidgetScheduleData(date: "", lessons: [], lastUpdated: "")
    }
}

struct WidgetLesson: Decodable, Hashable, Identifiable {
    var id: Int { num }
    let num: Int
    let subject: String
    let teacher: String
    let startTime: String
    let endTime: String
    let mark: String?
    let isPlaceholder: Bool
}

struct ScheduleWidgetEntryView: View {
    var entry: ScheduleEntry
    @Environment(\.widgetFamily) var family

    var lessonsToShow: Int {
        switch family {
        case .systemSmall: return 3
        case .systemMedium: return 4
        case .systemLarge: return 8
        default: return 4
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "calendar")
                    .foregroundColor(.white)
                Text("Расписание")
                    .font(.headline)
                    .foregroundColor(.white)
                Spacer()
                if !entry.scheduleData.date.isEmpty {
                    Text(entry.scheduleData.date)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            if entry.scheduleData.lessons.isEmpty {
                Spacer()
                Text("Нет уроков")
                    .foregroundColor(.white.opacity(0.8))
                    .frame(maxWidth: .infinity, alignment: .center)
                Spacer()
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(entry.scheduleData.lessons.prefix(lessonsToShow))) { lesson in
                        HStack(spacing: 8) {
                            Text("\(lesson.num)")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 18, height: 18)
                                .background(Color.white.opacity(0.2))
                                .clipShape(Circle())

                            VStack(alignment: .leading, spacing: 0) {
                                Text(lesson.subject)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.white)
                                    .lineLimit(1)

                                if family != .systemSmall && !lesson.teacher.isEmpty {
                                    Text(lesson.teacher)
                                        .font(.system(size: 9))
                                        .foregroundColor(.white.opacity(0.6))
                                        .lineLimit(1)
                                }
                            }

                            Spacer()

                            Text(lesson.startTime)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))

                            if let mark = lesson.mark, !mark.isEmpty {
                                Text(mark)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Color.white.opacity(0.25))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
        }
        .padding()
    }
}

struct ScheduleWidget: Widget {
    let kind: String = "ScheduleWidget"

    private var gradientBackground: some View {
        LinearGradient(
            gradient: Gradient(colors: [Color(red: 0.42, green: 0.07, blue: 0.80), Color(red: 0.15, green: 0.46, blue: 0.99)]),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: ScheduleProvider()) { entry in
            if #available(macOS 14.0, *) {
                ScheduleWidgetEntryView(entry: entry)
                    .containerBackground(for: .widget) {
                        gradientBackground
                    }
            } else {
                ZStack {
                    gradientBackground
                    ScheduleWidgetEntryView(entry: entry)
                }
            }
        }
        .configurationDisplayName("Расписание")
        .description("Ваши уроки на сегодня.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct ScheduleProvider: TimelineProvider {
    private static let appGroupId = "group.com.magisky.reschoolbeta"
    private static let dataKey = "widget_schedule_data"

    func placeholder(in context: Context) -> ScheduleEntry {
        ScheduleEntry(date: Date(), scheduleData: .empty)
    }

    func getSnapshot(in context: Context, completion: @escaping (ScheduleEntry) -> ()) {
        let entry = ScheduleEntry(date: Date(), scheduleData: getScheduleData())
        completion(entry)
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<ScheduleEntry>) -> ()) {
        let entry = ScheduleEntry(date: Date(), scheduleData: getScheduleData())
        let nextUpdate = Calendar.current.date(byAdding: .minute, value: 30, to: Date())!
        let timeline = Timeline(entries: [entry], policy: .after(nextUpdate))
        completion(timeline)
    }

    private func getScheduleData() -> WidgetScheduleData {
        if let data = getFromAppGroup() {
            return data
        }

        if let data = getFromFile() {
            return data
        }

        print("[ScheduleWidget] No data found from any source")
        return .empty
    }

    private func getFromAppGroup() -> WidgetScheduleData? {
        let userDefaults = UserDefaults(suiteName: Self.appGroupId)
        print("[ScheduleWidget] Trying App Group UserDefaults...")
        print("[ScheduleWidget] UserDefaults exists: \(userDefaults != nil)")

        if let jsonString = userDefaults?.string(forKey: Self.dataKey) {
            print("[ScheduleWidget] Found JSON in App Group, length: \(jsonString.count)")
            if let data = jsonString.data(using: .utf8) {
                do {
                    let decoded = try JSONDecoder().decode(WidgetScheduleData.self, from: data)
                    print("[ScheduleWidget] Decoded from App Group, lessons count: \(decoded.lessons.count)")
                    return decoded
                } catch {
                    print("[ScheduleWidget] Error decoding from App Group: \(error)")
                }
            }
        } else {
            print("[ScheduleWidget] No data in App Group UserDefaults")
            if let allKeys = userDefaults?.dictionaryRepresentation().keys {
                print("[ScheduleWidget] Available keys: \(Array(allKeys))")
            }
        }
        return nil
    }

    private func getFromFile() -> WidgetScheduleData? {
        print("[ScheduleWidget] Trying file-based fallback...")

        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupId) {
            let fileURL = containerURL.appendingPathComponent("Library/WidgetData/\(Self.dataKey).json")
            if let data = readFromFile(url: fileURL) {
                return data
            }
        }

        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let fileURL = appSupport.appendingPathComponent("ReSchoolWidgets/\(Self.dataKey).json")
            print("[ScheduleWidget] Checking fallback file: \(fileURL.path)")
            if let data = readFromFile(url: fileURL) {
                return data
            }
        }

        return nil
    }

    private func readFromFile(url: URL) -> WidgetScheduleData? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            print("[ScheduleWidget] File does not exist: \(url.path)")
            return nil
        }

        do {
            let jsonString = try String(contentsOf: url, encoding: .utf8)
            print("[ScheduleWidget] Found JSON in file, length: \(jsonString.count)")
            if let jsonData = jsonString.data(using: .utf8) {
                let decoded = try JSONDecoder().decode(WidgetScheduleData.self, from: jsonData)
                print("[ScheduleWidget] Decoded from file, lessons count: \(decoded.lessons.count)")
                return decoded
            }
        } catch {
            print("[ScheduleWidget] Error reading from file: \(error)")
        }
        return nil
    }
}