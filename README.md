# Dreadline

A local-first native macOS menu-bar calendar and persistent-reminder utility. Dark Halloween styling with original spectral artwork. Swift 6, SwiftUI/AppKit, EventKit, SQLite, UserNotifications, and ServiceManagement. macOS 14 or later. Universal arm64/x86_64 app. No runtime packages, account, server, LLM, telemetry, or app network client.

## Build and run

Use full Xcode with its Command Line Tools selected:

```sh
./scripts/build.sh
./scripts/test.sh
./scripts/run.sh
```

The shared scheme is `Dreadline` in `Dreadline.xcodeproj`. No project generator or dependency download is required. `scripts/generate-project.py` is an optional deterministic, standard-library-only maintenance tool for adding source files; the Xcode project itself is supplied.

Build output: `build/DerivedData/Build/Products/Debug/Dreadline.app`. Build/test scripts use ad hoc local signing (`CODE_SIGN_IDENTITY=-`) and build for direct distribution with App Sandbox disabled because Accessibility-based window control requires it. Release hardened runtime remains enabled. The local app is not Developer ID signed or notarized. Xcode compiler plugins and XCTest require a normal developer terminal; restricted automation sandboxes may require permission to run these commands outside that sandbox.

Create a local ZIP without replacing earlier packages:

```sh
./scripts/package-local.sh
```

It prints a new timestamped folder under `build/`. Prepare a signed release archive and ZIP with your own development team:

```sh
DEVELOPMENT_TEAM=YOUR_TEAM_ID ./scripts/release.sh
```

Release packaging refuses existing archive/ZIP destinations. It does not upload or notarize. Use Xcode Organizer for Developer ID export, then explicitly perform notarization/stapling before distribution. No signing identity or credentials are embedded.

## Demo video

`./scripts/render-demo-video.sh music.mp3 [out.mp4]` renders a 36-second 1080p trailer from the app's real haunting views, timed to the music, with the app's own scare sounds mixed in. It builds the app and runs `DemoVideoTests` (skipped in normal test runs). It takes about three minutes.

## First use

1. On first launch Dreadline opens a setup window and stays locked until four steps are done: calendar access, at least one chosen calendar, window control (Accessibility) and notifications. **Start Dreadline** unlocks the app and turns alerts on. If a permission is revoked later, the app returns to setup.
2. Click the ghost in the menu bar for the agenda: the next meeting with Join and Snooze, the rest of the day below, and Pause, Settings and Quit along the bottom.
3. Settings has four tabs: **General** (login, backup notifications, quiet hours, privacy), **Calendars** (watched calendars, which events count, Apple Reminders), **Haunting** (full screen or side window, early warning, snooze, sound, and **Test haunting**, the only test button in the app) and **Advanced** (permission status, history, diagnostics, reset).
4. Ten seconds before the early warning a ghost dashes across your screen. At the early warning (five minutes before, by default) your windows minimize, the ghost peeks down upside down or up from the bottom with a knock, then your windows come back. Five seconds before the start they minimize again: the ghost pops up on a black screen, lingers, and the meeting card slides down. Join brings your windows back and opens the meeting; Snooze flickers the screen with a warning; Dismiss gets a scary one. After thirty seconds the alert becomes a side reminder. See [the sequence notes](design/POLTERGEIST-SEQUENCE.md).
5. Pause before presentations or screen sharing. The app does not automatically identify every sharing session.

Fullscreen hauntings actually minimize supported open windows using Accessibility, then restore only the windows Dreadline changed. Access is granted during setup. Already-minimized windows stay minimized; fullscreen/protected windows may refuse control. Screen Recording is not used. Choose Side window or disable the entrance for a quieter experience. Reduced motion disables the animated entrance. Horror audio is optional and set under Settings → Haunting.

**Settings → Haunting → Test haunting** plays the sequence that matches your chosen style. Its Join never opens a real meeting. Escape/Close ends the preview; normal delivery resumes with a catch-up reminder if something became due meanwhile.

Local reminders appear in the agenda alongside meetings; add one with **+**. Diagnostics and data controls are under **Settings → Advanced**. Calendar access remains read-only application policy. Only explicit Done on a supported Apple Reminder writes to its source.

See [the sequence and edge-case notes](design/POLTERGEIST-SEQUENCE.md) for timing, artwork/audio provenance and platform limitations.

## Behavior and escape

New installations default to a four-second prelude five minutes before a meeting, followed by the main fullscreen alert at start time. Poltergeist entrance settings offer two, five or ten minutes of lead time. Existing saved preferences and per-occurrence overrides are retained. Ordered values are validated; coincident and missed stages are merged into the current stage. One queue is shown at a time. Per-occurrence timing/ceiling overrides can be reset. A lower-ceiling item is not promoted into another item's higher-intensity queue.

Acknowledge is local silence, not attendance/completion. If a dismissed or ended meeting is later moved to a new future time (by a minute or more), it alerts again; a skipped occurrence stays skipped. An item cancelled because its source was unavailable or deselected comes back when it reappears. Join opens a validated link and records “Link opened” only after successful OS handoff. Multiple links have an explicit chooser. Snooze and Skip affect one occurrence. Done completes a local occurrence and generates the next local recurrence. Local-series editing/deletion asks for explicit whole-series confirmation; Skip resolves a single occurrence.

Escape/Stop snoozes the displayed queue for the snooze length (five minutes by default; set in Settings → Alerts, or per local reminder), capped at event expiry; when no useful interval remains it skips the event. Pause stops all owned surfaces and sound, preserving unresolved state. Presets are 15 minutes, an hour, a chosen date/time (Settings), or indefinitely. Quiet hours use the current local time zone, including overnight ranges. Equal start/end means all day. Sound is opt-in, one bounded system sound per new interruption, with a volume control. There is no repeating alarm loop.

Calendar expiry is the earlier of event end or 15 minutes after start; invalid/zero-length ends use the grace window. Tasks stop automatic escalation 15 minutes after due and remain Pending. An explicit task snooze creates a new bounded window after its requested deadline. On restart, snoozes recover from saved absolute deadlines; running snoozes use monotonic time that keeps counting while the Mac sleeps but ignores clock changes. Clock changes can therefore change restarted-snooze timing only.

Real overlays are redacted and do not automatically activate the app, because public workspace signals do not reliably identify screen unlock. Click the card to interact with its keyboard controls; the fullscreen sandbox preview can activate deliberately. Ordinary window levels remain below system security surfaces. Main-window details are controlled by the privacy preference. See [KNOWN_LIMITATIONS.md](KNOWN_LIMITATIONS.md) for platform verification still required.

## Sources, recurrence, and sync

Calendar queries expand occurrences from 24 hours back to 30 days forward. macOS owns Google/Exchange/iCloud synchronization; there are no direct provider integrations. Refreshes occur on EventKit invalidation (debounced), five-minute recovery intervals, wake/session return, clock/time-zone changes, and manual refresh. Missing permission or failed fetch suppresses uncertain external delivery while preserving local state. A successful empty fetch is distinct. Calendar EventKit fetch has no provider-sync NSError channel; delayed/incomplete provider sync cannot always be identified.

Timed noncancelled events are enabled by source selection. Declined invitations are excluded. Tentative, unanswered, free, and all-day events require explicit filter choices. All-day and date-only tasks use configured local wall-clock times, default 09:00. Undated Apple Reminders remain visible without time-based delivery. Disappearing source IDs are never replaced with a same-named source.

Local recurrence supports daily, selected weekdays, weekly, and monthly rules. A monthly date past month end uses its last day. DST gaps resolve to the next valid time; repeated times use the first occurrence once. Subsequent recurring dates float with the local time zone; one-off dates are absolute instants. The first due date is explicitly chosen in the editor. Finishing/skipping/acknowledging a recurring local occurrence leaves the definition intact and schedules its next future occurrence. Unresolved recurring tasks are not multiplied into an unbounded backlog.

## Notifications, login, and privacy

Optional ordinary notifications default off, have separate permission, and never duplicate custom delivery while the app runs. The app schedules at most 32 future fallback requests using stable occurrence IDs. Pausing, editing, resolving, deselecting, and disabling fallback reconcile them. Standard macOS Quit and menu Quit offer to cancel scheduled notifications or keep them. Kept notifications can become stale while quit; actions refetch before being applied. They cannot show overlays, bypass Focus, or guarantee delivery.

Launch at login is opt-in through `SMAppService.mainApp`; the UI reflects actual status/approval requirements. A signed, installed app is needed for dependable platform verification. No helper or secret relaunch is installed. See [Apple's service documentation](https://developer.apple.com/documentation/servicemanagement/smappservice).

App data is in the per-user Application Support `Dreadline/state.sqlite` location reported in Diagnostics. Existing data at `~/Library/Containers/xyz.dreadline.app/Data/Library/Application Support/Dreadline/` is reused when present; new direct-download installations use the ordinary Application Support path. Settings, occurrence state, snapshots, pause, local definitions, and the bounded redacted log are stored transactionally in SQLite (WAL, synchronous FULL). History details default to 30-day retention. Minimal delivery identities for still-fetched dismissed items are retained to prevent resurrection after details are cleared. No remote event notes or participant data are persisted; local notes are part of your reminder definition.

Export diagnostics explicitly through a save panel. Ordinary logs contain transition/error categories, not titles, URLs, or source names. Failed/corrupt databases are preserved; recovery/reset is explicit. Reset local data cancels timers/notifications and clears local definitions, actions, source selection, and settings; source calendars/reminders are untouched. To uninstall, disable launch at login, cancel fallback notifications when quitting, remove the app, and optionally remove its container after preserving anything you want. No system settings are changed by the build scripts.

## Verification

[TESTING.md](TESTING.md) records automated results, actual UI checks, and an unchecked manual platform matrix. [ARCHITECTURE.md](ARCHITECTURE.md) explains reconciliation, states, gates, and recovery. Compilation is not proof that permission prompts, provider sync, Spaces, lock/unlock, or multi-display behavior passed.
