---
bug_id: c4e8a1
date: 2026-09-16
batch: cron-ai-removal
status: fixed
blast_radius: platform
symptom: |
  `test/contracts/proactive_coach_promotion_test.dart` had 3 RED tests on
  this branch, introduced by `f4d771d2` (the very first fix commit in
  this batch, before either plan-review round even ran) and missed by
  both prior review rounds because neither round ran `flutter test` —
  this repo's own pre-commit hook deliberately does not run it either
  (ADR-0018, cost-split 2026-08-11), so nothing local would have caught
  it before a push. `flutter test test/contracts/proactive_coach_promotion_test.dart`
  reported `+15 -3`:
  (1) `RANK_LABELS uses canonical ladder codes` — the test's `src` reads
  ONLY `supabase/functions/proactive-coach-promotion/index.ts`, but
  `f4d771d2` extracted `RANK_LABELS` into a new sibling file,
  `congrats.ts`. The test was never repointed.
  (2) `Gemini model is gemini-2.5-flash` — asserts behavior that no
  longer exists anywhere: `f4d771d2` removed the Gemini call entirely.
  (3) `system prompt enforces "no emojis" + military lexicon sparingly`
  — asserts against a system-prompt string that was deleted along with
  the Gemini call.
  This is a direct instance of this repo's own documented common-pitfall
  class, "Extracting or moving code breaks source-grep contracts in
  files you never touched" (`CLAUDE.md` §4.9) — nobody ran
  `grep -rn "RANK_LABELS\|gemini-2.5-flash" test/` after the extraction,
  in the original commit or in either review round. Found by an
  independent context-blind plan-review Round 3 (CLAUDE.md §4.12)
  dispatched with instructions to run the actual test suite rather than
  only read source, which neither Round 1 nor Round 2 had been asked to
  do. Independently re-verified by running
  `flutter test test/contracts/proactive_coach_promotion_test.dart`
  myself before acting — reproduced the identical `+15 -3` failure.
concept: proactive_coach_promotion_congrats
sot_registry_entry: |
  No existing docs/sot_registry.yaml entry covers this concept (same
  reasoning as the sibling b7c9e2/a1f7d3/e5c9b2 diagnose-docs in this
  batch). Not adding one here either — this fix repoints/rewrites test
  assertions, it does not introduce a new writer/reader contract.
writers:
  - { file: supabase/functions/proactive-coach-promotion/congrats.ts, method_or_widget: "RANK_LABELS (module-private const) — the actual current location of the map the Flutter contract test pins", line: 8 }
readers:
  - { file: test/contracts/proactive_coach_promotion_test.dart, method_or_widget: "RANK_LABELS (congrats.ts) uses canonical ladder codes — now reads congratsSrc (congrats.ts) instead of src (index.ts)", line: 250 }
hive_key_prefix: "n/a"
hive_key_formula: "n/a — this fix touches only a test file's source-grep target, no Hive involvement."
sync_methods: []
restore_methods: []
cloud_table: "n/a"
cloud_columns: []
contract_test_path: test/contracts/proactive_coach_promotion_test.dart
ist_handling:
  - "Not applicable — no date keys or clock-derived values involved in this fix."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "Not applicable — this fix touches only test assertions against static Edge Function source text, no runtime user-scoped behavior."
forbidden_patterns_checked:
  - { pattern: "src.contains\\('gemini-2.5-flash'\\).*isTrue (the stale positive Gemini-model assertion this fix removes)", absent: true }
proposed_fix: |
  Three changes to test/contracts/proactive_coach_promotion_test.dart:
  (1) add a congratsSrc read of congrats.ts alongside the existing src
  read of index.ts, and repoint the RANK_LABELS test at congratsSrc;
  (2) replace the stale positive Gemini-model assertion with a negative
  assertion (no gemini-2.5-flash / generativelanguage.googleapis.com /
  GEMINI_API_KEY reference in either file), mirroring the Deno-side
  negative test already in proactive-coach-promotion/index_test.ts;
  (3) replace the stale system-prompt assertion with a direct scan of
  the actual shipped congrats.ts template copy for emoji characters
  (via \p{Extended_Pictographic}), since brand-voice compliance is now
  structurally guaranteed by fixed, founder-approved copy rather than an
  LLM system-prompt instruction.
  A 4th defect was found DURING this fix's own mutate-it-and-run-it pass
  (rule 21), not by the review: the original RANK_LABELS test's bare
  'LS:'/'PO:' substring checks are themselves vacuous — 'LS:' nests
  inside 'RANK_LABELS:' (the declaration's own type annotation) and
  'PO:' nests inside 'MCPO:', so either check could stay green even if
  that rank's entry were deleted. Fixed by matching the full
  `code: "Label",` declaration instead of a bare `code:` fragment.
regression_test_planned:
  - "test/contracts/proactive_coach_promotion_test.dart — all 3 originally-failing tests fixed in place (not replaced with new tests); 1 additional latent vacuity in the RANK_LABELS test fixed as part of the same mutate-it-and-run-it pass."
impact_analysis: |
  Scope: proactive-coach-promotion is platform-tier. This fix touches
  ONLY test assertions — no Edge Function runtime code changes. Its
  blast radius is entirely about restoring CI/pre-push accuracy: per
  CLAUDE.md rule 20, a red main is a P0 blocker, and this branch's
  blast-radius (platform, >= account) means pre-push and CI both run the
  full flutter test suite — this would have failed the FIRST push of
  this branch had it not been caught here first. No production behavior
  is affected by this commit.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "test/contracts/proactive_coach_promotion_test.dart is a Dart/Flutter test file; flutter test test/contracts/proactive_coach_promotion_test.dart now reports 18/18 passed (was 15/18)." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function source changed by this fix — only the test that pins its shape." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No contract changed; the test now correctly reflects an EXISTING contract (congrats.ts's RANK_LABELS, the absence of any Gemini call) that was already true before this fix, just unverified." }
---

## Summary

An independent context-blind plan-review Round 3 (CLAUDE.md §4.12),
dispatched to check the state after Round 2's fixes landed, was
instructed to actually RUN the test suite rather than only read source —
something neither Round 1 nor Round 2 had done for the Flutter side. It
found this branch had 3 failing Flutter contract tests since its very
first fix commit (`f4d771d2`), invisible to every gate that ran so far
because this repo's pre-commit hook deliberately excludes `flutter test`
(ADR-0018) and the branch has not been pushed (so pre-push/CI never ran
either). Independently reproduced the exact `+15 -3` failure before
acting on the finding.

## Bug-history lookup (CLAUDE.md §4.1.5)

Grepped `docs/diagnoses/INDEX.md` for "source-grep contract", "extraction
breaks test". This is a NAMED, already-documented recurring class in this
repo: `CLAUDE.md` §4.9's common-pitfalls table carries the row
"Extracting or moving code breaks source-grep contracts in files you
never touched" (dated 2026-08-30, from the `profile-phase-fixes` batch,
which broke 4 assertions across 3 files the same way). This is a direct
recurrence of that named class, not a new one — the guidance that row
already gives ("grep the test tree for what is moving... before landing
any extraction") was not followed when `f4d771d2` extracted
`RANK_LABELS`/`composeCongrats` out of `index.ts`.

## Root cause (writer + reader named before proposing, per CLAUDE.md §4.1)

**Writer (the code that moved):** `f4d771d2` moved `RANK_LABELS` and
`composeCongrats` from `proactive-coach-promotion/index.ts` into a new
sibling file, `congrats.ts` (per the batch's own plan, Task 8 — the
non-serving-sibling-file pattern used across all 9 functions), and
deleted the Gemini call + its system prompt entirely.

**Reader (the test left behind):** `test/contracts/proactive_coach_promotion_test.dart`
— written 2026-05-29 (audit EF-1) against the PRE-extraction `index.ts`
shape, never updated when `f4d771d2` moved the code it was pinning.
Three of its assertions became false statements about the current code:
one because the concept moved to a different file (repointable), two
because the concept it asserted (a live Gemini call + system prompt)
was deleted entirely (needed converting to negative assertions).

## Fix

1. Added a `congratsSrc` read of `congrats.ts` and repointed the
   `RANK_LABELS` test at it.
2. Replaced the stale positive Gemini-model assertion with a negative
   one, mirroring the Deno-side `index_test.ts`'s existing pattern.
3. Replaced the stale system-prompt assertion with a direct
   `\p{Extended_Pictographic}` emoji scan of the actual shipped
   `congrats.ts` copy — the concept (brand-voice, no emoji) survives,
   just enforced against the real artifact instead of a prompt that no
   longer exists.
4. **Found during this fix's own mutation pass, not by the review:** the
   original `RANK_LABELS` test's bare `'LS:'`/`'PO:'` substring checks
   were themselves vacuous (nesting inside `'RANK_LABELS:'` and
   `'MCPO:'` respectively) — strengthened to match the full
   `code: "Label",` declaration.

## Verification

`flutter test test/contracts/proactive_coach_promotion_test.dart` — 18/18
passed (was 15/18 — `+15 -3`). `deno check --node-modules-dir=none` and
`deno test --no-check --allow-all --node-modules-dir=none` on
`proactive-coach-promotion/` and `morning-alert/` (the latter for a
sibling stale-comment fix bundled in the same commit) — both clean, 17/17
and unaffected respectively.

**Mutated and run** (rule 21), three separate mutations, one per
rewritten test:
1. Renamed `LS:` to `LS_RENAMED:` in `congrats.ts` — with the ORIGINAL
   bare-substring test, this stayed GREEN (a false negative: `'LS:'` is
   a substring of `'RANK_LABELS:'`, so the check passed even with the
   rank code renamed away — this is exactly the latent vacuity fixed in
   step 4 above, found BY this mutation). After strengthening to the
   full `code: "Label",` match, re-ran the same mutation: reddened
   exactly 1 of 18 tests. Reverted; re-ran green.
2. Reintroduced a `"gemini-2.5-flash"` string literal into `congrats.ts`
   — reddened exactly 1 of 18 tests (the negative Gemini assertion).
   Reverted; re-ran green.
3. Inserted 🎉 into one of the three approved copy variants in
   `congrats.ts` — reddened exactly 1 of 18 tests (the emoji scan).
   Reverted; re-ran green (18/18 final).

## Related

Direct continuation of this batch's review chain: `9c3d7a` (Round 1) →
`a1f7d3` + `e5c9b2` (Round 2, the latter itself a defect in `9c3d7a`'s
own fix) → this fix (Round 3). Also bundles a sibling P3 fix in the same
commit: two stale present-tense "via Gemini" comments in
`proactive-coach-promotion/index.ts` (lines 5, 58, 68, 189) and one in
`morning-alert/index.ts` (~line 568) that Round 2's earlier 4-file
comment cleanup (`bd543f34`) did not cover, since that cleanup was
scoped to a different 4 files.
