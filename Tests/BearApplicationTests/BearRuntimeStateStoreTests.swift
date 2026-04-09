@testable import BearApplication
import Foundation
import Testing

@Test
func donationPromptFirstBecomesEligibleAtTwentySuccessfulOperations() async throws {
    let store = BearRuntimeStateStore(databaseURL: temporaryRuntimeStateDatabaseURL())

    _ = try await store.recordSuccessfulMCPToolOperations(19)
    let beforeThreshold = try await store.loadDonationPromptSnapshot()
    #expect(beforeThreshold.isPromptEligible == false)
    #expect(beforeThreshold.totalSuccessfulOperationCount == 19)
    #expect(beforeThreshold.shouldShowSupportAffordance == false)

    let atThreshold = try await store.recordSuccessfulMCPToolOperations(1)
    #expect(atThreshold.totalSuccessfulOperationCount == 20)
    #expect(atThreshold.nextPromptOperationCount == 20)
    #expect(atThreshold.isPromptEligible == true)
    #expect(atThreshold.shouldShowSupportAffordance == true)
}

@Test
func donationPromptNotNowRepromptsAfterFiftyAdditionalOperations() async throws {
    let store = BearRuntimeStateStore(databaseURL: temporaryRuntimeStateDatabaseURL())

    _ = try await store.recordSuccessfulMCPToolOperations(20)
    let snoozed = try await store.recordDonationPromptAction(.notNow)
    #expect(snoozed.isPromptEligible == false)
    #expect(snoozed.nextPromptOperationCount == 70)
    #expect(snoozed.shouldShowSupportAffordance == true)

    _ = try await store.recordSuccessfulMCPToolOperations(49)
    let beforeReprompt = try await store.loadDonationPromptSnapshot()
    #expect(beforeReprompt.totalSuccessfulOperationCount == 69)
    #expect(beforeReprompt.isPromptEligible == false)

    let reprompted = try await store.recordSuccessfulMCPToolOperations(1)
    #expect(reprompted.totalSuccessfulOperationCount == 70)
    #expect(reprompted.isPromptEligible == true)
}

@Test
func donationPromptPermanentlySuppressesAfterDontAskAgain() async throws {
    let store = BearRuntimeStateStore(databaseURL: temporaryRuntimeStateDatabaseURL())

    _ = try await store.recordSuccessfulMCPToolOperations(20)
    let suppressed = try await store.recordDonationPromptAction(.dontAskAgain)
    #expect(suppressed.permanentSuppressionReason == .dontAskAgain)
    #expect(suppressed.isPromptEligible == false)
    #expect(suppressed.shouldShowSupportAffordance == false)

    let afterMoreUsage = try await store.recordSuccessfulMCPToolOperations(500)
    #expect(afterMoreUsage.permanentSuppressionReason == .dontAskAgain)
    #expect(afterMoreUsage.isPromptEligible == false)
    #expect(afterMoreUsage.shouldShowSupportAffordance == false)
}

@Test
func donationPromptPermanentlySuppressesAfterDonationAction() async throws {
    let store = BearRuntimeStateStore(databaseURL: temporaryRuntimeStateDatabaseURL())

    _ = try await store.recordSuccessfulMCPToolOperations(20)
    let donated = try await store.recordDonationPromptAction(.donated)
    #expect(donated.permanentSuppressionReason == .donated)
    #expect(donated.isPromptEligible == false)
    #expect(donated.shouldShowSupportAffordance == false)

    let afterMoreUsage = try await store.recordSuccessfulMCPToolOperations(500)
    #expect(afterMoreUsage.permanentSuppressionReason == .donated)
    #expect(afterMoreUsage.isPromptEligible == false)
    #expect(afterMoreUsage.shouldShowSupportAffordance == false)
}

#if DEBUG
@Test
func debugDonationHelpersCanTriggerEligibilityAndResetState() async throws {
    let store = BearRuntimeStateStore(databaseURL: temporaryRuntimeStateDatabaseURL())

    _ = try await store.recordSuccessfulMCPToolOperations(4)
    let eligible = try await store.debugMarkDonationPromptEligible()
    #expect(eligible.totalSuccessfulOperationCount == 20)
    #expect(eligible.nextPromptOperationCount == 20)
    #expect(eligible.isPromptEligible == true)
    #expect(eligible.permanentSuppressionReason == nil)

    let reset = try await store.debugResetDonationPromptState()
    #expect(reset.totalSuccessfulOperationCount == 0)
    #expect(reset.nextPromptOperationCount == 20)
    #expect(reset.isPromptEligible == false)
    #expect(reset.permanentSuppressionReason == nil)
}
#endif

private func temporaryRuntimeStateDatabaseURL() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString, isDirectory: true)
        .appendingPathComponent("runtime-state.sqlite", isDirectory: false)
}
