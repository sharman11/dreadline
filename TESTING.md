# Testing

## Setup gate, single test button and settings redesign — 2026-10-23

- Debug build succeeded. All 102 tests passed with zero failures. The setup test now also requires notification permission and checks the "Finish setup" menu title; native checks cover the 360-point self-sizing popover and the 560 × 580 tabbed Settings window.
- `UISnapshotTests` renders the menu (with and without meetings), each Settings tab and onboarding to PNGs when `TEST_RUNNER_SNAPSHOT_DIR` is set; it is skipped otherwise. All renders were visually inspected. Ghost artwork does not load in the test bundle, so it is blank there.
- Not yet verified live: the real calendar and notification prompts, and the popover against an actual calendar.

## Menu usability revision — 2026-10-23

- Debug build succeeded. All 74 tests passed with zero failures. Native checks cover the compact popover dimensions, entering/leaving the inline editor without model-driven dismissal, direct Alerts routing and Settings window reuse. A new integration case verifies completed one-time reminders leave the active list while repeating reminders retain a next occurrence and History remains available.
- Visually inspected the compact home, fixed navigation, reminder form, Alerts shortcut and calendar setup. Entered a draft title and verified Create became enabled; cancelled it without saving. Confirmed the completed smoke-test item no longer appears as an active reminder.
- No calendar access was requested, alert preferences enabled, or source records changed. Final app was left running in the menu bar.

## Menu-bar home — 2026-10-23

- Final Debug build succeeded. All 73 tests passed with zero failures, including new native checks for notification/alert routing to the popover, non-detachable presentation, Settings sizing and window reuse.
- Visually inspected the full agenda inside the status-item popover, opened History there, and opened/cancelled the inline reminder editor without saving.
- Opened the separate Settings window from the gear and verified its 720 × 650 content and dark controls. Closing Settings left no standalone window; reopening the app returned to the popover.
- Calendar permissions and source records were untouched. Existing fullscreen alerts remain separate interruption surfaces.

## Dark Halloween UI — 2026-10-23

- Debug build succeeded; existing XCTest suite passed all 71 tests with zero failures.
- Visually inspected the running main agenda, Calendars and Alerts settings, and the local reminder sheet through native UI automation. Dark title bars, surfaces, grouped forms, spectral artwork, orange actions and readable text were present.
- Opened and cancelled the reminder editor without saving. Started the meeting alert preview and ended it with the main-window End preview action. No calendar permissions were requested or source data modified.
- The automation screenshot surface selected the main window rather than the borderless fullscreen alert. Fullscreen artwork composition still requires a direct manual visual check; native panel geometry and Escape behavior are covered by the existing tests.

## Reproduce

```sh
./scripts/build.sh
./scripts/test.sh
codesign --verify --deep --strict build/DerivedData/Build/Products/Debug/Dreadline.app
codesign -d --entitlements - build/DerivedData/Build/Products/Debug/Dreadline.app
```

Xcode 27.1 (27A9275), Swift 6.4, macOS SDK 27, deployment target macOS 14, host arm64. Swift 6 language mode with complete checked concurrency. Both arm64/x86_64 app slices compile; XCTest executes on the arm64 host. Test code and source files are built into a hostless XCTest bundle using the same checked-in source; test dependencies are fake adapters and temporary SQLite stores. No personal calendar/reminder writes, system-clock changes, network calls, or source permission requests are made by tests.

The sandboxed command runner initially blocked SwiftUI macro plugins and XCTest's testmanagerd connection. The same scripts work from an approved normal developer terminal. Xcode also prints unrelated CoreDevice/iOS Simulator mismatch diagnostics; they did not prevent native macOS tests. Result bundles are under `build/DerivedData/Logs/Test/`.

## Automated coverage

`SchedulerTests`: ordered/coincident escalation; late joining; ceilings including mixed-ceiling queues; duplicate terminal commands; invalid/missing commands; rejecting calendar Done; capped/past snoozes; monotonic and restarted snooze recovery; explicit long task snoozes; grouped per-item actions; pause expiry; source/session/alert gates; task window versus event expiry; zero/malformed ends; later source edits during snooze; same-title separate commitments; provider ID changes; retained acknowledgement; recurring original anchors and detached moves; ambiguous identity; successful empty fetch, disappearing source, deselection; SQLite restart/crash-after-commit semantics; failing persistence; corrupt-file preservation; safe/multiple/malicious links; opaque long/emoji/RTL/HTML/instruction-like strings; earliest next deadline.

`RecurrenceTests`: monthly last-day clamp; leap year; travel; weekly/selected weekday rules; DST gaps and first fold; overnight/all-day quiet hours and boundary; local recurring completion/idempotence; history-retention redaction without resurrection; date-only, undated, explicitly zoned timed, and all-day resolution.

`IntegrationTests`: the actual AppModel command path with fake sources, notification adapter, persistence, presentation sink, clock, and deadline driver. Covers failed commit retaining the visible pending action; fetch failure preserving snapshots and suppressing external delivery; newer refresh discarding stale completion; source Done failure followed by honest local acknowledgement; pause/quiet shared policy; isolated demo ledger; restart after acknowledged/snoozed/skipped/completed actions; next-deadline scheduling and quit cleanup.

No test claims real provider recurrence semantics, actual OS notification delivery, permission prompts, full disk hardware failure, lock detection, or display configurations. There is no XCUITest target.

## Actual UI smoke check — 2026-10-22

Performed on this host through native UI automation with the local ad hoc app:

- Launched the built app; main/sidebar/menu entry present, Upcoming empty, source permission unavailable messages visible. No source prompts were shown.
- Opened Settings in denied/unconnected mode; both opt-in controls were initially disabled until a preview was used.
- Pressed the fullscreen preview control; explicit alert/fullscreen opt-in controls became enabled and remained off. The automation surface inspected only the main window, not the borderless overlay; this is not a fullscreen geometry/Escape verification.
- Opened the local reminder form, entered “UI smoke test — local only,” and saved it without source access. It appeared in Pending because its first lead time was already eligible.
- Pressed Done in its row; Pending returned to zero. History showed `completed` with outcome `Completed`.
- After rebuilding and restarting the actual app, History still showed the completed smoke-test record. The final Settings preview showed a running-state banner; Escape removed that banner, confirming demo cancellation through the app. The automation did not inspect borderless panel geometry.
- Quit using standard Command-Q. No calendar/reminder permission was granted and no source item was modified. The local completed smoke-test record remains in this development app's history.

An accessibility-tree inspection found row actions aggregated; `.accessibilityElement(children: .contain)` was subsequently added. Full VoiceOver operation still requires manual verification.

## Manual verification matrix — unchecked until performed

Use a consistently signed development build installed at a stable path. Create isolated source fixtures only after explicit opt-in; never use personal source writes as an automated test default.

| Area | Steps / expected result | Status |
| --- | --- | --- |
| First launch | No source prompts; previews isolated; no real alerts until preview, source selection, explicit enable | Main-window/opt-in smoke checked; delivery pending |
| Calendar permission | Grant full access; select one test calendar; deny/revoke on separate run; Settings/local reminders always usable | Not performed |
| Live acceptance | Test event → gentle/prominent/chosen fullscreen → snooze → quit/restart → one resumed queue → link/ack → accurate history | Not performed |
| Source edit/cancel | Move earlier/later, edit title/location/link, detach recurrence, cancel/delete; old timers/notifications/visible card invalidated | Fake-adapter coverage; live not performed |
| Calendar filters | Declined/free/tentative/unanswered/all-day, titleless/long/RTL, read-only/subscribed calendars, zero/overnight event | Core cases covered; provider UI not performed |
| Reminders permission | Separate contextual access; select test list; date-only 09:00, undated visible, timed due | Wall-clock tests; live not performed |
| Source Done | Nonrecurring Done writes exactly that item; failure stays pending; recurring/read-only action disabled; external completion retires alert | Fake-adapter coverage; live not performed |
| Local recurrence | Daily/weekday/weekly/month-end; resolve occurrence only; confirmed series edit/delete; one-off instant across travel | Core covered; full UI matrix not performed |
| Escape/input | Immediately Escape/Stop every stage; no held Return/Space acceptance; repeated Escape; expiry-near snooze becomes Skip | Domain covered; actual overlay keyboard pending |
| Contention | Several due items share one queue; actions per item; no sound cascade; low ceiling never promoted | Core covered; actual panel pending |
| Pause/quiet | Presets/chosen date/manual; overnight/DST; close active overlays and sound; resume one catch-up; cancel notifications | Core/coordinator covered; OS pending |
| Displays | Pointer display; other displays dim/click-through; hot-plug/mirror/scales/notch; no orphan windows | Not performed |
| Workspaces | Fullscreen browser/editor, Spaces, Stage Manager; system shortcuts remain available | Not performed |
| Session | Lock/unlock, sleep/wake, screen sleep, fast user switch; no above-lock-screen presentation; refetch before external delivery | Not performed |
| Accessibility | Keyboard navigation, VoiceOver controls, contrast, large text, reduced motion/transparency | Native controls inspected; full checks pending |
| Focus | Gentle/prominent never steal typing; real redacted panels click-interactive; demo restores still-running prior app | Not performed |
| Sharing | Manual title privacy and pause before sharing; no automatic detection claim | Not performed |
| Notifications | Separate grant/denial; foreground dedup; pause/quiet/edit cancellation; stale action refetch; quit keep/cancel choice; Focus delay | Fake sink covered; OS pending |
| Login/startup | Signed installed app; approval-required/disabled states; reboot/login; explicit quit never helper-relaunches | Not performed |
| Storage/recovery | Corrupt store retained; explicit reset/recovery; commit failure keeps recoverable UI; export redacted log | Temporary-store/failure tests; real disk-full pending |
| Offline/sync | Offline provider; delayed macOS sync; distinguish app validation from provider refresh capability | Not performed |
| Runtime baselines | macOS 14+, real Intel machine, release-signed build | Compiled universal; runtime pending |

## Results

See BUILD_STATUS.md for the final run count and artifact location. Earlier failing iterations were fixed and rerun; their logs do not imply a passing final run. Build/test logs and `.xcresult` bundles stay local under `build/` (with summary copies) or `/tmp/dreadline-*.log` during development.

## Simplified UX pass — 2026-10-22

- Universal Debug build passed after the UI redesign.
- Existing automated test suite passed.
- Running-app inspection verified the Up next empty/setup state, calendar settings, Alerts controls, preview launch, preview dismissal, and return to home. Home and Alerts layout were visually inspected.
- No calendar permission was granted or user preferences changed during inspection.
- Floating overlay geometry, populated meeting cards, menu-bar interactions, and live meeting-link handoff still require manual acceptance checks.

## Haunted visual theme — 2026-10-22

- Universal Debug build passed with the bundled original corridor artwork.
- All 39 existing tests passed; the final follow-up changed only form backgrounds, toolbar styling and layout dimensions and was rebuilt successfully.
- Visually inspected the haunted home/setup state, final dark calendar and alert settings, and the fullscreen scene on the available display.
- Verified fullscreen preview starts and Escape dismisses it. Side-window preview launch state was verified; its nonactivating panel was not available in the screenshot surface.
- No live calendar sources, permissions, or saved user preferences were changed during theme inspection.
- Smaller-screen sizing is adaptive in code; additional physical displays, populated calendar cards, and menu-bar layout still need manual acceptance checks.
- Creative research and asset-generation prompt are recorded in `design/HAUNTED-THEME.md`.

## Crooked Storybook / Poltergeist completion — 2026-10-22

- Full suite: 54 tests passed, 0 failures, including 11 haunting scheduler tests, 11 model integration tests and 2 native presentation smoke tests.
- Native tests instantiate the real OverlayCoordinator and verify a visible panel matching an available screen rectangle, a matching hosting-view size, Escape cancellation, and automatic prelude closure after four seconds. No sources are connected and no external window state is changed by these tests.
- NSHostingView sizing options now leave explicit panel geometry authoritative, avoiding intrinsic GeometryReader sizing for borderless fullscreen windows. Diagnostics reports presentation type, size and visibility.
- The Crooked Storybook main window was visually inspected. The computer-use capture continues to select the main app window during preview, so the final apparition's visual composition and real cross-app keyboard focus are not claimed as visually certified.
- Screen-sharing behavior, full-screen apps/Spaces, multiple monitors, mirrored displays, hot-plug, lock/unlock, and perception/volume of the original sound remain in the manual acceptance matrix.
- Full behavior, edge cases, generated ghost prompt and original sound provenance: `design/POLTERGEIST-SEQUENCE.md`.

## Knock/choreography pass — 2026-10-23

- All 57 tests passed, with zero failures. Native tests additionally cover Escape during an animated release, a newer presentation surviving an older close callback, and a watchdog releasing the latest queue after source/model updates.
- Verified the user-supplied MP3 is readable by Core Audio and bundled byte-for-byte without conversion; its metadata is 0.936 seconds, mono, 48 kHz.
- Updated normal release animations are cancellation-aware. Escape/Pause retain the immediate close path. Entrance-hidden controls do not accept clicks and are excluded from accessibility until revealed.
- Visual choreography, perceived sound level and multi-display/Spaces presentation still need direct human acceptance; automated assertions establish lifecycle/cleanup, not the subjective scare effect.

## Actual minimize/restore — 2026-10-23

- Final build/test run passed all 64 tests with zero failures, including seven isolated WorkspaceMinimizer tests.
- Tests cover minimizing supported open windows, preserving already-minimized windows, permission denial/revocation, closed windows, failed restore retry, preventing new ownership from overwriting failed restores, and repeated restore cleanup.
- Native presentation smoke tests explicitly inject fake window access; no real third-party windows were minimized by tests and no Accessibility permission was granted by automation.
- Verified the built app's entitlements omit com.apple.security.app-sandbox. Release hardened runtime remains enabled. Live acceptance requires enabling Accessibility for the rebuilt Dreadline app and previewing both stages.
- Escape, Pause, normal release, Quit and the bounded automatic release use restore. A menu-bar emergency Restore minimized windows control and a Settings retry are available. Crash/Force Quit cannot run cleanup and may require manual Dock restoration.

## Poltergeist horror pass — 2026-10-23

- All 69 tests passed with zero failures.
- Added tests for three-wave window minimization, early restoration canceling unstarted waves, canceled choreography not firing later window callbacks, reduced motion skipping the close-up, and the single close-up handing back to controls.
- User-supplied knocking MP3 remains bundled. The arrival close-up is a new original derived character asset; generation prompt and behavior notes are in design/POLTERGEIST-HORROR-PASS.md.
- Actual third-party window control is still tested through isolated fakes. The final scare and audio balance require direct visual/listening acceptance on the user's Mac with Accessibility granted.

## Animation cleanup — 2026-10-23

- All 71 tests passed with zero failures after consolidating sound/window/restore cues into one scene timeline.
- Added tests verify warning cue order, restoration before visual reveal, and cancellation preventing stale restoration callbacks.
- Full-screen shaking was removed; scratch drawing, pose changes, close-up fade, card entrance and the paper edge were smoothed. Existing native panel lifecycle and minimize/restore tests pass.
