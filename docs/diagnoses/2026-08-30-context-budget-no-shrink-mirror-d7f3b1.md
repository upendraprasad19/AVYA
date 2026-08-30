---
bug_id: d7f3b1
date: 2026-08-30
batch: board-budget
status: fixed
blast_radius: platform
symptom: >-
  `check_context_artifact_budget.dart` — a gate whose entire job is to notice
  when a context artifact changes size — reported `PASS: 3 within band` for a
  `CLAUDE.md` truncated to ZERO BYTES. Every negative drift was classified
  `BudgetStatus.ok`, so total loss of the repo's governing file was
  indistinguishable from no drift at all. Caught by context-blind review round 1
  on the branch, before the merge; never reached `main`.
concept: context_artifact_budget
sot_registry_entry: null
writers:
  - file: scripts/context_budget_lib.dart
    method: evaluateOne (status ternary)
    line: 162
readers:
  - file: scripts/check_context_artifact_budget.dart
    method_or_widget: main (report loop + anyBlocking)
    line: 104
  - file: scripts/pre-commit.sh
    method_or_widget: "the scripts/check_*.dart bounded-parallel gate loop"
    line: 326
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: test/scripts/context_budget_lib_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
impact_analysis:
  callers_audited:
    - scripts/check_context_artifact_budget.dart (the only consumer of evaluateAll / anyBlocking)
    - scripts/pre-commit.sh (bounded-parallel `scripts/check_*.dart` loop — picks the gate up by glob)
    - .github/workflows/test.yml (same glob, no skip-list entry)
    - test/scripts/context_budget_lib_test.dart
    - test/scripts/context_artifact_budget_e2e_test.dart
  callers_updated_in_this_batch:
    - scripts/check_context_artifact_budget.dart (also fixed the valid-JSON-wrong-shape message, which fell through silently and told the operator to run --record)
    - test/scripts/context_budget_lib_test.dart (5 shrink-band tests added; the pre-existing shrink test passed under the bug and was relabelled to say why it cannot detect it)
    - test/scripts/context_artifact_budget_e2e_test.dart (zero-byte truncation asserting exitCode 1, plus the wrong-shape message)
  callers_unchanged:
    - scripts/pre-commit.sh (no wiring change needed — the gate is auto-globbed and absent from the case-skip allowlist)
    - .github/workflows/test.yml (same; verified by Gate 33 check_gate_scripts_wired.dart)
    - backups/context_artifact_sizes.json (data, re-recorded rather than edited)
forbidden_patterns_checked:
  - pattern: "Shrinking is always fine"
    absent: true
  - pattern: "drift < hardShrink"
    absent: false
proposed_fix: >-
  Give the gate a lower bound as well as an upper one. `kSoftShrink` (-50%)
  warns and `kHardShrink` (-90%) blocks, plumbed through both `evaluateOne` and
  `evaluateAll`. Asymmetric against the growth bands on purpose: deliberate
  reclamation is a normal LARGE event — this batch's own board archive was
  -45.5% — and must never be blocked, while losing nine tenths of a governing
  file in one commit is not something anyone does on the way to somewhere else.
  `--record` remains the documented escape hatch for a genuine split into
  modules.
regression_test_planned:
  - test/scripts/context_budget_lib_test.dart
  - test/scripts/context_artifact_budget_e2e_test.dart
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "scripts/context_budget_lib.dart:162 now tests both directions. 35 tests green across the lib + e2e files; mutation deleting the shrink floor reddens 5, deleting the hard growth band reddens 7, removing fail-open 4, narrowing the key union 4; restored 35/35. Each mutation verified applied by an exact-match replace that aborts unless it matches exactly once." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "The gate reads file lengths and a JSON baseline. No Hive box is opened; context_budget_lib.dart imports nothing from dart:io at all." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No cloud row is read or written." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration in this batch; backups/applied_migrations.json untouched." }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "No Edge Function touched; supabase/functions/ absent from the diff." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron job dispatches this gate; it runs from pre-commit and CI only." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No table involved." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket or object involved." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "The gate reads no secret and makes no network call." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service is contacted." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "End-to-end through the real script: test/scripts/context_artifact_budget_e2e_test.dart runs the actual gate against temp fixtures and asserts exitCode 1 for a zero-byte CLAUDE.md against a 95,297 B baseline, plus exit 0 for every fail-open path. 10 e2e tests green." }
---

# A size gate with no lower bound calls a truncated file clean

## What happened

The gate shipped in `cfc9ebf9` with this classification:

```dart
final status = drift > hardBand
    ? BudgetStatus.fail
    : drift > softBand
        ? BudgetStatus.warn
        : BudgetStatus.ok;
```

and this comment above it: *"Shrinking is always fine, and is the point of the
batch that added this."*

That sentence is true about the case that motivated the batch — the board
archive cut `open_issues.md` by 44% and a gate firing on its own reclaim would
be worse than useless. It is false as a general rule, and the ternary encodes
the general rule. Review round 1 built the fixture and ran it: a `CLAUDE.md` of
zero bytes against its real recorded baseline of 95,297 B produced

```
[context-budget] PASS: 3 within band, 0 warned, 0 skipped.
```

## Why the tests did not catch it

There was exactly one shrink test, and it exercised the batch's own -45.5%
reclaim:

```dart
test('shrinking is ok, never a breach', () {
  final f = evaluateOne('a', baseline: 357664, actual: 194850);
  expect(f.status, BudgetStatus.ok);
});
```

It passes under the bug and it passes under the fix, because -45.5% is inside
the floor either way. **The test was written from the same mental model as the
code** — "shrinking is the good case" — so it probed the direction the author
already believed was safe. `.claude/skills/code-review/SKILL.md` lens 6 says
exactly this: *do not accept the diff's own tests as evidence for this lens;
ask instead what every test in the file silently assumes.*

## Recurrence

This is `guard_without_its_mirror` again — the class
`memory/feedback_mistake_guard_without_its_mirror.md` tracks at 15 instances
across 7 sessions. The specific shape here is the cheapest one to state: **a
threshold written for the direction you fear leaves the opposite direction
completely unguarded, and a band is two-sided by nature.** The author reached
for "how much growth is too much" and never asked the mirror question, "how much
loss is too much", despite the value being a single signed number where both
questions live.

Related: the same review round found the batch's headline fix — the index render
cap in `build_oi_index.dart` — shipped with no test that could detect its own
removal (reverting it left all 26 tests in `oi_index_test.dart` green). Both
defects are the same family: **protection that was never mutated is not known to
protect anything.**

## The fix

Two floors, asymmetric against the growth bands:

```dart
const double kSoftShrink = -0.50;  // warns, never blocks
const double kHardShrink = -0.90;  // blocks
```

Asymmetry is the design, not an oversight. Deliberate reclamation is normal,
large, and reported — so -50% only warns, and the next person who archives a
pile of closed entries is not stopped. Losing nine tenths of a governing file in
one commit is not incidental to anything, so -90% blocks, with `--record` as the
documented escape hatch for a real split into modules.

## What a future reader should take

If you add a band, a threshold, or a tolerance anywhere: **write the mirror test
before the mirror bug.** Ask what the value looks like at the other extreme, and
whether "obviously fine" is a property of the direction or only of the one
example you had in mind.
