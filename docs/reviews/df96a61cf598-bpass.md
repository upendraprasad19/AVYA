---
reviewed_at: 2026-09-08T22:40:00+05:30
staged_against: df96a61cf598
reviewed_at_hash: 0bd794b53b08
blast_radius: platform
reviewer: claude-sonnet-via-skill (2 context-blind agents, lens set split)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 5
false_alarms: 0
verdict: accepted
---

# Code Review (B-pass) — OI-166 Unit 1 — `df96a61cf598`

Two fresh Sonnet agents, no conversation context, lenses split 1-5 / 6-8. Both were told to find
bugs, not validate, and to give a verification command per finding.

⚠ **Two hashes, deliberately.** The agents read `0bd794b53b08`; `df96a61cf598` is the staged state
AFTER remediating all five findings. The gate that consumes this file keys on the commit, so the
filename carries the final hash — but the reviewers cannot be credited with reading it, and saying
so is cheaper than letting someone infer it.

**5 findings, 0 false alarms** (2 P0, 1 P1, 2 P2). Every one accepted and fixed in this batch per
§4.2 — none deferred, none downgraded.

---

## Finding 1 — P0 — oi_board_integrity — ACCEPTED, FIXED

- **file:** `docs/audit/open_issues.md`
- **claim:** the staged board minted `OI-167/168/169` for three findings while `main` had
  concurrently minted the SAME three numbers for entirely unrelated issues (debugging bug-class
  numbering / the §4.9 grep rule / `test/edge_functions` running nothing).
- **verification:** `git show main:docs/audit/open_issues.md | grep -n "^## OI-16[789]"` against
  the staged board — different titles, same numbers.
- **status:** fixed — renumbered to `OI-173/174/175`. `173-175` verified free across all four
  boards (open + closed, both sides) with a positive control on `OI-172`.
- **note:** found independently, by hand, minutes before this review returned; the reviewer
  confirmed it and correctly observed the fix was still unstaged. **The gate did not catch it.**
  `check_oi_numbering_unique.dart` reported `PASS (vacuous)` because this branch has zero commits,
  so `HEAD` is the merge commit it was cut from and the gate compared `HEAD^1` vs `HEAD^2` — two
  ancestors of the branch point — rather than the staged board against mainline. It even says
  *"this is a checked answer, not a skipped one"*, which is what makes it dangerous. Filed as its
  own OI; a green check is only as wide as its input set.

## Finding 2 — P0 — regression_test_completeness — ACCEPTED, FIXED

- **file:** `test/contracts/deload_eval_behavioral_test.dart`, `docs/diagnoses/…-b6d1f4.md`
- **claim:** the OI-171 regression test existed in the working tree but was NOT staged
  (`git diff --cached -- <path>` empty), and the diagnose-doc cited
  `contract_test_path: plan_week_for_date_behavioral_test.dart`, which contains zero references to
  `DeloadEvaluator` / `pushWorkoutPlanForSyncDomain` — so as staged, the fix shipped with exactly
  the zero coverage the test's own header says a B-pass had already caught.
- **verification:** `grep -c "liftWeekFour\|pushWorkoutPlanForSyncDomain\|DeloadEvaluator" test/contracts/plan_week_for_date_behavioral_test.dart` → `0`.
- **status:** fixed — test staged; `contract_test_path` repointed to `deload_eval_behavioral_test.dart`.
- **note:** a real artifact of holding staging while reviewers read the index, not a phantom. The
  citation half was a genuine error independent of staging.

## Finding 3 — P1 — blast_radius_mismatch — ACCEPTED, FIXED

- **file:** `docs/audit/oi166-regen-wave-alignment-plan.md:3`, `docs/audit/open_issues.md`, `lib/core/services/sync/sync_workout.dart`
- **claim:** three-way disagreement. The plan header declared tier `account` and §10 listed OI-170
  **out of scope**, while the staged diff implemented OI-170 inside `lib/core/services/sync/**`
  (pinned `platform`); the board still said `Status: OPEN` for OI-170/171 while their diagnose-docs
  said `status: fixed`; and no `feature_flag` existed despite `platform`'s `requires:` list
  (`docs/blast_radius.yaml:25`) and §4.6 both demanding one for a sync change.
- **verification:** `git diff --cached --name-only | dart run scripts/blast_radius_from_diff.dart -` → `platform`; `sed -n '25p' docs/blast_radius.yaml` → `requires: [..., feature_flag]`.
- **status:** fixed, by the reviewer's option (b) — the work is done, tested and mutation-proven, so
  the documents were corrected to match reality rather than the work split back out:
  - plan header rewritten to `platform`, **measured against the actual staged file list**. Its old
    parenthetical justified `account` by citing *"positive control `sync_workout.dart` →
    `platform`"* — a control that only holds while that file is out of the diff, so the sentence
    proving the tier became the sentence refuting it.
  - §10's OI-170 bullet struck through and kept, with both of its original reasons shown to be
    wrong: no corrupt-cloud fixture is needed (deriving makes the wire value unread), and it is not
    a different layer (the local half of the same off-by-one was already being fixed here).
  - OI-170/171 flipped to CLOSED with diagnose ids; board 90 → 88.
  - **kill-switch added** — `SyncFlags.deriveDayOfWeekOnRestore` /
    `configBox['disable_day_of_week_derive']`, opt-OUT polarity so the fix is live by default and
    the legacy path stays reachable (§4.6 step 2). Default-OFF was rejected on purpose: it would
    preserve the known-broken path, and a flag whose safe-looking default is the bug is not a
    safety mechanism. 5 new assertions; mutation-proven 2 legs (polarity inversion → 4 red, gate
    removed from the wiring → 1 red).
- ⚠ **Nothing enforces the `requires:` list.** `check_blast_radius_coverage.dart` never reads it
  (grep: 0 hits), so the entire gate loop ran green on a platform-tier sync change with no flag.
  It is review-read only, and review is the sole reason it was caught.

## Finding 4 — P2 — guard_without_its_mirror — ACCEPTED, FIXED

- **file:** `lib/core/services/deload_evaluator.dart:287`
- **claim:** the OI-171 fix was the only one of the three in this batch with no regression coverage
  of any kind. The reviewer deleted the line and ran four deload/sync suites: **all 60 tests stayed
  green** — a reddens-nothing mutation whose cause is simply that nothing executed the line. The
  diagnose-doc self-disclosed the gap ("the honest reason is fixture cost, not confidence"), which
  is a §4.2 deferral wearing a confession.
- **verification:** delete `deload_evaluator.dart:287`, run the four suites — 60/60 green before the fix.
- **status:** fixed — 3-assertion `OI-171` group added, pinning that the push EXISTS, is ORDERED
  AFTER the blob write (`indexOf(push) > indexOf(blobWrite)`), and stays UNAWAITED.
  Mutation-proven, both legs leaving the file compiling: **MOVING** the push above the blob write
  (the exact pre-fix defect) reddens exactly 1 — the ordering assertion — while presence and
  unawaited stay green, which is what proves ordering carries the weight rather than mere presence;
  **DELETING** it reddens 3.

## Finding 5 — P2 — guard_without_its_mirror — ACCEPTED, FIXED

- **file:** `scripts/schedule_row_builder_gate_lib.dart` — `constructsScheduleRow`
- **claim:** the new gate detected a schedule-row constructor only by literal map-key
  co-occurrence, so an ordinary Dart idiom — build the map, then assign the key by index — was
  invisible. The reviewer planted such a file and the gate reported `PASS` over 480 files. On the
  very gate whose stated purpose is to stop a fifth implementation being added.
- **verification:** plant the file, run `dart run scripts/check_single_schedule_row_builder.dart` → PASS.
- **status:** fixed — each key is now matched by literal-key **OR** index-assignment,
  independently, which also catches a file that MIXES the forms. Verified false-positive-free (no
  file under `lib/` writes both keys by index assignment). 6 new tests; the gate's mutation proof
  re-derived across all four legs rather than carried forward (legs 1 and 2 rose 2 → 4; the new
  index-assignment leg reddens 3).
- ⚠ **The residual is NAMED, not quietly closed.** A named-constant key still escapes — **verified
  by planting exactly that file and watching it PASS**, not assumed — and is now pinned as an
  executable test so the limit reddens if anyone ever closes it. A source grep is bounded by what
  its author could imagine writing; Unit 2's shared `buildScheduleRows` is the structural fix, and
  this gate is the §4.11 detector that must precede it. It stays WARN-only until then.

---

## Lenses returning clean (with the command run)

- **writer_reader_drift** — every write traced to its readers. `day_of_week` push/restore,
  `train_provider.dart:619/:816` readers unmodified and consistent with 0..6;
  `dayOfWeekFromDate` verified against Python's `date(2026,6,1).isoweekday()==1`;
  `template_service.dart` delegation confirmed behaviour-identical including the null-plan-start
  path. No code-level drift found — all three P0/P1s were process, not runtime.
- **function_exception_swallow** — `grep -n "functions.invoke"` over the staged diff → 0. The two
  new empty catch blocks are test teardown hygiene, not production logic.
- **secrets_in_tree** — credential-shaped regex sweep over the full staged diff → 0.
- **unawaited_no_error_sink** — the one new fire-and-forget call traced through
  `pushWorkoutPlanForSyncDomain` → `_ensureSessionOpen` → `_syncWorkoutPlan`; every level has its
  own try/catch + `ErrorTelemetry.recordNonFatal`. Nothing escapes as an unhandled rejection.
- **missing_input** — `pushWorkoutPlanForSyncDomain` confirmed pre-existing at
  `sync_workout.dart:2088`; new test-infra symbols (`GuardedBox.testBypassOwnership`,
  `HiveService.markInitializedForTests`, `configBoxName`) all confirmed present before use.
- **asserted_fixture_value** — the June 2026 weekday literals recomputed independently with
  Python (`2026-06-01` → Monday, `2026-06-07` → Sunday): match. All three mutation claims in the
  diagnose-docs and the gate ledger reproduced by the reviewer, with identical redden-counts.

## Founder triage notes

None required — all five accepted and fixed in-batch. Recorded for visibility: the batch grew a
kill-switch and rose from a documented `account` to a measured `platform` as a result of Finding 3,
and OI-170/171 moved from "filed, out of scope" to CLOSED-in-this-batch.
