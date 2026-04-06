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
        case .oauthToken:
            return await tokenResponse(for: request)
        case .mcp, .notFound:
            return BearBridgeHTTPApplication.notFoundResponse()
        }
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
        let port = candidate?.port ?? fallbackPort
        let scheme = isLoopbackHost(host) ? "http" : "https"
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        if !(scheme == "http" && port == 80),
           !(scheme == "https" && port == 443)
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
            let grant = try await store.ensureGrant(
                BearBridgeAuthGrantDraft(
                    clientID: client.id,
                    scope: requestedScope,
                    resource: context.resourceURL.absoluteString,
                    metadataJSON: metadataJSONString(
                        [
                            "approved_by": "phase3-bridge-local",
                            "resource": context.resourceURL.absoluteString,
                        ]
                    )
                )
            )
            let pendingRequest = try await store.createPendingAuthorizationRequest(
                BearBridgePendingAuthorizationRequestDraft(
                    clientID: client.id,
                    grantID: grant.id,
                    requestedScope: requestedScope,
                    redirectURI: redirectURI,
                    state: state,
                    codeChallenge: codeChallenge,
                    codeChallengeMethod: "S256",
                    expiresAt: now().addingTimeInterval(configuration.pendingRequestLifetime),
                    metadataJSON: metadataJSONString(
                        [
                            "approval_mode": "phase3-auto-approve",
                            "resource": context.resourceURL.absoluteString,
                        ]
                    )
                )
            )
            _ = try await store.updatePendingAuthorizationRequestStatus(
                id: pendingRequest.id,
                status: .approved
            )
            let issuedCode = try await store.issueAuthorizationCode(
                BearBridgeAuthorizationCodeDraft(
                    clientID: client.id,
                    grantID: grant.id,
                    pendingRequestID: pendingRequest.id,
                    scope: requestedScope,
                    redirectURI: redirectURI,
                    codeChallenge: codeChallenge,
                    codeChallengeMethod: "S256",
                    expiresAt: now().addingTimeInterval(configuration.authorizationCodeLifetime)
                )
            )
            _ = try await store.updatePendingAuthorizationRequestStatus(
                id: pendingRequest.id,
                status: .completed
            )
            return redirectSuccessResponse(
                redirectURI: redirectURI,
                code: issuedCode.code,
                state: state
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

    func metadataJSONString(_ metadata: [String: String]) -> String {
        guard let data = try? JSONSerialization.data(
            withJSONObject: metadata,
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
        return object[key] as? String
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
