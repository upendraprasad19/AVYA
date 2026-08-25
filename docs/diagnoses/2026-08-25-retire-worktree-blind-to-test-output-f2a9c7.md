---
bug_id: f2a9c7
date: 2026-08-25
batch: board-hygiene
status: fixed
blast_radius: feature
symptom: >
  Any worktree that had merely RUN the full test suite could never be retired. `retire_worktree.dart`
  reported "1 non-regenerable ignored file(s)" and KEPT the worktree forever, because
  test/plan_generator/v4_diagnostic_test.dart:234 writes test/plan_generator/v4_diagnostic_output.md
  into the worktree, .gitignore:112 ignores it, and the tool's regenerable allow-list had never heard
  of it. Hit live twice: on `open-issues-triage-976962` (2026-08-16, the filing instance) and on
  `auth-class-fixes` (2026-08-25, merged and tracked-clean, held by that one file alone). The
  practical consequence is the one CLAUDE.md §4.13 point 6 exists to prevent — the worktree count
  regrows unbounded, and it previously reached 106 directories / 17 GB.
blast_radius_note: >
  CORRECTED before merge. This doc first said `platform`, copying OI-128's own
  "Blast radius estimate: platform — the review/blast-radius machinery under
  scripts/ is individually pinned". That claim is FALSE:
  `grep -n retire_worktree docs/blast_radius.yaml` returns nothing, so both files
  fall through to the `scripts/** -> feature` catch-all, and
  `blast_radius_from_diff.dart` classifies this branch `feature`. The commit
  message says `Blast-radius: platform` for the same reason and is likewise wrong;
  left uncorrected rather than rewriting pushed history, and recorded here instead.
  ⚠ The MISMATCH itself is filed as OI-139: retire_worktree is the only tool in the
  repo that DELETES developer work, yet it is tiered the same as a docs edit, while
  every sibling that merely BLOCKS a commit is pinned platform.
concept: >
  An allow-list whose input set was enumerated from one source (things new-worktree.sh copies in, and
  Flutter build products) while a SECOND producer of ignored files — the test suite itself — wrote
  into the same tree and was never enumerated. The tool's protective leg is correct and stays
  correct; what was wrong is that it treated a regenerable artifact as precious, so the failure
  direction was inert-not-destructive. That is the right direction to fail, which is exactly why it
  survived: nothing broke loudly, worktrees just quietly never retired.
sot_registry_entry: >
  None added. `regenerableIgnoredPaths` is a static allow-list inside a build-tooling script, not a
  runtime writer/reader pair over Hive or Postgres state, so there is no SoT concept to register.
  The list's correctness is pinned by test/scripts/retire_worktree_lib_test.dart instead.
writers:
  - { file: test/plan_generator/v4_diagnostic_test.dart, method: "end-to-end test writes File('test/plan_generator/v4_diagnostic_output.md')", line: 234 }
  - { file: .gitignore, method: "ignores that output, which is what routes it into git's --ignored=matching lane", line: 112 }
readers:
  - { file: scripts/retire_worktree_lib.dart, method: "regenerableIgnoredPaths — the exact-match allow-list that omitted it", line: 236 }
  - { file: scripts/retire_worktree_lib.dart, method: "isRegenerableIgnored() — exact match after separator normalisation", line: 271 }
  - { file: scripts/retire_worktree_lib.dart, method: "classifyWorktree() leg 6 — non-regenerable ignored files KEEP the worktree", line: 125 }
hive_key_prefix: not_applicable — no Hive box, key or adapter is involved; this is build tooling operating on the filesystem.
hive_key_formula: not_applicable — see hive_key_prefix.
sync_methods: not_applicable — nothing in the sync fan-out reads or writes worktree retirement state.
restore_methods: not_applicable — worktree retirement is developer-machine hygiene, never part of a user snapshot.
cloud_table: none — retirement state is derived from git and the filesystem, not from Postgres.
cloud_columns: none — see cloud_table.
contract_test_path: test/scripts/retire_worktree_lib_test.dart
ist_handling: not_applicable — no date key, counter reset or cloud date column is touched.
provider_invalidations: none — no Riverpod provider is involved in build tooling.
telemetry_op_types: >
  None added. The tool is operator-invoked and prints its full decision table on every run, including
  the reason each worktree was kept; that printed reason is what surfaced this bug both times it was
  hit. A telemetry event would add nothing a human reading the output does not already get.
cross_account_guard: >
  not_applicable — no user-scoped data path. Worth stating because the neighbouring legs of this same
  function DO guard precious data (a nested secrets/.env), and this change deliberately does not
  touch them.
forbidden_patterns_checked: >
  Checked and clean. No Container with color+decoration, no inline isPro, no client-side API key, no
  raw flutter build, no bare `dart` in a hook path. The pattern that DID apply is the one this fix is
  an instance of, and it is named in feedback_green_check_input_set_width: a check that is only as
  wide as its input set. The allow-list was enumerated from two producers and a third existed.
proposed_fix: >
  Add the five gitignored test outputs to `regenerableIgnoredPaths` as EXACT, ROOT-ANCHORED paths:
  test/plan_generator/v4_diagnostic_output.md (.gitignore:112), analyze_output.txt (:107),
  flutter_test_output.txt (:108), baseline.json (:132), baseline-lints.json (:133). The set was
  ENUMERATED FROM .gitignore rather than fixing the one observed instance — the completeness rule is
  re-run the enumeration to empty, not "the symptom stopped". Deliberately NOT added:
  test/goldens/**/failures/ (.gitignore:183). It is genuinely regenerable, but it is a PATTERN, and
  this list's entire hard-won rule is exact-match-only — three prior review rounds each found a P0
  here caused by looser matching (prefix matching destroyed .envrc and .envs/; basename matching
  destroyed supabase/.env, a real 518-byte credentials file). The function header's own instruction
  for the needs-a-pattern case is to keep the worktree instead, and that instruction is followed here
  rather than overridden.
regression_test_planned: >
  Two tests added and the fix mutation-proven before commit. (1) The five new paths must classify
  regenerable. (2) Near-misses of each new entry must still BLOCK — v4_diagnostic_output.md.bak,
  archive/analyze_output.txt, flutter_test_output.txt.orig, data/baseline.json, the bare
  test/plan_generator/ directory, and test/goldens/home/failures/ — so the fix cannot have
  reintroduced prefix or basename matching under a new name. MUTATION RESULT, stated precisely
  rather than rounded up: deleting exactly the five new entries (the real regression — they were
  never there) reddens test (1) and the suite goes 34 passing to 33 passing 1 failing. Test (2) does
  NOT redden under that mutation and is not claimed to — it is a WIDENING guard, and it reddens on
  the opposite mutation (replacing exact match with a glob), which is the change it exists to catch.
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "No lib/ file changed; this is scripts/ build tooling." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No box, adapter or key involved." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No table read or written." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration; backups/applied_migrations.json untouched." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron job reads worktree state." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy involved." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket or object involved." }
  - { tier: 10, name: secrets_api_keys, status: verified, evidence: "The adjacent protective legs that keep a nested .env non-regenerable were re-run and still pass — supabase/.env, supabase/functions/.env and secrets/.env all classify NON-regenerable after the change (retire_worktree_lib_test.dart 34/34 green)." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "None involved." }
  - { tier: 12, name: client_to_server_contract, status: not_applicable, evidence: "No client-server contract; this is local developer tooling." }
impact_analysis: >
  Severity: P3, developer-machine hygiene only, zero user impact — no shipped code path reads this
  list. But the failure compounds: §4.13 point 6 exists because the worktree count reached 106
  directories / 17 GB, and a rule whose only enforcement is a §5 checklist row decays if the tool it
  points at cannot actually retire anything. Every worktree that ran the suite was permanently
  ineligible, which is most of them, so the retirement loop was closing far fewer worktrees than its
  operator would reasonably assume from a clean-looking run. Verified after the fix on the live
  instance: auth-class-fixes' remaining ignored set is now entirely regenerable.
---

# `retire_worktree` was blind to test-generated output (OI-128)

## What happened

`dart run scripts/retire_worktree.dart` reported:

```
KEEP    auth-class-fixes  [2 non-regenerable ignored file(s) — `git status` hides
                           these and `git worktree remove` does not refuse on them]
```

for a worktree whose branch was merged and whose tracked tree was completely clean. The two files
were `.claude/.ci_reconcile_pending.jsonl` and `test/plan_generator/v4_diagnostic_output.md`.

## Root cause

`regenerableIgnoredPaths` (`scripts/retire_worktree_lib.dart:236`) was enumerated from two producers:

1. what `scripts/new-worktree.sh` copies in (`.env`), and
2. Flutter/Dart build products (`.dart_tool/`, `build/`, the generated plugin registrant, …).

A **third** producer writes ignored files into the worktree and was never enumerated: **the test
suite itself.** `test/plan_generator/v4_diagnostic_test.dart:234` writes
`test/plan_generator/v4_diagnostic_output.md`, ignored at `.gitignore:112`.

Leg 6 of `classifyWorktree` then did exactly what it should — an unrecognised ignored file KEEPS the
worktree — so the tool was correct in mechanism and wrong only in its input set.

## Why it survived

The failure direction was **inert, not destructive**. The tool kept worktrees it could have retired;
nothing was ever lost, nothing errored, and the printed reason looked like a considered decision
rather than a gap. That is the right way for this tool to fail, and it is precisely why nobody
noticed: a check that fails safe also fails quietly.

## The other half of the live instance

`.claude/.ci_reconcile_pending.jsonl` was NOT added to the allow-list, and deliberately. It is a
work queue, not an artifact — it held one entry armed 2026-08-16 for sha `7331528e`. The designed
drain is `scripts/reconcile_ci.dart`, which keeps only surviving entries (`:103`) and deletes the
file when none remain (`:186`). Running it in that worktree reported `count: 0` and removed the file
— the correct outcome for a branch push, where ADR-0018 says no CI run is expected.

Treating a queue as a disposable artifact would have been the wrong fix: it would discard unconsumed
entries silently, which is the bad-news-vs-no-news class. Running the consumer is the right one.

⚠ Residual, stated rather than implied: that queue only drains when a session starts **in that
worktree**, because `.claude/` is per-worktree. A retired worktree's unconsumed entries would go with
it. Not a defect of this fix and not fixed here — filed as its own board item.

## Prior art in this exact function

The header records three review rounds that each found a P0 here, every one caused by matching
looser than exact:

- round 1 — no ignored check at all; an ignored `secrets/.env` was destroyed silently.
- round 2 — prefix matching; `.env` also matched `.envrc` and `.envs/`.
- round 3 — basename-at-any-depth; `.env` matched `supabase/.env`, a real credentials file. **A test
  in this very suite had asserted that must be regenerable — the suite had locked the bug in.**

This fix adds only exact root-anchored strings and adds a test asserting near-misses still block, so
that history cannot repeat under a new name.
