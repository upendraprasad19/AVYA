---
branch: profile-stale-restore
date: 2026-09-02
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/d8f51f77c896-review.md
hermes: not_required
---

# Plan review record — profile-stale-restore (diagnose b3c9d4)

## What shipped

Founder reported the name rendering on Home but not on the Profile tab, with
Edit Profile's Full Name field blank — same account, same session, same Hive
key. The diagnosis is that this is **not a name bug**: Home and Profile read the
same key through DIFFERENT providers, only Home was wired to the
restore-completed signal, so Home self-healed and Profile did not.

Fix, one principle — **one source, one invalidation**:

1. The three Home name providers derive from `userProfileProvider` instead of
   each running its own `UserRepository.instance.getProfile()`, so Home and
   Profile cannot hold different answers.
2. The `restoreCompletedTick` listener moved from `home_screen.dart` into
   `HiveTabScaffoldMixin`, so all four tab screens refresh after a background
   restore rather than only Home. `userProfileProvider` added to Home's
   invalidation set — the omission that caused the bug.
3. `profileCompletenessProvider` derived from the same source (round-1 finding).
4. Edit Profile re-seeds its name controller when the profile heals (round-1).
5. A separate `invalidateOnBackgroundRestore` hook so a background event and a
   user-tapped retry are not the same claim (B-pass finding).

## Ground truth verified

Not from prose — from live state, by the author:

- **The race, timestamped.** `client_errors` for the founder's own session:
  `restore_started` 19:23:23.492 → `profile_full_name_empty_at_read
  reader=user_first_name` 19:23:27.267 → `restore_step_done step=A
  path=singlecall` 19:23:31.194. **Home read the name 3.8 s before the restore
  finished.**
- **The prior fix is live and irrelevant.** Fetched the deployed 24,101,793-byte
  `main.dart.js` from app.icanbefitter.com; all four of d4e9a2's post-fix strings
  are present. Its telemetry has nonetheless been silent for three days, because
  `path=singlecall` bypasses the retry helper entirely and nothing was failing.
- **The cloud value was never wrong** — `users.full_name = 'Upendra'` by direct SQL.
- **94% is this bug.** `full_name` is 1 of 10 `kTier1Fields`, tier 1 weighted 60%:
  9/10 + full tier 2 = 54 + 40 = 94, matching the founder's screenshot exactly.

## Review rounds

**B-pass (adversarial, context-blind) — 8 findings, 0 false alarms.** Found the
P1 that the batch's own fix introduced: the mixin change made Nutrition's retry
set fire on a background event, and that set includes `aiBreakdownProvider`,
whose invalidation pops the Log Food sheet and would have discarded a user's
just-generated AI food analysis.

**Round 1 (context-blind, ground-truth) — 7 findings, 0 false alarms.** Found the
P1 the B-pass missed: `profileCompletenessProvider`, a fourth independent reader
in no invalidation list, rendering a permanently wrong percentage on the same
screen as the wrong name. Refuted the batch's written claim that "nothing exposed
is left unfixed."

**Round 2 (context-blind, on the HARDENED diff) — 3 findings, 0 false alarms.**
Verdict on the code: sound. Verdict on the docs: 5 of 11 citations in the
diagnose-doc pointed at the wrong line, one at an unrelated symbol — in a
document that lectures about citation drift. All 11 re-derived by the author.

**Converged:** round 2 found no functional defect in the hardening, and its
findings were documentation accuracy plus two P3 refinements. Successive rounds
were not still surfacing new material mechanism issues, which is the §4.12.1
signal to stop rather than split.

## Decisions worth recording

- **One finding declined, on evidence.** Removing Home's Train-provider
  invalidation as "now redundant" would regress an unvisited Train tab:
  `app_router.dart:359` is `StatefulShellRoute.indexedStack` with no `preload`,
  so branches build lazily and an unvisited tab has no listener. Kept, with the
  reasoning in-source.
- **Scope boundary, stated rather than assumed.** Only the three cheap name
  providers plus completeness derive from the source. `nutritionSummaryProvider`
  and `macroTargetsProvider` stay independent — both are already covered by a
  tab's invalidation set, and deriving them would couple macro recomputation to
  every profile field change (an avatar upload recomputing the day's nutrition).
  The boundary is cost, not scope: nothing exposed is left unfixed.
- **Rejected, deliberately:** making the Hive read itself reactive (`box.watch`,
  typed `AsyncValue` absence) is the stronger industry answer and would dissolve
  this class outright, but it touches every profile reader and per §4.11 needs
  its detection gate landing first. Not bundled here.

## Mutation proof (rule 21)

Every protection this batch added was broken once and watched:

| Mutation (the exact pre-fix line, restored in place) | Result |
|---|---|
| Derived name provider → `UserRepository.instance.getProfile()` | 2 red — `Expected: 'BRUCE' / Actual: 'USER'`, the founder's exact bug |
| Mixin listener registration removed | 2 red |
| Tick handler → `invalidateOnRetry(ref)` (pre-hardening shape) | 1 red |
| `profileCompletenessProvider` → `getProfile()` | 1 red — 6-point delta became 0 |

Each mutation was confirmed APPLIED by `grep -c` before the run, so a pattern
that silently matched nothing could not make a green run read as proof.

## Gates

`flutter analyze lib/` — 0 warnings, 0 errors (full tree, not per-file: the
`part`-file trap). Full `flutter test` — **5292 passed, 0 failed, 7 skipped**,
run before the push rather than discovering it at pre-push. Full pre-commit gate
loop green; it caught 7 stale SoT `line_range`s that this batch's own edits to
`home_provider.dart` had shifted, twice — mechanical work removed from reviewer
attention exactly as §4.12.5 intends.
