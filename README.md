# Dreadline

A local-first native macOS menu-bar calendar and persistent-reminder utility. Working name; neutral system styling. Swift 6, SwiftUI/AppKit, EventKit, SQLite, UserNotifications, and ServiceManagement. macOS 14 or later. Universal arm64/x86_64 app. No runtime packages, account, server, LLM, telemetry, or app network client.

## Build and run

Use full Xcode with its Command Line Tools selected:

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/run.sh
```

The shared scheme is `Dreadline` in `Dreadline.xcodeproj`. No project generator or dependency download is required. `scripts/generate-project.py` is an optional deterministic, standard-library-only maintenance tool for adding source files; the Xcode project itself is supplied.

Build output: `build/DerivedData/Build/Products/Debug/Dreadline.app`. Build/test scripts use ad hoc local signing (`CODE_SIGN_IDENTITY=-`) and retain App Sandbox and privacy entitlements. The local app is not Developer ID signed or notarized. Xcode compiler plugins and XCTest require a normal developer terminal; restricted automation sandboxes may require permission to run these commands outside that sandbox.

Create a local ZIP without replacing earlier packages:

```sh
./scripts/package-local.sh
```

It prints a new timestamped folder under `build/`. Prepare a signed release archive and ZIP with your own development team:

```sh
DEVELOPMENT_TEAM=YOUR_TEAM_ID ./scripts/release.sh
```

Release packaging refuses existing archive/ZIP destinations. It does not upload or notarize. Use Xcode Organizer for Developer ID export, then explicitly perform notarization/stapling before distribution. No signing identity or credentials are embedded.

## First use

1. Launch the app. The main window and menu-bar entry remain available without permission.
2. Preview reminder stages. The demo uses only ephemeral sample state; it never fetches or writes source data, persists an action, or schedules notifications. End the preview or press Escape; it also ends after 60 seconds.
3. In Settings → Sources, connect calendars or Apple Reminders separately. Select specific calendars/lists. Nothing is selected automatically.
4. In Settings → Behavior, preview and explicitly enable real alerts. Choose the ceiling; fullscreen requires its own opt-in. Save settings. Local reminders work without either source permission.
5. Create local reminders using explicit date/time controls. Pending holds unresolved tasks. History records local acknowledgement, link opened, completion, skip, expiry, and source cancellation separately.

The sidebar exposes Settings and Diagnostics even with denied access. Calendar and Reminders permissions can be reviewed in System Settings → Privacy & Security. Dreadline requires full EventKit permission to read calendars; read-only is application policy, and there is no calendar save/remove path. This follows [Apple's EventKit access requirements](https://developer.apple.com/documentation/eventkit/accessing-the-event-store). Only pressing Done on a supported Apple Reminder writes to that reminder. Recurring Apple Reminders completion is disabled pending provider verification; use local acknowledgement or the Reminders app.

## Behavior and escape

Default lead times: gentle 10 minutes before, prominent 2 minutes before, fullscreen at due time. Ordered values are validated; coincident and missed stages are merged into the current stage. One queue is shown at a time. Per-occurrence timing/ceiling overrides can be reset. A lower-ceiling item is not promoted into another item's higher-intensity queue.

Acknowledge is local silence, not attendance/completion. Join opens a validated link and records “Link opened” only after successful OS handoff. Multiple links have an explicit chooser. Snooze and Skip affect one occurrence. Done completes a local occurrence and generates the next local recurrence. Local-series editing/deletion asks for explicit whole-series confirmation; Skip resolves a single occurrence.

Escape/Stop snoozes the displayed queue for five minutes, capped at event expiry; when no useful interval remains it skips the event. Pause stops all owned surfaces and sound, preserving unresolved state. Presets are 15 minutes, an hour, a chosen date/time (Settings), or indefinitely. Quiet hours use the current local time zone, including overnight ranges. Equal start/end means all day. Sound is opt-in, one bounded system sound per new interruption, with a volume control. There is no repeating alarm loop.

Calendar expiry is the earlier of event end or 15 minutes after start; invalid/zero-length ends use the grace window. Tasks stop automatic escalation 15 minutes after due and remain Pending. An explicit task snooze creates a new bounded window after its requested deadline. On restart, snoozes recover from saved absolute deadlines; running snoozes use monotonic elapsed time. Clock changes can therefore change restarted-snooze timing.

Real overlays are redacted and do not automatically activate the app, because public workspace signals do not reliably identify screen unlock. Click the card to interact with its keyboard controls; the fullscreen sandbox preview can activate deliberately. Ordinary window levels remain below system security surfaces. Main-window details are controlled by the privacy preference. See [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) for platform verification still required.

## Sources, recurrence, and sync

Calendar queries expand occurrences from 24 hours back to 30 days forward. macOS owns Google/Exchange/iCloud synchronization; there are no direct provider integrations. Refreshes occur on EventKit invalidation (debounced), five-minute recovery intervals, wake/session return, clock/time-zone changes, and manual refresh. Missing permission or failed fetch suppresses uncertain external delivery while preserving local state. A successful empty fetch is distinct. Calendar EventKit fetch has no provider-sync NSError channel; delayed/incomplete provider sync cannot always be identified.

Timed noncancelled events are enabled by source selection. Declined invitations are excluded. Tentative, unanswered, free, and all-day events require explicit filter choices. All-day and date-only tasks use configured local wall-clock times, default 09:00. Undated Apple Reminders remain visible without time-based delivery. Disappearing source IDs are never replaced with a same-named source.

Local recurrence supports daily, selected weekdays, weekly, and monthly rules. A monthly date past month end uses its last day. DST gaps resolve to the next valid time; repeated times use the first occurrence once. Subsequent recurring dates float with the local time zone; one-off dates are absolute instants. The first due date is explicitly chosen in the editor. Finishing/skipping/acknowledging a recurring local occurrence leaves the definition intact and schedules its next future occurrence. Unresolved recurring tasks are not multiplied into an unbounded backlog.

## Notifications, login, and privacy

Optional ordinary notifications default off, have separate permission, and never duplicate custom delivery while the app runs. The app schedules at most 32 future fallback requests using stable occurrence IDs. Pausing, editing, resolving, deselecting, and disabling fallback reconcile them. Standard macOS Quit and menu Quit offer to cancel scheduled notifications or keep them. Kept notifications can become stale while quit; actions refetch before being applied. They cannot show overlays, bypass Focus, or guarantee delivery.

Launch at login is opt-in through `SMAppService.mainApp`; the UI reflects actual status/approval requirements. A signed, installed app is needed for dependable platform verification. No helper or secret relaunch is installed. See [Apple's service documentation](https://developer.apple.com/documentation/servicemanagement/smappservice).

App data is in the per-user Application Support `Dreadline/state.sqlite` location reported in Diagnostics. For the sandboxed identity this is normally `~/Library/Containers/xyz.dreadline.app/Data/Library/Application Support/Dreadline/`. Settings, occurrence state, snapshots, pause, local definitions, and the bounded redacted log are stored transactionally in SQLite (WAL, synchronous FULL). History details default to 30-day retention. Minimal delivery identities for still-fetched dismissed items are retained to prevent resurrection after details are cleared. No remote event notes or participant data are persisted; local notes are part of your reminder definition.

Export diagnostics explicitly through a save panel. Ordinary logs contain transition/error categories, not titles, URLs, or source names. Failed/corrupt databases are preserved; recovery/reset is explicit. Reset local data cancels timers/notifications and clears local definitions, actions, source selection, and settings; source calendars/reminders are untouched. To uninstall, disable launch at login, cancel fallback notifications when quitting, remove the app, and optionally remove its container after preserving anything you want. No system settings are changed by the build scripts.

## Verification

[TESTING.md](TESTING.md) records automated results, actual UI checks, and an unchecked manual platform matrix. [ARCHITECTURE.md](ARCHITECTURE.md) explains reconciliation, states, gates, and recovery. Compilation is not proof that permission prompts, provider sync, Spaces, lock/unlock, or multi-display behavior passed.
