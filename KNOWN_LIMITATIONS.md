# Known limitations and release prerequisites

## Delivery and platform verification

- The app is a reminder utility, not an enforcement/screen-locking system. No delivery is guaranteed while sleeping, locked, shut down, quit, under delayed provider sync, or without usable permission/source data.
- Real overlays intentionally remain redacted and nonactivating. Click the panel before keyboard operation; Escape is not globally intercepted from another application. The explicit fullscreen demo can activate. There is no reliable public lock detector here; session-active means session switch-in. Lock/unlock behavior has not been manually certified.
- Spaces/fullscreen-app visibility, Stage Manager, display hot-plugging/mirroring/scales, VoiceOver, fast user switching, actual sleep/wake, system accessibility modes, and focus restoration still require the manual matrix in TESTING.md. The window implementation uses public APIs; compilation does not prove these combinations work.
- Live calendar permission grant/revocation, provider sync, source editing/cancellation, and Apple Reminders completion have not been exercised on personal sources. Automated source tests use immutable isolated fixtures and fake adapters. No source events/reminders were created or modified during development.
- Recurring Apple Reminders Done is intentionally disabled, with an explanation and local acknowledgement available. Provider recurrence completion behavior has not been verified. Read-only source items also disable Done.
- EventKit calendar fetch returns an array without a provider-error channel. Authorization changes and nil reminder results are detected; an apparently successful but temporarily incomplete calendar sync can be indistinguishable from a true removal. The app cannot force provider sync or promise stale-data detection.
- Conservative identity matching handles available provider IDs and recurrence anchors. If a provider changes every identifier and original anchor, the app cannot prove identity; it creates a new occurrence rather than apply another occurrence's terminal state. Explicit ambiguity suppresses delivery and appears in diagnostics.
- Timed reminder rules use the time zone supplied by EventKit when available; date-only tasks use local time. Provider-specific component representations still need live testing.
- Local recurrence advances after an occurrence is deliberately resolved; it does not generate many additional overdue instances while an earlier task remains unresolved. The first due date is explicitly chosen. This behavior is documented in the app/README.

## Notifications and startup

- Fallback is opt-in and requests its own permission. It schedules at most 32 first-stage/snooze requests, not an unlimited multi-stage OS queue. Events changed while quit can leave stale notifications. Foreground delivery is deduplicated; actions revalidate on launch.
- Quiet-hour/pause filtering applies to app delivery and planned fallback times. macOS can delay a system notification (for example through Focus) beyond its requested time; the app cannot retract it while quit or promise an exact delivery time. Custom sound volume does not control system-notification volume.
- Scheduled notifications and launch-at-login approval have not been manually verified. Use a consistently signed, installed app for these platform checks. No helper restarts the app after explicit quit.
- Menu relative time updates at scheduling/source/state boundaries, not once per second or minute in the background. Reminder deadlines still use the next-deadline timer.

## Storage, packaging, and verification

- SQLite schema version 1 stores an encoded transactional state snapshot, not a separate relational row for every occurrence. Future incompatible versions fail closed. Tests simulate commit failure and corrupt stores; real disk-full hardware faults and interrupted migrations are not manually reproduced.
- Failed databases are retained until explicit recovery. Reset/recovery does not undo an Apple Reminder completion that the user already performed at its source.
- Build output is universal and ad hoc signed with App Sandbox disabled for Accessibility window control. It is not Developer ID signed or notarized; hardened runtime is disabled by Xcode for ad hoc debug signing. Release settings enable hardened runtime. A stable Apple Development/Developer ID team and identity are still needed for reliable TCC, launch-at-login, and distribution verification.
- This host's Xcode emits unrelated CoreDevice/iOS Simulator version-mismatch diagnostics. The macOS app build and host XCTest run work. Intel was compiled but tests ran on the Apple Silicon host; macOS 14 itself was not available for runtime checks.
- UI automation inspected the main window, source-denied mode, preview opt-in controls, local creation/completion, and accurate history. The borderless demo panel itself was not exposed by the automation surface, so its visual fullscreen geometry and panel-specific keyboard routing remain manual checks. Escape cancellation was verified through the app and its running-preview state. No live-source acceptance pass is claimed.
- No automated XCUITest target is supplied. Coordinator integration tests inject source, notification, persistence, presentation, clock, and deadline-driver fakes. UI smoke checks and unverified combinations are recorded separately.

## Actual minimize/restore — 2026-10-23

- Accessibility permission is required. Without it the alert can appear, but its status explicitly says windows were not minimized. The app never grants its own permission.
- Only initially non-minimized, supported windows are changed. Fullscreen/protected windows, unresponsive apps and inaccessible window lists may be skipped. Enumeration and minimize calls have bounded timeouts.
- Restore tracks the original window element and process launch identity, ignores closed/terminated windows, preserves existing Dock state, and retains failed restoration records for Retry. Restore windows is available in Settings and the menu-bar panel.
- Normal Escape, Pause, release, Quit, sleep/session changes and display changes run restoration. Force Quit/crash cannot run cleanup; in that case affected windows may need to be restored manually from the Dock. Restoration is not guaranteed after permission revocation; re-enable permission and use Restore windows while Dreadline is still running.
- Existing sandbox-container state is reused if present. Ad hoc rebuilds can require granting Accessibility again; stable signing is required for dependable release permissions.
- Live cross-app minimization has not been certified on this host because Dreadline has not been granted Accessibility during automated work. Tests use isolated fake window controls.
