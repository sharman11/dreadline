# Halloween art-direction research — 2026-10-22

Status: concept exploration, not an implemented redesign. The user rejected the previous cinematic corridor theme as generic. This pass investigates a stronger Halloween identity before changing the app again.

## Diagnosis

The existing theme uses a photographic banner, dark cards, dramatic serif copy and red accents. Its decoration dominates the calendar utility. The next direction should be recognizable through its typography, compact layout, illustration and controls even without a background image. Remove the promotional hero and use the real upcoming meeting as the primary content.

## References

1. Vintage Beistle original Halloween archive and reproductions: https://www.vintagebeistle.com/ and https://www.vintagebeistle.com/store/c/18-Vintage-Halloween.aspx . Reference for orange/black printing, expressive cats and pumpkins, cut-paper silhouettes and compact decoration.
2. The Walt Disney Family Museum, Making Spooky Wallpaper: https://www.waltdisney.org/education/workshops/sold-out-virtual-pop-making-spooky-wallpaper . Reference for eerie Victorian pattern, shape and tone.
3. Klei, Don't Starve official media: https://www.klei.com/games/dont-starve/ . Reference for a coherent illustrated world and expressive silhouettes. Do not reuse characters or game assets.
4. Panic, Designing for Playdate: https://help.play.date/developer/designing-for-playdate/ . Reference for deliberately constrained small-screen interfaces and clear controls.

## Proposed directions

### 01 — Halloween Print (recommended)

Vintage Halloween ephemera with a contemporary compact agenda. Pumpkin orange, cream paper, black ink. Condensed display lettering reserved for the app identity; clean native typography for times and actions. Original sinister jack-o-lantern/cat illustration serves as a small recognizable identity, with a stronger manifestation in fullscreen. Fine ruled rows replace card stacks. Sparse paper/ink texture stays outside reading areas.

Main screen: compact header and date, upcoming time and meeting, Join/Snooze, three agenda rows, Pause and Settings. No hero image, promotional prose or permanent sidebar.

Fullscreen: black field, one large original orange woodcut face, a plainly readable meeting title and countdown, consistent actions. The illustration changes expression on alert; no flashing is required.

### 02 — Haunted Hotel

Aubergine wallpaper at margins, ivory appointment slips, tarnished brass rules, room-key emblem and narrow serif headings. Main UI resembles a hotel appointment ledger. Fullscreen resembles a room summons. Strong atmosphere but less immediately recognizable as Halloween and more risk of excessive ornament.

### 03 — Crooked Storybook

Cream paper, charcoal ink and one sickly-green accent. Scratchy original ghost illustration, irregular decorative outlines around a precise UI grid. Strong character identity; can drift toward cute if expressions and silhouette are not controlled.

## Selection criteria

- Recognizable at menu-bar scale, not just fullscreen.
- Legible when filled with real long meeting names.
- Fewer screens and choices than the existing app.
- Character and theme support timing states, not random decorative animations.
- Keep functional labels literal: Join meeting, Snooze, Dismiss, Pause, Settings.
- Evaluate concept board before another wholesale implementation.

## Concept board

The former `design/halloween-directions.png` (removed 2026-10-23) was an exploratory mockup generated with the built-in image-generation tool. It is not a screenshot of implemented software. Production should reduce title size and decorative texture, use clean native typography for body text, and preserve precise alignment and accessibility.

Final generation prompt:

> Use case ui-mockup. Produce a high quality art-direction comparison board for Dreadline, a simple native Mac meeting reminder app for a Halloween hackathon. Wide landscape 3 columns, clean neutral light gray board, clear labels above three equally sized app window mockups. All three concepts show exactly the same compact functional UI: header DREADLINE and small settings gear, date OCT 31, title Up next, large time 09:41, meeting Design review, secondary text Starts in 2 min, primary Join meeting button, secondary Snooze 5 min, smaller upcoming rows 10:30 Team standup and 14:00 Project sync, bottom Pause alerts. Short enough text to render accurately. These must look like purpose-designed crafted usable desktop utilities, dense but legible, not marketing landing pages. No hero banner, no photographic image, no sidebar, no giant tagline, no floating glass cards or gradient buttons. Original art only. Concept A label 01 / HALLOWEEN PRINT: strongest recommendation, vintage 1930s Halloween printed ephemera aesthetic, pumpkin-orange header, warm cream paper workspace, coal-black typography and hairline ruled agenda rows, thick condensed wood-type DREADLINE logotype, original sinister black cat / jack-o-lantern face woodcut occupying small corner near clock, slight misregistered ink edges and very subtle paper speckle only in decorative areas, orange rectangular CTA, very polished restrained functional layout. Concept B label 02 / HAUNTED HOTEL: dark aubergine frame with original subtle damask wallpaper visible only at outer margins, ivory central appointment slip, brass thin rules and small antique key emblem, narrow elegant serif headings, plain readable UI text, room-key tag 13 small, rich hotel desk aesthetic, restrained ornate corners, elegant and quietly ominous. Concept C label 03 / CROOKED STORYBOOK: black-ink illustrated haunted storybook, muted cream charcoal and sickly green accent, original spindly long-armed ghost peeking from top-right corner, irregular hand-ink frame but precisely aligned functional rows, expressive crooked hand-drawn display lettering DREADLINE, clean small UI text, plain acid-green join button, unnerving whimsical indie-game quality, no copied game characters. Distinct visual identities grounded in typography, spacing, rules and controls. Labels and app windows dominate board. No extra annotations. Photoreal computer mockup not needed; flat crisp UI presentation.
