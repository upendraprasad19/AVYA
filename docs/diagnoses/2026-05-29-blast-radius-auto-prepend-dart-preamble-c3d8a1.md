---
bug_id: c3d8a1
date: 2026-05-29
batch: six-industry-gap-closures (follow-up fix during cross-check)
status: fixed
blast_radius: feature
symptom: >
  The Blast-radius auto-prepend (Track 2 deliverable) never fired. Neither
  the mega-commit (7d31f40) nor the cron-fix commit (7490dc9) received the
  expected "Blast-radius: <tier>" line in the commit body, despite the
  prepare-commit-msg hook being installed.
concept: blast_radius_commit_autotag
sot_registry_entry: not_applicable (dev tooling; not a user-data SoT concept)
writers:
  - { file: scripts/prepare-commit-msg.sh, line: 36, source: "consumer that parses helper stdout for the tier line" }
  - { file: scripts/blast_radius_from_diff.dart, line: 140, source: "emits 'Blast-radius: <tier>' to stdout" }
readers:
  - { file: scripts/prepare-commit-msg.sh, line: 36, source: "greps helper output, inserts tier into commit message" }
hive_key_prefix: not_applicable (dev tooling; no Hive)
hive_key_formula: not_applicable
sync_methods: not_applicable (local git hook; no cloud sync)
restore_methods: not_applicable
cloud_table: not_applicable (no cloud involvement)
cloud_columns: not_applicable
contract_test_path: not_applicable (shell git-hook behavior; verified by simulating the hook against a temp commit-message file with a staged path)
ist_handling: not_applicable (no dates)
provider_invalidations: not_applicable (no client providers)
telemetry_op_types: not_applicable
cross_account_guard: not_applicable (local dev tooling, no user scoping)
forbidden_patterns_checked: >
  Confirmed via od -c that dart's "Running build hooks..." preamble is
  written to stdout with NO trailing newline, concatenating onto the
  helper's "Blast-radius: <tier>" output as a single line. The anchored
  grep "^Blast-radius:" therefore never matched.
proposed_fix: >
  Change prepare-commit-msg.sh line 36 from an anchored
  `grep -E '^Blast-radius:'` to a prefix-tolerant
  `grep -oE 'Blast-radius: (feature|account|platform|catastrophic)' | tail -1`,
  which extracts the tier token regardless of any preamble prefix on the
  line. Hook re-installed via setup-hooks.sh + simulated end-to-end.
regression_test_planned: >
  Verified by simulating the installed hook
  (sh .git/hooks/prepare-commit-msg <tmpmsg> message) with a staged path:
  the message now gains "Blast-radius: feature" after the subject. Durable
  guard: any future shell consumer of a `dart run` script's stdout must use
  prefix-tolerant extraction (grep -oE), never an anchored ^ match — dart's
  build-hooks preamble pollutes stdout line 1. Noted in the hook's inline
  comment.
touched_layers_checked:
  - { tier: "Client code", status: fixed_in_this_batch, evidence: "scripts/prepare-commit-msg.sh line 36 changed to grep -oE prefix-tolerant extraction; hook re-installed + simulated, now prepends Blast-radius: feature" }
  - { tier: "Migrations applied", status: not_applicable, evidence: "no migration in this fix" }
  - { tier: "Postgres schema", status: not_applicable, evidence: "no DB involvement" }
impact_analysis: >
  Severity: low — a discipline/observability convenience, not a correctness
  path. Effect: commits since the Track 2 ship lacked the auto-tagged
  Blast-radius line, so the at-a-glance tier annotation was missing from
  commit bodies (the registry + coverage gate + diagnose-doc blast_radius
  field all still worked — only the commit-message convenience was dead).
  No user impact, no data impact. Found during 2026-05-29 cross-check when
  the cron-fix commit (7490dc9) was observed to lack the tag line.
---

# c3d8a1 — Blast-radius auto-prepend defeated by dart build-hooks preamble

## What happened

The Track 2 `prepare-commit-msg` hook is meant to auto-prepend a
`Blast-radius: <tier>` line to every commit body, computed from the
staged paths via `scripts/blast_radius_from_diff.dart`. It never fired —
verified across two real commits (the mega-commit and the cron-fix
commit), neither of which carried the line.

## Root cause

`dart run` emits a `Running build hooks...` preamble to **stdout** with
no trailing newline (Dart SDK native-build-hooks message). So the
helper's stdout is a single line:

```
Running build hooks...Running build hooks...Blast-radius: platform
```

The hook extracted the tier with an anchored `grep -E '^Blast-radius:'`,
which cannot match a line that starts with `Running`. `TIER_LINE` was
always empty, so the hook hit its "no staged changes" guard and exited 0
without modifying the message.

## Why our gates didn't catch it

There is no gate that asserts a commit body actually contains the
auto-prepended line — the feature is a convenience, not a guarded
invariant. The defect only surfaces by inspecting a real commit's body,
which the cross-check did.

## Resolution

`prepare-commit-msg.sh` now extracts the tier with
`grep -oE 'Blast-radius: (feature|account|platform|catastrophic)' | tail -1`,
which matches the token anywhere on the line. Re-installed via
`setup-hooks.sh`; simulated end-to-end against a temp message file with a
staged path — the line is now inserted correctly.

## Prevention

Any shell consumer that parses a `dart run` script's stdout must use
prefix-tolerant extraction (`grep -oE`), never an anchored `^` match,
because dart's build-hooks preamble pollutes the first stdout line.
Captured as an inline comment in the hook + this diagnose-doc.

## Linked artifacts

- Fix: `scripts/prepare-commit-msg.sh` (line 36 region)
- Helper: `scripts/blast_radius_from_diff.dart`
- Sibling cross-check fix: diagnose `b1f4e2` (alert cron columns)
- Batch: `project_six_industry_gap_closures_2026_05_28.md`
