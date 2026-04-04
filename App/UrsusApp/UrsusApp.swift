import AppKit
import BearApplication
import SwiftUI

let ursusMutedControlTint = Color(
    nsColor: NSColor(
        name: nil,
        dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedWhite: 0.72, alpha: 0.95)
            }

            return NSColor(calibratedWhite: 0.38, alpha: 0.95)
        }
    )
)

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
                .tint(ursusMutedControlTint)
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
