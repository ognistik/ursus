import BearApplication
import BearCore
import Foundation
import MCP

struct BearBridgeOAuthServer {
    struct Configuration: Sendable {
        var host: String
        var port: Int
        var mcpEndpoint: String
        var authDatabaseURL: URL
        var supportedScopes: [String]
        var protectedResourceScope: String
        var authorizationCodeLifetime: TimeInterval
        var accessTokenLifetime: TimeInterval
        var refreshTokenLifetime: TimeInterval
        var pendingRequestLifetime: TimeInterval

        init(
            host: String,
            port: Int,
            mcpEndpoint: String,
            authDatabaseURL: URL,
            supportedScopes: [String] = ["mcp"],
            protectedResourceScope: String = "mcp",
            authorizationCodeLifetime: TimeInterval = 300,
            accessTokenLifetime: TimeInterval = 3_600,
            refreshTokenLifetime: TimeInterval = 30 * 24 * 3_600,
            pendingRequestLifetime: TimeInterval = 300
        ) {
            self.host = host
            self.port = port
            self.mcpEndpoint = mcpEndpoint
            self.authDatabaseURL = authDatabaseURL
            self.supportedScopes = supportedScopes
            self.protectedResourceScope = protectedResourceScope
            self.authorizationCodeLifetime = authorizationCodeLifetime
            self.accessTokenLifetime = accessTokenLifetime
            self.refreshTokenLifetime = refreshTokenLifetime
            self.pendingRequestLifetime = pendingRequestLifetime
        }
    }

    private let configuration: Configuration
    private let store: BearBridgeAuthStore
    private let now: @Sendable () -> Date

    init(
        configuration: Configuration,
        store: BearBridgeAuthStore? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.configuration = configuration
        self.store = store ?? BearBridgeAuthStore(
            databaseURL: configuration.authDatabaseURL,
            now: now
        )
        self.now = now
    }

    func handle(request: HTTPRequest) async -> BearBridgeHTTPApplication.BridgeHTTPResponse {
        switch BearBridgeHTTPApplication.route(
            for: request.path,
            mcpEndpoint: configuration.mcpEndpoint
        ) {
        case .oauthProtectedResourceMetadata:
            return protectedResourceMetadataResponse(for: request)
        case .oauthAuthorizationServerMetadata:
            return authorizationServerMetadataResponse(for: request)
        case .oauthRegister:
            return await dynamicClientRegistrationResponse(for: request)
        case .oauthAuthorize:
            return await authorizationResponse(for: request)
        case .oauthDecision:
            return await authorizationDecisionResponse(for: request)
        case .oauthToken:
            return await tokenResponse(for: request)
        case .mcp, .notFound:
            return BearBridgeHTTPApplication.notFoundResponse()
        }
    }

    func hasAuthorizedMCPAccess(for request: HTTPRequest) async throws -> Bool {
        guard let accessToken = BearBridgeHTTPApplication.bearerToken(
            from: request.header(HTTPHeaderName.authorization)
        ) else {
            return false
        }

        let resource = endpointContext(for: request).resourceURL.absoluteString
        return try await store.validatedAccessToken(
            rawToken: accessToken,
            resource: resource,
            requiredScopes: [configuration.protectedResourceScope]
        ) != nil
    }
}

extension BearBridgeOAuthServer {
    static func originURL(
        hostHeader: String?,
        fallbackHost: String,
        fallbackPort: Int
    ) -> URL {
        let trimmedHost = hostHeader?
            .split(separator: ",", omittingEmptySubsequences: true)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let authority = (trimmedHost?.isEmpty == false)
            ? String(trimmedHost!)
            : "\(fallbackHost):\(fallbackPort)"
        let candidate = URL(string: "http://\(authority)")
        let host = candidate?.host ?? fallbackHost
        let scheme = isLoopbackHost(host) ? "http" : "https"
        let defaultPort = defaultPort(for: scheme)
        let port: Int
        if let explicitPort = candidate?.port {
            if !isLoopbackHost(host),
               isLoopbackHost(fallbackHost),
               explicitPort == fallbackPort
            {
                port = defaultPort
            } else {
                port = explicitPort
            }
        } else if isLoopbackHost(host) {
            port = fallbackPort
        } else {
            port = defaultPort
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if port != defaultPort
        {
            components.port = port
        }
        components.path = ""
        return components.url ?? URL(string: "\(scheme)://\(host)")!
    }

    static func isLoopbackHost(_ host: String) -> Bool {
        let normalized = host
            .trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .lowercased()
        return normalized == "localhost"
            || normalized == "127.0.0.1"
            || normalized == "::1"
            || BearBridgeConfiguration.isSupportedHost(normalized)
    }

    static func defaultPort(for scheme: String) -> Int {
        scheme.caseInsensitiveCompare("http") == .orderedSame ? 80 : 443
    }
}

private extension BearBridgeOAuthServer {
    struct AuthorizationServerMetadata: Encodable {
        let issuer: String
        let authorizationEndpoint: String
        let tokenEndpoint: String
        let registrationEndpoint: String
        let responseTypesSupported: [String]
        let grantTypesSupported: [String]
        let tokenEndpointAuthMethodsSupported: [String]
        let codeChallengeMethodsSupported: [String]
        let scopesSupported: [String]
        let protectedResources: [String]

        enum CodingKeys: String, CodingKey {
            case issuer
            case authorizationEndpoint = "authorization_endpoint"
            case tokenEndpoint = "token_endpoint"
            case registrationEndpoint = "registration_endpoint"
            case responseTypesSupported = "response_types_supported"
            case grantTypesSupported = "grant_types_supported"
            case tokenEndpointAuthMethodsSupported = "token_endpoint_auth_methods_supported"
            case codeChallengeMethodsSupported = "code_challenge_methods_supported"
            case scopesSupported = "scopes_supported"
            case protectedResources = "protected_resources"
        }
    }

    struct DynamicClientRegistrationRequest: Decodable {
        let redirectURIs: [String]
        let clientName: String?
        let grantTypes: [String]?
        let responseTypes: [String]?
        let tokenEndpointAuthMethod: String?

        enum CodingKeys: String, CodingKey {
            case redirectURIs = "redirect_uris"
            case clientName = "client_name"
            case grantTypes = "grant_types"
            case responseTypes = "response_types"
            case tokenEndpointAuthMethod = "token_endpoint_auth_method"
        }
    }

    struct DynamicClientRegistrationResponse: Encodable {
        let clientID: String
        let clientIDIssuedAt: Int
        let redirectURIs: [String]
        let clientName: String?
        let grantTypes: [String]
        let responseTypes: [String]
        let tokenEndpointAuthMethod: String

        enum CodingKeys: String, CodingKey {
            case clientID = "client_id"
            case clientIDIssuedAt = "client_id_issued_at"
            case redirectURIs = "redirect_uris"
            case clientName = "client_name"
            case grantTypes = "grant_types"
            case responseTypes = "response_types"
            case tokenEndpointAuthMethod = "token_endpoint_auth_method"
        }
    }

    struct OAuthErrorPayload: Encodable {
        let error: String
        let errorDescription: String?

        enum CodingKeys: String, CodingKey {
            case error
            case errorDescription = "error_description"
        }
    }

    struct TokenResponsePayload: Encodable {
        let accessToken: String
        let tokenType: String
        let expiresIn: Int
        let refreshToken: String
        let scope: String

        enum CodingKeys: String, CodingKey {
            case accessToken = "access_token"
            case tokenType = "token_type"
            case expiresIn = "expires_in"
            case refreshToken = "refresh_token"
            case scope
        }
    }

    func protectedResourceMetadataResponse(
        for request: HTTPRequest
    ) -> BearBridgeHTTPApplication.BridgeHTTPResponse {
        guard request.method.caseInsensitiveCompare("GET") == .orderedSame else {
            return methodNotAllowedResponse(allowing: ["GET"])
        }

        let context = endpointContext(for: request)
        let metadata = OAuthProtectedResourceServerMetadata(
            resource: context.resourceURL.absoluteString,
            authorizationServers: [context.issuerURL],
            scopesSupported: configuration.supportedScopes
        )
        return jsonResponse(metadata)
    }

    func authorizationServerMetadataResponse(
        for request: HTTPRequest
    ) -> BearBridgeHTTPApplication.BridgeHTTPResponse {
        guard request.method.caseInsensitiveCompare("GET") == .orderedSame else {
            return methodNotAllowedResponse(allowing: ["GET"])
        }

        let context = endpointContext(for: request)
        if let resource = queryParameters(from: request)["resource"],
           resource != context.resourceURL.absoluteString
        {
            return oauthErrorResponse(
                statusCode: 400,
                error: "invalid_target",
                description: "The requested resource is not served by this authorization server."
            )
        }

        let metadata = AuthorizationServerMetadata(
            issuer: context.issuerURL.absoluteString,
            authorizationEndpoint: context.authorizationEndpointURL.absoluteString,
            tokenEndpoint: context.tokenEndpointURL.absoluteString,
            registrationEndpoint: context.registrationEndpointURL.absoluteString,
            responseTypesSupported: ["code"],
            grantTypesSupported: ["authorization_code", "refresh_token"],
            tokenEndpointAuthMethodsSupported: ["none"],
            codeChallengeMethodsSupported: ["S256"],
            scopesSupported: configuration.supportedScopes,
            protectedResources: [context.resourceURL.absoluteString]
        )
        return jsonResponse(metadata)
    }

    func dynamicClientRegistrationResponse(
        for request: HTTPRequest
    ) async -> BearBridgeHTTPApplication.BridgeHTTPResponse {
        guard request.method.caseInsensitiveCompare("POST") == .orderedSame else {
            return methodNotAllowedResponse(allowing: ["POST"])
        }

        guard let body = request.body, !body.isEmpty else {
            return oauthErrorResponse(
                statusCode: 400,
                error: "invalid_client_metadata",
                description: "Dynamic client registration requires a JSON body."
            )
        }

        do {
            let registrationRequest = try JSONDecoder().decode(
                DynamicClientRegistrationRequest.self,
                from: body
            )
            try validateRegistrationRequest(registrationRequest)
            let metadataJSON = String(decoding: body, as: UTF8.self)
            let client = try await store.registerClient(
                BearBridgeAuthClientDraft(
                    displayName: registrationRequest.clientName,
                    redirectURIs: registrationRequest.redirectURIs,
                    metadataJSON: metadataJSON
                )
            )

            let response = DynamicClientRegistrationResponse(
                clientID: client.id,
                clientIDIssuedAt: Int(client.createdAt.timeIntervalSince1970),
                redirectURIs: client.redirectURIs,
                clientName: client.displayName,
                grantTypes: ["authorization_code", "refresh_token"],
                responseTypes: ["code"],
                tokenEndpointAuthMethod: "none"
            )
            return jsonResponse(response, statusCode: 201)
        } catch let error as BearError {
            return oauthErrorResponse(
                statusCode: 400,
                error: "invalid_client_metadata",
                description: error.localizedDescription
            )
        } catch {
            return oauthErrorResponse(
                statusCode: 400,
                error: "invalid_client_metadata",
                description: "Dynamic client registration payload could not be decoded."
            )
        }
    }

    func authorizationResponse(
        for request: HTTPRequest
    ) async -> BearBridgeHTTPApplication.BridgeHTTPResponse {
        guard request.method.caseInsensitiveCompare("GET") == .orderedSame else {
            return methodNotAllowedResponse(allowing: ["GET"])
        }

        let parameters = queryParameters(from: request)
        let context = endpointContext(for: request)

        guard parameters["response_type"] == "code" else {
            return oauthErrorResponse(
                statusCode: 400,
                error: "unsupported_response_type",
                description: "Only response_type=code is supported."
            )
        }

        guard let clientID = nonEmptyValue(parameters["client_id"]) else {
            return oauthErrorResponse(
                statusCode: 400,
                error: "invalid_request",
                description: "Authorization requests require client_id."
            )
        }

        let client: BearBridgeAuthClient
        do {
            guard let loadedClient = try await store.client(id: clientID) else {
                return oauthErrorResponse(
                    statusCode: 400,
                    error: "invalid_client",
                    description: "Unknown OAuth client_id."
                )
            }
            client = loadedClient
        } catch {
            return oauthErrorResponse(
                statusCode: 500,
                error: "server_error",
                description: "Failed to load OAuth client registration."
            )
        }

        guard let redirectURI = nonEmptyValue(parameters["redirect_uri"]) else {
            return oauthErrorResponse(
                statusCode: 400,
                error: "invalid_request",
                description: "Authorization requests require redirect_uri."
            )
        }

        guard client.redirectURIs.contains(redirectURI) else {
            return oauthErrorResponse(
                statusCode: 400,
                error: "invalid_request",
                description: "redirect_uri must exactly match a registered redirect URI."
            )
        }

        let state = nonEmptyValue(parameters["state"])
        guard let codeChallenge = nonEmptyValue(parameters["code_challenge"]) else {
            return redirectErrorResponse(
                redirectURI: redirectURI,
                state: state,
                error: "invalid_request",
                description: "Authorization requests require code_challenge."
            )
        }
        guard parameters["code_challenge_method"]?.caseInsensitiveCompare("S256") == .orderedSame else {
            return redirectErrorResponse(
                redirectURI: redirectURI,
                state: state,
                error: "invalid_request",
                description: "Only PKCE S256 is supported."
            )
        }

        if let resource = nonEmptyValue(parameters["resource"]),
           resource != context.resourceURL.absoluteString
        {
            return redirectErrorResponse(
                redirectURI: redirectURI,
                state: state,
                error: "invalid_target",
                description: "The requested resource is not available."
            )
        }

        let requestedScope: String
        do {
            requestedScope = try resolvedScope(
                rawValue: parameters["scope"],
                fallback: configuration.supportedScopes.joined(separator: " ")
            )
        } catch let error as BearError {
            return redirectErrorResponse(
                redirectURI: redirectURI,
                state: state,
                error: "invalid_scope",
                description: error.localizedDescription
            )
        } catch {
            return redirectErrorResponse(
                redirectURI: redirectURI,
                state: state,
                error: "invalid_scope",
                description: "The requested scope is invalid."
            )
        }

        do {
            if let existingGrant = try await store.activeGrant(
                clientID: client.id,
                scope: requestedScope,
                resource: context.resourceURL.absoluteString
            ) {
                let issuedCode = try await store.issueAuthorizationCode(
                    BearBridgeAuthorizationCodeDraft(
                        clientID: client.id,
                        grantID: existingGrant.id,
                        scope: requestedScope,
                        redirectURI: redirectURI,
                        codeChallenge: codeChallenge,
                        codeChallengeMethod: "S256",
                        expiresAt: now().addingTimeInterval(configuration.authorizationCodeLifetime)
                    )
                )
                return redirectSuccessResponse(
                    redirectURI: redirectURI,
                    code: issuedCode.code,
                    state: state
                )
            }

            let pendingRequest = try await store.createPendingAuthorizationRequest(
                BearBridgePendingAuthorizationRequestDraft(
                    clientID: client.id,
                    requestedScope: requestedScope,
                    redirectURI: redirectURI,
                    state: state,
                    codeChallenge: codeChallenge,
                    codeChallengeMethod: "S256",
                    expiresAt: now().addingTimeInterval(configuration.pendingRequestLifetime),
                    metadataJSON: metadataJSONString(
                        [
                            "client_name": client.displayName,
                            "resource": context.resourceURL.absoluteString,
                        ]
                    )
                )
            )
            return authorizationConsentResponse(
                request: pendingRequest.request,
                decisionToken: pendingRequest.decisionToken,
                clientName: client.displayName ?? client.id,
                resource: context.resourceURL.absoluteString
            )
        } catch {
            return redirectErrorResponse(
                redirectURI: redirectURI,
                state: state,
                error: "server_error",
                description: "Failed to create the local authorization grant."
            )
        }
    }

    func authorizationDecisionResponse(
        for request: HTTPRequest
    ) async -> BearBridgeHTTPApplication.BridgeHTTPResponse {
        guard request.method.caseInsensitiveCompare("POST") == .orderedSame else {
            return methodNotAllowedResponse(allowing: ["POST"])
        }

        let parameters = formParameters(from: request.body)
        guard let requestID = nonEmptyValue(parameters["request_id"]) else {
            return decisionErrorResponse(
                statusCode: 400,
                title: "Missing Authorization Request",
                message: "The browser approval form is missing its request identifier. Start the authorization again."
            )
        }
        guard let decisionValue = nonEmptyValue(parameters["decision"]),
              let decision = BearBridgePendingAuthorizationDecision(rawValue: decisionValue)
        else {
            return decisionErrorResponse(
                statusCode: 400,
                title: "Invalid Decision",
                message: "This browser approval request must be approved or denied explicitly. Start the authorization again if needed."
            )
        }
        guard let decisionToken = nonEmptyValue(parameters["decision_token"]) else {
            return decisionErrorResponse(
                statusCode: 400,
                title: "Missing Decision Token",
                message: "This browser approval form is missing its single-use decision token. Start the authorization again."
            )
        }

        do {
            let result = try await store.resolvePendingAuthorizationDecision(
                id: requestID,
                decision: decision,
                decisionToken: decisionToken,
                authorizationCodeLifetime: configuration.authorizationCodeLifetime
            )

            switch result.outcome {
            case .approved:
                guard let pendingRequest = result.request,
                      let authorizationCode = result.authorizationCode
                else {
                    return decisionErrorResponse(
                        statusCode: 500,
                        title: "Approval Failed",
                        message: "Ursus could not finish the browser approval flow. Start the authorization again."
                    )
                }
                return decisionCompletionResponse(
                    redirectURI: pendingRequest.redirectURI,
                    title: "Authorization Approved",
                    message: "Access was granted successfully. Ursus is returning to your client now.",
                    additions: [
                        URLQueryItem(name: "code", value: authorizationCode),
                        URLQueryItem(name: "state", value: pendingRequest.state),
                    ]
                )

            case .denied:
                guard let pendingRequest = result.request else {
                    return decisionErrorResponse(
                        statusCode: 500,
                        title: "Denial Failed",
                        message: "Ursus could not finish the browser denial flow. Start the authorization again."
                    )
                }
                return decisionCompletionResponse(
                    redirectURI: pendingRequest.redirectURI,
                    title: "Authorization Denied",
                    message: "Access was denied. Ursus is returning to your client now.",
                    additions: [
                        URLQueryItem(name: "error", value: "access_denied"),
                        URLQueryItem(
                            name: "error_description",
                            value: "The local owner denied this authorization request."
                        ),
                        URLQueryItem(name: "state", value: pendingRequest.state),
                    ]
                )

            case .expired:
                return decisionErrorResponse(
                    statusCode: 410,
                    title: "Authorization Expired",
                    message: "This browser approval request expired before it was completed. Start the authorization again from your client."
                )

            case .alreadyResolved:
                let message: String
                switch result.request?.status {
                case .denied:
                    message = "This browser approval request was already denied."
                case .completed:
                    message = "This browser approval request was already completed."
                case .expired:
                    message = "This browser approval request already expired."
                case .pending, .none:
                    message = "This browser approval request is no longer available."
                }
                return decisionErrorResponse(
                    statusCode: 409,
                    title: "Authorization Already Resolved",
                    message: message
                )

            case .invalidDecisionToken:
                return decisionErrorResponse(
                    statusCode: 400,
                    title: "Invalid Decision Token",
                    message: "This browser approval link is invalid or has already been used. Start the authorization again."
                )

            case .unknownRequest:
                return decisionErrorResponse(
                    statusCode: 404,
                    title: "Authorization Request Not Found",
                    message: "Ursus could not find this browser approval request. Start the authorization again."
                )
            }
        } catch {
            return decisionErrorResponse(
                statusCode: 500,
                title: "Authorization Failed",
                message: "Ursus could not process this browser approval request. Start the authorization again."
            )
        }
    }

    func tokenResponse(
        for request: HTTPRequest
    ) async -> BearBridgeHTTPApplication.BridgeHTTPResponse {
        guard request.method.caseInsensitiveCompare("POST") == .orderedSame else {
            return methodNotAllowedResponse(allowing: ["POST"])
        }

        let parameters = formParameters(from: request.body)
        let context = endpointContext(for: request)

        guard let grantType = nonEmptyValue(parameters["grant_type"]) else {
            return oauthErrorResponse(
                statusCode: 400,
                error: "invalid_request",
                description: "Token requests require grant_type."
            )
        }

        guard let clientID = nonEmptyValue(parameters["client_id"]) else {
            return oauthErrorResponse(
                statusCode: 400,
                error: "invalid_client",
                description: "Public clients must send client_id to the token endpoint."
            )
        }

        let client: BearBridgeAuthClient
        do {
            guard let loadedClient = try await store.client(id: clientID) else {
                return oauthErrorResponse(
                    statusCode: 400,
                    error: "invalid_client",
                    description: "Unknown OAuth client_id."
                )
            }
            client = loadedClient
        } catch {
            return oauthErrorResponse(
                statusCode: 500,
                error: "server_error",
                description: "Failed to load OAuth client registration."
            )
        }

        if let resource = nonEmptyValue(parameters["resource"]),
           resource != context.resourceURL.absoluteString
        {
            return oauthErrorResponse(
                statusCode: 400,
                error: "invalid_target",
                description: "The requested resource is not available."
            )
        }

        switch grantType {
        case "authorization_code":
            return await authorizationCodeTokenResponse(
                parameters: parameters,
                client: client,
                resource: context.resourceURL.absoluteString
            )

        case "refresh_token":
            return await refreshTokenResponse(
                parameters: parameters,
                client: client,
                resource: context.resourceURL.absoluteString
            )

        default:
            return oauthErrorResponse(
                statusCode: 400,
                error: "unsupported_grant_type",
                description: "Only authorization_code and refresh_token are supported."
            )
        }
    }

    func authorizationCodeTokenResponse(
        parameters: [String: String],
        client: BearBridgeAuthClient,
        resource: String
    ) async -> BearBridgeHTTPApplication.BridgeHTTPResponse {
        guard let code = nonEmptyValue(parameters["code"]),
              let redirectURI = nonEmptyValue(parameters["redirect_uri"]),
              let codeVerifier = nonEmptyValue(parameters["code_verifier"])
        else {
            return oauthErrorResponse(
                statusCode: 400,
                error: "invalid_request",
                description: "Authorization code exchanges require code, redirect_uri, and code_verifier."
            )
        }

        guard client.redirectURIs.contains(redirectURI) else {
            return oauthErrorResponse(
                statusCode: 400,
                error: "invalid_grant",
                description: "redirect_uri must exactly match the registered client redirect URI."
            )
        }

        do {
            guard let authorizationCode = try await store.authorizationCode(for: code) else {
                return oauthErrorResponse(
                    statusCode: 400,
                    error: "invalid_grant",
                    description: "The authorization code is invalid, expired, or already redeemed."
                )
            }
            guard authorizationCode.clientID == client.id else {
                return oauthErrorResponse(
                    statusCode: 400,
                    error: "invalid_grant",
                    description: "The authorization code does not belong to this client."
                )
            }
            guard authorizationCode.redirectURI == redirectURI else {
                return oauthErrorResponse(
                    statusCode: 400,
                    error: "invalid_grant",
                    description: "The authorization code redirect URI does not match."
                )
            }
            guard authorizationCode.codeChallengeMethod?.caseInsensitiveCompare("S256") == .orderedSame,
                  let expectedChallenge = authorizationCode.codeChallenge,
                  try PKCE.makeChallenge(from: codeVerifier) == expectedChallenge
            else {
                return oauthErrorResponse(
                    statusCode: 400,
                    error: "invalid_grant",
                    description: "PKCE verification failed for the authorization code."
                )
            }

            _ = try await store.markAuthorizationCodeRedeemed(id: authorizationCode.id)
            let refreshToken = try await store.issueRefreshToken(
                BearBridgeRefreshTokenDraft(
                    clientID: client.id,
                    grantID: authorizationCode.grantID,
                    scope: authorizationCode.scope,
                    expiresAt: now().addingTimeInterval(configuration.refreshTokenLifetime),
                    metadataJSON: metadataJSONString(["resource": resource])
                )
            )
            let accessToken = try await store.issueAccessToken(
                BearBridgeAccessTokenDraft(
                    clientID: client.id,
                    grantID: authorizationCode.grantID,
                    refreshTokenID: refreshToken.record.id,
                    scope: authorizationCode.scope,
                    expiresAt: now().addingTimeInterval(configuration.accessTokenLifetime),
                    metadataJSON: metadataJSONString(["resource": resource])
                )
            )
            return tokenSuccessResponse(
                accessToken: accessToken.token,
                refreshToken: refreshToken.token,
                scope: authorizationCode.scope
            )
        } catch let error as BearError {
            return oauthErrorResponse(
                statusCode: 400,
                error: "invalid_grant",
                description: error.localizedDescription
            )
        } catch {
            return oauthErrorResponse(
                statusCode: 500,
                error: "server_error",
                description: "Failed to issue bridge access tokens."
            )
        }
    }

    func refreshTokenResponse(
        parameters: [String: String],
        client: BearBridgeAuthClient,
        resource: String
    ) async -> BearBridgeHTTPApplication.BridgeHTTPResponse {
        guard let rawRefreshToken = nonEmptyValue(parameters["refresh_token"]) else {
            return oauthErrorResponse(
                statusCode: 400,
                error: "invalid_request",
                description: "Refresh token exchanges require refresh_token."
            )
        }

        do {
            guard let refreshToken = try await store.refreshToken(for: rawRefreshToken) else {
                return oauthErrorResponse(
                    statusCode: 400,
                    error: "invalid_grant",
                    description: "The refresh token is invalid, expired, or already rotated."
                )
            }
            guard refreshToken.clientID == client.id else {
                return oauthErrorResponse(
                    statusCode: 400,
                    error: "invalid_grant",
                    description: "The refresh token does not belong to this client."
                )
            }

            if let storedResource = metadataValue(named: "resource", in: refreshToken.metadataJSON),
               storedResource != resource
            {
                return oauthErrorResponse(
                    statusCode: 400,
                    error: "invalid_target",
                    description: "The refresh token does not apply to this protected resource."
                )
            }

            let scope: String
            if let requestedScope = nonEmptyValue(parameters["scope"]) {
                scope = try narrowedScope(requestedScope, within: refreshToken.scope)
            } else {
                scope = refreshToken.scope
            }

            let rotatedRefreshToken = try await store.issueRefreshToken(
                BearBridgeRefreshTokenDraft(
                    clientID: client.id,
                    grantID: refreshToken.grantID,
                    scope: scope,
                    expiresAt: now().addingTimeInterval(configuration.refreshTokenLifetime),
                    metadataJSON: metadataJSONString(["resource": resource])
                )
            )
            _ = try await store.rotateRefreshToken(
                id: refreshToken.id,
                replacedByTokenID: rotatedRefreshToken.record.id
            )
            let accessToken = try await store.issueAccessToken(
                BearBridgeAccessTokenDraft(
                    clientID: client.id,
                    grantID: refreshToken.grantID,
                    refreshTokenID: rotatedRefreshToken.record.id,
                    scope: scope,
                    expiresAt: now().addingTimeInterval(configuration.accessTokenLifetime),
                    metadataJSON: metadataJSONString(["resource": resource])
                )
            )
            return tokenSuccessResponse(
                accessToken: accessToken.token,
                refreshToken: rotatedRefreshToken.token,
                scope: scope
            )
        } catch let error as BearError {
            let oauthError = error.localizedDescription.contains("scope")
                ? "invalid_scope"
                : "invalid_grant"
            return oauthErrorResponse(
                statusCode: 400,
                error: oauthError,
                description: error.localizedDescription
            )
        } catch {
            return oauthErrorResponse(
                statusCode: 500,
                error: "server_error",
                description: "Failed to refresh bridge access tokens."
            )
        }
    }

    func validateRegistrationRequest(_ request: DynamicClientRegistrationRequest) throws {
        guard !request.redirectURIs.isEmpty else {
            throw BearError.invalidInput("Dynamic client registrations require at least one redirect URI.")
        }

        for redirectURI in request.redirectURIs {
            guard let url = URL(string: redirectURI),
                  url.scheme?.isEmpty == false,
                  url.fragment == nil
            else {
                throw BearError.invalidInput("Redirect URI `\(redirectURI)` is not a valid absolute URI.")
            }
        }

        if let tokenEndpointAuthMethod = request.tokenEndpointAuthMethod,
           tokenEndpointAuthMethod.caseInsensitiveCompare("none") != .orderedSame
        {
            throw BearError.invalidInput("Only public clients with token_endpoint_auth_method=none are supported.")
        }

        if let responseTypes = request.responseTypes,
           responseTypes.contains(where: { $0.caseInsensitiveCompare("code") != .orderedSame })
        {
            throw BearError.invalidInput("Only response_types=[\"code\"] is supported.")
        }

        if let grantTypes = request.grantTypes {
            let supportedGrantTypes = Set(["authorization_code", "refresh_token"])
            let unsupported = grantTypes.filter { !supportedGrantTypes.contains($0) }
            if !unsupported.isEmpty {
                throw BearError.invalidInput("Only authorization_code and refresh_token grant types are supported.")
            }
        }
    }

    func tokenSuccessResponse(
        accessToken: String,
        refreshToken: String,
        scope: String
    ) -> BearBridgeHTTPApplication.BridgeHTTPResponse {
        let payload = TokenResponsePayload(
            accessToken: accessToken,
            tokenType: "Bearer",
            expiresIn: Int(configuration.accessTokenLifetime),
            refreshToken: refreshToken,
            scope: scope
        )
        return jsonResponse(
            payload,
            headers: [
                "Cache-Control": "no-store",
                "Pragma": "no-cache",
            ]
        )
    }

    func authorizationConsentResponse(
        request: BearBridgePendingAuthorizationRequest,
        decisionToken: String,
        clientName: String,
        resource: String
    ) -> BearBridgeHTTPApplication.BridgeHTTPResponse {
        let escapedRequestID = htmlEscaped(request.id)
        let escapedDecisionToken = htmlEscaped(decisionToken)
        let expiryDescription =
            request.expiresAt.formatted(
                date: .abbreviated,
                time: .shortened
            )
        let body = """
        <section class="card">
          \(oauthPageHeaderHTML(title: "Approve access to Ursus"))
          <div class="meta-list">
            \(oauthMetadataRowHTML(label: "App", value: clientName))
            \(oauthMetadataRowHTML(label: "Bridge", value: resource))
            \(oauthMetadataRowHTML(label: "Expires", value: expiryDescription))
          </div>
          <p class="message">Approving lets this app connect to your protected Ursus bridge until you revoke access.</p>
          <form method="post" action="/oauth/decision">
            <input type="hidden" name="request_id" value="\(escapedRequestID)">
            <input type="hidden" name="decision_token" value="\(escapedDecisionToken)">
            <div class="actions">
              <button class="button approve" type="submit" name="decision" value="approve">Approve</button>
              <button class="button deny" type="submit" name="decision" value="deny">Deny</button>
            </div>
          </form>
          <p class="footer-note">Manage or revoke bridge access later in Ursus.</p>
        </section>
        """

        return oauthPageResponse(
            statusCode: 200,
            title: "Approve access to Ursus",
            body: body
        )
    }

    func decisionErrorResponse(
        statusCode: Int,
        title: String,
        message: String
    ) -> BearBridgeHTTPApplication.BridgeHTTPResponse {
        let body = """
        <section class="card">
          \(oauthPageHeaderHTML(title: title))
          <p class="message">\(htmlEscaped(message))</p>
        </section>
        """

        return oauthPageResponse(
            statusCode: statusCode,
            title: title,
            body: body
        )
    }

    func decisionCompletionResponse(
        redirectURI: String,
        title: String,
        message: String,
        additions: [URLQueryItem]
    ) -> BearBridgeHTTPApplication.BridgeHTTPResponse {
        let callbackURL = redirectLocation(
            redirectURI: redirectURI,
            additions: additions
        )
        let escapedCallbackURL = htmlEscaped(callbackURL)
        let callbackURLLiteral = javaScriptStringLiteral(callbackURL)
        let body = """
        <section class="card">
          \(oauthPageHeaderHTML(title: title))
          <p class="message">\(htmlEscaped(message))</p>
          <p class="footer-note">You can close this window if nothing else happens.</p>
          <input type="hidden" name="callback_url" value="\(escapedCallbackURL)">
        </section>
        """
        let script = """
        const callbackURL = \(callbackURLLiteral);

        function openClient() {
          try {
            window.location.replace(callbackURL);
          } catch (_) {}
        }

        openClient();

        window.setTimeout(() => {
          window.close();
        }, 500);
        """

        return oauthPageResponse(
            statusCode: 200,
            title: title,
            body: body,
            script: script
        )
    }

    func methodNotAllowedResponse(
        allowing methods: [String]
    ) -> BearBridgeHTTPApplication.BridgeHTTPResponse {
        .plain(
            statusCode: 405,
            headers: [
                HTTPHeaderName.allow: methods.joined(separator: ", "),
                HTTPHeaderName.contentType: "text/plain; charset=utf-8",
            ],
            body: Data("Method Not Allowed".utf8)
        )
    }

    func oauthErrorResponse(
        statusCode: Int,
        error: String,
        description: String
    ) -> BearBridgeHTTPApplication.BridgeHTTPResponse {
        jsonResponse(
            OAuthErrorPayload(error: error, errorDescription: description),
            statusCode: statusCode
        )
    }

    func redirectErrorResponse(
        redirectURI: String,
        state: String?,
        error: String,
        description: String
    ) -> BearBridgeHTTPApplication.BridgeHTTPResponse {
        guard var components = URLComponents(string: redirectURI) else {
            return oauthErrorResponse(statusCode: 400, error: error, description: description)
        }

        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "error", value: error))
        items.append(URLQueryItem(name: "error_description", value: description))
        if let state {
            items.append(URLQueryItem(name: "state", value: state))
        }
        components.queryItems = items

        return redirectResponse(to: components.url?.absoluteString ?? redirectURI)
    }

    func redirectSuccessResponse(
        redirectURI: String,
        code: String,
        state: String?
    ) -> BearBridgeHTTPApplication.BridgeHTTPResponse {
        guard var components = URLComponents(string: redirectURI) else {
            return oauthErrorResponse(
                statusCode: 500,
                error: "server_error",
                description: "Failed to format the authorization redirect."
            )
        }

        var items = components.queryItems ?? []
        items.append(URLQueryItem(name: "code", value: code))
        if let state {
            items.append(URLQueryItem(name: "state", value: state))
        }
        components.queryItems = items

        return redirectResponse(to: components.url?.absoluteString ?? redirectURI)
    }

    func redirectResponse(to location: String) -> BearBridgeHTTPApplication.BridgeHTTPResponse {
        .plain(
            statusCode: 302,
            headers: [
                "Location": location,
                HTTPHeaderName.contentType: "text/plain; charset=utf-8",
            ],
            body: Data("Redirecting".utf8)
        )
    }

    func jsonResponse<Value: Encodable>(
        _ value: Value,
        statusCode: Int = 200,
        headers: [String: String] = [:]
    ) -> BearBridgeHTTPApplication.BridgeHTTPResponse {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let data = (try? encoder.encode(value)) ?? Data("{}".utf8)
        var mergedHeaders = headers
        mergedHeaders[HTTPHeaderName.contentType] = "application/json"
        return .plain(statusCode: statusCode, headers: mergedHeaders, body: data)
    }

    func htmlResponse(
        statusCode: Int,
        html: String
    ) -> BearBridgeHTTPApplication.BridgeHTTPResponse {
        .plain(
            statusCode: statusCode,
            headers: [
                HTTPHeaderName.contentType: "text/html; charset=utf-8",
                "Cache-Control": "no-store",
                "Pragma": "no-cache",
            ],
            body: Data(html.utf8)
        )
    }

    func oauthPageResponse(
        statusCode: Int,
        title: String,
        body: String,
        script: String? = nil
    ) -> BearBridgeHTTPApplication.BridgeHTTPResponse {
        let scriptBlock: String
        if let script, !script.isEmpty {
            scriptBlock = """
              <script>
              \(script)
              </script>
            """
        } else {
            scriptBlock = ""
        }

        let html = """
        <!doctype html>
        <html lang="en">
        <head>
          <meta charset="utf-8">
          <meta name="viewport" content="width=device-width, initial-scale=1">
          <title>\(htmlEscaped(title))</title>
          <style>
            \(oauthPageStyleBlock())
          </style>
        </head>
        <body>
          <main class="page-shell">
            \(body)
          </main>
        \(scriptBlock)
        </body>
        </html>
        """

        return htmlResponse(statusCode: statusCode, html: html)
    }

    func oauthPageHeaderHTML(title: String) -> String {
        """
        <header class="header">
          <div class="logo-badge" aria-hidden="true">
            \(ursusLogoHTML())
          </div>
          <div class="header-copy">
            <p class="eyebrow">Ursus bridge</p>
            <h1>\(htmlEscaped(title))</h1>
          </div>
        </header>
        """
    }

    func oauthMetadataRowHTML(label: String, value: String) -> String {
        """
        <div class="meta-row">
          <div class="meta-label">\(htmlEscaped(label))</div>
          <div class="meta-value">\(htmlEscaped(value))</div>
        </div>
        """
    }

    func oauthPageStyleBlock() -> String {
        """
        :root {
          color-scheme: light dark;
          --page-background: #f3f0ea;
          --page-glow: rgba(255, 255, 255, 0.6);
          --card-background: rgba(255, 252, 247, 0.88);
          --card-border: rgba(32, 34, 31, 0.09);
          --card-shadow: 0 20px 48px rgba(27, 30, 26, 0.08);
          --text-primary: #1f221d;
          --text-secondary: #5a6055;
          --text-muted: #72786e;
          --meta-background: rgba(244, 240, 233, 0.92);
          --meta-border: rgba(32, 34, 31, 0.08);
          --logo-background: rgba(255, 255, 255, 0.82);
          --logo-border: rgba(32, 34, 31, 0.08);
          --logo-foreground: #252923;
          --approve-background: #1f221d;
          --approve-border: #1f221d;
          --approve-text: #fcfbf8;
          --deny-background: rgba(255, 255, 255, 0.72);
          --deny-border: rgba(32, 34, 31, 0.12);
          --deny-text: #3f453b;
        }

        @media (prefers-color-scheme: dark) {
          :root {
            --page-background: #161816;
            --page-glow: rgba(104, 116, 104, 0.16);
            --card-background: rgba(28, 31, 28, 0.88);
            --card-border: rgba(233, 238, 228, 0.09);
            --card-shadow: 0 24px 60px rgba(0, 0, 0, 0.34);
            --text-primary: #f1f3ec;
            --text-secondary: #c8cec2;
            --text-muted: #99a092;
            --meta-background: rgba(35, 38, 34, 0.92);
            --meta-border: rgba(233, 238, 228, 0.08);
            --logo-background: rgba(38, 42, 38, 0.94);
            --logo-border: rgba(233, 238, 228, 0.08);
            --logo-foreground: #f1f3ec;
            --approve-background: #f1f3ec;
            --approve-border: #f1f3ec;
            --approve-text: #1d201b;
            --deny-background: rgba(34, 37, 34, 0.94);
            --deny-border: rgba(233, 238, 228, 0.12);
            --deny-text: #d7ddd0;
          }
        }

        * { box-sizing: border-box; }

        html, body { min-height: 100%; }

        body {
          margin: 0;
          font-family: -apple-system, BlinkMacSystemFont, "SF Pro Text", sans-serif;
          background:
            radial-gradient(circle at top, var(--page-glow), transparent 42%),
            var(--page-background);
          color: var(--text-primary);
        }

        .page-shell {
          min-height: 100vh;
          display: grid;
          place-items: center;
          padding: 28px 18px;
        }

        .card {
          width: min(100%, 520px);
          padding: 28px;
          border-radius: 24px;
          border: 1px solid var(--card-border);
          background: var(--card-background);
          box-shadow: var(--card-shadow);
        }

        .header {
          display: flex;
          align-items: center;
          gap: 14px;
          margin-bottom: 20px;
        }

        .logo-badge {
          width: 46px;
          height: 46px;
          flex: 0 0 46px;
          display: grid;
          place-items: center;
          border-radius: 15px;
          border: 1px solid var(--logo-border);
          background: var(--logo-background);
          color: var(--logo-foreground);
        }

        .logo-badge svg {
          width: 24px;
          height: auto;
          display: block;
        }

        .header-copy {
          min-width: 0;
        }

        .eyebrow {
          margin: 0 0 4px;
          font-size: 12px;
          line-height: 1.2;
          color: var(--text-muted);
          letter-spacing: 0.02em;
        }

        h1 {
          margin: 0;
          font-size: 29px;
          line-height: 1.08;
          letter-spacing: -0.03em;
        }

        .meta-list {
          display: grid;
          gap: 10px;
          margin-bottom: 18px;
        }

        .meta-row {
          display: grid;
          grid-template-columns: 72px minmax(0, 1fr);
          gap: 14px;
          align-items: start;
          padding: 11px 13px;
          border-radius: 14px;
          border: 1px solid var(--meta-border);
          background: var(--meta-background);
        }

        .meta-label {
          font-size: 12px;
          line-height: 1.35;
          font-weight: 600;
          color: var(--text-muted);
        }

        .meta-value {
          min-width: 0;
          font-size: 14px;
          line-height: 1.45;
          color: var(--text-primary);
          word-break: break-word;
        }

        .message {
          margin: 0;
          font-size: 15px;
          line-height: 1.55;
          color: var(--text-secondary);
        }

        form {
          margin-top: 22px;
        }

        .actions {
          display: flex;
          gap: 12px;
          flex-wrap: wrap;
        }

        .button {
          appearance: none;
          min-height: 44px;
          padding: 0 18px;
          border-radius: 999px;
          border: 1px solid transparent;
          font: inherit;
          font-size: 15px;
          font-weight: 600;
          cursor: pointer;
          transition: transform 140ms ease, box-shadow 140ms ease, background-color 140ms ease;
        }

        .button:hover {
          transform: translateY(-1px);
        }

        .approve {
          background: var(--approve-background);
          border-color: var(--approve-border);
          color: var(--approve-text);
          box-shadow: 0 10px 24px rgba(16, 18, 15, 0.14);
        }

        .deny {
          background: var(--deny-background);
          border-color: var(--deny-border);
          color: var(--deny-text);
        }

        .footer-note {
          margin: 18px 0 0;
          font-size: 13px;
          line-height: 1.5;
          color: var(--text-muted);
        }

        input[type="hidden"] {
          display: none;
        }

        @media (max-width: 540px) {
          .card {
            padding: 24px;
            border-radius: 22px;
          }

          .meta-row {
            grid-template-columns: 1fr;
            gap: 6px;
          }

          h1 {
            font-size: 26px;
          }

          .button {
            width: 100%;
            justify-content: center;
          }
        }
        """
    }

    func ursusLogoHTML() -> String {
        // Keep the bridge OAuth UI self-contained by inlining the existing Ursus mark.
        """
        <svg viewBox="0 0 462.56 413.17" fill="currentColor" xmlns="http://www.w3.org/2000/svg">
          <path d="M254.01 122.12s-79.38 44.49-115.95 66.62l-85.94 15.39c-1.1-1.5 69.48-122.36 71.54-122.91l130.35 40.9Z"/>
          <path d="M114.41 73.99l66.85-45.58c31.58 2.32 63.23 3.51 94.82 5.37-7.04 2.24-110.37 28.08-163.44 42.78l-48.31 44.74-19.2-85.4c7.62-6.58 15.59-12.93 23.61-19 3.6-2.72 14.57-10.78 23.37-16.9 20.7 8.02 47.26 18.93 65.67 27.09l-43.38 46.9Z"/>
          <path d="M247.26 349.81L58.42 208.87l77.32-11.44 111.52 152.38Z"/>
          <path d="M410.56 131.56l-8.72-32.29-30.25-24.21 6.65-27.86-38.38-20.37c-12.57 3.57-192.28 51.84-192.28 51.84l112.53 37.22 50.95 34.56-49.93-20.4-115.95 63.85.72 2.02c22.74 33.31 140.44 195.13 140.44 195.13S104.87 247.35 43.57 208.72l19.54-82.96C33.23 181.52-.41 237.83 0 239.87l304.41 173.3-40.76-89.49c-.83.3 146.2-58.92 146.2-58.92l49.35-56.22 3.35-42.21c-17.21-11.8-36.22-20.95-52-34.75Z"/>
        </svg>
        """
    }

    func endpointContext(for request: HTTPRequest) -> EndpointContext {
        let origin = Self.originURL(
            hostHeader: request.header(HTTPHeaderName.host),
            fallbackHost: configuration.host,
            fallbackPort: configuration.port
        )
        let issuerURL = origin
        let resourceURL = url(byAppendingPath: configuration.mcpEndpoint, to: origin)
        return EndpointContext(
            issuerURL: issuerURL,
            resourceURL: resourceURL,
            authorizationEndpointURL: url(byAppendingPath: "/oauth/authorize", to: origin),
            tokenEndpointURL: url(byAppendingPath: "/oauth/token", to: origin),
            registrationEndpointURL: url(byAppendingPath: "/oauth/register", to: origin)
        )
    }

    func queryParameters(from request: HTTPRequest) -> [String: String] {
        guard let requestPath = request.path,
              let components = URLComponents(string: "http://placeholder\(requestPath)")
        else {
            return [:]
        }

        var parameters: [String: String] = [:]
        for item in components.queryItems ?? [] {
            parameters[item.name] = item.value ?? ""
        }
        return parameters
    }

    func formParameters(from body: Data?) -> [String: String] {
        guard let body,
              let bodyString = String(data: body, encoding: .utf8),
              !bodyString.isEmpty
        else {
            return [:]
        }

        var parameters: [String: String] = [:]
        for pair in bodyString.split(separator: "&", omittingEmptySubsequences: true) {
            let components = pair.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            let name = String(components[0])
                .replacingOccurrences(of: "+", with: " ")
                .removingPercentEncoding
            let value = components.count > 1
                ? String(components[1])
                    .replacingOccurrences(of: "+", with: " ")
                    .removingPercentEncoding
                : ""
            if let name {
                parameters[name] = value ?? ""
            }
        }
        return parameters
    }

    func resolvedScope(rawValue: String?, fallback: String) throws -> String {
        let normalized = nonEmptyValue(rawValue) ?? fallback
        let requestedScopes = Set(normalizedScopeComponents(normalized))
        guard !requestedScopes.isEmpty else {
            throw BearError.invalidInput("At least one supported scope is required.")
        }

        let supportedScopes = Set(configuration.supportedScopes)
        guard requestedScopes.isSubset(of: supportedScopes) else {
            throw BearError.invalidInput("Requested scope is not supported by the Ursus bridge.")
        }

        return requestedScopes.sorted().joined(separator: " ")
    }

    func narrowedScope(_ requestedScope: String, within originalScope: String) throws -> String {
        let requested = Set(normalizedScopeComponents(requestedScope))
        let original = Set(normalizedScopeComponents(originalScope))
        guard !requested.isEmpty else {
            throw BearError.invalidInput("Requested scope cannot be empty.")
        }
        guard requested.isSubset(of: original) else {
            throw BearError.invalidInput("Refresh token scope cannot expand beyond the originally granted scope.")
        }
        return requested.sorted().joined(separator: " ")
    }

    func normalizedScopeComponents(_ rawValue: String) -> [String] {
        rawValue
            .split(whereSeparator: \.isWhitespace)
            .map(String.init)
            .filter { !$0.isEmpty }
    }

    func nonEmptyValue(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed?.isEmpty == true ? nil : trimmed
    }

    func metadataJSONString(_ metadata: [String: String?]) -> String {
        let filtered = metadata.reduce(into: [String: String]()) { partialResult, entry in
            if let value = nonEmptyValue(entry.value) {
                partialResult[entry.key] = value
            }
        }

        guard let data = try? JSONSerialization.data(
            withJSONObject: filtered,
            options: [.sortedKeys]
        ) else {
            return "{}"
        }
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    func metadataValue(named key: String, in metadataJSON: String) -> String? {
        guard let data = metadataJSON.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            return nil
        }
        return nonEmptyValue(object[key] as? String)
    }

    func htmlEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&#39;")
    }

    func javaScriptStringLiteral(_ value: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [value]),
              let json = String(data: data, encoding: .utf8),
              json.count >= 2
        else {
            return "\"\""
        }

        return String(json.dropFirst().dropLast())
    }

    func redirectLocation(
        redirectURI: String,
        additions: [URLQueryItem]
    ) -> String {
        guard var components = URLComponents(string: redirectURI) else {
            return redirectURI
        }

        var items = components.queryItems ?? []
        items.append(contentsOf: additions.compactMap { item in
            item.value == nil ? nil : item
        })
        components.queryItems = items
        return components.url?.absoluteString ?? redirectURI
    }

    func url(byAppendingPath path: String, to baseURL: URL) -> URL {
        var url = baseURL
        let components = path
            .split(separator: "/", omittingEmptySubsequences: true)
            .map(String.init)
        for component in components {
            url.appendPathComponent(component, isDirectory: false)
        }
        return url
    }

    struct EndpointContext {
        let issuerURL: URL
        let resourceURL: URL
        let authorizationEndpointURL: URL
        let tokenEndpointURL: URL
        let registrationEndpointURL: URL
    }
}
