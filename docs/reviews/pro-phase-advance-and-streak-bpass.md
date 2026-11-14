---
reviewed_at: 2026-10-16T22:30:00+05:30
staged_against: 6db9eee3fcba (tree after both rounds; round 1 on a4afc5f3c6ba)
blast_radius: platform
reviewer: claude-sonnet-via-skill (2 fresh context-blind rounds; round 2 on the post-fix tree)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 16
verdict: accepted
---

# Code Review - pro-phase-advance-and-streak (Piece A, diagnose d9b3e7)

Two read-only fresh Sonnet reviewers with an exhaustive command list (no scripts, no database, no edits). Round 1 ran on the diff as first staged and was told to attack the one design deletion no plan-review round re-verified (an in-flight guard against a mid-generation Train rebuild and restore writers, deleted at plan v10). Round 2 ran on the tree after round 1's fixes, which nobody had reviewed.

## Round 1 (7 findings: 0 P0, 1 P1, 2 P2, 4 P3)

### Finding 1 - P1 - guard_without_its_mirror (the v10 deletion)
- **file:line:** lib/core/services/day_rollover_service.dart (both ensure call sites), lib/features/train/providers/train_provider.dart (`CurrentPlanNotifier.build` -> `_autoGeneratePlan`)
- **claim:** the tick bump / rollover invalidation makes Train rebuild lazily right after the ensure starts, see plan_start already moved and no week-1 rows, and regenerate the OLD phase over the new window.
- **verification:** reproduced by a failing test first (`A3`: every schedule row from 2026-10-12 carried phase 3, blob phase 3), then the fix passes it.
- **status:** accepted - fixed. `phaseAdvanceInFlight` (the lock's completer); `_autoGeneratePlan` waits and refreshes. Mutants: guard dropped, refresh dropped, completer never set - all red.

### Finding 2 - P2 - cross-account
- **claim:** the owner can change during `generateAndSchedule`'s awaits; `commitPhaseAdvance` would write the old account's phase to the new account.
- **status:** accepted - fixed for the progress commit (`expectedUid`, outcome `declined`, behavioral test swaps the account inside the awaited push). The per-write owner check inside `generateAndSchedule` is older, shared with the splash and card paths, and is an OI (see the diagnose doc).

### Finding 3 - P2 - PlanWindowReanchor
- **claim:** (a) a restore resolve between the window writes and the blob write reverts the window; (b) Edit Profile stamps the blob with phase 1 (it reads `profile['current_phase']`, a column that does not exist on `users`).
- **status:** accepted - fixed. (a) the window is pinned while the advance lock is held; (b) Edit Profile reads `user_progress` (presence pin only; the screen is not drivable here).

### Findings 4-7 - P3
- 4 (`proPhaseEvidenceGap` accepted a double the advance would throw on): accepted - strict int. 5 (a declined commit reported as generated): accepted - `{generated, committed}` and outcome `declined`. 6 (diagnose claim "no isPro() writer" false; `busy` is silent): accepted - doc corrected, busy documented. 7 (`isPhaseExpired` scanned twice per Train build): accepted - one read.

## Round 2 (9 findings: 0 P0, 0 P1, 5 P2, 4 P3)
- 1 P2 the stale-rows report awaited an unbounded network call inside the lock: accepted - bounded to 10 s.
- 2 P2 the Train wait and the restore pin were outside the kill switch: accepted - both off under `disable_pro_phase_ensure`.
- 3 P2 a PRO `expiresAt` of 2027-10-01 in the new test (clock bomb): accepted - relative to the real clock.
- 4 P2 the Train-rebuild test depended on a scheduler race: accepted - a deterministic held-lock companion test, sleeps became bounded polls, background repairs settle before the next test.
- 5 P2 the account-swap test swaps after every row write; the diagnose text over-claimed: accepted - text corrected, residual named.
- 6 P3 event dedupe suppressed repeat generated/declined/failed: accepted - only deferred/skipped dedupe.
- 7 P3 the pin was read once: accepted - re-checked before each window write.
- 8 P3 a declined build did not repaint: accepted - tick bumped.
- 9 P3 N whenComplete closures for N rebuilds: false_alarm in effect (benign, they coalesce into one refresh), no change.

## Checked and clean (both rounds)
Completer lifecycle (completes once in finally, null when the lock switch is on), call sites of `_runAdvanceWith`/`runProPhaseAdvance`/`commitPhaseAdvance` (git grep), import cycle (compiles, 59 pre-existing infos), `blobPhase` key, secrets scan (0 hits), source-grep tests reading these files (none broke), `flutter analyze lib/` 0 warnings 0 errors.

## Founder triage notes
Not yet triaged by the founder. Process residue: the plan-review record (docs/plan-reviews/pro-phase-advance-and-streak.md) lands in its own later commit (the hash fixed point described in the code-review skill).
