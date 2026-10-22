# Build status — 2026-10-22

Native implementation, terminal verification, documentation, and local packaging are complete. Live-source and platform acceptance verification remain outstanding as explicitly listed below. No distribution, upload, notarization, source fixture creation, or personal calendar/reminder write was performed.

## Delivered

- Real Xcode application project with shared Dreadline build/test scheme, macOS 14 deployment baseline, Swift 6 language mode, complete checked concurrency, and universal arm64/x86_64 compilation.
- A: SQLite versioned transactional store, normalized occurrence state, injectable clock/driver, local one-off reminder create/edit/delete, actionable owned overlay, initial fake-clock coverage.
- B: Separate contextual EventKit permissions, explicit calendar/list selection, expanded recurrence ingestion, source/account/provider/anchor reconciliation, invalidation generations, source gates, safe link chooser/handoff outcomes. Calendar ingestion has no write API path.
- C: Validated ordered escalation, independent fullscreen opt-in, grouped queues, per-item ceilings/actions, persisted and monotonic snoozes, pause/quiet hours, catch-up/restart/wake hooks, display selection/dim-window lifecycle, Escape/Stop, redacted nonactivating real presentation.
- D: Local wall-clock recurrence, guarded nonrecurring Apple Reminders completion, history/retention, functional settings/editors, diagnostics/export/recovery/reset, optional bounded ordinary notifications with foreground deduplication, opt-in SMAppService login registration.
- E: 38 passing automated tests, actual source-free UI smoke checks, safe build/test/run/local-package/release scripts, README, architecture, testing matrix, limitations, and an ad hoc signed .app/ZIP.

## Final verification

Environment: Xcode 27.1 (27A9275), Swift 6.4, macOS SDK 27, arm64 host. Both app architectures compiled. No third-party dependencies or unpinned tooling downloaded.

| Command | Result |
| --- | --- |
| `./scripts/build.sh` (also run by package script) | BUILD SUCCEEDED |
| `./scripts/test.sh` | TEST SUCCEEDED; 38 tests, 0 failures; 9 coordinator, 7 recurrence/time, 22 scheduler/persistence/identity/link tests |
| `./scripts/package-local.sh` | BUILD SUCCEEDED; .app and local ZIP created; strict signature verification passed |
| `codesign --verify --deep --strict build/DerivedData/Build/Products/Debug/Dreadline.app` | Passed |
| `codesign -d --entitlements - …/Dreadline.app` | App Sandbox, calendar personal-information, user-selected files retained; debug get-task-allow present; no test-runner exception entitlements in final package |
| `zsh -n scripts/*.sh` | Passed |
| `plutil -lint` for project, Info.plist, entitlements | Passed |

Final app: `build/Local-20261022-151527/Dreadline.app`

Final ZIP: `build/Local-20261022-151527/Dreadline-local.zip`

Convenience build: `build/DerivedData/Build/Products/Debug/Dreadline.app`

Final result bundle: `build/DerivedData/Logs/Test/Test-Dreadline-2026.10.22_15-14-30-+0530.xcresult`

Build/package/test logs are copied to `build/verification/`. Earlier timestamped local packages are retained, but the path above is the final revision. Build artifacts/logs are intentionally ignored by Git.

Signing is **ad hoc**, TeamIdentifier unset, **not notarized**. App Sandbox is enabled. Xcode disables hardened runtime for ad hoc debug signing; release configuration enables it. Apple Development/Developer ID signing credentials were not supplied. No privacy requirement was stripped to obtain a build.

The first sandboxed compilation/test attempt could not launch SwiftUI compiler plugins/testmanagerd; running the same commands with approved execution outside the automation sandbox resolved it. This host also emits unrelated CoreDevice/iOS Simulator framework mismatch diagnostics. Native macOS build/test actions succeed; no source compiler warnings remain.

## Actual UI verification

- App launched with no source permissions and usable Settings/Diagnostics.
- Preview explicitly enabled the real-alert/fullscreen opt-in controls, leaving both off.
- Created a local reminder without source access, observed it Pending, clicked Done, verified Completed history, quit, rebuilt/restarted, and verified the same completion survived.
- Verified the final sandbox-preview running-state banner appears and Escape clears it. Borderless panel geometry and panel-specific keyboard routing were not inspected by the automation surface.
- Standard Command-Q closed the app. One completed local smoke-test record remains in the development container. Real alerts remain off; no sources are selected.

## Outstanding acceptance work / release prerequisites

A stable signed development app and explicit test-source permission/fixture opt-in are needed to verify the live acceptance scenario: calendar connection and selection → real event stages → snooze/restart once → join/ack/history → source edits/cancellation. Nonrecurring Apple Reminders completion also needs live permission/provider testing. Recurring Apple Reminders completion remains intentionally disabled with an explanation.

No live-source permission was granted, no test calendar/list was created, and no source event/reminder was modified. Screen lock/unlock, Spaces/fullscreen apps, Stage Manager, display combinations, VoiceOver, true sleep/wake, login approval/reboot, Focus/notification behavior, Intel runtime, and macOS 14 runtime remain unverified. TESTING.md gives the exact unchecked matrix. KNOWN_LIMITATIONS.md documents conservative redacted/nonactivating real panels, EventKit provider-error ambiguity, notification staleness while quit, and other practical limits. Compilation and fixture tests are not represented as live acceptance success.
