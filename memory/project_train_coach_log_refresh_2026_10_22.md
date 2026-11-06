# train-coach-log-refresh: Train refreshes after a coach chat log; the chat workout card says what saved; readable rows (OI-370, OI-371) · 2026-10-22

Branch `train-coach-log-refresh` · PR #144, merged `dd0c527a` (main CI green) · plan
`docs/plans/train-coach-log-refresh.md` rev 11 · record `docs/plan-reviews/train-coach-log-refresh.md` (10 rounds,
platform tier, `bpass: accepted`) · closure `docs/audit/train-coach-log-refresh.closure.yaml` (75 mutations, all
red) · B-pass `docs/reviews/f7148ddecbe1-review.md` (0 P0/P1, 3 P2, 9 P3) · diagnoses `e2a418` (stale Train),
`5aa251` (card showed success for a failed write), `2e8b8f` (names cut). OI-370/371 CLOSED in `closed_issues.md`;
device and web check still owed under OI-348 (A12).

## How this batch started

The founder's A12 web walk (2026-10-21): a Bench Press logged from the coach chat card did not appear in Train's
expanded day until a page reload (OI-370), and the expanded row cut names to about four characters at phone width
(OI-371).

## What shipped

- One helper, `invalidateWorkoutSurfaces` (`lib/features/train/providers/workout_surface_invalidation.dart`, seven
  providers, each guarded), called by the three coach write paths (tool dispatcher, chat draft, completion prompt).
  The chat path calls it through the container captured before its first await, so a card disposed mid-submit still
  refreshes Train. A new exact-path rule in `docs/blast_radius.yaml` pins the helper at `account`.
- The chat workout card (B') attempts every exercise and shows saved / day-not-marked / partial / none-saved with
  founder copy; a new card is held while one is saving, saved or failed; "Discard the rest" asks first; a held card
  ignores CONFIRM for `kHeldCardTapGuard` (500 ms) after it appears.
- `ExpandedExerciseLogRow`: the name on its own unlimited line, the detail under it, `1 set` / `N sets`, numbers kept
  with their units (NBSP).

## Things worth carrying forward

**1. A hook that is declared but never assigned reads like coverage.** `WorkoutWriteService.onInvalidate` was
checked at nine sites and assigned nowhere, and caller comments said it "handles the full batch". That is how
OI-370 hid. When a comment says another component does the work, find the assignment, not the declaration
(remaining hand-written copies: OI-376).

**2. A fixture must exercise the property the test claims.** The first OI-371 test used long real names, which
wrapped whether or not the fix was in, so the `detail_beside_name` mutation stayed green. A short name with a short
detail was needed to prove the layout. Same family as "mutation-prove the surface, not the seam" (FOB-1).

**3. Fake time hangs an unguarded write.** Two mutations (`second_submit_not_refused`, `bp_tap_guard_removed`) hung
the suite because the write they let through ran inside `testWidgets` fake time. A real-time `tapWrite` helper and a
bounded `.timeout` turned a hang into a red test. A mutation that hangs proves nothing until it fails cleanly.

**4. Time-of-day tests use UTC instants.** The IST-midnight test built local `DateTime`s, passed on the VPS and failed
in the regression catalog after a merge. `DateTime.utc(2026,10,20,18,29)` / `(18,35)` fixed it, checked under UTC,
Asia/Kolkata and America/Los_Angeles.

**5. "Filed" means on the board.** The cardio duration bug surfaced in this batch's fixture (a cardio row read
0 min). It was reported as "filed separately" when only a suggested-task card existed; the founder was told so on
2026-10-22 and it was minted as OI-389. Do not say filed until `mint_oi.sh` has returned a number.

## Session mechanics (cloud)

- `scripts/safe_pr_merge.sh` 403s in a cloud session (GitHub GraphQL is blocked). With the founder's go, the same
  five required checks and the no-`.github/` rule were verified by hand and the merge pinned to the head SHA
  (precedent #134). It remains a deviation from the sanctioned wrapper.
- The cloud primary has no local `main` branch, so `retire_worktree.dart` reports `[branch not merged]` until
  `git fetch origin main:main`.
- `mint_oi.sh` needs `MINT_OI_TRANSPORT=git` here (the `gh api` transport fails), and that ref push runs the full
  pre-push suite.
- Two docs PRs into one board (`open_issues.md`, `OPEN_INDEX.md`, the code-review tuning history, the SoT registry,
  naming conventions) conflict on every merge; keep both sides, main first, regenerate the indexes.

## Open after this batch

OI-348 A12 device and web check of this batch; OI-376 (other hand-written invalidation copies); OI-377 (duplicate
exercise-log reader); OI-389 (cardio minutes and distance lost in `logExercise`).
