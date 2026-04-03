import AppKit
import BearApplication
import SwiftUI

struct UrsusApp: App {
    @NSApplicationDelegateAdaptor(UrsusAppDelegate.self) private var appDelegate
    @StateObject private var model = UrsusAppModel()

    var body: some Scene {
        WindowGroup {
            UrsusDashboardView(model: model)
                .frame(width: 720, height: 620)
        }
        .windowResizability(.contentSize)

        Settings {
            UrsusSettingsView(model: model)
                .frame(minWidth: 560, minHeight: 520)
        }
    }
}

@MainActor
final class UrsusAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
