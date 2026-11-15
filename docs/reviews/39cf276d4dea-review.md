---
reviewed_at: 2026-10-11
staged_against: df2b1282 (reviewed, before the fixes), 39cf276d4dea (the tree with every fix below applied; the file name)
blast_radius: platform
reviewer: claude-sonnet-via-skill (1 fresh context-blind reader, read-only, exhaustive command list)
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value, L21, L23, L24, L25, L27, L34, L37, L41, L50, L53]
findings_count: 8
verdict: accepted
---

# Code Review - `clean-orphan-media/**` becomes catastrophic tier (registry rule + tests)

Diff reviewed: the staged change on branch `blast-radius-clean-orphan-media` (8 files): one rule in `docs/blast_radius.yaml`
(`supabase/functions/clean-orphan-media/**`, catastrophic, above the `supabase/functions/**` catch-all), the new contract
test, two end-to-end cases in `test/scripts/plan_review_record_gate_e2e_test.dart`, a re-pointed cite in
`safe_merge_test.dart`, a comment-only edit in `plate_flags.dart`, the registry-range edit in `docs/sot_registry.yaml`,
the plan, and ledger row B6. One fresh reader, read-only, after two plan-review rounds. Headline: **no P0, P1 or P2.**
The rule, its order, all four registry readers, the new tests and the line cites held up. Eight P3s, every one verified
against the tree by the main thread before it was accepted, and every one fixed in this batch.

## Checked and clean (what the reader ran, and why the lens came back clean)

- **writer_reader_drift, moved prose.** Every line number re-derived from the staged and HEAD blobs (base catastrophic
  block :41-51, the new rule :54, the catch-all :495 -> :506, the registry's own rule :308 -> :319, migrations :73,
  `line_range: 39-506`). Nothing else reads the registry by position or count; only four production engines read it, and
  their `globToRegExp` / `parseRules` are code-identical. The only prose removed is the old B6 `reason:`.
- **blast_radius_mismatch.** The batch is platform; `index.ts` now classifies catastrophic; `_shared/paged_fetch.ts`,
  `_shared/cron_telemetry.ts` and `_shared/subscription.ts` stay platform as the comment says; migration 071's RPC has no
  SECURITY DEFINER so the comment's escape-hatch clause is accurate.
- **guard_without_its_mirror.** The reader defeated the tests by reasoning about mutants: deleting the rule, moving it
  below the catch-all, widening it, changing the tier or its spelling, a classifier that takes the last path's tier, and a
  keystone that cannot parse `catastrophic` or skips the hermes check all redden. The no-hermes case asserts the exact
  message only emitted at `check_plan_review_record_exists.dart:837`, so it does not pass for the wrong reason.
- **secrets_in_tree, function_exception_swallow, unawaited_no_error_sink, missing_input.** Clean or not applicable.
- **Commands the reader ran:** the contract test 11/11, the keystone e2e 16/16, `safe_merge_test` 15/15,
  `exercise_plate_widgets_test` 7/7, `flutter analyze lib/` (59 infos, no warning or error).

## Findings and triage (all verified by the main thread, all fixed)

1. **P3 asserted_fixture_value - the test header said the defect "was live in v14 until 2026-10-11".** True today (the
   deploy was done and verified), but the staged tree cannot show it and the OI-321 ledger row D1 on `main` still says
   "live v14 now". FIXED: the header says "live in v14 when OI-321 was fixed".
2. **P3 missing_input - the plan cites OI-334 and deploy-skill section 6.13 as existing.** Verified: `git grep OI-334` on
   this tree finds only the plan; the skill ends at 6.12. Both live on the unmerged branch `oi321-deploy-close`. FIXED:
   the plan says so in both places.
3. **P3 blast_radius_mismatch - platform's `requires: feature_flag` was never addressed.** Verified: no script reads the
   list (`scripts/safe_push.sh:132-135`, `scripts/reconcile_ci.dart:41`); the OI-282 registry batch recorded the same
   waiver. FIXED: a waiver paragraph in plan section 2.
4. **P3 guard_without_its_mirror - the pins on the delete path sit outside the rule's reach.** Verified with the real
   classifier: `clean_orphan_media_pro_recheck_test.dart` is `feature`, and so are the pins of `delete-account`,
   `razorpay-webhook` and `verify-payment`. A decision, not a defect, and consistent with the neighbours. FIXED: recorded as
   a scoping decision in plan section 2 and in ledger row B6, with the exact-path alternative named for the founder.
5. **P3 guard_without_its_mirror - only `.ts` probes.** A rule for a file KIND inserted above this one would stay green.
   FIXED: a twelfth test probes `README.md`, `CLAUDE.md`, `fixtures/...`, a dotfile and `deno.json`. MUTATED: four rules
   inserted above the catastrophic one (`*.md`, `fixtures/**`, `.*`, `*.json`, all tier feature) each redden exactly that
   one test, and each leaves the other eleven green, so the test is the only protection for the file-kind class.
6. **P3 writer_reader_drift - `safe_merge_test.dart` re-pointed a cite to `:73`, which rots on the next insertion.**
   FIXED: it cites the rule by its glob, as `plate_flags.dart` does.
7. **P3 asserted_fixture_value - "27 call sites in 17 files" in ledger rows G1-G6.** Re-run: 27 in 16 files without tests,
   28 in 17 with `_shared/subscription_test.ts`. FIXED: the plan and the six rows say "27 non-test ... in 16 files".
8. **P3 nit - a 330-character line, a hyphen where the source has an em dash, a cite that covered only the existence
   check, a hash-exclusion list missing `SKILL.md`.** All four verified (`sed -n 37p CRON_REGISTRY.md`, `sed -n 244,264p`,
   `sed -n 150,165p` of `check_code_review_pass_exists.dart`). FIXED.

## Could not verify (reader) and how it was closed

- The mutation results (11 mutants plus the two keystone mutants) were claimed in the plan but the record is not yet
  written. The main thread ran them (11 + 2 red) and ran the four new file-kind mutants above; all are recorded in
  `docs/plan-reviews/blast-radius-clean-orphan-media.md` (a separate, later commit: it is part of the diff hash).
- The full pre-commit gate loop was not run by the reader (forbidden); the main thread ran it on the final tree: exit 0.
