# Design System

## Scope

This document defines the visible product language for DSH Remote on iOS and Android. DSH Desktop continues to host the upstream Harness Web UI and should not be reskinned by these rules.

DSH Remote is a mobile continuation surface for a developer's computer. It should feel like the same Harness product expressed with native iPhone and Android ergonomics: compact, calm, information-rich, and explicit about remote state.

## Product hierarchy

The primary information model is:

`Computer → Project → Session → Conversation / Trajectory`

A task is not a separate top-level object. Running, waiting, completed, failed, queued, and confirmation-required are states of a session. Every screen should make the user's current computer, project, session, and execution state understandable without adding decorative chrome.

## Visual direction

- Use a flat canvas with hairlines and restrained surfaces. Do not turn every object into a card.
- Reserve high-radius containers for focused objects: composer, user messages, confirmation flows, and modal sheets.
- Match the DSH Web hierarchy: assistant output is flat, reasoning is a compact disclosure, tools are rows until expanded, and trajectory is a ledger.
- Use color to reinforce a written state, never as the only state indicator.
- Use system typography and native navigation semantics, while drawing all visible page, field, row, tab, and button shells with Remote components.

## Tokens

The platform sources of truth are `RemoteDesignSystem.swift` on iOS and `ui/theme/RemoteTheme.kt` plus `ui/components/RemoteComponents.kt` on Android.

### Color roles

| Role | Light | Dark | Usage |
| --- | --- | --- | --- |
| Canvas | `#F9FAFB` | `#151517` | Page background |
| Surface | `#FFFFFF` | `#232324` | Grouped content and composer |
| Raised surface | `#F6F7F9` | `#2C2C2E` | Selected rows and secondary controls |
| Muted surface | `#F1F3F6` | `#353638` | Quiet pills and search fields |
| Accent | `#2E5CBF` | `#679EFE` | Selection, primary action, active execution |
| User message | `#EDF3FE` | `#2C2C2E` | User-authored transcript content |

Semantic colors are green for success, amber for waiting or approval, red for failure or destructive action, violet for reasoning, and orange for tools. Hairlines adapt to appearance and remain lower contrast than text.

### Type

- Page identity: semantic `title2` or `headline`, depending on hierarchy.
- Body and transcript: semantic `body` / `subheadline`.
- UI labels: semantic `subheadline` / `caption`.
- Metadata: `caption2`, using monospaced digits only for measurements and sequence numbers.
- Avoid fixed small text. Fixed sizes are limited to symbols and code.

### Geometry

- Spacing rhythm: 4, 6, 8, 12, 16, 20, 24 points.
- Row radius: 8–14 points.
- Code and expanded tool radius: 12 points.
- Confirmation and modal card radius: 20 points.
- Composer and user message radius: 22 points.
- Every interactive target is at least 44 × 44 points, even when its visible glyph or pill is smaller.

## Shared primitives

- `RemotePageHeader`: custom visible header with native stack dismissal and edge-swipe support.
- `RemoteSheetHeader`: consistent modal title, context, and close action.
- `RemoteActionButtonStyle`: primary, secondary, ghost, and destructive actions.
- `RemoteIconButtonStyle` / `RemoteToolbarButtonStyle`: 44-point icon actions.
- `RemoteSectionHeader`: quiet section labels with optional metadata.
- `RemoteStatusPill`: concise status where text and color agree.
- `RemoteInlineNotice`: recoverable information, warning, failure, or success.
- `RemoteEmptyState`: one clear explanation and at most one primary action.
- `remoteSurface` / `remoteFieldSurface`: the only standard grouped-content and input shells.

Native `NavigationStack`, sheets, menus, text inputs, focus, refresh, and accessibility behavior remain in use. Default visible `List`, `Form`, inset-grouped sections, navigation titles, bordered buttons, and stock empty-state styling do not.

## Screen rules

### Computers and onboarding

The first screen explains the phone-to-computer relationship, leads with one connection action, and offers the offline experience only when no computer is saved. Saved computers use compact rows with transport and address, not promotional cards.

### Add computer and scanner

Prefer QR pairing. Manual input explains the HTTPS boundary before submission. Verification, storage, and notification permission occur only after the user explicitly connects. Camera failure always has a readable fallback state.

### Projects and sessions

Projects are disclosure rows in one quiet surface. Sessions remain visibly subordinate. Running state is shown at both project and session level. Directory-based grouping is explicitly labeled as a fallback when authoritative workspaces are unavailable.

### Conversation

Keep the transcript central. User content is a bubble; assistant content is flat. Reasoning is collapsed by default. Tools remain in execution order and expand in place. Context and lifecycle rows stay compact and lead to a native detail sheet.

Images belong to their originating message, without a surrounding gallery card. A single image uses a stable large preview; multiple images use compact tiles. Loading, success, and retry states reserve the same geometry so attachment delivery never steals scroll position.

Initial history appears already positioned at the latest item. Streaming follows only when the user is near the bottom or has just sent a message; otherwise an updates control appears without stealing the reading position.

### Composer, queue, and interaction

The composer is a sticky 22-point surface containing delivery, model, stop, and send controls. Queue content visually tucks behind it. A pending approval or question replaces the composer without losing transcript state or draft state. Options are custom rows and must not resemble a Settings form.

An active, paused, or blocked Goal appears as one quiet strip behind the composer and opens read-only details. Plan is a compact read-only label inside the composer controls. Durable Goal and Plan changes remain flat transcript and trajectory rows; they never become dashboards or standalone cards.

### Models

Model and reasoning choices use grouped custom rows. The deployment-default side effect must appear before any selectable model. Selection failures preserve the current value and remain retryable.

### Trajectory and details

Trajectory is a flat chronological ledger with a small execution overview, turn grouping, searchable summaries, and compact state glyphs. Detail sheets use a flat header, 44-point tabs, selectable text, code/diff surfaces, and a full-payload copy action.

### About and destructive actions

Privacy, transport boundaries, support, licensing, notification settings, and local data removal use the same custom rows and surfaces. Destructive actions require a dedicated confirmation sheet and state exactly what is and is not removed.

## Motion and accessibility

- Use short 0.12–0.22 second ease-out transitions for local state changes.
- Never animate the initial jump to the latest message.
- Respect Reduce Motion by avoiding ornamental or continuous animation; progress indicators may still communicate work.
- Preserve Dynamic Type, VoiceOver labels/values/hints, keyboard safe areas, native sheet dismissal, and interactive back gestures.
- Do not rely on truncated labels to carry critical state. At accessibility sizes, controls may reflow vertically.

## Acceptance checklist

Before shipping a visual change, verify the fresh-install onboarding, saved-computer list, add/scan/error flows, project loading/fallback/stale states, conversation and trajectory, detail types, queue edit, approval and questions, model loading/failure/selection, About, and destructive confirmation in light and dark appearance. Recheck at an accessibility content size and confirm that task execution, streaming, scroll ownership, queue authority, and unresolved interactions retain their prior behavior.
