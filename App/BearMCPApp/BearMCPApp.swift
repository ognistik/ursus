import SwiftUI

@main
struct BearMCPApp: App {
    @StateObject private var model = BearMCPAppModel()

    var body: some Scene {
        WindowGroup {
            BearMCPDashboardView(model: model)
                .frame(minWidth: 860, minHeight: 620)
                .onOpenURL { url in
                    model.recordIncomingCallback(url)
                }
        }
        .defaultSize(width: 980, height: 720)

        Settings {
            BearMCPSettingsView(model: model)
                .frame(minWidth: 560, minHeight: 520)
        }
    }
}
