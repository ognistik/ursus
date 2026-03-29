import AppKit
import BearCore
import BearXCallback
import Foundation

@main
struct BearSelectedNoteHelperEntry {
    @MainActor
    static func main() {
        let app = NSApplication.shared
        let delegate = BearSelectedNoteHelperAppDelegate()
        app.setActivationPolicy(.prohibited)
        app.delegate = delegate
        withExtendedLifetime(delegate) {
            app.run()
        }
        Foundation.exit(delegate.exitCode)
    }
}

@MainActor
final class BearSelectedNoteHelperAppDelegate: NSObject, NSApplicationDelegate {
    private let callbackHost = BearSelectedNoteCallbackHost(
        requestURLAuthorizer: { requestURL in
            try BearSelectedNoteRequestAuthorizer.prepareManagedRequestURL(requestURL)
        }
    )

    fileprivate var exitCode: Int32 { callbackHost.exitCode }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSAppleEventManager.shared().setEventHandler(
            self,
            andSelector: #selector(handleURLAppleEvent(_:withReplyEvent:)),
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )

        callbackHost.start(arguments: CommandLine.arguments)
    }

    func applicationWillTerminate(_ notification: Notification) {
        NSAppleEventManager.shared().removeEventHandler(
            forEventClass: AEEventClass(kInternetEventClass),
            andEventID: AEEventID(kAEGetURL)
        )
    }

    @objc
    private func handleURLAppleEvent(_ event: NSAppleEventDescriptor, withReplyEvent replyEvent: NSAppleEventDescriptor) {
        callbackHost.handleAppleEvent(event)
    }
}
