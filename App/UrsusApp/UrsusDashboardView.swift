import SwiftUI

enum UrsusDashboardSection: Hashable {
    case setup
    case preferences
    case tools
}

struct UrsusDashboardView: View {
    @ObservedObject var model: UrsusAppModel
    @ObservedObject var updaterController: UrsusUpdaterController
    @State private var selectedSection: UrsusDashboardSection = .setup

    var body: some View {
        TabView(selection: $selectedSection) {
            UrsusSetupView(model: model, selectedSection: $selectedSection)
                .tabItem {
                    Label("Setup", systemImage: "sparkles.rectangle.stack")
                }
                .tag(UrsusDashboardSection.setup)

            UrsusPreferencesView(
                model: model,
                updaterController: updaterController,
                showsStandaloneHeader: false
            )
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
        .alert("Support Ursus", isPresented: $model.showsDonationPrompt) {
            Button("Buy Me a Coffee") {
                model.handleDonationAction()
            }
            Button("Not Now") {
                model.handleDonationNotNow()
            }
            Button("Don’t Ask Again") {
                model.handleDonationDontAskAgain()
            }
        } message: {
            Text("Ursus is free and open source. If it has been useful to you, a small donation helps support continued development.")
        }
    }
}

struct UrsusSettingsView: View {
    @ObservedObject var model: UrsusAppModel
    @ObservedObject var updaterController: UrsusUpdaterController

    var body: some View {
        UrsusPreferencesView(
            model: model,
            updaterController: updaterController,
            showsStandaloneHeader: true
        )
    }
}

#Preview {
    UrsusDashboardView(
        model: UrsusAppModel(),
        updaterController: UrsusUpdaterController()
    )
        .frame(width:720, height: 620)
}
