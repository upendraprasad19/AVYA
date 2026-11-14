# Exercise plate artwork

Derived from [workout-guide](https://github.com/bryllim/workout-guide) by Bryl Lim
(commit `aac599224bb9780305239607ef98540b7e0ce389`), itself vector-traced from
[Everkinetic](https://github.com/everkinetic/data).

Both are licensed **CC BY-SA 4.0** — https://creativecommons.org/licenses/by-sa/4.0/

**Changes made:** each `viewBox` was cropped to the ink bounds — the union of both
frames for a two-position movement, the frame's own bounds for a static hold — and
the fill was changed from `#fff` to `currentColor` so the app can tint it. No path
data was altered.

Redistributed under the same licence. The per-frame creator and Everkinetic source
for every drawing is preserved in `docs/plans/exercise-plates-manifest.json`.

⚠ **This file documents the obligation; it does not DISCHARGE it.** It ships inside
the APK — the flat asset line bundles the whole directory — but no user will ever
open it. `assets/exercise_plates/LICENSE-CC-BY-SA-4.0.txt` is registered with
Flutter's own `LicenseRegistry` at startup and reachable from Profile → CREDITS &
LICENCES, and *that* is what puts the attribution in front of a person.
