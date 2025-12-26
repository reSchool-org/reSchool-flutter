import WidgetKit
import SwiftUI

@main
struct ReSchoolWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ScheduleWidget()
        HomeworkWidget()
        GradesWidget()
    }
}

struct WidgetScheduleData: Codable {
    let date: String
    let lessons: [WidgetLesson]
    let lastUpdated: String

    static var empty: WidgetScheduleData {
        WidgetScheduleData(date: "", lessons: [], lastUpdated: "")
    }
}

struct WidgetLesson: Codable, Identifiable {
    let num: Int
    let subject: String
    let teacher: String
    let startTime: String
    let endTime: String
    let mark: String?
    let isPlaceholder: Bool

    var id: Int { num }
}

struct WidgetHomeworkData: Codable {
    let items: [WidgetHomeworkItem]
    let lastUpdated: String

    static var empty: WidgetHomeworkData {
        WidgetHomeworkData(items: [], lastUpdated: "")
    }
}

struct WidgetHomeworkItem: Codable, Identifiable {
    let subject: String
    let text: String
    let date: String
    let deadline: String?
    let hasFiles: Bool

    var id: String { "\(subject)-\(date)" }
}

struct WidgetGradesData: Codable {
    let periodName: String
    let grades: [WidgetGrade]
    let lastUpdated: String

    static var empty: WidgetGradesData {
        WidgetGradesData(periodName: "", grades: [], lastUpdated: "")
    }
}

struct WidgetGrade: Codable, Identifiable {
    let subject: String
    let average: String
    let rating: String?
    let totalMarks: Int?

    var id: String { subject }
}

struct WidgetDataProvider {
    static let appGroupId = "group.com.magisky.reschoolbeta"

    static func loadScheduleData() -> WidgetScheduleData {
        guard let userDefaults = UserDefaults(suiteName: appGroupId),
              let jsonString = userDefaults.string(forKey: "widget_schedule_data"),
              let data = jsonString.data(using: .utf8) else {
            return .empty
        }

        do {
            return try JSONDecoder().decode(WidgetScheduleData.self, from: data)
        } catch {
            print("Error decoding schedule data: \(error)")
            return .empty
        }
    }

    static func loadHomeworkData() -> WidgetHomeworkData {
        guard let userDefaults = UserDefaults(suiteName: appGroupId),
              let jsonString = userDefaults.string(forKey: "widget_homework_data"),
              let data = jsonString.data(using: .utf8) else {
            return .empty
        }

        do {
            return try JSONDecoder().decode(WidgetHomeworkData.self, from: data)
        } catch {
            print("Error decoding homework data: \(error)")
            return .empty
        }
    }

    static func loadGradesData() -> WidgetGradesData {
        guard let userDefaults = UserDefaults(suiteName: appGroupId),
              let jsonString = userDefaults.string(forKey: "widget_grades_data"),
              let data = jsonString.data(using: .utf8) else {
            return .empty
        }

        do {
            return try JSONDecoder().decode(WidgetGradesData.self, from: data)
        } catch {
            print("Error decoding grades data: \(error)")
            return .empty
        }
    }
}

struct GradientBackground: View {
    let colors: [Color]

    var body: some View {
        LinearGradient(
            gradient: Gradient(colors: colors),
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }
}

struct WidgetHeader: View {
    let icon: String
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white.opacity(0.9))

            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.white)

                if let subtitle = subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10))
                        .foregroundColor(.white.opacity(0.7))
                }
            }

            Spacer()
        }
    }
}

struct EmptyStateView: View {
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 24))
                .foregroundColor(.white.opacity(0.5))

            Text(message)
                .font(.system(size: 11))
                .foregroundColor(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
    }
}