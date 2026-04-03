import AppKit
import BearApplication
import SwiftUI

struct UrsusApp: App {
    @NSApplicationDelegateAdaptor(UrsusAppDelegate.self) private var appDelegate
    @StateObject private var model = UrsusAppModel()

    var body: some Scene {
        WindowGroup {
            UrsusDashboardView(model: model)
                .frame(
                    minWidth: 720,
                    idealWidth: 760,
                    maxWidth: 860,
                    minHeight: 560,
                    idealHeight: 640,
                    maxHeight: 820
                )
        }
        .defaultSize(width: 760, height: 640)
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
