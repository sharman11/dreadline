# Testing

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
