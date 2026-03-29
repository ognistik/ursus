# PROJECT_STATUS.md

This file exists to preserve project context across Codex threads, workspace renames, and future contributors.

## What This Project Is

The current codebase implements a local macOS MCP server for Bear Notes with:

- Swift package/binary name: `bear-mcp`
- MCP server name presented to clients: `bear`
- local stdio transport
- direct SQLite reads from Bear's local database
- Bear x-callback-url writes for note mutations and UI actions

## What This Project Is Not

- not a generic MCP bridge
- not a remote MCP proxy
- not a Shortcuts-first runtime
- not an AppleScript-first runtime
- not a direct Bear database writer
- not a single giant branching tool

## Old System Reference Only

These old assets are important references but must not be modified as part of this project:

- Schema: `/Users/ognistik/Dropbox/2-Areas/SystemAndApps/Alter/Tools/Schemas/bear-notes`
- AppleScript bridge: `/Users/ognistik/Dropbox/2-Areas/SystemAndApps/Alter/Tools/Scripts/bear-notes.scpt`

The old tool proved the feature surface. It should not define the new architecture.

## Key Product Decisions Already Made

### 1. Swift is the chosen implementation language

Reasons:

- native macOS integration
- easier signing/notarization later
- good fit for SQLite, URL launching, and local CLI distribution
- aligned with a long-term shareable binary

### 2. Layering

Current package layout:

- `BearCore`: domain types, errors, config paths, template rendering
- `BearDB`: read-only Bear SQLite access through GRDB
- `BearXCallback`: URL building and Bear app launching for writes
- `BearApplication`: orchestration, guards, template application, mutation planning
- `BearMCP`: MCP tool registration and argument decoding
- `BearMCPCLI`: executable entrypoint

### 3. Read/write split

- Read note data locally from the Bear database.
- Do not write directly to the database.
- Perform writes through Bear's x-callback-url endpoints.
- For v1, verify many writes by polling the database after launching the Bear URL.

### 4. Replace strategy

The user explicitly clarified an important behavior:

- `bear_replace_content` should build the new full note content programmatically outside Bear.
- The write path should then use Bear's full replacement mode.
- Even when the user conceptually wants to change a title, a word, a phrase, or the entire content, the system can still compute the final full text locally and perform one full replacement write.

Current implementation follows that direction, and the app-side configuration editor now auto-saves validated changes directly back into the JSON-backed config instead of relying on an explicit manual save step.

### 5. Tool philosophy

- explicit tools
- batch-capable mutation inputs
- compact mutation receipts
- keep destructive actions separated

Tools intentionally excluded for now:

- trash
- unarchive

### 6. Inbox notes / discovery

The old inbox-style discovery behavior is important.

Current direction:

- represent inbox-note listing as an explicit discovery tool
- `bear_find_notes_by_inbox_tags` is driven by configured inbox tags from config
- discovery tools return compact note summaries, not full note bodies
- archive reads are explicit via tool input (`location: notes|archive`), not mixed into default note discovery

## Current Code Status

As of 2026-03-28, the repo contains a working initial scaffold plus note-tag mutation support, with Phases 1, 2, and Phase 3 of the app-unification plan now landed and manually validated end-to-end against the real Bear app, the current Phase 4 Keychain slice refined further so selected-note token access stays inside `Bear MCP.app`, and the current Phase 5 work now broadened in a more host-agnostic direction: the local app build embeds the `bear-mcp` CLI inside `Bear MCP.app`, the app now installs and repairs one public launcher at `~/.local/bin/bear-mcp` that forwards into the bundled CLI, normal dashboard launch automatically reconciles that launcher when it is missing or stale, doctor now reports both generic local-stdio readiness and the shared launcher path, the dashboard has moved beyond read-only diagnostics into a real editable configuration surface with tool enable/disable controls plus proactive launcher repair messaging when auto-management is not enough, and the terminal-facing CLI now has its first direct user utility flags for `--new-note`, `--apply-template`, and CLI-only note trashing through `--delete-note`. Host-specific snippets for Codex and Claude Desktop remain convenience guidance rather than the primary product direction. The app is increasingly the canonical product surface; the standalone helper remains only as a narrow fallback when the preferred app is missing.

Implemented:

- Swift package manifest and dependency graph
- real Bear DB reader against the installed Bear schema
- transient SQLite busy/locked retry handling on normal Bear DB reads
- config/bootstrap path helpers
- shared selected-note token resolution that prefers Keychain and falls back to legacy config
- non-secret config metadata that records whether the selected-note token is expected to live in Keychain, so CLI startup and tool exposure do not need an eager Keychain read
- routine doctor/dashboard settings loading now uses that non-secret Keychain hint instead of eagerly re-reading Keychain, so normal diagnostics avoid authorization prompts unless the user explicitly loads or changes the token
- single-file create-note template support
- runtime lock handling that prefers a shared process lock and falls back to temp locks when Codex launches additional stdio children
- stdio runtime shutdown that exits when the MCP connection closes or the original parent process disappears
- process-lock acquisition that prefers `~/Library/Application Support/bear-mcp/Runtime/.server.lock` and falls back to temp runtime locks when sandbox policy denies that location or another live stdio launch already holds the shared lock
- application service layer
- x-callback URL builder
- x-callback launcher transport with best-effort polling
- shared selected-note callback integration for Bear's token-backed `open-note?selected=yes` flow, with an embedded background helper app now preferred for interruption-free callback handling
- shared selected-note callback-host runtime in `BearXCallback`, now used by both the main app and the standalone helper shell
- first-party selected-note helper executable/app shell plus local `.app` bundling script
- minimal `Bear MCP.app` Xcode target that links shared package code through a local package product
- app bundle registration for `bearmcp://`
- headless callback-host mode in `Bear MCP.app` that preserves the response-file JSON contract used by the CLI
- embedded selected-note helper app support inside `Bear MCP.app/Contents/Library/Helpers`, so one installed app can launch an on-demand background callback host without stealing focus
- shared selected-note request authorization that can fill in a tokenless selected-note Bear URL before launching Bear, keeping managed-token access available to both the app shell and the helper shell
- app diagnostics/settings shell views backed by shared `BearApplication` dashboard snapshot loading
- app token-management controls for saving to Keychain, importing a legacy config token, and removing the token from both Keychain and legacy config
- local app build script for unsigned development bundles
- local app build script now embedding the `bear-mcp` CLI at `Bear MCP.app/Contents/Resources/bin/bear-mcp`
- shared bundled-CLI locator plus public-launcher install support for `~/.local/bin/bear-mcp`
- app settings actions for installing, repairing, copying, and revealing the public launcher path
- normal dashboard launch auto-reconciliation for the public launcher, so the shared host/Terminal path is refreshed from the current app bundle when needed
- doctor/dashboard diagnostics for bundled CLI presence and public launcher exposure, so stale launcher installs are surfaced clearly
- shared app/dashboard CLI health snapshots that expose one launcher status for both hosts and Terminal usage
- proactive dashboard CLI attention cards that surface launcher install/repair actions when needed
- generic local-stdio host guidance in the app/dashboard so local MCP setup is documented independently of any one host app
- shared host-app onboarding snapshots and diagnostics for Codex, Claude Desktop, and ChatGPT, all centered on the public launcher path
- app settings UI for host-app setup guidance, including copyable Codex/Claude snippets plus guided checks and local config-path reveal/copy actions
- editable app configuration UI for core defaults, discovery limits, inbox tags, and tool availability
- inline app configuration validation with debounced auto-save and per-field warning/error messaging
- config-backed tool enable/disable support that filters the live MCP tool catalog and rejects direct calls to disabled tools
- app lifecycle behavior that now quits when the last dashboard window closes, unless the app is running in headless selected-note callback-host mode
- background note-mutation URL normalization that explicitly sends `open_note=no` and `show_window=no` when notes should stay closed
- background Bear URL launches that now route through `open -g` plus hidden selected-note helper launches, keeping the visible dashboard app out of the selected-note callback critical path
- redacted x-callback debug logging that preserves behavior flags while hiding large note-text and file payloads
- explicit selected-note callback-host debug logging that records whether the app or helper path was chosen
- doctor/config support for visible-app detection plus embedded selected-note helper visibility
- MCP server/tool registration
- empty MCP resource/resource-template list handlers for client compatibility during discovery
- CLI commands: `mcp`, `--update-config`, `doctor`, `paths`
- direct CLI utility flags: `--new-note`, `--apply-template [note-id-or-title ...]`, `--delete-note [note-id-or-title ...]`
- a few core tests

Verified locally:

- `swift build`
- `swift test`
- `swift run bear-mcp doctor`
- `swift run bear-mcp --help`
- `CONFIGURATION=Debug Support/scripts/build-bear-mcp-app.sh`
- confirmed the local Debug app bundle now contains `.build/BearMCPApp/Build/Products/Debug/Bear MCP.app/Contents/Resources/bin/bear-mcp`
- confirmed `swift run bear-mcp doctor` now reports `bundled-cli`, `public-cli-launcher`, and `host-local-stdio`, and will flag an older launcher that has not yet been refreshed from the embedded CLI
- refreshed `~/Applications/Bear MCP.app` from the current Debug build, installed `~/.local/bin/bear-mcp`, and confirmed the public launcher now reports `bundled-cli` plus `public-cli-launcher` as healthy while describing the selected-note token as `Managed in Keychain` without a routine secure read
- manual MCP stdio `bear_get_notes` call with `selected: true` against the real Bear app while `Bear MCP.app` was not running, resolving the selected note through the installed app path with `callbackAppInstalled=true`
- manual MCP stdio `bear_get_notes` call with `selected: true` against the real Bear app while `Bear MCP.app` was already open in dashboard mode, resolving the selected note through the running app with `host=app reason=preferred-app-running reuseExistingInstance=true`

## Current Tool Surface

Implemented MCP tool names:

- `bear_find_notes`
- `bear_get_notes`
- `bear_list_tags`
- `bear_find_notes_by_tag`
- `bear_find_notes_by_inbox_tags`
- `bear_list_backups`
- `bear_delete_backups`
- `bear_open_tag`
- `bear_rename_tags`
- `bear_delete_tags`
- `bear_add_tags`
- `bear_remove_tags`
- `bear_apply_template`
- `bear_create_notes`
- `bear_insert_text`
- `bear_replace_content`
- `bear_add_files`
- `bear_open_notes`
- `bear_archive_notes`
- `bear_restore_notes`

## Current File Map

Primary files:

- `Package.swift`
- `BearMCPApp.xcodeproj`
- `App/BearMCPApp/BearMCPApp.swift`
- `App/BearMCPApp/BearMCPDashboardView.swift`
- `App/BearMCPApp/BearMCPAppModel.swift`
- `Sources/BearDB/BearDatabaseReader.swift`
- `Sources/BearApplication/BearAppSupport.swift`
- `Sources/BearApplication/BearSelectedNoteAppHost.swift`
- `Sources/BearApplication/BearService.swift`
- `Sources/BearApplication/BearBackupFileStore.swift`
- `Sources/BearCore/BearMCPCLILocator.swift`
- `Sources/BearCore/BearMCPAppLocator.swift`
- `Sources/BearApplication/BearHostAppSupport.swift`
- `Sources/BearXCallback/BearSelectedNoteCallbackHost.swift`
- `Sources/BearXCallback/BearXCallbackURLBuilder.swift`
- `Sources/BearXCallback/BearXCallbackTransport.swift`
- `Sources/BearMCP/BearMCPServer.swift`
- `Sources/BearMCPCLI/main.swift`
- `Sources/BearSelectedNoteHelper/main.swift`
- `docs/ARCHITECTURE.md`
- `docs/SELECTED_NOTE_HELPER.md`
- `Support/app/Info.plist`
- `Support/scripts/build-bear-mcp-app.sh`

## Current Runtime Paths

Current local runtime paths are:

- config: `~/.config/bear-mcp/config.json`
- note template: `~/.config/bear-mcp/template.md`
- public launcher: `~/.local/bin/bear-mcp`
- backups: `~/Library/Application Support/bear-mcp/Backups/`
- backup index: `~/Library/Application Support/bear-mcp/Backups/index.json`
- process lock (preferred shared path): `~/Library/Application Support/bear-mcp/Runtime/.server.lock`
- process lock (contention/temp fallback): `TMPDIR/bear-mcp/Runtime/.server.lock` and `TMPDIR/bear-mcp/Runtime/locks/<pid>.server.lock`
- temporary debug log: `~/Library/Logs/bear-mcp/debug.log`
- default Bear DB path:
  `/Users/ognistik/Library/Group Containers/9K33E3U3T4.net.shinyfrog.bear/Application Data/database.sqlite`

Important: repo/GitHub naming can change to `bear-inbox` without immediately changing these runtime paths.

## Important Implementation Details

### Search/read side

- The current DB reader queries `ZSFNOTE`, `ZSFNOTETAG`, and `Z_5TAGS`.
- Find currently uses structured SQL filtering over title, body, tags, tag presence, dates, attachment presence, and attachment OCR/index text.
- Discovery tools always exclude trashed notes.
- Discovery tools search either normal notes or archived notes, never both in one call.
- MCP tool descriptions now explicitly steer clients to omit `location` unless the user asks for archived notes, and user-overridable defaults are injected from the loaded config at startup.
- MCP tool descriptions now explicitly steer clients away from calling `bear_get_notes` only to resolve note selectors before note-targeting mutations, and `expected_version` descriptions frame that field as an optional optimistic-concurrency guard rather than a default requirement.
- `bear_list_tags` now defaults `location` to `notes`, excludes trashed and permanently deleted notes, returns location-scoped tag counts, and supports optional `query` and hierarchical `under_tag` filters.
- MCP tag-tool descriptions now cross-reference `bear_list_tags`, `bear_find_notes_by_tag`, and `bear_open_tag` so clients have clearer discovery hints when an exact tag name is required versus when the goal is UI navigation.
- `bear_get_notes` now defaults `location` to `notes`, never returns trashed notes, and only searches archived notes when `location: archive` is explicitly requested.
- `bear_get_notes` now accepts a single `notes` selector array, resolves each selector as exact note id first and then exact case-insensitive title within the requested location, preserves selector order, and deduplicates results by note id.
- When config indicates selected-note token availability, note-selector tools expose `selected: true` as an alternative to explicit selectors. The MCP layer now prefers resolving the selected Bear note through an app-hosted `bearmcp://` callback in the separately installed `Bear MCP.app`, captures Bear's callback `identifier`, and then reuses that concrete note id through the existing read/write pipeline. On the preferred app-installed path, the CLI now sends a tokenless selected-note request and lets `Bear MCP.app` inject the managed token locally before Bear is launched. If the app is already open in dashboard mode, the CLI reuses that running instance by sending it a `bearmcp://` start-request URL that preserves the existing response-file JSON contract. The standalone helper app remains available only as a narrow fallback when the preferred app is not installed.
- `bear_find_notes`, `bear_find_notes_by_tag`, and `bear_find_notes_by_inbox_tags` now share a batched summary result shape. Each operation returns compact note summaries with note id, title, body snippet, optional attachment snippet, optional matched fields, tags, created/modified timestamps, archive status, and pagination metadata, or an inline error.
- Discovery pagination is cursor-based per operation. Discovery tools accept an optional opaque `cursor`, return `hasMore` plus `nextCursor`, and paginate over the full internal sort key.
- Internal tag values are normalized as bare tag names. When rendering note text, single-word tags use `#tag` and tags containing whitespace use Bear's wrapped form `#tag with spaces#`.
- Bear's DB tag list remains the effective/discovery view, which may include implicit parent tags for subtags. Template matching and note-tag mutations now separately parse literal tag tokens from note text so DB-expanded parent tags do not poison template-aware reads or writes.
- Discovery limits and snippet lengths are config-driven defaults with per-operation overrides and server-side hard caps, and the live default/cap values are injected into MCP property descriptions at startup.
- Snippets are template-aware when the current template can be matched back to the stored note body; otherwise they fall back to the parsed note body.
- Attachment snippets are built from `ZSFNOTEFILE.ZSEARCHTEXT` in attachment insertion order and truncated with the same configured snippet limit.
- `bear_find_notes` supports query-less filtering by tags, presence flags, or dates and accepts supported past/present natural-language date phrases that are resolved server-side in the local timezone.
- Text discovery now applies deterministic ranking when `text` is present: exact full-query phrase matches sort ahead of ordered-term matches, which sort ahead of unordered all-term matches, with ties broken by modified date plus note id. Filter-only discovery still uses pure recency ordering.
- `from` and `to` are inclusive bounds rather than named-period presets; using the same phrase on both sides narrows the query to that one resolved interval.
- Notes are normalized into typed models.
- Full note fetches now return a lean structured record with `noteID`, `title`, canonical template-aware `content`, tags, timestamps, version, and per-file attachment records including Bear's attachment search text when available. The exposed note `version` now tracks Bear's changing SQLite row revision field (`Z_OPT`) rather than the mostly static `ZVERSION` column.
- Attached file OCR/index text currently comes from `ZSFNOTEFILE.ZSEARCHTEXT` and is returned separately from note content.
- Normal DB reads now do a short bounded retry on transient SQLite busy/locked errors so immediate post-write reads are more resilient when Bear is still settling its local database.

### Config behavior

- Missing config keys fall back to defaults in memory during load.
- `bear-mcp --update-config` rewrites `config.json` in canonical current format, preserving existing values while filling in any newer keys.
- `bear-mcp --update-config` is now considered temporary compatibility behavior. Once the app provides an easy built-in path for config migration and CLI refresh/update flows, this flag should be removed rather than kept around as dead code.
- `config.token` is still retained as a compatibility fallback for selected-note access, but the preferred source of truth is now Keychain and the longer-term direction is to remove routine dependence on the JSON token field.
- when no legacy config token exists, config encoding now omits the `token` key entirely instead of writing `"token": null`
- `backupRetentionDays` controls durable backup retention under Application Support. `0` disables capture and prunes stored backups.

### Mutation side

- Create builds final text locally, then uses Bear x-callback create.
- Create uses a config-driven default for whether the new note opens at all, plus config-driven open style defaults when it does open.
- Create uses config `tagsMergeMode` as the default for how requested tags combine with configured inbox tags, and `bear_create_notes` can override that per operation with `use_only_request_tags` when the user explicitly asks.
- Before note-destructive mutations (`bear_insert_text`, `bear_replace_content`, `bear_add_files`, `bear_apply_template`, and `bear_restore_notes`), the service now captures one pre-mutation backup snapshot per logical note operation in a durable file-backed store under Application Support. Template-aware multi-step add-file flows snapshot only once before internal anchor writes so backup history does not include temporary transport states.
- Note-targeting mutation tools now accept title-or-ID selectors at the MCP surface. Selectors resolve as exact note id first, then exact case-insensitive title across notes and archive, and ambiguous title matches require the note id.
- `bear_get_notes`, `bear_list_backups`, `bear_delete_backups`, `bear_add_tags`, `bear_remove_tags`, `bear_apply_template`, `bear_insert_text`, `bear_replace_content`, `bear_add_files`, `bear_open_notes`, `bear_archive_notes`, and `bear_restore_notes` now also support selected-note targeting when the Bear API token is configured.
- Insert now supports both top/bottom placement and relative-target placement. Without a relative target, it tries to preserve the current note template: when template management is enabled and the current note matches the current `template.md`, the service inserts inside the `{{content}}` region locally and writes the full note back through `replace_all`; otherwise it falls back to Bear's direct add-text prepend/append path. Omitted `position` still defaults to config `defaultInsertPosition`. With a relative target, the service resolves one heading-title or exact editable-content string match and writes the updated note through `replace_all`.
- Replace content computes full new note text locally from title/body/content-scoped edit intents, then writes through add-text with `replace_all`.
- Note-tag mutations are split by scope: `bear_add_tags` and `bear_remove_tags` edit one note's literal tags through full-body replacement, while `bear_delete_tags` deletes a tag globally through Bear's official x-callback action.
- Template-aware note-tag mutations now treat the current template as the highest-priority tag placement when a note matches it and the template contains `{{tags}}`. If no template match exists, add-tags extends the first raw tag-only cluster when found; otherwise it applies the current template to the note when template management is enabled or inserts one canonical tag line at the configured default position when template management is disabled. When template management requires that fallback template application and `template.md` is missing or lacks a valid `{{tags}}` slot, add-tags now fails clearly so the template can be fixed before continuing.
- `bear_apply_template` is an explicit batched normalization tool. It always loads the current `template.md`, even when template management is disabled for other flows, migrates all tag-only clusters from editable content into the template `{{tags}}` slot, preserves inline prose hashtags, de-duplicates tags in first-seen order, cleans whitespace after cluster removal, and re-renders the full note through Bear's full replacement path. Missing or invalid `template.md` files now fail clearly for this tool.
- For note-opening mutation flows, omitted `new_window` now consistently falls back to config `openUsesNewWindowByDefault`.
- Background note mutations now always serialize `open_note=no` and `show_window=no` when the effective presentation keeps the note closed, even if the client omitted `open_note` and the closed state came from defaults.
- x-callback debug traces now log the outgoing action plus a redacted query summary so `open_note`, `show_window`, `new_window`, `mode`, and similar flags can be inspected without dumping full note text or base64 file payloads.
- Selected-note callback invocation now redacts token-bearing callback URL/query data in debug traces, and transport error messages no longer echo full token-bearing URLs.
- `Bear MCP.app` now has a headless callback-host mode: it can be launched with the existing response-file contract, rewrite Bear's `x-success` and `x-error` targets to `bearmcp://`, receive the callback, write the same JSON payload the CLI already expects, and exit without changing the CLI-facing runtime contract.
- When `Bear MCP.app` is already running in dashboard mode, the CLI now sends that live app instance a `bearmcp://x-callback-url/start-selected-note-host?...` request so it can start an in-process callback session without quitting or relaunching the app, while still returning the same response-file payload the CLI already expects.
- The standalone selected-note helper executable remains a thin shell around the same shared `BearSelectedNoteCallbackHost` logic in `BearXCallback`, preserving a narrow helper fallback path when the preferred app is not available.
- Add file now defaults omitted `position` to config `defaultInsertPosition`, base64-encodes the local file payload for Bear's documented `add-file` URL parameters, and supports both top/bottom placement and relative-target placement. For template-aware top/bottom placement, it preserves current template boundaries by inserting through a temporary backend-only header anchor inside the `{{content}}` region before cleaning that anchor back out with `replace_all`. For relative-target placement, it uses the same anchor orchestration for both templated and non-templated notes after resolving one heading-title or exact editable-content string match. Cleanup now tolerates Bear rewriting the anchor line by appending the attachment inline instead of leaving the header on its own line. In every anchor-managed path, Bear's header-targeted add-file call uses `prepend`; final placement is determined by where the temporary anchor is inserted in editable content.
- `bear_list_backups` returns compact snapshot summaries for one note or across notes, `bear_delete_backups` deletes one explicit `snapshot_id` or clears one note's saved backup history when `delete_all: true` is paired with a note selector, and `bear_restore_notes` restores either the latest saved snapshot for a note or an explicit `snapshot_id`.
- Open tag uses Bear open-tag for a single canonical tag name and returns a compact UI-action receipt rather than note data.
- Rename tags use Bear rename-tag with batched `operations: []` input and only send `show_window` when the caller explicitly requests it.
- Delete tags use Bear delete-tag with batched `operations: []` input and only send `show_window` when the caller explicitly requests it.
- Open uses Bear open-note.
- Archive uses Bear archive.

### Receipt behavior

- Mutations return compact receipts by design.
- Create currently uses best-effort note discovery by title and recent modification time.
- Other mutations try to verify completion by polling Bear's DB for concrete note-state changes such as version, modified timestamp, raw text, and attachment-count deltas rather than relying on version bumps alone.
- Tag rename and delete use best-effort verification by polling tag lists across both notes and archive locations.

## Known Gaps / Risks

- Live write behavior has not yet been validated end-to-end for every Bear x-callback action.
- Create receipt matching is heuristic and may be ambiguous when titles collide.
- Keychain-backed token storage is now wired for selected-note resolution, and the preferred app-installed path now keeps Keychain reads inside `Bear MCP.app`, but the repo still keeps a legacy `config.token` fallback for compatibility until broader migration/cleanup is complete.
- The repo now includes a working app-hosted callback path, running-instance reuse for the installed app, a narrow helper fallback, standard-location detection that prefers `/Applications/Bear MCP.app` while still fully supporting `~/Applications/Bear MCP.app` for user-specific installs, and the first Phase 4 Keychain-backed token-management slice, but it does not yet ship signed release artifacts or a broader editable settings UI beyond token management.
- The current app UI is functionally ahead of its information architecture: it now exposes real editing/onboarding surfaces, but the Overview, Hosts, Configuration, and Token tabs still carry too much implementation detail and too much explicit save/setup ceremony for the intended polished app-first product.
- The public launcher currently prefers the current app bundle path and standard app-install fallbacks, so app moves outside `/Applications` or `~/Applications` still rely on reopening the app to repair the launcher.
- Closing the main app window currently leaves the app running. That default macOS lifecycle behavior is now a UX mismatch for the current product because the app is not intended to provide background-only functionality.
- Backup restore is strongest for note-text mistakes. Attachment-related rollback is still best-effort because restoring saved raw markdown cannot perfectly model every Bear attachment side effect.
- Find now has deterministic text-aware ranking, but it still does not use fuzzy matching, typo tolerance, stemming, BM25, or SQLite FTS scoring.
- Runtime config directory is still named `bear-mcp`; migrating it to `bear-inbox` would be a separate compatibility decision.
- Debug tracing now writes under `~/Library/Logs/bear-mcp/debug.log` with simple size-based rotation.
- The preferred shared runtime lock lives under `~/Library/Application Support/bear-mcp/Runtime/.server.lock` so the user-facing config folder only contains editable files.
- When Codex launches additional stdio MCP children while another Bear server is already running, the runtime now falls back to temp per-launch lock files instead of refusing to start.
- The stdio server now shuts down on either transport EOF or loss of the original parent PID so Codex restarts do not leave orphaned MCP instances holding the lock.
- When the preferred Application Support lock path is not writable under the client sandbox, the server falls back to a temp-directory lock path so Codex can still launch the MCP process.

## User Preferences That Should Survive Future Threads

- Favor easy local installation and eventual GitHub sharing.
- Keep the local MCP architecture first-class; remote/proxy work is a separate project.
- Keep the old Alter/Shortcuts bridge untouched.
- The create template matters for creation behavior, tag placement, and template-aware insert positioning.
- The MCP surface should stay simple: note mutation tools only expose `open_note` and `new_window`, `bear_open_notes` only exposes `new_window`, `bear_open_tag` accepts a single canonical `tag`, and `bear_rename_tags` only exposes optional `show_window`.
- Create defaults are config-driven for whether creation opens the note; explicit `open_note` and `new_window` values override config for that request.
- User-overridable defaults should be reflected in MCP tool descriptions using the live loaded config, but internal-only config should stay out of the schema text.
- User phrasing like "floating window" should map to `new_window`; the server should not emit Bear's `float` URL parameter.
- Bear x-callback URLs should use an action-aware activation policy: UI-navigation actions and note-opening mutations foreground Bear, while background mutations stay unfocused.
- Presentation flags in MCP mutation inputs are optional overrides and should normally be omitted so config defaults apply.
- Batch operations matter.
- Returning giant note bodies after mutations wastes tokens and should usually be avoided.
- The project name `aft-bear` was rejected.
- The likely public repo name is now `bear-inbox`.
- The MCP itself being named `bear` is acceptable.

## Recommended Next Steps

1. Continue simplifying the app UI now that auto-save is in place: reduce Overview clutter further, keep host guidance detected-only where possible, and trim low-value implementation details from primary views.
2. Add lightweight first-run and post-update refresh prompts/checks so missing or stale CLI copies are repaired proactively from the app.
3. Add direct user-facing CLI utility commands for selected-note workflows: `--new-note`, `--delete-note`, and `--apply-template`.
4. Remove `--update-config` after the app owns config migration and CLI refresh/update flows cleanly enough that the flag no longer provides meaningful value.
5. Clean up remaining runtime/config details as a coordinated compatibility pass: move debug logs into Application Support and plan any bundle-id / Keychain namespace migration together rather than piecemeal.
