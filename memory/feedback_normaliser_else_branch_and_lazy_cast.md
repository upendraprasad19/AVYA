# Two silent-loss shapes found in OI-389 (2026-10-22)

**1. A normaliser's else-branch silently covers every type added later.** `_normalizeSetsByLoggingType`
(a4c7d1, 2026-09-22) had two branches, `timed` and "everything else", and the else zeroed `durationSec`.
`cardio` and `distance` fell into it, so every cardio minute was saved as 0 for a month while the swap fix it was
written for worked. Rule: a per-type table enumerates every type and states what each keeps; the default case
is the weight types, named as such. In this repo the table is `fieldsClearedFor` (`workout_write_service.dart`),
read by the writer, `exerciseSetFromInput` and the heal: one table, never a copy.

**2. A lazy `.cast<Map<String, dynamic>>()` on a list read from Hive is dead code.** Hive hands back
`Map<dynamic, dynamic>`; the cast is lazy and throws on the first element read, and a surrounding catch swallows
it. `_healMismatchedExerciseLogs` has never healed a disk row (found in plan review round 3, pinned by T10b; the
live heal is OI-394). Rule: when reviewing a Hive reader, check every `.cast<...>()` against what Hive returns;
convert with `Map<String, dynamic>.from(e)` when the code must run, and when its footprint must stay as it is,
pin that with a test on a `Map<dynamic, dynamic>` fixture.

Diagnose `docs/diagnoses/2026-10-22-cardio-duration-distance-e7240a.md`; skill red flags in
`.claude/skills/debugging/bug-classes.md`.
