---
branch: progress-map-consolidation
date: 2026-07-30
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/9d758b27ab29-review.md
---

# Plan review — progress-map-consolidation

OI-45 named `UserRepository`'s progress-map writers as a HIGH lost-update race citing 4 writers;
a prior board-correction pass found the real writer set was 3x undercounted. This unit
("Unit 3a", split mid-investigation from a larger originally-scoped "Unit 3" — see below)
investigated that claim with the same behavioral rigor as the sibling usage-counter-race batch:
does the claimed race actually reproduce, and what is the real fix. A `Completer`-based mutex
mirroring `ProfileWriteService._withLock` was built first, matching established codebase
convention — then tested via negative control (temporarily disabled, full suite re-run) and found
to provide NO correctness benefit for any concurrent `updateProgress`/`saveProgress` pairing
(same structural-safety class as `UsageCounterService.increment()`: Hive's `Box.put()` lands its
in-memory mutation synchronously) AND to actively BREAK 2 pre-existing tests by serializing two
previously-independent unawaited fire-and-forget writers into a genuine queue — a real timing
regression with no offsetting gain. The mutex was removed, not patched around. The GENUINE,
confirmed bug is different and simpler: `pro_phase_advance.dart` and `simulation_service.dart`
read `progress`, awaited REAL slow plan-generation work, then wrote the WHOLE map back from that
pre-await snapshot — clobbering anything an independent writer landed during the gap. Fixed by
converting both to `updateProgress(delta)`. Two sibling OI-45 findings (`BadgeService`,
`HealthSyncService`) were investigated in the same pass. Tier is `platform` — not because the
diagnosed bug is (it's `account`, one user's own data), but because the B-pass round (below) found
and fixed a real gap in `docs/blast_radius.yaml` itself, which is platform-tier by its own
registry.

## Rounds

| Round | Outcome |
|---|---|
| 1 — independent, context-blind (general-purpose agent), on the first-hardened diff | **PASS.** Re-verified every claim against actual code, including independently re-reading the pinned Hive 2.2.3 package source to re-derive the synchronous-`Box.put()` claim from first principles rather than trusting it as asserted. 2 findings: (P2, fixed) `health_sync_service.dart`'s new `_syncInFlight` guard called `completer.complete()` unconditionally in `finally`, so a deduped follower would silently observe SUCCESS even when the leader's sync actually failed — fixed to propagate the real outcome via `completeError`+`rethrow`. (P2, confirmed real but NOT fixed — spun out as tracked follow-up "Unit 3c") `graduation_screen.dart`'s `_onPro()` has the same general bug class — `nextPhase` computed before a slow `generateAndSchedule` await — but already uses `updateProgress(delta)` (narrower blast radius) and needs real conflict-resolution design since the plan generation has already produced real schedule rows by the time of the stale write, unlike a mechanical delta-conversion. |
| 2 — independent, context-blind (a different general-purpose agent, no memory of round 1), on the round-1-hardened diff | **PASS.** Re-verified the mutex-removal claim by reading `user_repository.dart` directly (confirmed zero lock code remains), independently re-derived the synchronous-`Box.put()` claim again from the Hive source, re-ran all tests live, and grepped fresh for every remaining `saveProgress`/`updateProgress` caller to rule out un-fixed instances of the same bug class (found none). Found a NEW issue round 1's OWN fix introduced — exactly the risk §4.12 names ("the corrections themselves can introduce new defects"): the completer's `completeError()` call, in the common case where no concurrent follower ever attaches a listener to `completer.future`, is treated by Dart as an unhandled error and reported a SECOND time to the current `Zone` — independently reproduced via a `runZonedGuarded` repro script (not taken on the reviewing agent's word) confirming a duplicate FATAL Crashlytics report on every ordinary sync failure. Fixed with a silencing `completer.future.catchError((_) {})` attached before the first await — verified via a second repro that this suppresses the phantom duplicate without preventing a real follower from observing the true outcome (Future listeners fan out, not consume). Also found and fixed: a stale line-number citation, and a stale "9 files" writer-count figure never recounted as the enumerated list grew across three separate correction passes (resolved with a single fresh count: 15 write callsites across 11 files). |
| B-pass — fresh context-blind (sonnet, `/code-review` skill, 5 lenses), on the round-2-hardened diff | **PASS → accepted.** 4 findings, detail in `docs/reviews/9d758b27ab29-review.md`. (P2, fixed) A real, load-bearing gap in `docs/blast_radius.yaml` itself: its own comment said `lib/shared/repositories` is `account`-tier, but no rule implemented it — the path fell through to a `feature` catch-all under first-match-wins ordering, independently reproduced via the classifier's own stdin mode before fixing. Same mechanism hit `graduation_screen.dart` (Unit 3c's target). This meant Units 3b and 3c, both already queued as this batch's own follow-ups, would each silently clear zero review gate. Fixed with 2 narrowly-scoped new rules plus a behavioral test spawning the real classifier subprocess against 4 real paths. (P2, fixed) A test that proved less than its name claimed — `total_workouts_done` silently came back `null` in a "do not corrupt each other" test, independently reproduced via a temporary print (reverted after confirming) — not a bug but `saveProgress`'s real REPLACE-not-merge contract, undocumented until now; fixed with an explicit assertion, a renamed test, and a new warning on `saveProgress`'s own doc comment. (P3, fixed) A stale test-filename citation. (P2, spawned as tracked follow-up, task #41 — not fixed inline) The only regression test for this diagnose-doc's central bug proves the bug pattern via `UserRepository`'s own primitives, never the actual production functions (`advanceProPhaseIfExpired`, `_maybeAdvancePhase`) — confirmed via grep that every existing test referencing those functions is source-grep style. Scoped out rather than forced in: building a real behavioral test needs a `WidgetRef`-capture bridge (pattern exists) PLUS driving real plan generation against exercise-library/profile/subscription fixtures (no existing pattern to extend) — genuinely novel test infrastructure, disproportionate to the same pass that found it. |

## Why this is converged rather than merely green

Three consecutive rounds, three consecutive genuinely NEW findings, each non-overlapping with
what the prior round caught: round 1 found a real defect in the original fix (the unconditional
`complete()`); round 2 found a real defect IN ROUND 1'S OWN FIX (the unlistened-Future duplicate
Zone error) — the exact "corrections introduce new defects" risk §4.12 exists to catch, caught
here in practice, not just in principle; the B-pass found a structural gap in the REVIEW
INFRASTRUCTURE itself (the blast-radius registry under-classifying the very files this batch
touches), which neither round 1 nor round 2 was looking for because neither was scoped to check
the registry's own correctness — only a differently-framed pass (the B-pass's lens-based
checklist, specifically the `blast_radius_mismatch` lens) caught it. That last point mirrors the
sibling `oi46-daily-cap-triggers` record's own lesson: a structural gap in the ANALYSIS
infrastructure survives rounds framed as "review this diff" and needs a differently-shaped pass to
surface. Every fix at every round was verified by re-running the actual tests afterward, not
assumed correct from the finding's plausibility — 18 contract tests green after the final round
(5 stale-snapshot + 3 badge-invariant + 6 health-sync-dedup + 4 blast-radius-paths), up from 0
before round 1 started (the fix and its own regression tests landed together, pre-round-1).
`flutter analyze` clean (one pre-existing, correctly-disclosed info-lint) at every checkpoint.

Also converged in the sense §4.12 explicitly names as the alternative to a 5th review round: when
successive findings kept surfacing genuinely new material (the mutex's own removal, then Unit 3c,
then the blast-radius gate gap, then the test-coverage gap), each was independently assessed for
whether it belonged in THIS unit or needed its own scope — Units 3b and 3c were split out during
investigation itself (before round 1 even started) because they need real design work, not just
implementation; the B-pass's Finding 4 was split out (task #41) because it needs real test
infrastructure with no existing pattern to extend. The two genuinely-in-scope B-pass findings that
COULD be fixed cheaply and correctly in this pass (the blast-radius gap, the test's overclaim) were
fixed inline rather than reflexively deferred — the split/fix decision was made per-finding based
on genuine tractability, not as a blanket "ship it now" shortcut.

## Ground truth

Verified directly against live code and files at every step, not taken from any round's own prose:
the mutex-removal claim was verified by reading `user_repository.dart` directly at both round 1
and round 2 (zero lock code remains, only doc-comment prose); the synchronous-`Box.put()` claim
was independently re-derived from the actual pinned Hive 2.2.3 package source (`box_impl.dart`,
`keystore.dart`) twice, by two different reviewing agents, rather than trusted as asserted; the
`graduation_screen.dart` Unit 3c citations (lines 568/573/588/591-604/642-659/665) were confirmed
against the live file by direct read, not the diagnose-doc's prose; the round-2 Zone-error P1 was
independently reproduced via a standalone `dart run` repro script BY ME (not just accepted from the
reviewing subagent), both the broken and fixed shapes, confirming the duplicate fires only in the
unlistened (common) case and the fix genuinely preserves follower observability; the B-pass's
blast-radius finding was independently reproduced BY ME via the classifier's own stdin mode before
AND after the fix, plus 2 control paths (`plan_engine/**` staying `platform`, other `train/**`
files staying `feature`) to confirm the fix didn't over-broadly promote unrelated paths; the
`total_workouts_done` REPLACE-semantics finding was independently reproduced BY ME via a temporary
print statement, confirmed via `git diff` that the revert left no residue before making the real
fix; the "15 write callsites across 11 files" recount was independently re-derived BY ME via a
fresh `grep -rn '\.updateProgress(\|\.saveProgress('` across `lib/`, not copied from any prior
pass's number.

## Residuals, stated

- **Unit 3b (not started):** cross-device optimistic locking for the `progress` map — the dormant
  `update_streak_progress` RPC (built 2026-05-11, never wired) needs finally wiring into
  `syncFreezes()`, a new sibling RPC for the fields it doesn't cover, local version-tracking, and
  bounded retry-on-mismatch. OI-45 stays OPEN until this lands.
- **Unit 3c (not started, found by round-1 review):** `graduation_screen.dart`'s `_onPro()` writes
  a `nextPhase` value computed before a slow await, not re-derived after it. Narrower blast radius
  than the fixed bug (delta write, not whole-map), needs real conflict-resolution design.
- **Behavioral test for the real phase-advance callsites (not started, found by B-pass, task
  #41):** `advanceProPhaseIfExpired`/`_maybeAdvancePhase` have zero behavioral coverage of their
  own write path — only the bug pattern is proven, via `UserRepository`'s own primitives. Needs
  the `day_rollover_provider_invalidation_behavioral_test.dart` `WidgetRef`-bridge pattern plus
  real exercise-library/profile/subscription Hive fixtures to drive
  `WorkoutScheduleService.autoGenerateNextPhaseIfNeeded` for real.
- Unit 3a does NOT change server-side protection for ANY progress field — same-device races (the
  confirmed bug) are closed; cross-device races (unconfirmed, no known live incident, migration
  056 sat unwired for 2.5 months with no reported symptom) are not addressed here.
- `saveProgress`'s REPLACE-not-merge contract (B-pass Finding 2) is now documented but not
  redesigned — its only 2 real callers today don't need merge semantics, so changing the contract
  itself would be unjustified scope for a theoretical (not live) sharp edge.
