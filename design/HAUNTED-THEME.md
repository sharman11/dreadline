# Current palette (2026-10-23): ice blue on pitch black

All colours live in `AppStyle` (Dreadline/Views/HauntedTheme.swift). Background and overlay darkness are pure black (#000000), so the black-backed ghost faces blend with no seam. Primary is ice blue (`accent`, ≈ #8CDBFF) for buttons, highlights and tint; `poison` is a paler frost for glows; text is cold white; borders are dark steel blue. Red (`blood`) is reserved for the Dismiss warning. The app icon is an ice-blue ghost on black. The orange palette described below is retired.

---

# After Dark — current Dreadline UI

Updated 2026-10-23 after the menu-bar usability review.

The menu popover is now a task-focused 500 × 560 surface (shorter on small
displays). A compact ghost trio and wordmark retain the Halloween identity;
the large promotional banner is removed. Near-black surfaces, ivory text,
ember-orange actions and muted spectral figures remain throughout the app.

Upcoming, Reminders and History are fixed segmented tabs. New reminder has one
persistent, labeled entry point. Upcoming leads with the next item and its time;
later items use compact rows. Empty states explain what is missing and give the
relevant next step. Operational copy uses literal names rather than horror
metaphors. Completed one-time reminders appear in History instead of remaining
in the active Reminders list. Repeating reminders show their next occurrence.

The reminder editor keeps Create/Save and Cancel at the top. Title, date and
repeat are visible immediately; notes, links and alert options are progressive
disclosures. Repeat time follows the selected due time. The occurrence timing
editor accepts minutes and explains ordering. Escape backs out of an editor,
stops an active preview, or closes the normal popover.

Test alert, Refresh and Pause are fixed footer actions. Extra preview variants
and Quit are in App options. Setup actions open the Calendars or Alerts tab of
the single Settings window. Alerts can be explicitly enabled without a hidden
preview prerequisite; preview remains available. No saved alert preferences are
automatically changed by this UI revision.

The popover anchor is not rewritten while open, preventing model updates from
interrupting navigation and editing. Settings remains the only standalone app
window. Fullscreen delivery, audio and reduced-motion behavior are retained.

Artwork is code-native in `Dreadline/Views/HauntedTheme.swift`; no new raster
assets or dependencies are required. The menu-bar line icon is unchanged.

---

## Previous direction and asset provenance (historical)

# The Watcher — Dreadline's haunted identity

## Research and interpretation

- BFI / Sight and Sound, [Curtis Harrington on supernatural horror](https://www.bfi.org.uk/sight-and-sound/features/ghoulies-ghosties-curtis-harrington-evolution-supernatural-horror-film): its discussion of Vampyr emphasizes the dramatic power of light, shadow, and suggested presence. Applied here as a distant figure and a slow, single reveal.
- BFI / Sight and Sound, [Shadow and substance: Nosferatu](https://www.bfi.org.uk/sight-and-sound/features/shadow-substance-f-w-murnaus-nosferatu): familiar architecture and empty space can acquire supernatural weight. Applied here as an ordinary calendar utility framed by a decaying corridor.

These are creative influences, not artwork sources. All corridor imagery is original AI-generated artwork. No film frames or franchise assets are bundled.

## Visual system

Charcoal canvas, aged ivory text, crimson actions, fine borders, serif display typography, monospaced signal labels, an eye emblem and static scanlines. The fullscreen alert gives its right side to the figure and keeps the left side readable for the meeting and actions. The home banner uses the same composition. Settings and editors use quiet dark surfaces. The menu and side panel share the typography and palette.

There is one 1.8-second image fade on presentation, disabled by system Reduce Motion or the app's reduced-motion preference. No recurring flashing or surprise audio was added. Join, Snooze, Dismiss, Pause and Escape retain their established actions. Real alert titles retain the existing redaction policy.

## Asset provenance

Built-in image generation tool, 2026-10-22. Former asset `haunted-corridor.png` (removed 2026-10-23; replaced by the six ghost images in POLTERGEIST-SEQUENCE.md). Original generated output retained under the tool's generated_images directory. The project generator now includes app resources in its build phase.

Final prompt:

> Use case: stylized-concept. Create an original cinematic psychological horror background for a native Mac haunted calendar app. Landscape 1536x1024. A decaying narrow Victorian corridor recedes toward an open doorway in the RIGHT THIRD of the frame. Within the doorway, a barely visible impossibly tall humanlike shadow with elongated arms and a pale indistinct face, eerie and genuinely frightening but no gore. A thin cold ivory light escapes from behind the figure; faint deep blood-red light grazes peeling walls and damp floor. LEFT HALF mostly near-black negative space for legible UI text. Analog 35mm grain, charcoal blacks, desaturated warm gray, faint volumetric fog, very dark yet silhouette and architectural detail visible. Sophisticated film still, photographic texture, restrained composition, no cartoon, no pumpkins, no Halloween decorations, no words, no logos, no watermark.
