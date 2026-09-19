---
bug_id: b3e7a1
date: 2026-09-19
batch: gate-integrity (Task 2 / OI-155)
status: fixed
blast_radius: platform
symptom: >
  Six `scripts/check_*.dart` gates ran NOWHERE — not in pre-commit's loop, not
  in CI's loop, not from /build-apk, not from any hook — while Gate 33
  (`scripts/check_gate_scripts_wired.dart`, whose whole job is "is every gate
  wired") reported PASS on every commit. Two of the six are the repo's only
  live-SQL security gates (`check_onconflict_live_arbiter.dart`,
  `check_two_user_cross_account.dart`); one (`check_migrations_live.dart`)
  cannot pass by construction and its allowlist entry named a "/build-apk Gate
  14b" that does not exist; one (`check_snapshot_contract.dart`) passes today
  and was skipped for a stale reason. OI-155 (P1).
concept: gate_fail_closed_discipline
sot_registry_entry: not_applicable
writers: >
  scripts/check_gate_scripts_wired.dart `_allowList` — pre-fix a
  `Map<String, String>` of gate name to FREE PROSE ("Requires live Supabase
  MCP — runs in /build-apk skill Gate 14b, not pre-commit"), pre-fix lines
  37-82 (`git show b2435ef5:scripts/check_gate_scripts_wired.dart`). The
  prose was the only statement of where an allowlisted gate ran. Post-fix the
  map is `Map<String, List<GateRunner>>` at lines 52-124: every entry is a
  typed runner (`file(path)` / `loop(name)` / `manual(OI-N)`).
readers: >
  NONE — that is the bug. Pre-fix line 179 was
  `if (_allowList.containsKey(script)) continue;`: an allowlisted gate was
  skipped outright and its prose never read by anything, so a false "runs in
  X" claim was structurally invisible. Post-fix the reader is
  `runnerViolations()` (scripts/gate_scripts_wired_lib.dart:160-208), called
  for every allowlisted gate at check_gate_scripts_wired.dart:244-250, plus
  `staleAllowlistViolations()` (lib:213-220, gate:272) as the mirror for an
  entry whose script is gone. For NON-allowlisted gates the wiring inference
  at gate:255-258 now uses `invokesGate()` (lib:139-147) instead of
  `content.contains(script)`, so a comment or prose mention no longer reads
  as wired.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: not_applicable
restore_methods: not_applicable
cloud_table: not_applicable
cloud_columns: not_applicable
contract_test_path: test/scripts/gate_scripts_wired_runners_test.dart
ist_handling: not_applicable
provider_invalidations: not_applicable
telemetry_op_types: not_applicable
cross_account_guard: not_applicable
forbidden_patterns_checked: >
  (1) an allowlist whose entries are prose read by nothing — absent post-fix
  (every entry is a typed GateRunner that runnerViolations() verifies);
  (2) wiring inference by `contains(name)` where a comment or prose mention
  counts as an invocation — absent post-fix (invokesGate requires
  `run scripts/<gate>` on a non-comment line; every live invocation line of an
  allowlisted gate carries that shape — post-fix build-apk.md:242/381/389,
  test.yml:343, pre-commit.sh:293/304/403, commit-msg.sh:74, re-derived with
  `grep -n 'run scripts/check_'` on 2026-09-19);
  (3) a `manual:` entry that keeps passing after its blocker OI is CLOSED —
  absent (CLOSED / absent-from-both-boards / unreadable open board all add a
  violation; IN_PROGRESS is accepted so the session fixing it is not blocked);
  (4) an allowlist key surviving the deletion of its script — absent
  (staleAllowlistViolations mirrors gate_test_ledger_lib's own check);
  (5) a `};` above `_allowList` — absent (gate_wiring_args_required_test
  slices the file from `const _allowList` to the FIRST `};`; `_readOrNull`
  is a block-bodied top-level function placed AFTER the map).
proposed_fix: >
  Type the allowlist and make Gate 33 read it: `GateRunner.file(path)` must be
  invoked on a live line of that file; `GateRunner.loop(preCommit|ci)` must
  not be case-skipped in that loop's file; `GateRunner.manual(OI-N)` must cite
  an OI that is OPEN or IN_PROGRESS on the merged boards
  (`mergedBoardStatuses`, reused from oi_closure_lib.dart — never a third
  parser). Give the six dormant gates truthful runners: snapshot_contract ->
  NO entry (its case-skip lines deleted from pre-commit.sh and test.yml; it
  runs in both loops and passes today); unawaited_has_error_sink -> loop:ci
  (advisory exit 0; CI's log is its only reader, pre-commit runs every loop
  gate as >/dev/null 2>&1 so it stays skipped there); migrations_live ->
  manual:OI-223 (minted this batch: cannot pass by construction, 125/139 never
  registered live, 75 founder raw-SQL applies, recommendation RETIRE);
  onconflict_live_arbiter + two_user_cross_account -> manual:OI-165 (403 with
  the current PAT); test_runtime_budget -> manual:OI-101 (spawns the full
  suite; re-arm-or-delete is a founder scope call). So 4 of the 6 are
  `manual:` — stated plainly, a manual entry is not a fix of the gate; it is a
  machine-checked, self-reopening statement that the gate runs nowhere and
  WHY, replacing a prose claim that it ran somewhere it did not. The other 8
  entries convert to their real runner (apk_size / apk_release_signed /
  razorpay -> file(build-apk.md); plan_review_record_exists -> file(test.yml);
  regression_catalog + no_deferral_euphemism -> file(pre-commit.sh);
  closes_oi_cited -> file(commit-msg.sh); hooks_installed -> loop(preCommit)).
  Checked STRICTLY from the first commit — every entry passes on the real
  tree (Gate 33 PASS: 97 check_*, 11 validate_*/audit_*).
regression_test_planned: >
  test/scripts/gate_scripts_wired_runners_test.dart — 22 tests, pure (no
  subprocess): invokesGate (comment / prose / invocation-shaped prose /
  case-skip / live line), runnerViolations red paths for every runner kind
  (comment-only file, prose-only file, unreadable file, case-skipped loop,
  unknown loop, CLOSED OI, absent OI, unreadable board, malformed OI target,
  no runner), and staleAllowlistViolations. Existing pins kept green:
  test/contracts/gate_wiring_args_required_test.dart (5),
  test/contracts/apk_release_signed_gate_test.dart (12).
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "scripts/gate_scripts_wired_lib.dart (+GateRunner, invokesGate, runnerViolations, staleAllowlistViolations), scripts/check_gate_scripts_wired.dart (typed _allowList, board read, invokesGate inference, stale mirror), scripts/pre-commit.sh (snapshot_contract skip deleted; counts 97/84/13/86/87 re-derived), .github/workflows/test.yml (unawaited + snapshot_contract skips deleted; arm comment re-derived). dart run scripts/check_gate_scripts_wired.dart -> PASS exit 0 on the real tree; dart run scripts/check_snapshot_contract.dart -> exit 0; dart run scripts/check_unawaited_has_error_sink.dart -> exit 0 (advisory). flutter analyze on the three Dart files -> No issues found. 39/39 across the three named test files; 53/53 across the four neighbouring contract tests that read the touched files (pre_commit_gate_loop_parallel, blast_radius_content_rule_wired_all_scripts, snapshot_contract_consolidated, ai_snapshot_builder_only)." }
  - { tier: 2_hive, status: not_applicable, evidence: "no Hive surface — gate tooling only" }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no schema change" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no data touched" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration; OI-223 records why check_migrations_live cannot pass against the ledger" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function touched" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written; the two 403-ing live-SQL gates stay manual:OI-165 until that OI names the token" }
  - { tier: 11_external_services, status: not_applicable, evidence: "no external service call added; the Management-API gate is not run by this fix" }
  - { tier: 12_client_server_contract, status: not_applicable, evidence: "no client/server seam — the contract fixed is allowlist-claim -> Gate-33-verdict, covered under tier 1" }
impact_analysis: >
  Gate tooling only; no product code. What changes for every future commit:
  check_snapshot_contract.dart now runs in BOTH loops (a live ±15-line
  reader-citation blocker — accepted, it passes today) and
  check_unawaited_has_error_sink.dart runs in CI's loop (advisory, exit 0).
  Gate 33 now FAILS a commit when: a file() runner's file stops invoking the
  gate; a loop() runner's gate gets case-skipped; a manual() runner's OI is
  CLOSED, absent, or the open board is unreadable; or an allowlist key has no
  script on disk. The last two are the forcing function: closing OI-165 /
  OI-101 / OI-223, or retiring a gate, must touch this file in the same
  commit. Residual, stated: `manual:` is a truthful "runs nowhere" — the two
  live-SQL security gates still do not run until OI-165 names a working
  token, and check_migrations_live still cannot pass until the founder
  retires or redesigns it (OI-223). pre-commit.sh's loop count moves 75->84
  (13 case-skipped, 97 files); test.yml's skip block 13->11 entries.
mutation_proven: >
  Five lib mutations + two real-gate mutations, run after commit a664844c
  against the committed tree, each with `grep -c` proving it applied and
  `git checkout --` + a 0-line `git diff` after. Lib (22 tests in
  test/scripts/gate_scripts_wired_runners_test.dart): M1 invokesGate body ->
  `return content.contains(gate)` = 5 red (comment-only, prose-without-shape,
  case-skip invokesGate tests + file-runner comment-only and prose-only red
  paths); M2 `status == 'CLOSED'` -> `'NEVER'` = 1 red (CLOSED OI); M3 empty
  the `boardStatuses == null` branch body (compiles) = 1 red (unreadable
  board); M4 staleAllowlistViolations -> `const []` = 1 red (stale key); M5
  delete the `caseSkipsOf(c).contains(gate)` arm = 1 red (loop case-skips).
  Sum 9 of 22, exactly the plan's expected 5+1+1+1+1. Real gate: M6
  `manual('OI-101')` -> `'OI-9999'` = Gate 33 FAIL exit 1 "manual:OI-9999
  names no OI on either board"; M6b -> `'OI-172'` (CLOSED on the open board)
  = FAIL exit 1 "manual:OI-172 is CLOSED -- give the gate a real runner or
  re-file the blocker". Every mutation compiled; none reddened via a compile
  error; none reddened zero.
related_bugs:
  - "a9f2c6 (2026-07-29): gates that silently skip what they cannot parse — the same allowlist's dynamic-wiring inference misclassified a guaranteed crash as wired; that fix ADDED an allowlist entry, this one makes every entry checkable"
  - "d7a3f9 (2026-07-29): CI gate loop missing a skip entry — Gate 33 PASSed on the commit that broke CI; its regression test (gate_wiring_args_required_test) constrains this fix's `_allowList` shape (first `};` slice)"
  - "OI-155 (board): six unwired gates + prose allowlist; OI-165: live-SQL gates 403; OI-101: test_runtime_budget re-arm-or-delete; OI-223 (minted here): migrations_live cannot pass by construction"
recurrence: >
  Third instance of the gate-fail-closed class on THIS gate (a9f2c6 -> d7a3f9
  -> this). The prior two fixed one entry each; the class is "a claim about
  where a gate runs that nothing verifies", and this fix closes the class for
  the allowlist by making the claim typed and re-verified on every commit.
---

# Six gates ran nowhere while the gate that checks wiring said PASS

## What happened

`scripts/check_gate_scripts_wired.dart` (Gate 33) exists to answer "is every
`check_*.dart` gate invoked somewhere". Its `_allowList` — the escape hatch for
gates deliberately outside the two dynamic loops — was a `Map<String, String>`
whose VALUES were free prose, and the only thing the gate did with an
allowlisted key was `continue`. The prose said things like *"Requires live
Supabase MCP — runs in /build-apk skill Gate 14b, not pre-commit"*. There is no
Gate 14b in `.claude/commands/build-apk.md` (`grep -ic 14b` → 0), and
build-apk.md never invoked five of the six. Re-derived mechanically by two
independent readers across `pre-commit.sh`, `pre-push.sh`, `commit-msg.sh`,
`pre-merge-commit.sh`, `test.yml`, `build-apk.md` (skip-list and comment lines
excluded; control `check_apk_size_within_bounds` → `build-apk.md:381`), the six
with ZERO live invocation sites were:

| gate | what its prose claimed | truth |
|---|---|---|
| `check_unawaited_has_error_sink` | "surfaced in audit reports" | nothing ran it; pure `lib/` scan, advisory exit 0, 1.7 s |
| `check_snapshot_contract` | "requires generated snapshot manifest — runs in /build-apk" | needs nothing; passes today ("57 keys checked, 4 reader citations checked. OK") |
| `check_migrations_live` | "runs in /build-apk skill Gate 14b" | no such section; FAILS on the real project (125/139 never registered live) — OI-223 |
| `check_onconflict_live_arbiter` | "runs in /build-apk skill" | 403 with the current PAT — OI-165 |
| `check_two_user_cross_account` | "runs in /build-apk skill alongside …" | wrapper over the arbiter, inherits the 403 — OI-165 |
| `check_test_runtime_budget` | "Manual / CI artifact gate" | nothing runs it; spawns the full suite — OI-101 |

## Writer / reader

- **Writer:** the `_allowList` prose (pre-fix `check_gate_scripts_wired.dart:37-82`).
- **Reader:** none. Pre-fix `:179` `if (_allowList.containsKey(script)) continue;`.
  A claim nobody reads cannot be wrong, so it was never found wrong.

## Fix

`scripts/gate_scripts_wired_lib.dart` gains `GateRunner` (`file` / `loop` /
`manual`), `invokesGate`, `runnerViolations`, `staleAllowlistViolations`.
`_allowList` becomes `Map<String, List<GateRunner>>` with 13 entries (14 minus
`check_snapshot_contract`, which now runs in both loops), and Gate 33 verifies
every entry on every commit:

- `file(path)` — `path` must contain `run scripts/<gate>` on a non-comment line.
- `loop(preCommit|ci)` — that loop file must have the dynamic loop and must
  NOT case-skip the gate.
- `manual(OI-N)` — `N` must be OPEN or IN_PROGRESS on the merged boards
  (`mergedBoardStatuses` from `oi_closure_lib.dart`, reused). CLOSED, absent,
  or an unreadable open board FAIL.
- Mirror: an allowlist key with no `scripts/<key>` on disk FAILS.
- Non-allowlisted gates: the loop inference now uses `invokesGate` instead of
  `contains(script)`.

Skip-block edits: `scripts/pre-commit.sh` loses `check_snapshot_contract.dart|\`;
`.github/workflows/test.yml` loses `check_unawaited_has_error_sink.dart|\` and
`check_snapshot_contract.dart|\`. Counts re-derived: 97 `check_*.dart` files;
pre-commit loop runs 84 (13 case-skipped), 86 of 97 with the two explicit
invocations, 87 on a merge; test.yml's block 13 → 11.

## §4.2 tension, stated

Four of the six become `manual:`. That is not a fix of those gates. It is a
machine-checked, self-reopening statement that the gate runs nowhere and WHY,
replacing a prose claim that it ran somewhere it did not — and closing the
cited OI without giving the gate a runner turns Gate 33 red. The two live-SQL
security gates still do not run until OI-165 names a working token.

## Mutation ledger

Run after commit `a664844c` against the committed tree. Each row: the token
`grep -c` proved gone (or present, for the real-gate rows), the run, and the
restore (`git checkout -- <file>`; `git diff <file> | wc -l` → 0 every time).

| # | file | mutation | applied proof | reddened |
|---|---|---|---|---|
| M1 | `gate_scripts_wired_lib.dart` | `invokesGate` body → `return content.contains(gate);` | `final needle = 'run scripts/` 1 → 0 | **5**: invokesGate comment-only · prose-without-shape · case-skip; runnerViolations file-runner comment-only · prose-only |
| M2 | lib | `status == 'CLOSED'` → `'NEVER'` | `status == 'CLOSED'` 1 → 0 | **1**: manual runner citing a CLOSED OI |
| M3 | lib | `boardStatuses == null` branch body emptied (`else if` chain intact, compiles) | `OI board is unreadable` 1 → 0 | **1**: manual runner with an unreadable board |
| M4 | lib | `staleAllowlistViolations` → `const []` | `stale -- delete the entry` 1 → 0 | **1**: allowlist key with no script on disk |
| M5 | lib | delete the `caseSkipsOf(c).contains(gate)` arm | `case-skips it` 1 → 0 | **1**: loop runner for a case-skipped gate |
| M6 | `check_gate_scripts_wired.dart` | `manual('OI-101')` → `'OI-9999'` | `OI-9999` 0 → 1 | Gate 33 **FAIL exit 1**: `check_test_runtime_budget.dart: manual:OI-9999 names no OI on either board` |
| M6b | gate | `manual('OI-101')` → `'OI-172'` (CLOSED on `open_issues.md:3559`) | `manual('OI-172'` 0 → 1 | Gate 33 **FAIL exit 1**: `manual:OI-172 is CLOSED -- give the gate a real runner or re-file the blocker` |

Lib sum **9 of 22** (= the plan's expected 5+1+1+1+1). No mutation reddened
via a compile error (the runner printed test names, never `Error:`); none
reddened zero. After the last restore `git status --short` was empty and the
real gate returned to `PASS: all 108 gate/validator scripts covered`.
