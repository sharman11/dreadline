# Poltergeist horror pass — 2026-10-23

The warning is now a disturbance, not a character introduction: three knocks, three real window-minimization waves, nail-like scratches at different edges, a bounded visual jolt, then a faint presence in darkness. The workspace restores before the four-second release.

At meeting time the windows minimize, a single 650 ms close-up confronts the viewer, and then the meeting controls appear. The supplied knock clip is retained for the warning; the original synthetic sting aligns with the arrival close-up. There is no looping flashing.

Three entrances remain. Reduced motion skips the jolt and close-up. Escape cancels choreography, pending minimization waves, sound, and restores windows. Existing minimized-window state and failed-restore handling are retained. The sequence never moves or resizes other apps' windows; its jolt is drawn inside Dreadline's own overlay.

Verification: 69 tests passed. New tests cover minimization in three groups, canceling unstarted waves, canceling later knock callbacks, reduced-motion behavior, and the close-up transitioning back to controls. Subjective horror, audio balance and cross-Space/display behavior still require a direct manual pass.

Former (removed 2026-10-23, replaced by the six ghost images) generated asset: `Dreadline/Resources/apparition-closeup.png`. Created with the built-in image-generation tool using `storybook-ghost.png` as the character reference. Original reference and prior assets were retained.

Final generation prompt:

> Use case: style-transfer / illustration-story. Reference image is the app's existing ghost character; derive a MUCH MORE FRIGHTENING close-up apparition from the same character for a 0.6 second fullscreen reveal. Square composition, head and two skeletal hands only, the face looks straight out at viewer as if pressed against the inside of the screen. Huge ragged black eye cavities, tiny off-center pale pinpoints deep within, grotesquely elongated open mouth, crumbling parchment-white shroud, sharp uneven ink contours, long bony fingers splayed against imaginary glass framing the face. Uncanny asymmetry, deeply menacing, stark black India ink, antique woodcut crosshatching and scratched dry-brush detail, original gothic horror storybook illustration. Tight face fills central 65 percent, hands at side edges, full head intact, transparent outer background. No gore, no blood, no text, no smiling cute ghost, no photorealism, no scenery, no border. Preserve the recognizable shrouded character while making it confronting and startling.

## Animation polish — 2026-10-23

- Audio, window waves, arrival sting and restoration now run from the same absolute-time, cancellable scene timeline. Separate audio and restoration timers were removed; the independent maximum-duration watchdog remains.
- Removed the full-screen positional shake and spring bounce. Scratches draw in as trimmed curves, with thinner strokes and less contrast.
- The close-up has a short eased entrance, hold and fade-out; the meeting card fades/slides into place afterward. The secondary ghost moves continuously between poses instead of snapping when a stage changes.
- The paper edge uses a shallow organic contour rather than a large sawtooth. Restoration is called before the reveal begins.
- Reduced motion, immediate Escape/Pause, source-update deduplication and restoration ownership remain intact.
- All 71 tests pass. Added checks establish cue ordering and cancellation of a stale scene's restore callback. Visual feel still requires direct acceptance on the user's Mac.
