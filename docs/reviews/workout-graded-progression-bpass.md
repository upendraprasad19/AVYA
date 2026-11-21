---
branch: workout-graded-progression
batch: 3b-ii
scope: W2.1 graded double progression (progression_resolver + shared parseRepRange)
blast_radius: platform
reviewer: context-blind adversarial B-pass (self-initiated, §4.3)
verdict: accepted
verdict_note: initial verdict changes-needed (1 P2 + 1 actionable P3); both fixed + re-verified → accepted
---

# B-pass — W2.1 graded double progression

Context-blind adversarial review of `git diff main -- lib/ test/`. Every load-bearing claim was
verified by the reviewer against the worktree files, `git show main:…`, `exercise_library.json`
(258 exercises), and the profile writers. Findings re-verified by me against the code before fixing.

## Verified-clean (the high-risk items hold)

- **Flag-OFF byte-identical — CONFIRMED.** With `enable_graded_progression` unset (`graded=false`),
  `allByExercise` is null (never allocated), the profile read is gated inside `if (graded)`, and the
  per-exercise branch falls through to the character-for-character shipped 10/5 block. `base`,
  `est1rm`, `lastSession` most-recent `date.isAfter` tie-break, Epley clamp + `toStringAsFixed(1)`
  are unchanged. The `_SessionTop` row hoist allocates one struct/row even when OFF, but output is
  identical. Nothing leaks to the OFF path → shipped ⑦a decay untouched.
- **`parseRepRange` + `_applyWave` rewire inert — CONFIRMED.** The only library rep_range not matching
  `^[0-9]+-[0-9]+$` is `30-60s` (Wall Sit, `logging_type: timed`) which early-returns before the parse.
  Zero rep-based exercises carry a non-clean range, so the shared parser returns the identical
  `(min,max)` the old per-part split produced for every real input. Diverges only on reversed/malformed
  ranges that don't exist → behavior-preserving (and removes a latent `clamp(lo>hi)` throw).
- **top-2 / 2-consecutive gate — CONFIRMED.** `_top2DistinctDays` de-dupes by `(y,m,d)` keep-heaviest,
  sorts desc, takes 2; back-off fires only when both top-2 distinct days are below `lo`. Same-day dupes
  → 1 distinct day → HOLD. `base`/`est1rm` sourced solely from `lastSession` → ⑦a untouched.
- **Bands + Epley + rounding — CONFIRMED.** Clean partition `[hi,∞)` progress / `[lo,hi)` hold /
  `(-∞,lo)` back-off; no off-by-one. `est1rm` from pre-decay `top.weight`; clamp applied to the graded
  result incl. beginner-linear.
- **ON vs OFF proven distinct.** `"8-12"@10 reps`: ON → 100.0 (hold), OFF → 102.5 (progress) — non-vacuous.

## Findings + resolution

### P2 — `beginnerLinear` read raw `DateTime.now()` → clock-seam violation + time-bombed test — FIXED
`progression_resolver.dart:111` computed training-age with raw `DateTime.now()` while the same
function's ⑦a decay path uses the adopted clock seam (`istTodayStr()`). Per `ist_date.dart:59-64`,
"what is today" reads MUST call `nowWall()` so the dev-panel time-travel + year-sim harness fast-forward
the calendar in one place (release-identical to `DateTime.now()`). Concrete consequence: the
`beginner + <120d → progress` test (`progression_resolver_graded_test.dart:154-158`) seeds
`onboardedDaysAgo:30` against a pinned `fixedNow`, but `setTestClockTo` only overrides the seam — so
`:111` read the **real** wall clock and the test would flip to HOLD (100.0 ≠ 102.5) once the real clock
passed ~2026-10-11 → a known-future red on `main` (rule 20).
**Fix:** `DateTime.now()` → `nowWall()` (`ist_date.dart` already imported at `:6`; `nowWall()` not
`istNow()` — training-age is an elapsed-instant diff against a UTC-parsed timestamp). Re-verified: the
beginner-window test now passes **deterministically** (`setTestClockTo` reaches `nowWall()` → training-age
pinned at 30d forever). 15/15 graded+decay tests green, analyze clean.

### P3 — `getProfile()` throw would empty the whole progression map — FIXED
`getProfile()` (new this batch, `:106`) sat inside the outer try whose catch returns defaults for
**every** exercise. A GuardedBox userBox desync throw would therefore nuke suggested weights for users
whose workout logs are perfectly readable — a regression this batch introduces.
**Fix:** wrapped the profile read in its OWN `try/catch (_) → beginnerLinear = false`, matching the
`gradedProgressionEnabled` getter's own-try/catch hardening (F6). A profile-read failure now only closes
the beginner window; graded/fixed progression still runs off the workout logs.

### P3 — invariance test pins the parser, not `_applyWave` output — NO CHANGE (sound)
`periodization_wave_reps_invariant_test` asserts `parseRepRange` tuples, not `_applyWave` reps across
archetypes×weeks. The reviewer independently verified the composition argument (parser equivalence +
library cleanliness) and the `*_archetype_test` suite pins end-to-end (160/160 green). The test's own
header documents this honestly. Noted for the record; no code change needed.

## Verdict: accepted
Both actionable findings fixed in `progression_resolver.dart` and re-verified (15/15 graded+decay tests
green + deterministic, `flutter analyze` clean, 160/160 archetype suite unaffected). The high-risk
invariants (flag-OFF byte-identical, parser inert, ⑦a untouched) held under adversarial review.
