---
bug_id: b2e9f4
date: 2026-08-20
batch: fob5-hold-telemetry
blast_radius: platform
status: fixed
symptom: >
  `scripts/pre-push.sh` blocked a push whose commit was fully green in CI's own
  terms. The full-suite gate ran a bare `flutter test` while CI runs
  `flutter test test/ --exclude-tags golden` under `TZ: Asia/Kolkata`. Measured
  2026-08-20 on the same commit and the same machine: 4 failures under the bare
  form, 0 under CI's form. The 4 were 2 Windows-rendered goldens and 2 IST
  date-boundary contracts — none of them touched by the pushed diff.
concept: pre_push_ci_parity
sot_registry_entry: n/a  # the SoT registry records writer/reader DATA contracts; this bug is in process tooling and touches no app state, so an entry would be noise rather than coverage
writers:
  - { file: scripts/pre-push.sh, line: 141, source: "run_full_suite() — the local full-suite invocation. Now `TZ=Asia/Kolkata flutter test test/ --exclude-tags golden`, mirroring CI literally." }
readers:
  - { file: .github/workflows/test.yml, line: 28, source: "`TZ: Asia/Kolkata` pinned at WORKFLOW level, so every job inherits it — which is why the divergence was invisible when reading the job step alone" }
  - { file: .github/workflows/test.yml, line: 112, source: "`flutter test test/ --exclude-tags golden --reporter expanded` — the authoritative full-suite invocation this gate now matches" }
hive_key_prefix: n/a
hive_key_formula: "n/a — process tooling, no app state"
sync_methods: [n/a]
restore_methods: [n/a]
cloud_table: n/a
cloud_columns: []
contract_test_path: test/scripts/pre_push_matches_ci_invocation_test.dart
ist_handling:
  - { file: scripts/pre-push.sh, line: 141, fn: "the gate now RUNS under Asia/Kolkata, which is the point: the repo's date-boundary contracts assert IST behaviour and read the ambient zone, so a UTC runner fails them for reasons unrelated to the change under test" }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  n/a — this is a local git hook. It touches no user data and no cloud state.
forbidden_patterns_checked:
  - "hardcoding the expected command string in the test — NOT done. The test PARSES both files and compares them, so CI legitimately changing its invocation reddens the test instead of silently re-opening the gap."
  - "matching `flutter test` anywhere on a line — rejected after it bit during authoring: pre-push's own progress `echo` quotes the command it is about to run, so the loose pattern read the echo and reported the gap as open while the real invocation was already correct. The pattern is line-anchored, permitting only leading VAR=value assignments."
  - "loosening or skipping the failing tests to get the push through — NOT done. The tests are correct; the RUNNER was wrong."
  - "reaching for --no-verify. That is the failure mode this fix exists to remove: the only way past a false red is a flag that also disables every REAL gate."
proposed_fix: >
  Make run_full_suite's invocation byte-equivalent to CI's: pin TZ to
  Asia/Kolkata and pass --exclude-tags golden, with test/ named explicitly to
  mirror CI literally rather than rely on flutter test's default.
regression_test_planned: >
  test/scripts/pre_push_matches_ci_invocation_test.dart — 3 cases, each parsing
  BOTH scripts/pre-push.sh and .github/workflows/test.yml rather than asserting
  a hardcoded string. Mutation-proven on all three legs: dropping
  --exclude-tags golden reddens 1, dropping TZ reddens 2, and demoting the
  correct command to a comment above the function while leaving a bare
  `flutter test` executing reddens 3.
impact_analysis: >
  This LOOSENS a gate, so the risk direction is "does it now let something
  through that CI would catch". It does not. The gate moves from a SUPERSET of
  CI's run to CI's run exactly: the only tests it stops running locally are the
  `golden`-tagged ones, which CI does not run either, on any platform. Every
  test CI would fail on still runs here and still blocks the push.

  What genuinely changes: a Windows developer, whose goldens DID pass locally,
  loses that incidental coverage at push time. That is a real and deliberate
  trade. Golden coverage that only exists on one contributor's operating system
  is not a gate — it is a machine-dependent surprise, and it was already absent
  from CI, from every non-Windows machine, and from this container. Making it
  uniformly absent is worse than making it uniformly present, and better than
  leaving it uniformly unpredictable. Restoring it properly means either
  regenerating goldens per-platform or running them in a pinned container; both
  are real work and neither belongs in a hook alignment fix.

  ⚠ The cost of NOT fixing this is what makes it worth a commit. A gate that
  fails what CI passes produces only false reds, and the sole way past a false
  red is `--no-verify` — which switches off every REAL gate at the same time.
  Two separate one-push `--no-verify` authorizations had already been spent on
  this exact divergence before anyone looked at the cause. The defect was not
  costing a few minutes; it was steadily converting an operator into someone who
  reaches for the bypass by reflex.

  No user-facing behaviour changes. No app code, schema, Edge Function, cron,
  policy, bucket, secret or external service is touched.
touched_layers_checked:
  - { tier: 1, name: client_code, status: verified, evidence: "no lib/ change; `flutter analyze --no-fatal-infos` 0 errors/warnings" }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "process tooling only" }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "no schema touched" }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "no data touched" }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration in this fix" }
  - { tier: 6, name: edge_function_deploy, status: not_applicable, evidence: "no Edge Function touched" }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron touched" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "no policy touched" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no bucket or object touched" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret read or written; the hook takes no credentials" }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "no external service involved" }
  - { tier: 12, name: client_server_contract, status: fixed_in_this_batch, evidence: "the contract here is hook-vs-CI. Verified by running the same two previously-failing files both ways on one machine: bare -> 2 failures, TZ=Asia/Kolkata -> 24/24 pass. The three existing hook tests (hook_gate_placement, pre_push_analyze_always_e2e, dart_bin_resolver MIRROR) re-run green, so the analyze-placement and dart-resolution invariants are intact." }
---

# b2e9f4 — the pre-push gate was stricter than CI, in the direction that forces a bypass

## What happened

A `catastrophic`-tier push (FOB-5, migration 120) triggered pre-push's full
suite. The suite reported 4 failures. The same commit had already run
**+4751, exit 0** under CI's invocation minutes earlier.

The 4:

| Failing test | Why |
|---|---|
| `ward_rank_pill_golden_test.dart` (×2) | goldens are rendered on Windows; they fail on font rasterisation anywhere else. CI excludes the `golden` **tag**. |
| `logout_login_round_trip_test.dart` | asserts IST date behaviour, reads the ambient zone |
| `session_date_and_home_start_behavioral_test.dart` | same |

None is touched by the diff.

## Root cause

`scripts/pre-push.sh` ran a bare `flutter test`. `.github/workflows/test.yml`
runs `flutter test test/ --exclude-tags golden` (`:112`) with `TZ: Asia/Kolkata`
pinned at **workflow** level (`:28`).

Two divergences, and the TZ one hides well: it is not on the job step, it is
workflow-wide env, so reading the step alone shows nothing wrong.

**The scope never diverged.** Bare `flutter test` already defaults to `test/`,
so the goldens were included by *tag*, not by path. An earlier reading of this
called it a three-way divergence including scope; that was wrong, and `test/` is
now passed explicitly only to mirror CI literally.

## Why this is a real defect and not a cosmetic mismatch

A gate that fails what CI passes is worse than no gate. Its failures are all
false, the only way past a false red is `--no-verify`, and `--no-verify`
disables every **real** gate in the same breath. So a lying gate does not merely
fail to protect — it actively trains the operator to disarm the protections that
work. This one had already consumed two separate one-push `--no-verify`
authorizations before anyone looked at the cause.

## The fix

`run_full_suite()` now invokes `TZ=Asia/Kolkata flutter test test/
--exclude-tags golden`.

`test/scripts/pre_push_matches_ci_invocation_test.dart` pins it by **parsing
both files and comparing them** — not by asserting a hardcoded expected string.
That matters: if CI's invocation legitimately changes, the test reddens and
forces the hook to follow, instead of quietly drifting apart again. The test
also asserts the CI-side baselines it depends on (that CI excludes the tag, that
CI pins TZ), so if those assumptions die the test says so rather than passing
vacuously.

One authoring note worth keeping: the first extractor matched `flutter test`
anywhere on a line and picked up pre-push's own progress `echo`, whose message
quotes the command it is about to run. The test then reported the gap as still
open while the real invocation was already correct. The pattern is now
line-anchored, allowing only leading `VAR=value` assignments — a reminder that a
source-scanning test's *extractor* needs the same scrutiny as its assertion.

## Related

- **OI-106** — local `flutter test` runs ~3.9× slower per file than CI, cause
  unknown. Same "local and CI are not the same runner" family; not the same bug,
  and not addressed here.
- The `--no-verify` policy in CLAUDE.md §4.3 is unchanged. This fix removes one
  standing *reason* to reach for it.
