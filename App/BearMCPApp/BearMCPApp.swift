import AppKit
import BearApplication
import SwiftUI

@main
struct BearMCPApp: App {
    @NSApplicationDelegateAdaptor(BearMCPAppDelegate.self) private var appDelegate
    @StateObject private var model = BearMCPAppModel()

    var body: some Scene {
        WindowGroup {
            if model.runsHeadlessCallbackHost {
                BearMCPHeadlessCallbackView()
            } else {
                BearMCPDashboardView(model: model)
                    .frame(minWidth: 860, minHeight: 620)
            }
        }
        .defaultSize(width: 980, height: 720)

        Settings {
            if model.runsHeadlessCallbackHost {
                EmptyView()
            } else {
                BearMCPSettingsView(model: model)
                    .frame(minWidth: 560, minHeight: 520)
            }
        }
    }
}

private struct BearMCPHeadlessCallbackView: View {
    var body: some View {
        Color.clear
            .frame(width: 1, height: 1)
            .task {
                await MainActor.run {
                    for window in NSApp.windows {
                        window.orderOut(nil)
                    }
                }
            }
    }
}

@MainActor
final class BearMCPAppDelegate: NSObject, NSApplicationDelegate {
    private let callbackHost = BearSelectedNoteAppHost()

    func applicationWillFinishLaunching(_ notification: Notification) {
        callbackHost.configureApplication()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLAppleEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        callbackHost.start()
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        !BearSelectedNoteAppHost.shouldRunHeadless()
    }

    @objc
    private func handleURLAppleEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        guard
            let rawURL = event.paramDescriptor(forKeyword: AEKeyword(keyDirectObject))?.stringValue,
            let url = URL(string: rawURL)
        else {
            return
        }

        if callbackHost.handleIncomingURL(url) {
            return
        }

        NotificationCenter.default.post(name: .bearMCPDidReceiveIncomingCallbackURL, object: url)
    }
}
