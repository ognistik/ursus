import BearApplication
import BearCore
import Foundation
import Testing

@Test
func bridgeAuthStorePrepareStorage() throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = tempRoot
        .appendingPathComponent("Auth", isDirectory: true)
        .appendingPathComponent("bridge-auth.sqlite", isDirectory: false)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let snapshot = try BearBridgeAuthStore.prepareStorage(databaseURL: databaseURL)

    #expect(fileManager.fileExists(atPath: databaseURL.path))
    #expect(snapshot.storagePath == databaseURL.path)
    #expect(snapshot.storageReady == true)
    #expect(snapshot.registeredClientCount == 0)
    #expect(snapshot.activeGrantCount == 0)
    #expect(snapshot.pendingAuthorizationRequestCount == 0)
    #expect(snapshot.activeAuthorizationCodeCount == 0)
    #expect(snapshot.activeRefreshTokenCount == 0)
    #expect(snapshot.activeAccessTokenCount == 0)
    #expect(snapshot.revocationCount == 0)
}

@Test
func bridgeAuthStorePersistence() async throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = tempRoot
        .appendingPathComponent("Auth", isDirectory: true)
        .appendingPathComponent("bridge-auth.sqlite", isDirectory: false)
    let fixedNow = Date(timeIntervalSince1970: 1_744_000_000)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let store = BearBridgeAuthStore(
        databaseURL: databaseURL,
        now: { fixedNow }
    )

    let client = try await store.registerClient(
        BearBridgeAuthClientDraft(
            displayName: "ChatGPT",
            redirectURIs: ["https://example.com/callback"],
            metadataJSON: #"{"client_name":"ChatGPT"}"#
        )
    )
    let grant = try await store.createGrant(
        BearBridgeAuthGrantDraft(
            clientID: client.id,
            scope: "tools:read tools:call",
            resource: "https://bridge.example/mcp"
        )
    )
    _ = try await store.createPendingAuthorizationRequest(
        BearBridgePendingAuthorizationRequestDraft(
            clientID: client.id,
            grantID: grant.id,
            requestedScope: grant.scope,
            redirectURI: "https://example.com/callback",
            state: "state-1",
            codeChallenge: "challenge-1",
            codeChallengeMethod: "S256",
            expiresAt: fixedNow.addingTimeInterval(300)
        )
    )
    let authCode = try await store.issueAuthorizationCode(
        BearBridgeAuthorizationCodeDraft(
            clientID: client.id,
            grantID: grant.id,
            scope: grant.scope,
            redirectURI: "https://example.com/callback",
            codeChallenge: "challenge-1",
            codeChallengeMethod: "S256",
            expiresAt: fixedNow.addingTimeInterval(300)
        )
    )
    let refreshToken = try await store.issueRefreshToken(
        BearBridgeRefreshTokenDraft(
            clientID: client.id,
            grantID: grant.id,
            scope: grant.scope,
            expiresAt: fixedNow.addingTimeInterval(86_400)
        )
    )
    let accessToken = try await store.issueAccessToken(
        BearBridgeAccessTokenDraft(
            clientID: client.id,
            grantID: grant.id,
            refreshTokenID: refreshToken.record.id,
            scope: grant.scope,
            expiresAt: fixedNow.addingTimeInterval(3_600)
        )
    )
    _ = try await store.revokeAccessToken(rawToken: accessToken.token, clientID: client.id, reason: "test")

    let reopenedStore = BearBridgeAuthStore(
        databaseURL: databaseURL,
        now: { fixedNow }
    )
    let snapshot = try await reopenedStore.snapshot(prepareIfMissing: false)

    #expect(snapshot.storageReady == true)
    #expect(snapshot.registeredClientCount == 1)
    #expect(snapshot.activeGrantCount == 1)
    #expect(snapshot.pendingAuthorizationRequestCount == 1)
    #expect(snapshot.activeAuthorizationCodeCount == 1)
    #expect(snapshot.activeRefreshTokenCount == 1)
    #expect(snapshot.activeAccessTokenCount == 0)
    #expect(snapshot.revocationCount == 1)
    #expect(try await reopenedStore.client(id: client.id)?.displayName == "ChatGPT")
    #expect(try await reopenedStore.grant(id: grant.id)?.scope == "tools:read tools:call")
    #expect(try await reopenedStore.authorizationCode(for: authCode.code)?.id == authCode.record.id)
    #expect(try await reopenedStore.refreshToken(for: refreshToken.token)?.id == refreshToken.record.id)
    #expect(try await reopenedStore.accessToken(for: accessToken.token) == nil)
}

@Test
func bridgeAuthStoreReviewSnapshotAndGrantRevocation() async throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = tempRoot
        .appendingPathComponent("Auth", isDirectory: true)
        .appendingPathComponent("bridge-auth.sqlite", isDirectory: false)
    let fixedNow = Date(timeIntervalSince1970: 1_744_000_000)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let store = BearBridgeAuthStore(
        databaseURL: databaseURL,
        now: { fixedNow }
    )

    let client = try await store.registerClient(
        BearBridgeAuthClientDraft(
            displayName: "Review Client",
            redirectURIs: ["https://example.com/callback"]
        )
    )
    let grant = try await store.createGrant(
        BearBridgeAuthGrantDraft(
            clientID: client.id,
            scope: "mcp",
            resource: "https://bridge.example/mcp"
        )
    )
    let pendingRequest = try await store.createPendingAuthorizationRequest(
        BearBridgePendingAuthorizationRequestDraft(
            clientID: client.id,
            requestedScope: "mcp",
            redirectURI: "https://example.com/callback",
            expiresAt: fixedNow.addingTimeInterval(300),
            metadataJSON: #"{"resource":"https://bridge.example/mcp"}"#
        )
    )

    let reviewSnapshot = try await store.reviewSnapshot(prepareIfMissing: false)
    #expect(reviewSnapshot.storageReady == true)
    #expect(reviewSnapshot.pendingRequests.count == 1)
    #expect(reviewSnapshot.pendingRequests.first?.clientDisplayName == "Review Client")
    #expect(reviewSnapshot.pendingRequests.first?.resource == "https://bridge.example/mcp")
    #expect(reviewSnapshot.activeGrants.count == 1)
    #expect(reviewSnapshot.activeGrants.first?.clientDisplayName == "Review Client")

    _ = try await store.revokeGrant(id: grant.id)
    let revokedReviewSnapshot = try await store.reviewSnapshot(prepareIfMissing: false)
    #expect(revokedReviewSnapshot.pendingRequests.count == 1)
    #expect(revokedReviewSnapshot.activeGrants.isEmpty)

    let loadedPendingRequest = try await store.pendingAuthorizationRequest(id: pendingRequest.request.id)
    #expect(loadedPendingRequest?.status == .pending)
}

@Test
func bridgeAuthStoreResolvesBrowserFirstPendingRequests() async throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = tempRoot
        .appendingPathComponent("Auth", isDirectory: true)
        .appendingPathComponent("bridge-auth.sqlite", isDirectory: false)
    let fixedNow = Date(timeIntervalSince1970: 1_744_000_000)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let store = BearBridgeAuthStore(
        databaseURL: databaseURL,
        now: { fixedNow }
    )

    let client = try await store.registerClient(
        BearBridgeAuthClientDraft(
            displayName: "Approval Client",
            redirectURIs: ["https://example.com/callback"]
        )
    )
    let approvableRequest = try await store.createPendingAuthorizationRequest(
        BearBridgePendingAuthorizationRequestDraft(
            clientID: client.id,
            requestedScope: "mcp",
            redirectURI: "https://example.com/callback",
            expiresAt: fixedNow.addingTimeInterval(300),
            metadataJSON: #"{"resource":"https://bridge.example/mcp"}"#
        )
    )
    let deniableRequest = try await store.createPendingAuthorizationRequest(
        BearBridgePendingAuthorizationRequestDraft(
            clientID: client.id,
            requestedScope: "mcp",
            redirectURI: "https://example.com/callback",
            state: "state-2",
            expiresAt: fixedNow.addingTimeInterval(300),
            metadataJSON: #"{"resource":"https://bridge.example/mcp"}"#
        )
    )

    let approvedRequest = try await store.resolvePendingAuthorizationDecision(
        id: approvableRequest.request.id,
        decision: .approve,
        decisionToken: approvableRequest.decisionToken,
        authorizationCodeLifetime: 300
    )
    let deniedRequest = try await store.resolvePendingAuthorizationDecision(
        id: deniableRequest.request.id,
        decision: .deny,
        decisionToken: deniableRequest.decisionToken,
        authorizationCodeLifetime: 300
    )

    #expect(approvedRequest.outcome == .approved)
    #expect(approvedRequest.request?.status == .completed)
    #expect(approvedRequest.authorizationCode?.isEmpty == false)
    #expect(deniedRequest.outcome == .denied)
    #expect(deniedRequest.request?.status == .denied)
    #expect(try await store.activeGrant(clientID: client.id, scope: "mcp", resource: "https://bridge.example/mcp") != nil)

    let reviewSnapshot = try await store.reviewSnapshot(prepareIfMissing: false)
    #expect(reviewSnapshot.pendingRequests.isEmpty)
    #expect(reviewSnapshot.activeGrants.count == 1)
}

@Test
func bridgeAuthStoreRejectsInvalidOrReusedDecisionTokens() async throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = tempRoot
        .appendingPathComponent("Auth", isDirectory: true)
        .appendingPathComponent("bridge-auth.sqlite", isDirectory: false)
    let fixedNow = Date(timeIntervalSince1970: 1_744_000_000)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let store = BearBridgeAuthStore(
        databaseURL: databaseURL,
        now: { fixedNow }
    )

    let client = try await store.registerClient(
        BearBridgeAuthClientDraft(
            displayName: "Decision Client",
            redirectURIs: ["https://example.com/callback"]
        )
    )
    let request = try await store.createPendingAuthorizationRequest(
        BearBridgePendingAuthorizationRequestDraft(
            clientID: client.id,
            requestedScope: "mcp",
            redirectURI: "https://example.com/callback",
            expiresAt: fixedNow.addingTimeInterval(300),
            metadataJSON: #"{"resource":"https://bridge.example/mcp"}"#
        )
    )

    let invalidDecision = try await store.resolvePendingAuthorizationDecision(
        id: request.request.id,
        decision: .approve,
        decisionToken: "udt_invalid",
        authorizationCodeLifetime: 300
    )
    #expect(invalidDecision.outcome == .invalidDecisionToken)
    #expect(try await store.activeGrant(clientID: client.id, scope: "mcp", resource: "https://bridge.example/mcp") == nil)

    let firstApproval = try await store.resolvePendingAuthorizationDecision(
        id: request.request.id,
        decision: .approve,
        decisionToken: request.decisionToken,
        authorizationCodeLifetime: 300
    )
    let secondApproval = try await store.resolvePendingAuthorizationDecision(
        id: request.request.id,
        decision: .approve,
        decisionToken: request.decisionToken,
        authorizationCodeLifetime: 300
    )

    #expect(firstApproval.outcome == .approved)
    #expect(secondApproval.outcome == .alreadyResolved)
    #expect(secondApproval.request?.status == .completed)
}

@Test
func bridgeAuthStoreValidatesAccessTokenResourceAndScope() async throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let databaseURL = tempRoot
        .appendingPathComponent("Auth", isDirectory: true)
        .appendingPathComponent("bridge-auth.sqlite", isDirectory: false)
    let fixedNow = Date(timeIntervalSince1970: 1_744_000_000)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let store = BearBridgeAuthStore(
        databaseURL: databaseURL,
        now: { fixedNow }
    )

    let client = try await store.registerClient(
        BearBridgeAuthClientDraft(
            displayName: "Access Client",
            redirectURIs: ["https://example.com/callback"]
        )
    )
    let grant = try await store.createGrant(
        BearBridgeAuthGrantDraft(
            clientID: client.id,
            scope: "mcp notes:read",
            resource: "https://bridge.example/mcp"
        )
    )
    let refreshToken = try await store.issueRefreshToken(
        BearBridgeRefreshTokenDraft(
            clientID: client.id,
            grantID: grant.id,
            scope: grant.scope,
            expiresAt: fixedNow.addingTimeInterval(86_400),
            metadataJSON: #"{"resource":"https://bridge.example/mcp"}"#
        )
    )
    let accessToken = try await store.issueAccessToken(
        BearBridgeAccessTokenDraft(
            clientID: client.id,
            grantID: grant.id,
            refreshTokenID: refreshToken.record.id,
            scope: grant.scope,
            expiresAt: fixedNow.addingTimeInterval(3_600),
            metadataJSON: #"{"resource":"https://bridge.example/mcp"}"#
        )
    )

    #expect(
        try await store.validatedAccessToken(
            rawToken: accessToken.token,
            resource: "https://bridge.example/mcp",
            requiredScopes: ["mcp"]
        )?.id == accessToken.record.id
    )
    #expect(
        try await store.validatedAccessToken(
            rawToken: accessToken.token,
            resource: "https://other.example/mcp",
            requiredScopes: ["mcp"]
        ) == nil
    )
    #expect(
        try await store.validatedAccessToken(
            rawToken: accessToken.token,
            resource: "https://bridge.example/mcp",
            requiredScopes: ["tools:call"]
        ) == nil
    )
}

@Test
func bridgeSnapshotAuthCounts() async throws {
    let fileManager = FileManager.default
    let tempRoot = fileManager.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
    let bridgeRuntimeStateURL = tempRoot.appendingPathComponent("Runtime/bridge-runtime-state.json", isDirectory: false)
    let launchAgentPlistURL = tempRoot.appendingPathComponent("LaunchAgents/com.aft.ursus.plist", isDirectory: false)
    let standardOutputURL = tempRoot.appendingPathComponent("Logs/bridge.stdout.log", isDirectory: false)
    let standardErrorURL = tempRoot.appendingPathComponent("Logs/bridge.stderr.log", isDirectory: false)
    let authDatabaseURL = tempRoot.appendingPathComponent("Auth/bridge-auth.sqlite", isDirectory: false)
    let fixedNow = Date(timeIntervalSince1970: 1_744_000_000)
    defer {
        try? fileManager.removeItem(at: tempRoot)
    }

    let store = BearBridgeAuthStore(
        databaseURL: authDatabaseURL,
        now: { fixedNow }
    )
    let client = try await store.registerClient(
        BearBridgeAuthClientDraft(
            displayName: "Remote host",
            redirectURIs: ["https://example.com/callback"]
        )
    )
    let grant = try await store.createGrant(
        BearBridgeAuthGrantDraft(
            clientID: client.id,
            scope: "tools:call"
        )
    )
    _ = try await store.createPendingAuthorizationRequest(
        BearBridgePendingAuthorizationRequestDraft(
            clientID: client.id,
            grantID: grant.id,
            requestedScope: "tools:call",
            redirectURI: "https://example.com/callback",
            expiresAt: fixedNow.addingTimeInterval(300)
        )
    )

    let configuration = BearConfiguration.default.updatingBridge(
        BearBridgeConfiguration(
            enabled: true,
            host: "127.0.0.1",
            port: 6190,
            authMode: .oauth
        )
    )

    let snapshot = BearAppSupport.bridgeSnapshot(
        configuration: configuration,
        selectedNoteTokenConfigured: false,
        fileManager: fileManager,
        launchAgentPlistURL: launchAgentPlistURL,
        standardOutputURL: standardOutputURL,
        standardErrorURL: standardErrorURL,
        bridgeRuntimeStateURL: bridgeRuntimeStateURL,
        bridgeAuthDatabaseURL: authDatabaseURL,
        launchctlRunner: { _ in
            BearProcessExecutionResult(exitCode: 0, stdout: "", stderr: "")
        },
        endpointProbe: { _, _ in
            BearBridgeEndpointProbeResult(reachable: false, transportReachable: false, protocolCompatible: false)
        }
    )

    #expect(snapshot.requiresOAuth == true)
    #expect(snapshot.auth.storageReady == true)
    #expect(snapshot.auth.storagePath == authDatabaseURL.path)
    #expect(snapshot.auth.registeredClientCount == 1)
    #expect(snapshot.auth.activeGrantCount == 1)
    #expect(snapshot.auth.pendingAuthorizationRequestCount == 1)
    #expect(snapshot.authStateSummary == "OAuth ready. 1 remembered grant.")
}
