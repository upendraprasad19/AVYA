---
branch: usage-counter-race
date: 2026-07-29
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/e0f4fb3263d0-review.md
---

# Plan review — usage-counter-race

OI-45's `UsageCounterService.increment()` had carried a CRITICAL "cross-device race" rating
through two prior board re-verification passes, both of which re-confirmed the code's SHAPE
(`read(); await write(current+1)`, no lock) but never tested the RUNTIME behavior that shape
implies. This unit's investigation tested it directly and found the original claim does not
reproduce, for a documentable structural reason (Dart's single-threaded scheduler + Hive's
`Box.put()` synchronous in-memory write) — but the investigation itself, applied with equal rigor
at every subsequent step, surfaced one genuine bug the original finding never named. Tier is
`platform`: a new/modified Postgres migration (`114_raise_vision_analysis_cap_to_20.sql`) is
categorically `platform` per `docs/blast_radius.yaml`, dominating the `account`-tier client
touches.

## Rounds

| Round | Outcome |
|---|---|
| 1 — independent, context-blind (general-purpose agent), on the first-draft diff | **PASS.** 5 findings, all fixed + independently re-verified before acceptance (not trusted from the subagent's prose, per `feedback_audit_verifier_cannot_trust_own_subagent.md`). Most consequential: `checkAndResetCounters()` is a SECOND, previously-unlocked writer of the same 3 keys (fires on every app-resume via `day_rollover_service.dart`, not just cold boot) with 4 genuinely-sequential-awaiting writes, unlike `increment()`'s shape — a plausible reset-vs-increment race the doc's first draft missed entirely. Investigated with the same test-the-unlocked-code rigor as the original claim: did NOT reproduce (see round 1's own group in the test file). Also caught: a checked-in live-verification SQL asset (`test/sql/oi46_daily_cap_triggers_live_verify.sql`, inherited from Unit 4) hardcoded the superseded cap=15 values, which would have silently false-failed once migration 114 went live; 3 stale line-number citations. |
| 2 — independent, context-blind (general-purpose agent), on the round-1-hardened diff | **PASS → CONVERGED.** Verified every citation, the core synchronous-Hive-write claim (read Hive 2.2.3's actual `box_impl.dart`/`keystore.dart` source directly), migration 111-vs-114 byte diff, and all 12 new/updated tests — all confirmed clean. Found 3 P1s, all fixed: the diagnose-doc's `status: fixed` frontmatter contradicted its own tier-5 "not yet applied" evidence (corrected to the precedented `status: fixed_pending_live_apply` + `status: deferred` on that tier, matching diagnose `a2c8e6`'s own precedent for a held live-apply); the "checkAndResetCounters vs increment" test's `anyOf(0,1)` assertion was WEAKER than what's actually provable — reviewer traced (and this session independently re-verified via a 20-run empirical probe) that the outcome is fully DETERMINISTIC given the coded list order, not merely "not observed" — tightened to two explicit deterministic-outcome tests, one per order; a stale, unannotated copy of the superseded "STILL OPEN" claim survived elsewhere in `open_issues.md`'s 2026-07-26 audit table, un-pointed-to the correction — annotated. |
| B-pass — fresh context-blind (sonnet, `/code-review` skill, 5 lenses) | **PASS → accepted.** 2 findings (detail + triage in `docs/reviews/e0f4fb3263d0-review.md`), both fixed and — unusually — both taken further than the review itself demanded. Finding 1 (P2, but the load-bearing one): `DayRolloverObserver` has no re-entrancy guard, and a duplicate `resumed` lifecycle event dispatches a SECOND, independently-scheduled `checkAndResetCounters()` call that round 1/round 2's single-resetter analysis never covered — and THIS shape genuinely races: verified by reverting the fix and re-running a deterministic (not flaky) 3-operation `Future.wait` construction, 20/20 runs lost the increment. This is the one real, reproducible bug the entire investigation found. Closed with an outer double-checked-locking guard, verified 20/20 safe across 3 orderings post-fix. Finding 2 (P2): `MessageLimitNotifier.incrementToday()`'s lock had only a presence test, unlike its sibling's behavioral one — closed, and honestly found to also be a non-race once tested (consistent with everything else in this doc). |

## Why this is converged rather than merely green

Three consecutive rounds, three consecutive NEW findings, each genuine and non-overlapping:
round 1 found a second unlocked writer the original analysis never named; round 2 found the
round-1 fix's own regression test was true but provably weaker than what the code guarantees,
and a documentation-consistency gap; the B-pass found a THIRD writer-interaction shape (two
independent resetters, not one resetter vs. one incrementer) that neither prior round's
single-pair framing was positioned to catch — and this one, unlike every other race examined in
this unit, is real. That asymmetry is itself the signal the process worked as designed: two
rounds of "does this specific claimed race reproduce" correctly and repeatedly said no, without
that repeated "no" ever collapsing into a reflexive assumption that NOTHING here could race —
the moment a genuinely different shape (double-dispatch) was proposed, it was tested with the
identical rigor and, this time, confirmed. Every fix at every round was verified by reverting it
and re-running the actual test against the unlocked/unfixed code, not assumed correct from the
finding's plausibility — the single discipline this whole unit's diagnose-doc is built around.

## Ground truth

Verified directly against live code and files, not taken from any round's own prose: every
`increment()`/`checkAndResetCounters()`/`incrementToday()` line-number citation was grepped
against the actual current file after each round of edits (line numbers shifted twice as doc
comments grew, caught both times); Hive's `Box.put()` synchronous-in-memory-mutation claim was
independently confirmed by reading the actual pub-cache Hive 2.2.3 source
(`box_impl.dart`/`keystore.dart`), not just asserted from the diagnose-doc; the
"double-dispatched checkAndResetCounters" bug was reproduced via a live, run-in-this-session test
against the actual pre-fix code (not hypothesized) — 20/20 runs lost the increment, confirmed by
temporarily reverting the fix from a backup and restoring it after; migration 111 vs. 114 was
diffed by eye against both actual files; `DayRolloverObserver`'s lack of a re-entrancy guard and
its late `last_known_date` write were confirmed by reading `day_rollover_service.dart` directly,
not inferred from the B-pass reviewer's description.

## Residuals, stated

- The outer double-checked-locking guard closes the SPECIFIC double-dispatch shape reachable via
  `DayRolloverObserver`'s duplicate-`resumed` gap. It does not add a re-entrancy guard to
  `DayRolloverObserver` itself (the B-pass's "cheaper, alternative" fix) — that would also protect
  `refillIfNewWeek`/`reckonStreakDecayAndPersist`/the provider-invalidation block from the same
  double-fire class, but those are outside this unit's file list and a different, separately-scoped
  concern; not bundled in here.
- `UserRepository.updateProgress`, `BadgeService.checkAndUnlock`/`checkAll`, and
  `HealthSyncService.syncToHive` (OI-45 findings 2-4) are unchanged by this unit — Unit 3's scope.
  OI-45 stays OPEN.

## Post-review: live apply (2026-07-30)

Per CLAUDE.md §4.3, plan approval is not deploy approval — migration 114's live apply required
its own separate, explicit founder authorization, requested via `AskUserQuestion` after this
review converged. Approved; applied to `dedsavbjuwgarrhphgnl` at 2026-07-30T06:06:57+05:30.
Verified live via `pg_proc.prosrc` (threshold + message both read `20`) AND the full
live-Postgres behavioral test (`test/sql/oi46_daily_cap_triggers_live_verify.sql` Case 3, run in
a rollback transaction): 20 combined `scan_meal`/`cart_auditor` rows succeed, the 21st raises
P0001 `vision_analysis_daily_limit_reached (cap=20)`. `backups/applied_migrations.json` updated
in the same commit as the code (`applied_migrations_parity_test.dart` requires every committed
migration file to have a manifest entry, which structurally forces apply-before-commit for any
unit introducing a new migration — the same sequencing Unit 4 used). Full detail in the
diagnose-doc's "Live apply" section.
