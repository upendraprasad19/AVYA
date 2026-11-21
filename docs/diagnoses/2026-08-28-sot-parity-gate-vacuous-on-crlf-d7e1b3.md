---
bug_id: d7e1b3
date: 2026-08-28
batch: oi89-bodyweight-floor
status: fixed
blast_radius: platform
symptom: >-
  main went red on the OI-89 merge. The Audit Gates job failed on
  check_sot_registry_parity with three stale line_ranges, while every other CI
  job passed — and the same gate had reported PASS on all 18 local commits that
  introduced the drift, in a pre-commit loop that runs it and does not skip it.
concept: gate_wiring_coverage
sot_registry_entry: null
writers:
  - file: docs/sot_registry.yaml
    method: line_range fields on writer/reader entries
    line: 3707
readers:
  - file: scripts/check_sot_registry_parity.dart
    method_or_widget: blockRegex over the registry text
    line: 141
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: []
contract_test_path: null
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked:
  - pattern: "readAsStringSync\\(\\);\\s*\\n\\s*final errors"
    absent: true
proposed_fix: >-
  Normalise CRLF to LF at the point the registry is read, so the newline-anchored
  regexes below it parse a Windows working copy identically to CI's LF checkout.
regression_test_planned: []
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "Three stale line_ranges corrected to each method's true span. The gate normalises CRLF at the read. Proven by execution rather than asserted: main (LF, ranges fixed) exits 0; the oi89-bodyweight-floor worktree (CRLF, ranges still stale) exits 1 where it exited 0 before the change — same tree, same stale data, opposite verdict." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No Hive involvement; this is a build-time gate over a YAML file." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No data change." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function involved." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron involved." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No policy." }
  - { tier: 9, name: storage_buckets, status: not_applicable, evidence: "No storage." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "No external service." }
  - { tier: 12, name: client_server_contract, status: not_applicable, evidence: "No request carries any of this." }
impact_analysis: >-
  The user-facing blast radius is zero — no shipped behaviour depended on it. The
  process blast radius is not: a gate wired into pre-commit, absent from the
  skip-list, and reported as coverage by Gate 33's wiring check has been
  examining NOTHING on every developer machine for as long as this repo has been
  checked out on Windows. Its only real coverage was CI, i.e. exclusively after a
  push had landed, which is the most expensive possible place to learn. The
  registry it guards is the file CLAUDE.md §4.1 tells every bugfix to consult for
  writer/reader file:line, so silent rot there degrades the discipline that
  depends on it.
---

# A gate that examined nothing, and said PASS

## What was wrong

Two layers. The first is ordinary; the second is why this doc exists.

**Layer 1 — three stale `line_range` entries.** Edits in this batch shifted the
cited methods:

| file | method | was | is |
|---|---|---|---|
| `edit_profile_screen.dart` | `_save` | 1592-1620 | 1696-2063 |
| `exercise_repository.dart` | `getCustomExercises` | 387-410 | 427-450 |
| `sync_profile.dart` | `_restoreUserPreferences` | 655-720 | 723-793 |

**Layer 2 — the gate could not see them.** `check_sot_registry_parity.dart`
parses the registry with regexes anchored on `\n` and captures paths with
`[^\n]+`:

```dart
r'file:\s*([^\n]+)\n\s*line_range:\s*(\d+)-(\d+)…'
```

On a CRLF working copy every captured path retains a trailing carriage return.
`File('$projectRoot/$relPath')` then resolves nothing, every entry is skipped,
and the gate prints:

```
[check_sot_registry_parity] PASS — registry file:line parity checked (0 errors …)
```

**A vacuous pass, in the same colour as a real one.** "0 errors" was true and
meaningless: it had examined zero entries.

## Why it went unnoticed for so long

Git stores this repo with LF; Windows checks it out as CRLF. So **every worktree
on the dev machine sat in the vacuous state**, permanently. The gate is in
`pre-commit.sh`'s `scripts/check_*.dart` loop and is **not** on the skip-list, so
it ran on all 18 commits of this batch and reported PASS each time.

CI checks out LF. It parsed the registry properly, found the drift, and failed —
which is the correct behaviour arriving at the most expensive possible moment,
after the push had landed and turned `main` red.

This also means `check_gate_scripts_wired.dart` (Gate 33) counted this gate as
wired coverage. It was wired. It was not covering anything.

## The fix, and the proof

One line: normalise CRLF at the read, before any regex sees the text.

Asserting "now it works" would repeat the original error, so it was executed both
ways on the same stale data:

| tree | line endings | ranges | before | after |
|---|---|---|---|---|
| `main` | LF | fixed | — | **exit 0** |
| `oi89-bodyweight-floor` worktree | CRLF | **stale** | **exit 0** | **exit 1** |

The bottom-right cell is the whole proof. Same worktree, same stale registry,
opposite verdict — so the gate now discriminates where it previously could not.

## Recurrence

`feedback_green_check_input_set_width.md`, **REPRESENTATION** sub-class — which
that file already names from a 2026-08-17 incident where CRLF-vs-LF made two
checks return empty and empty was read as proof of absence. Second time the same
representation difference has made a check silently examine nothing.

The generalisable rule, now earned twice: **a text-processing check that anchors
on `\n` must normalise line endings at the read.** And the older rule this is a
special case of — *an empty input set reports nothing in the same colour as
nothing-wrong* — applies to gates as much as to greps. A gate that reports
"0 errors" should be able to say how many entries it examined; if it cannot, "0"
is not evidence.

## The sibling sweep — RUN, not filed

The obvious worry is that other gates share the idiom. That was measured rather
than assumed, and the answer is **zero**: no other `check_*.dart` uses a
negated-newline character class at all. The gates that read whole files use
`readAsLinesSync()`, which Dart strips of both `\n` and `\r\n`, so they are
CRLF-safe by construction. This gate was the only one combining
`readAsStringSync()` with newline-anchored regexes.

Recorded as a measurement because "other gates might share this" is exactly the
kind of residual that gets written into a doc, never checked, and read a year
later as a known-open risk. It is closed.
