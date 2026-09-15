---
branch: oi83-restore-monotonic
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/108ba4f867b7-review.md
hermes_report: not_required
---

# Plan review — `oi83-restore-monotonic`

Unit A of the post-batch residuals. **Closes OI-83**, opens **OI-85**. Diagnose `d1f6b3`.

## Tier

Measured on the actual staged set, after the LAST edit:

```
git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -
→ platform
```

**The plan predicted `account` and was wrong.** Per-file attribution:
`lib/core/services/sync/sync_profile.dart` is the platform-tier path; every other touched file
(`auth_session_bootstrapper`, `plan_integrity_reconciler`, `user_repository`,
`pro_phase_advance`, `graduation_screen`, `error_telemetry`) is `account`. Two consequences
follow from the tier rather than from taste, and both changed the unit: `bpass: accepted` is
REQUIRED not advisory, and `docs/blast_radius.yaml:25` requires a `feature_flag` — which is why
a kill-switch ships despite the first draft arguing none was needed. Hermes is NOT required
(catastrophic only). The trailing `-` is load-bearing.

## Ground truth verified

- All **seven** `put('progress', …)` writers read directly, unpiped. Exactly **two** are
  demotion vectors; the other five read-modify-write a narrow freeze/version key set and
  preserve `current_phase`. OI-83 had flagged two of those five as "wants the same audit" — this
  is that audit, and its result is now in the SoT registry so it is not re-derived.
- The comment at `sync_profile.dart:592-609` justified the wholesale merge with "a fresh restore
  read is always at least as new as whatever's local." True of the server-owned
  `streak_progress_version` it was written about; **false** of a client-advanced field. Corrected
  in the same commit — leaving it would re-justify the bug for the next reader.
- `withPhaseAdvanceLock` read directly and confirmed a **TRY-lock** (`return ifBusy`, no queue) —
  this refuted the approved plan's own second half before a line of it shipped.
- `_syncWorkoutPlan` confirmed to run only on the DAILY full sync and to snapshot every
  `schedule_*` key box-wide — the two facts that refuted the round-1 repair.
- Founder decision (local-max-wins) traced to its consequences: the only writes that lower the
  phase are onboarding's fresh-account first write and the dev-panel `resetJourney`
  (`simulation_service.dart:108`, debug-only), so no production backward move is blocked.

## Round 1 — 7 findings

1 P1, 4 P2, 2 P3; all verified against the cited file:line before being acted on, all real.

The P1: **`longest_gap_days` was a guard pointed backwards.** OI-83 listed it as monotonic. It is
inverted — higher is worse, it gates a rank (`rank_service.dart:506`, and a failed rung blocks
every rung above), no client writer populates it, and migration 115 already GREATESTs it
server-side. Local-max-wins there could only ever REFUSE a server correction and pin the ladder
shut. Removed; the set is 3.

The rest: no kill-switch at platform tier (a registry requirement, not a judgement call); the
success telemetry fired unconditionally while `reconcile` returned `void` and swallowed
everything across six early-exits; the new events were absent from `highPriorityOpTypes`; the
helper block had been inserted between `saveProgress`'s doc comment and `saveProgress`.

**Then a round-1 fix introduced a P0**, caught by this unit's own reinstall test: treating a
non-numeric value as malformed also caught `null`, so a fresh reinstall would have restored with
no `current_phase` at all. Absent is not malformed.

## Round 2 — 5 findings, ALL regressions from round-1 fixes

Fourth batch running with the §4.12.1 signature. The top finding was a **data-loss P0 in the
repair mechanism round 1 asked for**: cloud `plan_json` is pushed only by the daily full sync, so
the orphan sweep would re-anchor to a snapshot describing the PREVIOUS phase window and delete
the winner's freshly-generated rows. Its sibling P1: `preferSnapshot` applied to every snapshot
key box-wide would revert an un-synced local exercise swap on any planned day.

**That is three mechanisms for one sub-problem, each wrong in a new way** — restore-takes-the-lock
(drops the restore), force-past-`needsHeal` (inert), `preferSnapshot`+sweep (data loss). §4.12.1
says ship the smallest converged piece rather than review the large thing a fourth time, so the
repair was **backed out entirely** and replaced with a `phase_advance_declined_rows_stale` event
that makes the condition measurable for the first time. The repair is **OI-85**, carrying all
three refutations so a fourth attempt starts from the evidence.

Also from round 2: branch-ordering (absent-local × garbage-cloud wrote garbage through silently),
and a prose sweep where "4 fields" survived in eight places after the set became 3.

## B-pass — accepted

5 findings, all fixed. The material one is another **writer/reader drift the guard exposed rather
than caused**: the login restore's plan regeneration read the raw cloud `current_phase` instead of
the post-merge value, so a refused demotion would still reach the generated plan. Record:
`docs/reviews/108ba4f867b7-review.md`.

## Convergence

| | P0 | P1 | P2 | P3 | new defects in the ORIGINAL merge |
|---|---|---|---|---|---|
| Round 1 | 0 | 1 | 4 | 2 | 7 |
| Round 2 | 1 | 1 | 2 | 1 | **0** — all five are round-1 regressions |
| B-pass | 0 | 2 | 2 | 1 | 1 (a pre-existing reader the guard exposed) |

**Verdict: converged** — for the merge. Round 2 found nothing new in it; every round-2 finding
was in a round-1 correction, and the one that mattered lived in the *repair*, which is now out of
scope and on the board. The merge itself has been through three passes and has accumulated only
count/citation corrections since round 1.

This IS the §4.12.1 "split it" signal, and it was acted on rather than argued with: the
converged piece (the demotion fix) ships; the piece that resisted three designs (the repair) is
filed with evidence. Splitting here is not a deferral — OI-85 is a terminal board record, the
condition is now instrumented, and what ships is strictly better than `main`, which has neither
the guard nor any visibility.

## Feature flag

§4.6 kill-switch `disable_progress_restore_monotonic_merge`, default **OFF meaning the guard is
ACTIVE**. NOT ship-dark (§4.12.4 requires default-OFF-meaning-inert), so the full ×2 + B-pass
applies and no `docs/ship_dark_pending_review.yaml` entry is owed. The argument for it is
specific: `phaseAdvanceTarget`'s doc reasons that a switch which only re-enables a defect is not
a safety valve, and that holds for a proven total order over one field — but this is a
hand-written per-field judgement list, and round 1 proved the list can be wrong.

## Residual requiring a separate authorization

`supabase/functions/log-client-error/index.ts` gains three op-types in its
`HIGH_PRIORITY_OP_TYPES` twin list. **Code only — NOT deployed.** The client half is live on
merge; until that function is deployed the server still classifies those events as LOW priority.
An Edge Function deploy needs its own explicit founder go per §4.3, so it is recorded here and in
the diagnose-doc's tier-6 evidence rather than assumed.

## Process findings

- **Verify the primitive before designing against it.** The approved plan's second half died on
  one `Read` of `withPhaseAdvanceLock`. Two of the three refuted mechanisms would have been
  avoided by reading `mergeScheduleEntry` and `_syncWorkoutPlan` first — the same "name the
  writer AND the reader before proposing" rule §4.1 already states, applied to a primitive rather
  than a field.
- **A bypass on the outer gate is not a bypass on the inner one.** `force:` cleared `needsHeal`
  and then hit an identical per-row predicate. Sibling of Unit 6's "a green check is only as wide
  as its input set".
- **Count tests by RUNNING them.** Three different methods disagree — `grep -c 'test('` counts
  declarations, the runner's `+N` includes `tearDownAll`, and a `for` loop over 2 writers turns 3
  declarations into 6 executions. Three drafts of the diagnose-doc published 22, 26 and 29 before
  31 (23 + 8) was verified by execution.
- **Reviewers were told, in the brief, not to write to the tree**, with the Unit 7 incident
  quoted. All three complied. The whole diff was staged before each reviewer ran.
