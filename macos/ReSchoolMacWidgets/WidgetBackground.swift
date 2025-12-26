import SwiftUI
import WidgetKit

extension View {
    @ViewBuilder
    func applyWidgetBackground(_ background: some View) -> some View {
        if #available(macOS 14.0, *) {
            containerBackground(for: .widget) {
                background.ignoresSafeArea()
            }
        } else {
            self.background(background)
        }
    }
}