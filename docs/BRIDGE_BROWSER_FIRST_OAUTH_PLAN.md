# Bridge Browser-First OAuth Plan

## Summary

Ursus should move from an app-approved bridge OAuth flow to a browser-first consent flow.

The browser popup opened during OAuth should become the primary place where the user approves or denies access. `Ursus.app` should remain the place to inspect granted clients, revoke remembered access, and review bridge auth state, but it should no longer be the required approval surface for normal authorization.

Because Ursus has not shipped publicly yet, this should be treated as a cleanup-oriented redesign rather than a compatibility-preserving migration. Any bridge-OAuth code that only exists to support the current browser-to-app approval handoff should be removed once the new flow is complete.

## Product Decision

- Make the browser popup the default and primary consent surface.
- Keep `Ursus.app` as the local control center for bridge access management.
- Do not preserve app-only approval behavior just for backward compatibility.
- Remove bridge-OAuth handoff code that is no longer needed after the redesign.

## Why Change

The current bridge OAuth flow works, but it is awkward:

1. The user starts OAuth from a host app.
2. The browser popup opens.
3. The popup tells the user to switch to `Ursus.app`.
4. The user approves in `Ursus.app`.
5. The popup continues and still may need manual cleanup.

This creates unnecessary context switching and makes the bridge feel more complicated than it is.

The desired user experience is:

1. The user starts OAuth from a host app.
2. The browser popup opens.
3. The popup shows clear consent details and `Approve` / `Deny`.
4. The popup redirects back to the client and closes if possible.
5. `Ursus.app` remains available to inspect and revoke access later.

## Goals

- Reduce OAuth approval to a single browser consent step.
- Preserve OAuth correctness: redirect URI validation, PKCE, scoped grants, resource binding, token issuance, and bearer validation.
- Keep grant management local to `Ursus.app`.
- Simplify the bridge auth architecture by removing app-approval-specific plumbing.
- Keep the implementation understandable and well tested.

## Non-Goals

- Do not change stdio MCP behavior.
- Do not change selected-note helper behavior; it is unrelated to bridge OAuth.
- Do not add cloud services, accounts, or external identity infrastructure.
- Do not introduce a generic browser session framework beyond what the bridge needs.

## Current Flow To Replace

Today the bridge OAuth authorize route validates the request, creates a pending local approval request when no remembered grant exists, and returns an HTML waiting page. That page polls `/oauth/request-status` until `Ursus.app` approves or denies the request. The app watches the auth store, brings itself to the front, and exposes pending-request approve/deny buttons.

This is the behavior to remove.

## Target Flow

### First-Time Authorization

1. OAuth client opens `GET /oauth/authorize`.
2. Ursus validates:
   - `response_type=code`
   - registered `client_id`
   - exact `redirect_uri`
   - `code_challenge`
   - `code_challenge_method=S256`
   - supported scope
   - correct protected resource
3. If a remembered active grant already exists for the same client, resource, and scope:
   - issue an authorization code immediately
   - redirect back to the client
4. Otherwise:
   - create a pending authorization request
   - render a consent page in the browser popup
5. The consent page shows:
   - client display name
   - requested scope
   - target resource
   - expiry info
   - `Approve` button
   - `Deny` button
6. The user clicks one choice in the popup.
7. Ursus processes that choice through a protected `POST` decision route.
8. On approve:
   - create or reuse the remembered grant
   - issue an authorization code
   - mark the request completed
   - redirect to the client callback
9. On deny:
   - mark the request denied
   - redirect to the client callback with `access_denied`

### Repeat Authorization

1. OAuth client opens `GET /oauth/authorize`.
2. Ursus finds an active remembered grant for the same client, resource, and scope.
3. Ursus immediately issues an authorization code and redirects.
4. No popup consent screen appears beyond the normal OAuth redirect round trip.

### Access Management In Ursus.app

`Ursus.app` should continue to show bridge auth state and remembered grants, but it should stop being the mandatory approval surface.

The app should support:

- viewing remembered grants
- revoking remembered grants
- showing compact bridge auth status
- optionally listing recent auth activity if useful

The app does not need to remain a co-equal approval surface unless a concrete product reason emerges later.

## Architecture Changes

### 1. Browser Consent Becomes Authoritative

The bridge-local authorization server remains the source of truth. The browser is only the presentation layer for consent, but it becomes the primary place where the decision is collected.

This is still a valid OAuth model because the bridge server is the authorization server and continues to:

- validate the OAuth request
- validate redirect URIs
- verify PKCE at token exchange
- issue authorization codes
- issue refresh and access tokens
- validate bearer tokens for `/mcp`

### 2. Remove The Browser-To-App Polling Handoff

The following browser-to-app approval mechanics should be removed once the browser-first flow is complete:

- HTML waiting page that tells the user to open `Ursus.app`
- `/oauth/request-status` polling loop
- app-side auto-foregrounding when new pending bridge auth requests appear
- app UI language that says approval is waiting in `Ursus.app`
- app approval buttons that only exist to complete the old handoff

### 3. Keep Auth Storage, Simplify State Transitions

The existing bridge auth store should remain the durable source of truth, but the request state machine should be simplified around the new flow.

Recommended request states:

- `pending`
- `denied`
- `completed`
- `expired`

The intermediate `approved` state should be removed if approval and authorization-code issuance happen inside the same `POST` decision request.

That simplification removes a whole browser-polling state and keeps the request lifecycle tighter.

## OAuth Route Design

### Keep

- `/.well-known/oauth-protected-resource/...`
- `/.well-known/oauth-authorization-server`
- `POST /oauth/register`
- `GET /oauth/authorize`
- `POST /oauth/token`

### Add

- `POST /oauth/decision`

### Remove

- `GET /oauth/request-status`

## `GET /oauth/authorize`

Behavior:

- validate the full OAuth authorization request
- fast-path remembered grants exactly as today
- otherwise create a pending request and render a consent page

Consent page behavior:

- server-rendered HTML, no app handoff required
- includes hidden request identifier
- includes a one-time decision token
- submits `POST /oauth/decision`

The consent page should not rely on background polling.

## `POST /oauth/decision`

This route is the critical new piece.

Required inputs:

- `request_id`
- `decision`
- `decision_token`

Valid `decision` values:

- `approve`
- `deny`

Behavior on approve:

1. load pending request
2. verify it is still pending and not expired
3. verify the decision token is valid, bound to that request, unexpired, and unused
4. create or reuse grant
5. issue authorization code
6. mark request completed
7. consume decision token
8. redirect to callback with `code` and original `state`

Behavior on deny:

1. load pending request
2. verify it is still pending and not expired
3. verify the decision token is valid, bound to that request, unexpired, and unused
4. mark request denied
5. consume decision token
6. redirect to callback with OAuth `access_denied` and original `state`

Failure behavior:

- invalid or reused token: render a clear error page
- expired request: render a clear retry message
- already completed request: render a clear completion message

## Consent Token Model

Approval must not be possible with `request_id` alone.

Use a one-time browser consent token tied to the pending authorization request.

Recommended model:

- generate a random `decision_token` when the pending request is created
- store only its hash in the auth store
- store token expiry alongside the pending request
- mark token consumed after a successful approve or deny

The token must be:

- single-use
- short-lived
- bound to one request
- invalid once the request leaves `pending`

This keeps browser approval safe without turning the popup into an unauthenticated control surface.

## Data Model Changes

### Pending Request Record

Extend the pending authorization request storage with fields equivalent to:

- `decision_token_hash`
- `decision_token_expires_at`
- `decision_token_consumed_at`

If the existing table becomes awkward, a small dedicated pending-request-decision table is also acceptable. Prefer the smaller schema that keeps the flow easy to reason about.

### Grant Metadata

Grant metadata should no longer say approval came from `"ursus-app"` if browser-first consent is the new model.

Recommended metadata cleanup:

- remove `approval_mode` from pending-request metadata
- replace `"approved_by":"ursus-app"` with a neutral or browser-specific value only if that information is actually useful
- avoid keeping metadata that exists only to explain the retired app handoff

## UI Plan

### Browser Consent UI

The consent page should be intentionally simple:

- title that clearly says the client is requesting bridge access
- client name
- scope summary
- protected resource summary
- concise note that approval affects access to the local Ursus bridge
- `Approve` and `Deny` buttons
- optional small link or secondary button to open `Ursus.app` for access management, not for mandatory approval

On successful approval or denial:

- redirect immediately when the OAuth client expects a callback
- if the popup remains visible, show a short completion page and attempt `window.close()`

The page should not tell the user to switch apps for normal approval.

### Ursus.app UI

Rename and narrow the current app auth surface so it reflects its new role.

Recommended direction:

- rename `Bridge Access Review` to `Bridge Access`
- remove pending-request approval copy and controls
- keep remembered-grant revoke controls
- keep auth summary text
- optionally add a recent activity section later if useful

If there is no strong reason to show pending requests in the app after the redesign, remove that section entirely.

## Cleanup Scope

Once the browser-first flow is implemented and tested, remove code that only serves the retired app-handoff flow.

Expected cleanup targets:

- `/oauth/request-status` route handling
- waiting-page HTML and polling JavaScript
- `approved` request status if no longer used
- app-side 1-second bridge auth refresh loop for pending-request surfacing
- app auto-activation on pending bridge auth requests
- pending-request approve/deny buttons in the app
- setup copy that says approvals are waiting in `Ursus.app`
- tests that exist only for the polling handoff

Keep only the app code that still serves an active purpose in the browser-first model.

## Files Likely To Change

- `Sources/BearMCPCLI/BearBridgeOAuthServer.swift`
- `Sources/BearMCPCLI/BearBridgeHTTPApplication.swift`
- `Sources/BearApplication/BearBridgeAuthStore.swift`
- `App/UrsusApp/UrsusAppModel.swift`
- `App/UrsusApp/UrsusBridgeAuthReviewSheet.swift`
- `App/UrsusApp/UrsusSetupView.swift`
- `Tests/BearMCPCLITests/BearBridgeHTTPApplicationTests.swift`
- `Tests/BearApplicationTests/BearBridgeAuthStoreTests.swift`
- `PROJECT_STATUS.md`
- `docs/ARCHITECTURE.md`

## Security Requirements

The browser-first design is acceptable only if these rules are enforced:

- no approve or deny action via `GET`
- no decision based on `request_id` alone
- one-time decision token required
- decision token stored hashed at rest
- decision token expiry enforced
- exact redirect URI matching preserved
- PKCE challenge preserved until token exchange
- resource binding preserved for grants and tokens
- remembered-grant lookup stays scoped to client, resource, and scope

Origin and CSRF checks are helpful, but the one-time decision token is the minimum hard requirement.

## Test Plan

Add or update tests for all of the following:

### Authorization Page

- first-time authorize request returns consent HTML with approve and deny actions
- remembered grant still skips consent and redirects immediately

### Decision Route

- approve decision returns callback redirect with `code` and `state`
- deny decision returns callback redirect with `access_denied` and `state`
- expired request cannot be approved
- invalid decision token is rejected
- reused decision token is rejected
- already completed request cannot be reused

### Token Flow

- authorization-code token exchange still works unchanged
- refresh-token rotation still works unchanged

### Protected MCP

- protected `/mcp` still rejects missing or invalid bearer tokens
- protected `/mcp` still accepts valid bridge-issued bearer tokens

### App Surface

- app bridge auth snapshot still shows remembered grants
- app no longer expects pending-request approval flow if that UI is removed

### Cleanup Validation

- `/oauth/request-status` returns not found once retired
- no test still depends on app approval to complete the primary OAuth flow

## Implementation Order

1. Update this plan only if implementation decisions materially change.
2. Add decision-token storage and helpers in `BearBridgeAuthStore`.
3. Refactor pending-request state machine and remove `approved` if implementation confirms it is unnecessary.
4. Rework `GET /oauth/authorize` to render a real consent page instead of a waiting page.
5. Add `POST /oauth/decision`.
6. Update auth-store and bridge tests for the new decision path.
7. Simplify `Ursus.app` auth UI to access management.
8. Remove `/oauth/request-status` and the app polling/foreground handoff.
9. Update architecture and status docs to reflect the shipped flow.
10. Run focused auth tests, then full `swift test`.

## Verification Checklist

Before merging implementation work:

- browser popup approval works end to end
- denial works end to end
- repeat authorization with remembered grant skips consent
- popup closes or clearly completes after redirect
- app still revokes grants correctly
- no remaining bridge OAuth code exists only for the retired app-handoff flow
- full test suite passes

## Suggested Final Product Copy

Use language like:

- browser: `Approve access to your local Ursus bridge`
- app: `Bridge Access`
- app summary: `Manage remembered access for clients that connect to the protected HTTP bridge.`

Avoid language that implies `Ursus.app` must be opened to finish OAuth.
