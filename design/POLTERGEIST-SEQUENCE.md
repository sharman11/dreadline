# Current sequence (2026-10-23)

Constants live in `Haunt` (Domain.swift); choreography in `HauntScene`; delivery in `Scheduler.evaluate`.
Times below are for a meeting at 10:00 with the default 5-minute early warning.

| When | Stage | What happens |
| --- | --- | --- |
| 9:54:50 (`dashLead` 10 s before the warning) | Dash | The ghost streaks across the screen once (~0.55 s) with two afterimages. No windows move, clicks pass through, focus never changes. Silent. Once per due time. |
| 9:55:00 | Early warning | All supported windows minimize → the ghost hangs down from the top upside down, or rises from the bottom (alternating), with a knock and claw scratches → it slips away → windows return. ~3.5 s; capped at `preludeSeconds`. Escape ends it. |
| 9:59:55 (`arrivalLead` 5 s before) | Meeting alert | Windows minimize → the screen is black and the clawed face is suddenly there with the sting and a jolt → it withdraws into the full ghost, which lingers → the meeting card slides down from the top while the ghost drifts back to hover beside it. Lands at start time. |
| User presses Join | Exit | The ghost vanishes → windows return → the link opens in its browser, on top. Kept off screen during the handoff; a failed handoff returns as a side reminder with an error. |
| User presses Snooze or Escape | Exit | The black overlay flickers like a failing light (changes ≥ 330 ms apart, under 3 flashes/s), the ghost visible in the dark frames, with a warning ("Snooze all you like. I don't sleep.") → windows return → snoozed. |
| User presses Dismiss | Exit | The clawed face lunges back with a red warning ("You can't dismiss me.") and the sting → windows return → dismissed. |
| No action for 30 s | Settle | Windows return; the alert becomes a side reminder. |

**Artwork** (WebP, `Dreadline/Resources`, user-generated 2026-10-23 from the reference prompts; views in HauntScene.swift):

| File | Used for | Notes |
| --- | --- | --- |
| `ghost-dash.webp` (2172×724, transparent) | Dash | Faces right; mirrored for right-to-left. Moved per frame by `DashMotion`. |
| `ghost-hanging.webp` (1024×1536, transparent) | Early warning from above | Hangs from the top edge; no rotation, hair falls naturally. |
| `ghost-crawling.webp` (1536×1024, transparent) | Early warning from below | Ledge line at 86% of its height sits on the screen's bottom edge. |
| `ghost-grin.webp` (1254², on black) | Meeting scare | Edges feathered into the dark. |
| `ghost-standing.webp` (1024×1536, transparent) | Lingering ghost, Snooze flicker | Hovers beside the meeting card. |
| `ghost-scream.webp` (1254², on black) | Dismiss warning | Edges feathered into the dark. |

**Sounds** (`HauntSound` / `HauntSounds` in Domain.swift, `Dreadline/Resources/haunt-*.m4a`, AAC 192 kbps, 48 kHz stereo). User-supplied on 2026-10-23:

| File | Source (as downloaded) | Edit |
| --- | --- | --- |
| `haunt-basement.m4a` | `alex_jauk-noise-in-the-basement-398732.mp3` | Full 2.59 s, 150 ms fade-out |
| `haunt-shatter.m4a` | `alex_jauk-loud-shattering-sound-198080.mp3` | Full 2.38 s, 150 ms fade-out |
| `haunt-scream.m4a` | `jusatti890-scream-horror-sfx-490916.mp3` | 13.8–18.6 s (the scream), 20 ms fade-in, 450 ms fade-out |
| `haunt-deep.m4a` | `virtual_vibes-scary-noise-effects-404258.mp3` | Full clip (4.0 s), converted to AAC, no trim |

| Moment | Sound |
| --- | --- |
| Early warning, Snooze flicker, side reminders | basement |
| Dismiss | shatter |
| Meeting scare — Scare meter Low / Medium / High | shatter / scream / deep |

**Tests play the real scare.** Test haunting uses the selected level's sound, so High plays `deep` in tests and real meetings alike. Test: `testScareLevelsMapToTheirOwnSoundInTestsToo`.

Confirm each clip's licence before distributing builds. Sound stays opt-in (Settings → Alerts → Play horror sound) with the volume slider; "Hear a sound" previews each one.

Actions are applied only after their exit plays (or when it is interrupted), so the state is never lost.
Missed stages are never replayed after sleep, restart or pause. Reduced motion removes all movement and flicker; windows still minimize and the warnings still show as text.

Menu bar → Test alert (and Settings → Alerts → Preview full sequence) plays dash → early warning → meeting alert, compressed. In a preview, Escape closes immediately.

---

# Current behavior: actual minimization (2026-10-23)

This update supersedes the earlier cover-only mechanism documented below. The user requires real minimization. Fullscreen stages now use WorkspaceMinimizer and public Accessibility attributes to minimize supported, initially non-minimized windows, including Dreadline's own ordinary windows. Restoration starts ahead of the paper reveal and also runs on immediate/normal close, Pause and Quit. Permission is requested only by the explicit Enable Accessibility button. The direct-download target has App Sandbox disabled; release hardened runtime remains enabled.

Failed restores remain tracked for Retry. Closed windows and terminated/restarted apps are not reopened. Existing minimized windows are untouched. Force Quit/crash cannot execute restoration and can leave windows minimized; no external recovery helper is installed. Fullscreen/protected windows may refuse minimization. See KNOWN_LIMITATIONS.md.

The final build and all 64 tests passed, including the menu/closed-own-window guard refinement. Tests of the window-control policy use isolated fakes; real cross-app minimization awaits user-granted Accessibility and manual acceptance.

---

# Crooked Storybook / Poltergeist sequence

User-selected direction: 03, Crooked Storybook. User-selected mechanism: cover/reveal the workspace, not actual minimization of other applications.

## Implemented behavior

- New preferences use a five-minute prelude and an alert at meeting start. Existing saved choices are retained until the user selects Poltergeist entrance in Settings → Alerts.
- Prelude: opaque owned windows cover the available displays, with a hand-inked ghost on the pointer display. The apparition enters once and the cover clears after four seconds. Return now or Escape ends the prelude without completing/dismissing the meeting occurrence.
- Arrival: a faster single entrance leads to the fullscreen meeting controls. After thirty seconds, the fullscreen presentation becomes a side reminder. Join, Dismiss, Snooze, Pause and app Quit also release the cover.
- The app never minimizes, moves, resizes or closes another application's windows. No Accessibility or Screen Recording permission was added, and sandboxing remains enabled.
- Sound is an original 2.8-second synthetic bowed/detuned sting, without third-party samples. Sound remains opt-in, with a volume control and Hear the sound button. Pausing or closing the preview stops audio. The user's future sound can replace the bundled WAV.
- Reduced motion (system or app preference) shows a static apparition instead of the entrance. There is no flashing loop.

## Edge cases handled

| Case | Behavior |
| --- | --- |
| Calendar refresh while the prelude is visible | Retains the original expiry, without replaying the entrance. |
| Restart, waking or catching up after a pause | Skips missed preludes; due meetings use a smaller catch-up reminder. |
| Several meetings starting together | One queue; no parallel fullscreen overlays. |
| A second prelude begins during the first | Shares the first prelude's end time, avoiding an extended takeover. |
| Meeting time arrives during another prelude | Meeting-time alert takes priority. |
| Prelude is dismissed early | Meeting-time alert is still scheduled. |
| User snoozes an arrival alert | Snooze returns as a smaller reminder, without another entrance. |
| Meeting is canceled or rescheduled | Reconciliation cancels the old presentation; a changed due time can receive its own prelude. |
| The app is paused, disabled or loses usable source access | Owned overlays close; no external window state needs restoring. |
| A meeting becomes due during a demo | Ending the demo resumes normal delivery as a smaller catch-up reminder. |
| App crashes or quits | Its owned windows disappear; other apps' windows remain untouched. |
| Existing data from before this feature | Optional fields decode without resetting data or silently enabling the effect. |
| No sound asset / sound disabled | Visual effect still works; sound failure does not block controls. |

## Remaining limits / release acceptance checks

- Screen sharing, live presentations and ongoing calls are not reliably detectable across macOS apps. Pause is explicit; the settings explain that others may see an effect during sharing.
- Cross-Space visibility, exclusive fullscreen applications, Stage Manager, multiple physical monitors, mirrored displays and hot-plug still need a manual device matrix. System security surfaces stay above ordinary app windows; this is not a screen lock.
- Public lifecycle signals do not provide a dependable screen-unlock detector. Sleep/session changes are handled conservatively; lock/unlock must still be manually checked. Real overlays retain title redaction.
- Keyboard Escape depends on the alert receiving keyboard focus. The panel requests key status, has an explicit Return/Close control, and is time-bounded; real focus routing across applications needs acceptance testing.
- Timers cannot run while the process or machine is suspended. The time bounds apply while responsive, and catch-up suppresses replay on wake/restart.
- New meetings arriving after a completed prelude can cause another prelude. A configurable global scare cooldown is a possible later refinement if real calendars prove noisy.

## Why cover/reveal

Apple's Accessibility APIs expose other-app UI control, while hide/unhide APIs operate at the application level and explicitly report possible failure. True minimize/restore would require remembering per-window state, handling app termination and permissions, and could not guarantee exact restoration of every window and Space. The selected overlay mechanism avoids those dependencies entirely.

References:
- https://developer.apple.com/documentation/applicationservices/axuielement_h
- https://developer.apple.com/documentation/appkit/nsrunningapplication
- https://developer.apple.com/documentation/appkit/nsrunningapplication/unhide()

## Artwork and sound provenance

Former (removed 2026-10-23, replaced by the six ghost images) ghost asset: `Dreadline/Resources/storybook-ghost.png`, generated with the built-in image tool. The earlier corridor image is retained as an unused prior artifact.

Final image prompt:

> Use case: illustration-story. Asset: transparent original character cutout for a haunted storybook Mac reminder app. Full body of a deeply unsettling tall thin ghost, crooked silhouette leaning forward, parchment-white tattered shroud, huge asymmetrical black empty eye sockets, long narrow open mouth, impossibly long black skeletal fingers extending below the shroud, spindly arms and frayed cloth trailing into ink wisps. Hand-drawn scratchy black India ink and dry-brush crosshatching, antique gothic storybook illustration, expressive irregular lines. Tiny muted sickly chartreuse tint within the eyes only. Charming craftsmanship but genuinely ominous, not a cute emoji, not photorealistic, no gore. Isolated single character with generous transparent margins and no ground, no scene, no text, no logo, no border. Portrait composition with character centered; preserve entire hands and head. True transparent background.

Original sound: `Dreadline/Resources/poltergeist.wav`, reproducible with `scripts/generate-haunt-sound.py`. Mono PCM, 44.1 kHz, 16-bit, 2.8 seconds, peak capped at 28% before the user's volume setting. No external sound library or license dependency.

## Final verification

54 tests passed with zero failures. The native presentation tests verify visible screen-sized panels, matching hosting-view geometry, Escape cleanup and four-second automatic closure with the real coordinator. The computer-use surface captures the main app rather than the floating preview, so cross-application focus and the final visual composition still need a direct manual pass. NSHostingView intrinsic sizing is disabled for the panel, keeping the chosen screen rectangle authoritative. Diagnostics now reports panel type, size and visibility.

## Knock and character choreography — 2026-10-23

- Bundled `door-knock.mp3` is an unchanged copy of the user-provided `tanweraman-door-knock-505136.mp3` (0.936 seconds, mono, 48 kHz). Source, workspace and app-bundle SHA-256 were verified equal: `ced60af77f35a815a10bc897ac1e937cb21f5cbe6f1a27cae18f3d2e50e6f79a`.
- Warning: the apparition peeks at the edge of the visible workspace. The supplied knock clip plays at 0, 1.05 and 2.10 seconds when sound is enabled. Darkness gathers after 0.9 seconds, then the ghost withdraws and an irregular paper mask reveals the real workspace from 3.25 seconds onward. The four-second release bound remains.
- Arrival: a faster 0.28-second peek becomes a close apparition beside a paper meeting invitation. The original synthetic arrival sting plays once at the entrance. The automatic paper reveal starts before the existing thirty-second fallback.
- Three authored entrances rotate between right, below and left. A scene is retained across source refreshes and text updates, so they cannot restart its animation or audio. A display-layout change cancels the effect instead of replaying it.
- Successful Join, Done, Dismiss and normal completion use a short withdrawal/paper reveal. Escape, Pause and Quit still cancel immediately. All audio tasks and pending close callbacks are canceled; a generation guard protects newer presentations from stale callbacks.
- Other display covers follow the same reveal and block blind clicks to covered apps. No screenshots or Accessibility/Screen Recording permission are used.
- The menu-bar icon and header ghost distinguish paused, watching and idle states. The empty agenda uses an empty-chair motif. Settings separately preview the knock and arrival sting.
- System/app reduced motion skips the moving entrance and paper wipe. Sound remains independently opt-in; no flashing was introduced.
