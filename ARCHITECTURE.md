# Architecture

## Boundaries

- `Core/Domain.swift`: immutable/value occurrence snapshots, preferences, recurrence rules, states, retention.
- `Core/Scheduler.swift`: deterministic state reduction, command validation, delivery gates, reconciliation, next deadline.
- `Core/WallClock.swift`: date-only/all-day local clock resolution.
- `Core/DeadlineDriver.swift`: injectable single-deadline driver; production uses one nonrepeating main-run-loop timer with 250 ms tolerance.
- `Core/SQLiteStore.swift`: versioned transactional durable persistence through system SQLite.
- `Adapters/EventKitAdapter.swift`: serialized main-actor EventKit operations, permissions, read-only event fetches, guarded reminder completion. Every query uses its own store; no cached EventKit objects cross async boundaries. Reminder callback objects are converted into Sendable value snapshots before resuming the caller.
- `Adapters/Notifications.swift`: contextual authorization, stable bounded fallback requests, foreground deduplication, and notification action dispatch.
- `AppModel.swift`: main-actor application coordinator. Injects clock, deadline driver, store, source adapter, notification sink, and presentation sink. Implements commit-before-publication, refresh generations, recovery gates, commands, and lifecycle subscriptions.
- `Presentation/OverlayCoordinator.swift`: owned panels/dim windows, screen selection, display changes, sound, focus policy, and SwiftUI host updates.
- `Views/`: source selection, onboarding, editors, list/history, settings, menu, diagnostics.

No private API, input interception, screen recording, Automation, Accessibility permission, network client, helper, or source calendar writes are used.

## Occurrence identity

Each normalized occurrence has an internal UUID, source kind, stable calendar/list ID, account/source ID, provider item ID, external provider ID when available, recurrence anchor/original occurrence date, current due/end, and local-series UUID when applicable. Titles, URLs, and due times alone never identify an item.

Reconciliation is confined to the same source and account. A provider ID or nonempty external ID must match; recurring items additionally require the same recurrence anchor. This preserves the internal UUID, terminal state, snooze, timing/ceiling overrides, and outcome through normal edits and identifier changes. Wednesday cannot inherit Tuesday's acknowledgement. Copies across calendars remain separate.

Multiple matches produce an `identity.ambiguous` diagnostic, preserve prior states, and suppress those items. Unmatchable identifier-and-anchor changes become fresh items rather than inheriting another item's dismissal. This is conservative and cannot solve every provider identity rewrite; see limitations.

A successful fetch cancels unmatched unresolved occurrences from that source kind, distinguishing source deselection, disappearance, and source removal/completion. A failed fetch never invokes destructive reconciliation. Existing snapshots stay present, with external delivery validation withheld. An earlier async result cannot overwrite a newer generation. Deselecting never substitutes a same-named source.

## State machine and commands

| State | Valid next states |
| --- | --- |
| scheduled | eligible, acknowledged, snoozed, completed (tasks), skipped, expired (events), cancelled (source reconciliation) |
| eligible | presenting, acknowledged, snoozed, completed (tasks), skipped, expired (events), cancelled |
| presenting | acknowledged, snoozed, completed (tasks), skipped, expired (events), cancelled |
| snoozed | eligible after elapsed/recovered deadline and current first lead, acknowledged, completed (tasks), skipped, expired (events), cancelled |
| acknowledged / completed / skipped / expired / cancelled | terminal; duplicate actions are idempotent no-ops |

Completion on calendar events and missing IDs are rejected. Invalid/past snoozes are rejected. Calendar snoozes cap at expiry; Escape skips when a useful snooze is unavailable. Pause, quiet hours, unavailable sources, disabled delivery, and unusable sessions are gates, preserving unresolved states. `presenting` records delivery eligibility/presentation history; a gate can hide its surface without destroying the occurrence.

Local recurring resolution generates one next future wall-clock occurrence. The series definition survives. Skip/acknowledgement also advance the series. An unresolved recurring task remains one pending item rather than generating an accumulating backlog. Editing/deleting the series is a separate confirmed operation. Apple recurring source completion is rejected in the real adapter until provider behavior is verified.

Join validates the selected URL and waits for the OS handler handoff. Only then does it commit “Link opened”; it never claims attendance. Failed handoff retains the reminder. HTTPS plus narrowly constrained Zoom/Teams schemes are allowed. Structured URLs precede detected note links. Source text is rendered as text.

## Transaction and recovery order

1. Copy current value state and scheduler bookkeeping.
2. Validate/reduce the command into the candidate.
3. Encode and commit SQLite state inside `BEGIN IMMEDIATE` / `COMMIT`.
4. Publish the candidate and engine bookkeeping.
5. Update/close the interruption surface and reconcile notifications.

Storage failure leaves the published reminder and action recoverable. A crash after commit and before UI closure cannot resurrect the action: the next process reads terminal/snoozed state. Source completion is necessarily a separate external transaction. If Apple saves completion and the local commit fails, the UI reports local failure and retains pending state; retry/refetch safely reconciles the already-completed source item. No claim of an atomic cross-store transaction is made.

SQLite uses WAL, synchronous FULL, a busy timeout, version 1 schema, quick integrity checking, and a singleton encoded state row. Future schema versions and undecodable/corrupt stores fail closed without deleting originals. Explicit recovery closes the failed connection, preserves database/WAL/SHM in a unique Recovery directory, and creates a new store. Reset has a confirmation and never modifies sources.

History details are cleared after the configured retention period. Old local terminal occurrences are removed. Terminal external identities still present in a successful working fetch retain a minimal redacted delivery record, preventing a dismissed incomplete source task from becoming new after history expiry. Obsolete external records can be removed after a successful fetch confirms absence. Ordinary logs contain bounded category strings (500 entries), not source content.

## Time, stages, and gates

The scheduler receives a clock and returns a grouped presentation and earliest future deadline. The driver owns one nonrepeating timer; source recovery runs separately at five-minute intervals. No permanent high-frequency poll or hidden countdown is used. The relative menu label refreshes on state/source/deadline changes rather than a per-second timer.

The current stage is computed directly from ordered lead instants. Coincident stages merge. Joining late skips missed stages. Global and item ceilings cap delivery, and fullscreen has an independent opt-in. A higher-intensity queue excludes items whose ceiling would be exceeded. Resolving a queued item updates the host without creating a new sound for each remaining item.

One-off deadlines are instants. Recurring rules are local calendar components. DST gaps use `.nextTime`; folds use `.first`, once per date. Monthly days clamp to month end. Time-zone changes recompute future scheduled local recurring occurrences. A running snooze uses system uptime; restart recovers from its absolute persisted deadline. Snoozed events moved later cannot present before their new first lead. Explicit task snoozes get a persisted bounded resumed window; tasks otherwise stop automatic interruption after their due-time window and remain Pending.

On startup/wake/session return/manual resume, source validation is cleared, local reminders can continue independently, and external items are refetched before presentation. Catch-up is one prominent-or-lower queue. Expired calendar events never cascade through fullscreen. Pause expiry and quiet-hours exit permit a grouped catch-up. Settings and lifecycle changes immediately close gated surfaces and cancel/suppress fallback requests.

## Windows, focus, and privacy

Panels use public `.floating` level and `.canJoinAllSpaces`, `.fullScreenAuxiliary`, `.stationary` behaviors available at macOS 14. No security/login-window level is used. Card display is selected from the pointer's screen with a main-display fallback. Optional other-screen dim windows ignore mouse events. All windows close together, and screen-parameter changes rebuild the owned set.

Real panels are nonactivating, redacted, and click-interactive. Reliable public lock detection is unavailable in this implementation. `sessionDidBecomeActive` is treated as session switch-in, not an unlock notification. Sleep, display sleep, and session switch-out conservatively close/gate delivery. The explicit fullscreen demo can activate and restore the previous still-running app when appropriate. Focus from real typing is not automatically stolen. A 600 ms arming guard protects primary actions; Escape/Stop and Pause are available immediately. No global key handler is installed, so keyboard commands belong to the panel after it receives keyboard focus.

## System notifications

Fallback defaults off. Stable `UUID.fallback` identifiers and one category dispatch acknowledgement/snooze through the coordinator. Foreground delegate delivery is suppressed because custom presentation owns the running-app surface. Only the first eligible future stage or snooze deadline is scheduled, with a conservative app bound of 32. The bound is an app policy, not a claimed OS maximum.

Reconciliation cancels older generations. Adds are serialized behind the prior generation so a cancelled async add cannot resurrect a request or remove a newer same-ID request. Source gates and quiet hours filter the working set. Notification actions refetch before modifying current occurrences. The quit policy explicitly chooses cancel or retain; no app calendar-update mechanism runs while quit. Focus and OS-delayed notification delivery remain controlled by macOS.
