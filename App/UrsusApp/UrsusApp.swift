import AppKit
import BearApplication
import SwiftUI

let ursusMutedControlTint = Color(
    nsColor: NSColor(
        name: nil,
        dynamicProvider: { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return NSColor(calibratedWhite: 0.54, alpha: 0.95)
            }

            return NSColor(calibratedWhite: 0.27, alpha: 0.97)
        }
    )
)

struct UrsusApp: App {
    @NSApplicationDelegateAdaptor(UrsusAppDelegate.self) private var appDelegate
    @StateObject private var model = UrsusAppModel()
    @StateObject private var updaterController = UrsusUpdaterController()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            UrsusWindowSurface {
                UrsusDashboardView(model: model, updaterController: updaterController)
                    .frame(width: 720, height: 620)
            }
        }
        .windowResizability(.contentSize)
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                model.applicationDidBecomeActive()
            }
        }
        .commands {
            CommandGroup(after: .appInfo) {
                UrsusCheckForUpdatesCommand(updaterController: updaterController)
            }
        }

        Settings {
            UrsusWindowSurface {
                UrsusSettingsView(model: model, updaterController: updaterController)
                    .frame(minWidth: 560, minHeight: 520)
            }
        }
    }
}

@MainActor
final class UrsusAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

private struct UrsusWindowSurface<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        content
            .tint(ursusMutedControlTint)
            .background(UrsusInitialFirstResponderResetView())
            .background(
                ursusPageBackgroundColor
                    .ignoresSafeArea()
            )
    }
}

private struct UrsusInitialFirstResponderResetView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        UrsusInitialFirstResponderResetNSView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private final class UrsusInitialFirstResponderResetNSView: NSView {
        private var didResetInitialFirstResponder = false

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard !didResetInitialFirstResponder else {
                return
            }

            didResetInitialFirstResponder = true
            DispatchQueue.main.async { [weak self] in
                self?.window?.makeFirstResponder(nil)
            }
        }
    }
}
