import SwiftUI

@main
struct DevCleanerApp: App {
    @StateObject private var model = DashboardViewModel()

    var body: some Scene {
        WindowGroup("DevCleaner") {
            DashboardView(model: model)
                .frame(minWidth: 740, minHeight: 560)
        }
        .defaultSize(width: 860, height: 650)
    }
}
