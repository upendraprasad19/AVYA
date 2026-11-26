---
reviewed_at: 2026-07-19T00:00:00+05:30
staged_against: 9a36dcb1
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, gains_only_tier, stub_normalization, e261, universal_pool, migration_regen, test_rewrite, doc_consistency]
findings_count: 3
verdict: accepted
---

# Code Review (B-pass) — Batch 13-A (exercise-lib-13a, dd51a40a..9a36dcb1)

Fresh context-blind Sonnet reviewer over the committed diff (18 files, +3670/-3575). The reviewer
inspected the diff directly, validated the 259-row JSON corpus with `node` scripts, and RAN the 4
new/modified test files (`flutter test`, all pass) + `flutter analyze` on every touched `.dart` (clean).

## Standard lenses — all CLEAN
- **writer_reader_drift:** `grep muscle_primary|is_compound|sets_default lib/ supabase/functions/ test/` → 0
  reader hits of the dropped stub keys (the `rest_seconds`/`is_custom` hits belong to the DOWNSTREAM
  planned-exercise + user-custom-exercise schemas, a different concept — confirmed by reading write sites).
  All 259 rows share ONE 38-key signature.
- **function_exception_swallow:** 0 `.functions.invoke(` in the diff. N/A.
- **blast_radius_mismatch:** migration 074 header carries all 4 tags; ON CONFLICT DO UPDATE includes the
  coach-read columns + excludes created_at/instructions; ledger hash matches the file byte-for-byte;
  `diagnose: ada3fb` preserved. §4.6 kill-switch exception well-founded (gains-only = ADD-only, 0 removed
  lines verified; byte-identical for non-injured users).
- **secrets_in_tree:** 0 credential-shaped literals.
- **unawaited_no_error_sink:** 0 `unawaited(` in the diff. N/A.

## Batch-specific — CLEAN
- **A gains-only:** 90 hunks, 0 removed lines, all added tokens canonical, 0 empty/duplicate/non-canonical tier.
- **B stubs:** all 9 injury tags sensible (E252→knee, E256→shoulder+elbow, E258→ankle); all 13 stub-only keys gone; muscle relabels follow per-field corpus convention.
- **C E261:** 38 keys; injury:[] consistent with the pulling-plane rear-delt group (Face Pull/Band Pull Apart/Reverse Fly all []).
- **D universalPool:** 3 replacement names each resolve to 1 real bodyweight row of the correct pattern; cascade_tracer copy byte-identical; `universal_pool_mirror_test` 1/1.
- **E migration:** header tags + 259 tuples + ada3fb preserved.
- **F test rewrite:** `injury_filter_behavioral_test` 12/12; retired assertions correctly moved to the pre-existing deterministic `injury_safe_omission_production_test`.

## Findings — 3 × P2 (documentation/traceability), ALL FIXED IN-BATCH (§4.2)

## Finding 1 — P2 — doc_consistency
- **file:line:** docs/plan-reviews/exercise-lib-13a.md:2
- **claim:** `plan:` cited a repo path `.claude/plans/ok-lock-1a-and-atomic-balloon.md` that does not exist in the repo (the plan artifact lives in the session/user plans dir, not committed).
- **verification:** `ls .claude/plans/ok-lock-1a-and-atomic-balloon.md` → No such file.
- **suggested-fix:** point `plan:` at the record itself (the convention, cf. workout-plateau-12b).
- **status:** fixed — `plan: docs/plan-reviews/exercise-lib-13a.md`.

## Finding 2 — P2 — doc_consistency
- **file:line:** lib/shared/repositories/plan_engine/CLAUDE.md:297
- **claim:** the "Pike Push Up assigned to rear delt slot" pitfall row said "Fix in split_resolver.dart, NOT by editing the universal pool" — contradicting this batch, which fixed the WRONG-PATTERN entry by editing the pool.
- **verification:** `grep -n "Pike Push Up assigned to rear delt" lib/shared/repositories/plan_engine/CLAUDE.md`.
- **suggested-fix:** reconcile — pool is right for a wrong-PATTERN entry; split_resolver is right for over-ALLOCATION frequency.
- **status:** fixed — row rewritten to distinguish the two causes + cite c3f9b2.

## Finding 3 — P2 — doc_consistency
- **file:line:** docs/diagnoses/2026-07-19-universal-pool-dupes-c3f9b2.md:21 (+ docs/sot_registry.yaml)
- **claim:** cited `cascade_tracer.dart, line: 52` for `universalPoolV4Mirror`; actual declaration is line 53 (a comment expansion shifted it).
- **verification:** `grep -n "universalPoolV4Mirror =" test/plan_generator/v4_diagnostic/cascade_tracer.dart` → 53.
- **suggested-fix:** `:52` → `:53` in the diagnose-doc + SoT entry.
- **status:** fixed — both corrected to :53.

## Founder triage notes
No P0/P1. Data-quality fixes verified correct + internally consistent (scorecard deltas cross-checked
between baseline_plans.md + baseline_scorecard.json byte-consistent; all 4 contract tests executed, pass).
The 3 P2 doc-traceability gaps are all fixed in this same batch (B-pass-fixes commit). verdict: accepted.
