import SwiftUI

enum UrsusDashboardSection: Hashable {
    case setup
    case preferences
    case tools
}

struct UrsusDashboardView: View {
    @ObservedObject var model: UrsusAppModel
    @State private var selectedSection: UrsusDashboardSection = .setup

    var body: some View {
        TabView(selection: $selectedSection) {
            UrsusSetupView(model: model, selectedSection: $selectedSection)
                .tabItem {
                    Label("Setup", systemImage: "sparkles.rectangle.stack")
                }
                .tag(UrsusDashboardSection.setup)

            UrsusPreferencesView(model: model, showsStandaloneHeader: false)
                .tabItem {
                    Label("Preferences", systemImage: "slider.horizontal.3")
                }
                .tag(UrsusDashboardSection.preferences)

            UrsusToolsView(model: model)
                .tabItem {
                    Label("Tools", systemImage: "wrench.and.screwdriver")
                }
                .tag(UrsusDashboardSection.tools)
        }
    }
}

struct UrsusSettingsView: View {
    @ObservedObject var model: UrsusAppModel

    var body: some View {
        UrsusPreferencesView(model: model, showsStandaloneHeader: true)
    }
}

#Preview {
    UrsusDashboardView(model: UrsusAppModel())
        .frame(width:720, height: 620)
}
