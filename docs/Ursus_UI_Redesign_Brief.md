# Ursus UI Redesign Brief

## Product intent

Ursus.app is not a diagnostics dashboard.

It is the setup and repair companion for Ursus, a local macOS MCP runtime for Bear. The window should help normal users:

1. get Ursus working quickly
2. change a small set of durable preferences
3. repair a broken bridge or host setup when needed

The app should stop presenting itself as a runtime inspector.

## Product truths to preserve

- Ursus is a local macOS app and MCP runtime for Bear.
- Canonical MCP path remains stdio.
- Optional localhost HTTP bridge remains important and user-visible.
- Reads come from Bear SQLite.
- Writes go through Bear x-callback-url actions.
- Template editing remains part of the app.
- Tool availability controls stay available, but not in the main surface.
- CLI remains the place for diagnostics, paths, and deeper inspection.

## Core UX stance

- Optimize for normal users first.
- No first-run modal onboarding flow that can be missed or become stateful baggage.
- The main app window itself should communicate the setup sequence clearly.
- Show only state that changes what the user should do next.
- Move explanation-heavy material to docs or hover help.
- Remove implementation detail from primary screens.

## Primary user journey

The main journey is:

1. Configure defaults
2. Save Bear token
3. Connect an app or enable the bridge
4. Done

This should be reflected directly in the UI hierarchy.

## Information architecture recommendation

Replace the current dashboard-style 4-tab structure with a calmer task-based structure.

### Recommended top-level structure

#### 1. Setup
Primary screen. This is the default destination.

Contains only:
- Bear token section
- Preferences summary / most important defaults
- Connect Apps section
- Bridge section

This screen should be enough for most users.

#### 2. Preferences
Secondary screen for durable customization.

Contains:
- Template management enabled toggle
- Template editor, only visible when template management is enabled
- Inbox tags editor with chips/pills UI if practical
- Create opens note by default
- Open uses new window by default
- Create adds inbox tags by default
- Default insert position
- Tags merge mode
- Default discovery limit
- Default snippet length
- Backup retention days

Do not expose database path here.

#### 3. Advanced
Hidden from the primary flow, but still available.

Contains:
- Tool availability controls
- Reveal config
- Reveal template
- Open logs / reveal logs if truly needed
- Any deeper repair actions that remain useful

Do not put runtime diagnostics wall, file path inventory, or raw internal status matrix here unless they are highly condensed and actionable.

## Setup screen behavior

### Bear token
Keep simple:
- one status line
- input field
- save / replace
- remove
- show / hide token if already stored

Remove extra explanatory copy except one short helper sentence.

### Connect Apps
This should be compact and purpose-driven.

Show only relevant integrations:
- Codex if detected
- Claude Desktop if detected
- Bridge always available

For local stdio hosts:
- present a clean card or row with app name and status
- provide a primary action like Copy Setup or Copy Snippet
- optionally provide a secondary small action to reveal config
- do not show raw JSON/TOML snippets by default
- do not show generic stdio example in the main UI

For apps not installed:
- hide them rather than showing warning states

Do not show ChatGPT block in the app.

### Bridge
Bridge should be visible and easy, but not verbose.

Keep:
- running / not running status
- MCP URL
- copy URL
- install / repair / pause / resume / remove
- editable port

Remove from main surface:
- launcher path
- LaunchAgent path
- stdout/stderr reveal actions
- protocol-health phrasing unless something is broken
- long explanation text

If bridge has an error, then show concise inline troubleshooting with one action.

## Preferences screen behavior

### Template
Template editor stays in-app.

Requirements:
- only visible when template management is enabled
- compact text editor sized for short templates
- inline validation
- no need to push users to edit raw file in Finder

### Inbox tags
The current text field is too raw for the importance of this setting.

Preferred direction:
- pill/chip editor if practical
- otherwise a cleaner tokenized multi-value field

### Tool availability
Keep available, but not in main settings flow.
This is advanced host-control behavior, not a first-class beginner preference.

## What to remove from the current UI

From Overview:
- full runtime checks block
- paths section
- launcher detail block as a major section
- green/orange/red walls of status
- implementation-heavy bridge detail text

From Hosts:
- host guidance essay
- generic stdio example
- always-visible snippets
- ChatGPT section
- merge notes and long guided checks in expanded detail by default

From Configuration:
- database path from primary user-facing preferences
- huge one-screen settings wall
- always-visible tool availability block in the main form
- open/reveal template emphasis over actual in-app editing

## Interaction and visual direction

Use the design skills as constraints, not decoration.

### Apply from redesign-skill
- improve the existing SwiftUI structure rather than rewriting the app from scratch
- remove dashboard tropes and generic card overload
- add more whitespace and reduce density
- use stronger hierarchy and fewer repetitive containers

### Apply from taste-skill
- keep visual density low
- use clear above-field labels, concise helper text, and inline errors
- use cards only when hierarchy truly needs elevation
- prefer grouping by spacing/dividers over boxing every section

## State model

The app should mostly show these states:
- ready
- needs setup
- needs attention

Avoid showing every internal subsystem state.

Examples:
- Good: “Bridge is running”
- Good: “Token missing”
- Good: “Codex detected”
- Bad: “process-lock-fallback ok”
- Bad: “backups-metadata ok”
- Bad: full path inventory in normal mode

## Recommended implementation strategy

Do this in phases, not one giant rewrite.

### Phase 1: information architecture cleanup
- define the new screens and section hierarchy
- remove Overview as a diagnostics dashboard
- remove Hosts as a verbose host encyclopedia
- decide whether Setup becomes the default landing screen

### Phase 2: strip implementation detail
- remove runtime checks from main UI
- remove path inventory from main UI
- remove ChatGPT block
- hide generic stdio example
- condense bridge section to actionable controls only

### Phase 3: simplify preferences
- move durable settings into a smaller user-friendly preferences surface
- hide advanced settings from the main preferences flow
- keep template editor in-app and simplify its presentation
- improve inbox tags editor presentation

### Phase 4: conditional host presentation
- detect installed host apps and show only relevant ones
- keep snippets copyable, but not visible by default
- reduce reveal-config actions to secondary affordances

### Phase 5: polish
- improve spacing, section rhythm, labels, helper text, and inline status treatment
- reduce colored noise
- use fewer boxes and more visual breathing room

## Files and areas to inspect first

- `UrsusDashboardView.swift`
- related view models in `UrsusAppModel`
- host detection and host snapshot production
- bridge status snapshot production
- configuration field grouping and any settings snapshot types

## Architectural constraints

- Do not change the underlying Ursus product architecture.
- Do not blur the stdio-first product truth even if bridge becomes more prominent in UI.
- Do not remove bridge support.
- Do not remove template editing.
- Do not remove tool availability controls entirely.
- Do not add onboarding state machines unless explicitly requested later.
- Prefer deleting old UI paths instead of preserving old dashboard surfaces behind compatibility flags.

## Definition of success

A normal user should be able to open Ursus.app and understand within seconds:
- whether Ursus is ready
- where to paste the token
- how to connect their app
- how to copy the bridge URL if they want the bridge
- where to change the few defaults they actually care about

Anything beyond that should be secondary.
