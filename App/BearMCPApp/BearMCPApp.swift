import AppKit
import BearApplication
import SwiftUI

@main
struct BearMCPApp: App {
    @NSApplicationDelegateAdaptor(BearMCPAppDelegate.self) private var appDelegate
    @StateObject private var model = BearMCPAppModel()

    var body: some Scene {
        WindowGroup {
            BearMCPDashboardView(model: model)
                .frame(minWidth: 860, minHeight: 620)
        }
        .defaultSize(width: 980, height: 720)

        Settings {
            BearMCPSettingsView(model: model)
                .frame(minWidth: 560, minHeight: 520)
        }
    }
}

@MainActor
final class BearMCPAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}
