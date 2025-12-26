import WidgetKit
import SwiftUI

@main
struct ReSchoolMacWidgetsBundle: WidgetBundle {
    var body: some Widget {
        ScheduleWidget()
        HomeworkWidget()
        GradesWidget()
    }
}