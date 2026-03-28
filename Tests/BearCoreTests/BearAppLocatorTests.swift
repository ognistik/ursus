import BearCore
import Foundation
import Testing

@Test
func appLocatorGuidanceMarksSystemApplicationsAsPreferred() {
    #expect(BearMCPAppLocator.preferredAppBundleURL.path == "/Applications/Bear MCP.app")
    #expect(BearMCPAppLocator.installGuidance.contains("`/Applications/Bear MCP.app` (preferred)"))
    #expect(
        BearMCPAppLocator.installationLocationDescription(
            forAppBundleURL: BearMCPAppLocator.preferredAppBundleURL
        ) == "preferred install location"
    )
}

@Test
func appLocatorGuidanceMarksUserApplicationsAsSupportedUserSpecificLocation() {
    #expect(
        BearMCPAppLocator.installationLocationDescription(
            forAppBundleURL: BearMCPAppLocator.userSpecificAppBundleURL
        ) == "supported user-specific install location"
    )
    #expect(
        BearSelectedNoteHelperLocator.installationLocationDescription(
            forAppBundleURL: BearSelectedNoteHelperLocator.userSpecificAppBundleURL
        ) == "supported user-specific install location"
    )
}
