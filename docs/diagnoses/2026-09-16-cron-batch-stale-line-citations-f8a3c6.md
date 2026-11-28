---
bug_id: f8a3c6
date: 2026-09-16
batch: cron-ai-removal
status: fixed
blast_radius: platform
symptom: |
  Two more RED/stale-citation defects surfaced by proactively running the
  FULL set of Flutter contract tests referencing any of this batch's 9
  touched functions, after Round 3's review found a similar defect in
  `proactive_coach_promotion_test.dart` (diagnose `c4e8a1`) — the same
  extraction-breaks-source-grep-contract class, recurring twice more in
  the same batch:
  (1) `test/contracts/streak_guardian_eligibility_test.dart`'s "root
  cause 2 — the unbounded PR branch is gone from every surface" group
  asserted `src.contains('milestone!')` and
  `src.contains('Almost at your goal weight!')` against
  `streak-guardian/index.ts` only — but this batch's own Task 2 (commit
  `6200dbb5`) extracted the entire streakDays/weight if-chain those
  strings live in out of index.ts into a sibling file, `message.ts`
  (`pickStreakMessage`). `flutter test
  test/contracts/streak_guardian_eligibility_test.dart` reported
  `+10 -1`.
  (2) `docs/snapshot_contract.yaml`'s `future_prediction` and
  `morning_alert` reader citations pointed at stale line numbers
  (288 and 620 respectively) — this batch's own edits (removing the
  Gemini prediction path from future-prediction, removing the AI branch
  from morning-alert) shifted the actual self-read lines to 251 and 413.
  `flutter test test/contracts/snapshot_contract_consolidated_test.dart`
  reported `+173 -2` (`FAIL reader-read` for both keys).
  Neither was caught by either prior review round, because — like
  `c4e8a1` — nothing in this batch's own workflow (Deno tests, pre-commit
  gates, both review rounds before Round 3) ran `flutter test` until
  Round 3 was specifically instructed to.
concept: streak_guardian_message_composition, future_prediction_streak_forecast, morning_alert_ai_removal
sot_registry_entry: |
  No new entries — both fixes repoint/rewrite existing test/contract
  citations at code that already exists; neither introduces a new
  writer/reader contract.
writers:
  - { file: supabase/functions/streak-guardian/message.ts, method_or_widget: "pickStreakMessage — the milestone/goal-weight if-chain the streak_guardian_eligibility_test.dart 'root cause 2' group pins", line: 22 }
  - { file: supabase/functions/future-prediction/index.ts, method_or_widget: "the 30-day re-prediction self-read (recentPrediction.snapshot_json.future_prediction) — actual current location of the future_prediction reader citation", line: 251 }
  - { file: supabase/functions/morning-alert/index.ts, method_or_widget: "the per-user alert-cache self-read (snap.snapshot_json?.morning_alert) — actual current location of the morning_alert reader citation", line: 413 }
readers:
  - { file: test/contracts/streak_guardian_eligibility_test.dart, method_or_widget: "root cause 2 group — now reads messageSrc (message.ts) for the milestone/goal-weight assertions instead of src (index.ts)", line: 163 }
  - { file: docs/snapshot_contract.yaml, method_or_widget: "future_prediction key's readers[0].line, corrected 288 -> 251", line: 638 }
  - { file: docs/snapshot_contract.yaml, method_or_widget: "morning_alert key's readers[0].line, corrected 620 -> 413", line: 655 }
hive_key_prefix: "n/a"
hive_key_formula: "n/a — both fixes touch only test/contract-manifest source-grep targets, no Hive involvement."
sync_methods: []
restore_methods: []
cloud_table: "n/a"
cloud_columns: []
contract_test_path: test/contracts/streak_guardian_eligibility_test.dart, test/contracts/snapshot_contract_consolidated_test.dart
ist_handling:
  - "Not applicable — no date keys or clock-derived values involved in either fix."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "Not applicable — both fixes touch only test assertions / a documentation manifest against static Edge Function source text."
forbidden_patterns_checked:
  - { pattern: "file: supabase/functions/future-prediction/index.ts, line: 288 (the stale future_prediction citation this fix removes)", absent: true }
  - { pattern: "file: supabase/functions/morning-alert/index.ts, line: 620 (the stale morning_alert citation this fix removes)", absent: true }
proposed_fix: |
  (1) Added a messageSrc read of streak-guardian/message.ts in
  streak_guardian_eligibility_test.dart's setUpAll, and repointed the
  "surviving arms of the else-if chain" + "braces and parens balance"
  assertions at it (the latter checks BOTH files now, since index.ts
  is still its own compilation unit). Strengthened 3 other assertions in
  the same group (recentPR / "You hit a PR recently" / recent_pr_exercise
  absence checks) to also scan messageSrc, since the concept now spans
  two files.
  (2) Corrected docs/snapshot_contract.yaml's future_prediction
  (288->251) and morning_alert (620->413) reader line citations to their
  current, post-batch locations, with an explanatory note appended
  (matching the existing note style on the morning_alert entry, which
  already carried one prior line-drift correction from 2026-07-26).
regression_test_planned:
  - "test/contracts/streak_guardian_eligibility_test.dart — all previously-failing assertions fixed in place, repointed at message.ts."
  - "test/contracts/snapshot_contract_consolidated_test.dart — passes via docs/snapshot_contract.yaml's corrected citations (the test itself was not modified; it validates the manifest, which was the stale artifact)."
impact_analysis: |
  Scope: streak-guardian and (indirectly, via the shared snapshot
  contract manifest) future-prediction and morning-alert are all
  platform-tier. Both fixes touch ONLY test assertions and a
  documentation manifest — no Edge Function runtime code changed. Same
  impact class as c4e8a1: this restores pre-push/CI accuracy that would
  otherwise have failed the FIRST push of this branch (blast-radius
  platform triggers the full flutter test suite at both pre-push and
  CI), not a production behavior change.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter test test/contracts/streak_guardian_eligibility_test.dart test/contracts/snapshot_contract_consolidated_test.dart test/contracts/proactive_coach_promotion_test.dart now reports 45/45 passed (previously 10/11, 173/175, and 15/18 respectively across the three files before c4e8a1 + this fix)." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function source changed by either fix — only tests/manifests that pin an already-correct current shape." }
  - { tier: 12, name: "Client -> server contract", status: not_applicable, evidence: "No contract changed; both fixes make an existing, already-true contract (message.ts's milestone copy; the two self-read citations) correctly verified again." }
---

## Summary

After Round 3's review found `proactive_coach_promotion_test.dart` had 3
stale, RED assertions from an earlier extraction in this same batch
(`c4e8a1`), the same class was proactively swept across every other
Flutter contract test referencing any of this batch's 9 touched
functions — rather than waiting for a Round 4 to find these one at a
time. Two more instances turned up, both fixed in the same pass:
`streak_guardian_eligibility_test.dart` (its own extraction, this
batch's Task 2) and `docs/snapshot_contract.yaml` (line-drift from
Gemini-removal edits in `future-prediction` and `morning-alert`).

## Bug-history lookup (CLAUDE.md §4.1.5)

Same class as `c4e8a1`, itself citing `CLAUDE.md` §4.9's named
common-pitfalls row "Extracting or moving code breaks source-grep
contracts in files you never touched" — this is the class's 2nd and 3rd
recurrence within this single batch (4th and 5th counting the
`morning_alert` citation's own PRIOR drift correction from 2026-07-26,
which is a different batch but the identical mechanism). The
`snapshot_contract.yaml` case is a close cousin: not an EXTRACTION but a
LINE-COUNT SHIFT from code removed above the cited line — the same
underlying lesson (a file:line citation is only as durable as the lines
around it) that row's own guidance already covers.

## Root cause (writer + reader named before proposing, per CLAUDE.md §4.1)

**Writer 1:** `streak-guardian/message.ts`'s `pickStreakMessage` (this
batch's own Task 2, commit `6200dbb5`) — the milestone/goal-weight
if-chain moved here from `index.ts`.
**Reader 1 (stale):** `streak_guardian_eligibility_test.dart`'s "root
cause 2" group, still reading `index.ts` only.

**Writer 2 & 3:** `future-prediction/index.ts` and `morning-alert/index.ts`
— both had lines removed above their respective self-read sites during
this batch's Gemini-removal edits (Tasks 9-10 and 7 respectively).
**Reader 2 & 3 (stale):** `docs/snapshot_contract.yaml`'s
`future_prediction` and `morning_alert` key entries, citing pre-edit
line numbers.

## Fix

Repointed `streak_guardian_eligibility_test.dart`'s "root cause 2" group
at `message.ts` via a new `messageSrc` read; corrected both stale line
citations in `docs/snapshot_contract.yaml`.

## Verification

`flutter test test/contracts/streak_guardian_eligibility_test.dart
test/contracts/snapshot_contract_consolidated_test.dart
test/contracts/proactive_coach_promotion_test.dart` — 45/45 passed.

**Mutated and run** (rule 21), two separate mutations:
1. Changed `` `${streakDays}-day milestone!` `` to `` `${streakDays}-day achievement` `` in `message.ts` — reddened exactly 1 of 11
   `streak_guardian_eligibility_test.dart` tests. Reverted; re-ran green.
2. Reverted both `docs/snapshot_contract.yaml` citations back to their
   stale values (288, 620) — reddened exactly 1 of 16
   `snapshot_contract_consolidated_test.dart` tests (`FAIL reader-read`
   for both keys, correctly caught by the SAME assertion since the gate
   script itself reports both violations in one run). Reverted; re-ran
   green.

## Related

Direct continuation of the same review chain as `c4e8a1` — found by
proactively widening the same class-sweep after Round 3's finding,
rather than waiting for it to surface function-by-function across
further review rounds.
