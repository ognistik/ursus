# HTTP Bridge OAuth Plan

## 1. Current-state analysis

### Actual bridge/runtime entrypoints

- `Sources/BearMCPCLI/UrsusMain.swift`
  - `UrsusCLIRuntime.runBridge` creates the optional HTTP bridge, builds `UrsusMCPServer`, and records bridge runtime state once the bridge is ready.
- `Sources/BearMCPCLI/BearBridgeHTTPApplication.swift`
  - `BearBridgeHTTPApplication.start()` owns the NIO HTTP server lifecycle.
  - `handleHTTPRequest(_:)` manually answers `initialize` and repeated `initialize` compatibility handshakes before delegating all other MCP traffic to `StatelessHTTPServerTransport`.
  - `bridgeValidationPipeline()` intentionally removes the SDK’s localhost-only host/origin guard so forwarded tunnel requests can reach the loopback-bound bridge.
  - `BearBridgeHTTPHandler.handleRequest(...)` currently hard-rejects every path except the configured MCP endpoint and `makeHTTPRequest(...)` drops both the request path and peer socket identity before handing the request to the MCP transport.
- `Sources/BearCore/BearBridgeConfiguration.swift`
  - The bridge config currently knows only `enabled`, `host`, and `port`, and validation enforces loopback-only bind addresses.

### Actual MCP registration points

- `Sources/BearMCP/UrsusMCPServer.swift`
  - `registerHandlers(on:)` wires `resources/list`, `resources/templates/list`, `tools/list`, and `tools/call`.
  - `ToolCatalog.makeTools(...)` is the one place where tool metadata is assembled.
  - `bridgeSurfaceMarker(...)` already hashes the effective `Tool` catalog, so auth-related tool metadata changes will naturally flow into restart detection if they are added here.

### Actual app-side bridge/status surfaces

- `Sources/BearApplication/BearBridgeSupport.swift`
  - `BearAppBridgeSnapshot` is the current bridge status payload.
  - `bridgeSnapshot(...)` is the central bridge health/status builder.
  - `probeBridgeEndpoint(...)` and `probeBridgeProtocol(...)` assume unauthenticated `initialize` and `tools/list`.
- `App/UrsusApp/UrsusSetupView.swift`
  - The Setup tab already has a compact `Remote MCP Bridge` card with minimal controls and status text.
  - This is the right place for a very small remote-auth status/review affordance.

### Important code-level constraints discovered

1. The current bridge cannot serve OAuth discovery or authorization endpoints at all.
   - `BearBridgeHTTPHandler` only accepts the MCP endpoint path, so `/.well-known/oauth-protected-resource`, `/.well-known/oauth-authorization-server`, `/oauth/authorize`, `/oauth/token`, and any consent/status routes would all 404 today.

2. The current bridge cannot classify request source robustly enough for local-vs-remote policy.
   - The bridge handler has access to the NIO channel, but it does not preserve peer address.
   - The MCP `HTTPRequest` passed downstream currently contains only method, headers, and body.
   - There is no trusted-proxy config or forwarded-header parser anywhere in the repo.

3. Tool metadata is centralized, but there is no first-class typed auth/security field in the current Swift MCP `Tool` model.
   - The SDK `Tool` type supports `_meta` with arbitrary additional fields, but not a typed `securitySchemes` property.
   - That is enough for Ursus to emit host-specific auth metadata if needed, but the exact ChatGPT-consumed shape is not enforced by the SDK.

4. The current bridge/app diagnostics strongly favor keeping `initialize` and `tools/list` public.
   - Existing bridge readiness checks rely on unauthenticated `initialize` and `tools/list`.
   - Preserving that behavior keeps the app simple and avoids teaching the app its own bridge OAuth flow just for health checks.

## 2. Recommended architecture

### What should change

- Keep OAuth entirely inside the optional HTTP bridge path.
- Add a small bridge-scoped auth layer that runs before MCP requests reach `StatelessHTTPServerTransport`.
- Add bridge-only auth state/storage and app-facing bridge auth snapshots in `BearApplication`.
- Add bridge auth config and auth/runtime paths in `BearCore`.
- Extend `ToolCatalog` in `BearMCP` so `tools/list` can advertise which tools are OAuth-protected.

### What should not change

- Do not change the stdio-first product shape.
- Do not push auth concerns into `BearDB`, `BearXCallback`, or Bear note business logic.
- Do not add user accounts, usernames, or passwords.
- Do not add Cloudflare-specific branching to core bridge behavior.
- Do not rewrite the transport stack or replace the current NIO bridge with a different server framework.

### Smallest structural cut that makes this clean

Add one bridge-owned request classification/router layer in `BearCLIRuntime`, sitting in front of the existing stateless MCP transport:

1. Parse and preserve request path.
2. Serve OAuth well-known/auth endpoints directly when the path is not `/mcp`.
3. For `/mcp`:
   - check the bridge auth-mode toggle
   - when bridge OAuth is enabled, enforce auth at the HTTP boundary for the whole MCP surface
   - return `401`/`403` at the HTTP boundary when needed
   - otherwise pass the request through to the existing manual-`initialize` + stateless MCP flow

That is the smallest change that solves the path, routing, and auth-challenge requirements without contaminating stdio.

## 3. Trust-boundary model

### Revised v1 recommendation

For v1, avoid automatic local-vs-remote auth decisions entirely.

Instead, use a simple bridge-level product decision:

- default bridge mode: unauthenticated local HTTP bridge
- optional bridge toggle: `Require OAuth for all bridge requests`

When the toggle is off:

- the optional HTTP bridge behaves as it does today
- no OAuth endpoints need to be exercised by normal local users

When the toggle is on:

- every request to the HTTP bridge requires OAuth
- there is no mixed-auth behavior
- there is no local-bypass inside that bridge mode
- ChatGPT and other remote hosts can use the bridge as a standard OAuth-protected MCP server

### Why this is the best v1 tradeoff

- It is much simpler for users to understand.
- It avoids the hardest implementation problem in the earlier plan: proving whether a loopback request is truly local or is tunnel/proxy traffic arriving from the same machine.
- It removes the need for trusted-proxy configuration, forwarded-header parsing, and ambiguous fail-closed heuristics in v1.

### Deferred future model

If later needed, Ursus can add a more sophisticated policy such as:

- local loopback bypass + remote OAuth
- trusted-proxy handling
- mixed auth for selected endpoints/tools

That should be treated as a later enhancement, not a requirement for the first secure ChatGPT-compatible bridge release.

## 4. OAuth model

### Recommended OAuth shape

Implement a built-in, bridge-local OAuth 2.1 authorization server for the HTTP bridge only, activated when the bridge-level `Require OAuth for all bridge requests` toggle is enabled.

Use:

- Authorization Code + PKCE
- Refresh tokens
- Dynamic Client Registration for public clients
- No user accounts
- No password login
- One local resource owner
- Durable remembered grants so approval is usually one-time per client/resource/scope set

### Why this is the best fit

- MCP auth is transport-level HTTP auth, not stdio auth.
- OpenAI’s ChatGPT developer-mode docs say remote MCP apps support `OAuth`, `No Authentication`, and `Mixed Authentication`, and that when static credentials are not provided, dynamic client registration is used.
- Using full bridge OAuth lets Ursus present a simpler server shape to ChatGPT than mixed auth.
- The MCP auth spec prefers Client ID Metadata Documents when available, but ChatGPT compatibility is the stronger requirement here. For Ursus v1, implementing DCR is the safest bet.

### Authorization server placement

Host the authorization server inside the same bridge HTTP process, under the same optional remote HTTP surface, for example:

- `/.well-known/oauth-protected-resource[...]`
- `/.well-known/oauth-authorization-server[...]`
- `/oauth/authorize`
- `/oauth/token`
- `/oauth/register`
- a tiny approval-status route for polling while waiting on local consent

Do not create a second daemon or auth microservice.

### Consent model

The authorization endpoint should not rely on a public browser approval page alone. Because Ursus has no user accounts and the auth endpoint may be reachable through a public tunnel, browser-only approval would be too weak.

Recommended approach:

1. `/oauth/authorize` creates a pending authorization request.
2. It surfaces that pending request inside `Ursus.app` as a local-owner approval sheet/dialog.
3. The browser page polls a request-status endpoint and redirects back with an auth code once the local app approves.
4. Approved grants are stored durably so repeat authorizations from the same client can auto-approve when policy allows.

This preserves “single local owner” semantics without inventing accounts.

### Token/storage model

Use opaque tokens in v1, not JWTs.

- Access tokens: random opaque bearer tokens, short-lived
- Refresh tokens: random opaque tokens, longer-lived
- Authorization codes: one-time, short-lived, opaque
- Registered clients, grants, tokens, pending auth requests, and revocation state: local Ursus-owned storage under `~/Library/Application Support/Ursus/Auth/` (prefer a small SQLite store over multiple JSON files)
- Hash tokens at rest rather than storing raw bearer values

Because v1 can use opaque tokens, no JWT signing key is required initially.

If a later phase needs JWT access tokens:

- store the signing key in macOS Keychain
- publish a JWKS endpoint from the built-in auth server

## 5. Tool/auth surface

### Recommended v1 behavior

When bridge OAuth is enabled, treat the entire `/mcp` bridge surface as OAuth-protected.

That means:

- `initialize` requires OAuth
- `tools/list` requires OAuth
- `resources/list` requires OAuth
- `resources/templates/list` requires OAuth
- all Bear `tools/call` requests require OAuth

Unauthenticated access should still be allowed for the OAuth-specific endpoints themselves, including:

- Protected Resource Metadata
- Authorization Server Metadata
- client registration
- authorization
- token exchange

### Why this is the best fit for Ursus

- It gives ChatGPT a plain `OAuth` server instead of a mixed-auth server.
- It avoids per-tool auth metadata as a release blocker.
- It avoids keeping app health checks and bridge routing in sync with partially public MCP methods.
- It keeps the product story simple: the bridge is either open for local use or fully OAuth-protected.

### Tool metadata impact

For v1 full-bridge OAuth, Ursus does not need per-tool security metadata to be correct in order to function with ChatGPT.

Tool metadata can remain focused on tool usability and restart-surface hashing. If later Ursus adds mixed auth, then `ToolCatalog.makeTools(...)` becomes the place to emit host-consumed auth metadata.

## 6. UI/app implications

Keep the UI minimal.

### Setup surface

Extend the existing `Remote MCP Bridge` card with only:

- a simple toggle: `Require OAuth for all bridge requests`
- a compact protection status line
- a `Review Grants` action when OAuth is enabled
- no auth-mode matrix

### App approval/revocation surface

Add:

- a pending-approval sheet/dialog when a new OAuth authorization request arrives
- a small grant list with revoke/remove actions

This can live in the app shell without exposing transport implementation details.

### Configuration surface

Do not add proxy trust settings in v1.

Recommended approach:

- keep the main Setup card simple
- avoid any Cloudflare-specific toggle
- avoid any trusted-proxy config until a later phase actually needs it

## 7. Implementation phases

### Phase 1: Bridge auth mode plumbing and multi-route support

Status: completed on 2026-04-06

Implemented:

- `BearBridgeConfiguration` now carries a typed bridge auth mode with a simple `open` vs `oauth` toggle, while preserving legacy config decoding defaults.
- App config/save/snapshot plumbing now exposes the bridge-level `Require OAuth for all bridge requests` toggle without affecting stdio or Bear integration layers.
- The HTTP bridge now preserves request paths in `HTTPRequest`, routes `/mcp` separately from future OAuth routes, and no longer hard-404s every non-`/mcp` path.
- In OAuth-required mode, the full `/mcp` bridge surface now returns `401` with a Bearer challenge at the HTTP boundary.
- In open mode, existing `/mcp` behavior remains unchanged.
- Recognized future OAuth routes currently return placeholder `501` responses rather than implementing the authorization server early.
- Bridge status/probe logic now treats an OAuth challenge as an expected protected-bridge signal instead of a generic health failure.
- Tests now cover auth-mode config defaults/round-trips, app plumbing, route classification, multi-route HTTP behavior, and full-bridge auth gating.

Likely files:

- `Sources/BearMCPCLI/BearBridgeHTTPApplication.swift`
- `Sources/BearCore/BearBridgeConfiguration.swift`
- `Sources/BearCore/BearConfiguration.swift`
- `Sources/BearApplication/BearAppSupport.swift`
- `Tests/BearMCPCLITests/BearBridgeHTTPApplicationTests.swift`

Work:

- preserve request path in `HTTPRequest`
- replace the single-path hard gate with a small router that can serve `/mcp` plus OAuth endpoints
- add a bridge-level auth mode / OAuth-required toggle to config and app plumbing
- keep existing bridge behavior unchanged when OAuth is off

Checkpoint:

- existing local `/mcp` behavior still passes
- non-`/mcp` well-known endpoints can be served
- bridge can switch cleanly between open and OAuth-required modes in tests

Notes for next phase:

- No actual OAuth authorization server behavior exists yet.
- Protected-resource metadata, authorization-server metadata, DCR, authorize, token, and grant-review flows are still pending.
- The app toggle and bridge routing boundary are now in place specifically so those next pieces can land without another transport refactor.

### Phase 2: Bridge auth state/storage and app snapshot plumbing

Status: completed on 2026-04-06

Implemented:

- `BearPaths` now exposes bridge-auth storage under `~/Library/Application Support/Ursus/Auth/bridge-auth.sqlite`.
- `BearBridgeAuthStore` now provides durable SQLite-backed storage for registered clients, remembered grants, pending authorization requests, authorization codes, refresh tokens, access tokens, and revocations, while hashing bearer secrets at rest.
- Bridge/app snapshot plumbing now includes a compact auth snapshot with storage readiness plus client/grant/request/token counts.
- The Setup bridge card now shows a minimal auth-state summary, and `ursus bridge status` now reports auth-storage readiness and compact counts.
- Tests now cover auth-store creation, durability across reopen, runtime path wiring, and bridge snapshot auth-count plumbing.

Primary files:

- `Sources/BearApplication/BearBridgeAuthStore.swift`
- `Sources/BearApplication/BearBridgeSupport.swift`
- `Sources/BearCore/BearPaths.swift`
- `Sources/BearMCPCLI/UrsusMain.swift`
- `App/UrsusApp/UrsusSetupView.swift`
- `Tests/BearApplicationTests/BearBridgeAuthStoreTests.swift`

Notes for next phase:

- No OAuth discovery, registration, authorize, token, or consent endpoints are implemented yet.
- The durable store and compact app/CLI status plumbing are now in place so Phase 3 can focus on HTTP authorization-server behavior rather than another storage refactor.

### Phase 3: Built-in authorization server

Status: completed on 2026-04-06

Implemented:

- The bridge now serves real OAuth discovery metadata at `/.well-known/oauth-protected-resource/...` and `/.well-known/oauth-authorization-server`, using the current bridge origin/resource identity instead of the earlier placeholders.
- Protected `/mcp` challenges now advertise `resource_metadata` so a clean OAuth client can discover the built-in authorization server from a `401` response.
- `POST /oauth/register` now supports dynamic client registration for public clients and persists registrations in the Phase 2 durable auth store.
- `GET /oauth/authorize` now validates PKCE authorization requests, creates durable pending authorization requests, reuses or creates durable grants, and issues authorization codes through the shared auth store.
- `POST /oauth/token` now exchanges authorization codes and refresh tokens for opaque bearer tokens, rotates refresh tokens, and stores all issued secrets hashed at rest through the shared auth store.
- Tests now cover OAuth discovery, dynamic client registration, authorization-code + PKCE exchange, refresh-token rotation, and the updated discovery challenge on protected `/mcp`.

Primary files:

- new bridge-auth files under `BearCLIRuntime` and/or `BearApplication`
- `Sources/BearMCPCLI/BearBridgeHTTPApplication.swift`
- `Sources/BearMCPCLI/BearBridgeOAuthServer.swift`
- `Sources/BearApplication/BearBridgeAuthStore.swift`
- new tests in `Tests/BearMCPCLITests`

Notes for next phase:

- Authorization currently auto-approves through the bridge-local single-owner flow so Phase 3 can validate end-to-end HTTP OAuth without landing the app approval UI early.
- `/mcp` remains challenge-only in bridge OAuth mode; token-backed MCP access is still deferred to Phase 5.
- The next phase should replace auto-approval with app-mediated pending-request review, approval, denial, and remembered-grant management.

### Phase 4: Local-owner consent mediation via Ursus.app

Status: completed on 2026-04-06

Implemented:

- `App/UrsusApp/UrsusAppModel.swift`
- `App/UrsusApp/UrsusSetupView.swift`
- `App/UrsusApp/UrsusBridgeAuthReviewSheet.swift`
- shared bridge-auth store/runtime files

Implemented behavior:

- `GET /oauth/authorize` now creates a pending authorization request and returns a small browser waiting page when no remembered grant exists, instead of using the temporary Phase 3 auto-approval path.
- The waiting page polls `GET /oauth/request-status`, which resolves to redirect-ready success or denial URLs once the local app owner responds.
- `Ursus.app` now polls bridge-auth review state in the background, auto-surfaces a bridge access review sheet when new requests arrive while the app is open, and exposes approve/deny actions for pending requests.
- App approval now persists a remembered grant immediately, so repeat authorizations for the same client/resource/scope set can skip the prompt.
- The Setup bridge card now exposes a `Review Access` entry point, and the review sheet also shows remembered grants with revoke actions.
- Grant revocation now clears remembered-grant reuse and revokes associated stored authorization codes, refresh tokens, and access tokens in the bridge auth store.
- Tests now cover pending review snapshots, approve/deny transitions, revocation, denied request resolution, remembered-grant repeat authorization, and request completion after token exchange.

Notes for next phase:

- `/mcp` remains challenge-only in bridge OAuth mode; token-backed MCP access is still deferred to Phase 5.
- The next phase should validate bearer tokens on protected MCP requests while leaving OAuth discovery, registration, authorize, status, and token lifecycle routes public.

### Phase 5: Full-bridge OAuth enforcement

Likely files:

- `Sources/BearMCP/UrsusMCPServer.swift`
- bridge auth router/classifier files
- `Tests/BearMCPCLITests/BearBridgeHTTPApplicationTests.swift`

Work:

- enforce `401` on the full `/mcp` surface when bridge OAuth is enabled and the request lacks valid authorization
- keep OAuth discovery and token lifecycle routes public
- verify repeated `initialize` still works correctly after authorization

Checkpoint:

- bridge-open mode still works with no OAuth
- bridge-protected mode returns `401` + `WWW-Authenticate` on unauthenticated MCP requests
- authenticated `initialize` and `tools/list` succeed end-to-end

### Phase 6: Host interoperability validation

Validate against:

- local loopback client with no auth
- proxied/tunneled client with auth required
- ChatGPT developer mode remote MCP setup

Specific checks:

- DCR
- PKCE
- token refresh
- mixed-auth tool discovery
- repeated `initialize`
- app bridge health/status still works

## 8. Risks / unknowns

### 1. Current bridge handler drops some routing data auth needs

Today Ursus throws away request path before handing off to MCP transport logic, and it only serves the MCP endpoint path. This is the main structural blocker, but it is fixable with a small bridge-layer change.

### 2. Public browser consent is not enough

Because Ursus intentionally has no user accounts, the authorization server needs a real local-owner approval signal. The cleanest signal is the local app.

### 3. Public resource identity must be reconstructed correctly

OAuth discovery and audience binding need the canonical HTTPS resource identity that users expose to remote hosts, not `http://127.0.0.1:6190/mcp`. Ursus will need a clean way to configure or derive that public origin for OAuth-enabled bridge deployments.

### 4. Current bridge health probes assume public `initialize` and `tools/list`

If Ursus moves to full-bridge auth, app diagnostics will need an OAuth-aware health probe or a lighter “transport up / auth configured” model for protected bridges.

## 9. Recommendation

Build one built-in, single-user OAuth authorization server into the optional HTTP bridge, keep stdio untouched, add a simple bridge toggle for `Require OAuth for all bridge requests`, and use `Ursus.app` as the local-owner consent surface with durable remembered grants.

This is the best fit because it:

- matches MCP transport-level auth requirements
- gives ChatGPT a simpler plain-`OAuth` server shape
- avoids user accounts and password UX
- keeps local usage simple when the toggle is off
- avoids Cloudflare-specific coupling
- avoids trusted-proxy and mixed-auth complexity in the first secure release

## Research notes

- MCP Authorization spec: <https://modelcontextprotocol.io/specification/2025-11-25/basic/authorization>
- MCP changelog note introducing resource-server auth and protected resource metadata: <https://modelcontextprotocol.io/specification/2025-06-18/changelog>
- OpenAI ChatGPT developer mode docs: <https://developers.openai.com/api/docs/guides/developer-mode>
- MCP Apps authorization guidance for per-server vs per-tool enforcement: <https://apps.extensions.modelcontextprotocol.io/api/documents/authorization.html>
