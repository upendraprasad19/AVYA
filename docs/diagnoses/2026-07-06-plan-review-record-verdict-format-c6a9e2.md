---
bug_id: c6a9e2
date: 2026-07-06
batch: ci-gate-plan-review-format-fix
status: fixed
blast_radius: feature
symptom: >
  CI run 28711975359 (the coach-gemini-reliability merge, b2ea2e3) failed the
  "Plan-review record (>=account merge-to-main)" gate even though the ×2
  review + B-pass + Hermes genuinely happened and both reached a real
  ship/accept verdict.
concept: plan_review_record_verdict_format
sot_registry_entry: >
  Not a Hive/cloud writer-reader storage concept — this is CI-gate governance
  tooling. The contract: check_plan_review_record_exists.dart (P1.H
  anti-fabrication check) requires that when a plan-review record's
  frontmatter claims bpass: accepted / hermes: accepted, it names a
  bpass_review: / hermes_report: file that EXISTS and contains a literal
  line-anchored `verdict: accepted` — not a prose verdict like
  "## Verdict: SHIP" or "**Verdict: ACCEPTED**".
writers:
  - "{ file: docs/reviews/coach-gemini-reliability-bpass.md, method: n/a-doc, line: 1 } — authored during the coach-gemini-reliability batch with a prose verdict ('## Verdict: **SHIP**') instead of a machine-checked line."
  - "{ file: docs/reviews/coach-gemini-reliability-hermes.md, method: n/a-doc, line: 1 } — same gap ('**Verdict: ACCEPTED**' prose, no bare `verdict: accepted` line)."
  - "{ file: docs/plan-reviews/coach-gemini-reliability.md, method: n/a-doc, line: 8 } — set bpass: accepted / hermes: accepted with no bpass_review:/hermes_report: pointer fields."
readers:
  - "{ file: scripts/check_plan_review_record_exists.dart, method: main, line: 201 } — bpass: accepted branch requires bpass_review: naming a file with a line-anchored `verdict: accepted`."
  - "{ file: scripts/check_plan_review_record_exists.dart, method: main, line: 219 } — hermes: accepted branch requires hermes_report: naming a file with a line-anchored `verdict: accepted`."
hive_key_prefix: n/a
hive_key_formula: n/a
sync_methods: n/a
restore_methods: n/a
cloud_table: n/a
cloud_columns: n/a
contract_test_path: >
  n/a — enforced by the existing CI gate itself
  (scripts/check_plan_review_record_exists.dart), not a new test. The gate
  cannot re-fire against THIS commit (it only runs on a merge-to-main commit,
  and this is a plain commit) — the proof is a direct grep confirming both
  review docs now contain the exact line-anchored pattern the gate's regex
  requires, plus the gate re-validating fresh at any FUTURE merge-to-main.
ist_handling: n/a
provider_invalidations: n/a
telemetry_op_types: n/a
cross_account_guard: n/a
forbidden_patterns_checked: >
  The frontmatter added to both review docs is a faithful, non-fabricated
  translation of their own PRE-EXISTING verdicts (bpass "## Verdict: **SHIP**"
  → `verdict: accepted`; hermes "**Verdict: ACCEPTED**" → `verdict: accepted`)
  — no content was invented, only reformatted into the gate's required shape.
  staged_against values (ff82b5c / dd51ae7) are copied verbatim from each
  doc's own pre-existing "HEAD"/"Commit under review" text, not guessed.
proposed_fix: >
  Add minimal YAML frontmatter (staged_against + verdict: accepted) to both
  docs/reviews/coach-gemini-reliability-{bpass,hermes}.md, and add
  bpass_review:/hermes_report: pointer fields to
  docs/plan-reviews/coach-gemini-reliability.md's frontmatter, so the gate's
  anti-fabrication check can confirm what already genuinely happened.
regression_test_planned: >
  None new — the gate script itself is the enforcement and will re-validate
  this exact record shape at any FUTURE merge-to-main reusing this filename
  pattern. Manually verified via grep that both review docs now contain the
  line-anchored `verdict: accepted` the gate's regex requires.
touched_layers_checked:
  - "{ layer: client_code, status: fixed_in_this_batch, evidence: added staged_against + verdict:accepted frontmatter to docs/reviews/coach-gemini-reliability-bpass.md and -hermes.md, and bpass_review:/hermes_report: pointer fields to docs/plan-reviews/coach-gemini-reliability.md; grep-verified both files now contain the line-anchored verdict: accepted pattern the gate requires. }"
  - "{ layer: client_to_server_contract, status: not_applicable, evidence: no runtime behavior changed — this only corrects a documentation/governance artifact; FC1-FC7 code is untouched. }"
impact_analysis: >
  Zero runtime/behavioral impact — FC1-FC7 (the coach-gemini-reliability
  fixes) are unchanged by this commit. This fix only corrects the paper trail
  so it accurately reflects that the x2 review + B-pass + Hermes already
  happened and reached real ship/accept verdicts, closing the gap the CI gate
  correctly caught. Note: the ORIGINAL failed CI run (28711975359, commit
  b2ea2e3) will remain marked failed in GitHub's history — Actions does not
  retroactively re-evaluate a historical commit's status when a LATER commit
  is pushed; the gate is a point-in-time check at the merge commit, not a
  continuously re-evaluated invariant. Going forward, any NEW merge-to-main
  is checked fresh against its own diff.
closes-diagnose: c6a9e2
---

# c6a9e2 — Plan-review record missing machine-checked verdict format

## What happened
The coach-gemini-reliability merge (`b2ea2e3`) failed CI's "Plan-review record"
gate. The review process behind it was real — both a B-pass and a Hermes pass
ran, read every changed file, and reached genuine ship/accept verdicts — but
the two review documents recorded their verdicts as prose headers ("## Verdict:
**SHIP**", "**Verdict: ACCEPTED**") rather than the literal, line-anchored
`verdict: accepted` the gate's anti-fabrication check (P1.H) requires, and the
plan-review record itself never named the `bpass_review:`/`hermes_report:`
pointer files at all.

## Root cause
`scripts/check_plan_review_record_exists.dart` was hardened (P1.H) to refuse a
bare `bpass: accepted` / `hermes: accepted` claim unless it points at a real
file containing a real, unambiguous verdict line — precisely so a claim can't
be fabricated. Whoever authored these two review docs used the code-review /
hermes-pass skills' natural prose convention instead of the exact machine-
checked shape the (newer) gate expects, and the plan-review record was never
updated with the pointer fields once the gate existed.

## Fix
Added minimal, non-fabricated frontmatter to both review docs (translating
their own already-stated verdicts into the literal form) and the two pointer
fields to the plan-review record. No review content was changed or invented.

## Recurrence
None found — grepped `docs/diagnoses/INDEX.md` and `feedback_*.md` for
"plan-review record" / "bpass_review" / "verdict: accepted"; this is the first
instance of a review doc using prose instead of the machine-checked line.
Worth watching: any future B-pass/Hermes-pass invocation should end with a
literal `verdict: accepted|rejected` line, not just a prose header — the
code-review skill's own documented output format already specifies this
(`verdict: pending  # → accepted | rejected`), it just wasn't followed here.
