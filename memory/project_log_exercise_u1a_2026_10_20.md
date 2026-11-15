# U1a — one LOG per exercise in Active Workout (ship dark) · 2026-10-20

PR #128 · branch `active-workout-log-exercise` · feat commit `344cd2d` · merged to `main` as `451b028`
Plan `docs/plans/active-workout-log-exercise.md` (rev 5) · record `docs/plan-reviews/active-workout-log-exercise.md`
(5 rounds, converged, `tier: ship_dark_build`) · B-pass `docs/reviews/0ca89ed08961-review.md` (0 P0, 0 P1, 6 P2,
all fixed; verdict left `pending` for founder triage) · closure `docs/audit/active-workout-log-exercise.closure.yaml`
(14/14) · ship-dark entry in `docs/ship_dark_pending_review.yaml` with HARD flip preconditions.

## What shipped

Behind `enable_log_exercise_button` (default OFF, only the debug dev panel writes it): each exercise card gets a
`− N +` stepper and one LOG button instead of a check tap per set. `ActiveWorkoutNotifier.logSets` is additive and
bounds-checked; `LogExerciseController` (screen-owned) ignores taps for 400 ms after an advance on a monotonic
Stopwatch, expands the next unfinished exercise and scrolls an unfinished superset partner into view. A blocked LOG
reads `Add/Fix weight|reps|time|distance` and focuses the missing field. OFF path untouched.

Founder decisions 2026-10-19: no skipping a middle set (`−` removes the last); each superset exercise keeps its own
LOG; "2 + 1 split, drop save changes" — batch 2 (OI-356: UNDO, mirror of set 1's typed weight/duration/distance,
last-exercise emphasis) is flip-ready; batch 3 (OI-357) is polish after the flip.

## Things worth carrying forward

**1. A widget test whose tap writes Hive must run that tap in `runAsync`.** The spike hung twice: once on fonts
(render the AppTypography families before any path_provider mock), once because LOG's `_persistActiveState` `put`
started inside fake async and tearDownAll waited forever. `test/features/train/log_exercise/card_harness.dart`
`tapWithRealIo` is the pattern. Same family as the §4.9 "`await`-ing real disk I/O inside `testWidgets`" row.

**2. State precedence is a bug class of its own.** The blocked label was checked AFTER the LOGGED state, so a logged
exercise with a newly invalid edit showed LOGGED. The fix scans every set for a failure first; the B-pass caught it.

**3. Merging `origin/main` into a feature branch can make the staged diff catastrophic.** The first conflict merge
pulled in OI-341's payment Edge Functions, so `check_code_review_pass_exists.dart` demanded an accepted review of the
merge itself (`docs/reviews/47d4758398c7-review.md`, provenance only). The merge-to-main gate is unaffected: it
reads the two-dot net change, which is this branch's own account tier.

**4. `safe_pr_merge.sh` cannot run from a cloud session.** It reads the PR with `gh pr view`/`gh repo view`
(GraphQL), and this environment answers GraphQL with 403. It fails closed, correctly, but that leaves no sanctioned
merge path here; the founder merged #128 with the GitHub button after CI was green on the head. The fix would be
REST calls (`gh api repos/{owner}/{repo}/pulls/{n}`) in `scripts/safe_pr_merge.dart`. Not filed yet.

**5. OI-311 (`dart run` exit 254, `File not formatted as yaml: .`) hit this PR.** Fourth sighting with output,
recorded on the board. The session could not re-run the job (`rerun-failed-jobs` 403); the next push went green.
New fact: the two CLI-spawning blast-radius test files sort adjacently, so the round-robin partition always puts
them in one shard, running concurrently.

## Still open after the merge

- Device check on a debug build with the flag ON and OFF (§5 row; cannot be done from a cloud container).
- Founder triage of `docs/reviews/0ca89ed08961-review.md` (verdict `pending`).
- Batch 2 (OI-356) needs its own ×2 plan review; the flip needs batch 2, a full ×2 review and the founder's go.
