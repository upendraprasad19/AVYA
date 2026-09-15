---
bug_id: b4d7e9
date: 2026-08-27
batch: oi98-notification-prefs
status: fixed
blast_radius: platform
symptom: >
  `dart run scripts/retire_worktree.dart` reports
  `KEEP <slug> [1 non-regenerable ignored file(s)]` for a worktree that is merged, has no tracked
  changes and nothing unpushed. Nothing names the file — the message states a count, not a path —
  so the operator is told the worktree is unsafe to remove without being told why. Every worktree
  where a batch has closed since 2026-08-25 is in this state, and none of them can ever retire.
concept: >
  A tool that WRITES INTO the worktree made the worktree permanently unretirable. §5's `Stop` hook
  drops `.claude/.batch_close_state` — its once-per-HEAD marker — into whichever worktree the batch
  closed in. `retire_worktree_lib.dart` classifies any gitignored file that is not on its
  exact-match `regenerableIgnoredPaths` list as PRECIOUS and refuses. The marker was not on that
  list, so the refusal was correct by the predicate and wrong in effect.
sot_registry_entry: not_applicable
sot_registry_note: >
  Worktree retirement is operator tooling, not a data concept: it has no writer/reader pair in
  `docs/sot_registry.yaml` and touches no Hive key or cloud column. §4.13 point 6 is its contract.
writers:
  - { file: scripts/batch_close_hook.dart, method: "_statePath — writes .claude/.batch_close_state, 41 bytes holding one sha, rewritten on every fire", line: 29 }
  - { file: .gitignore, method: "the entry that makes the marker invisible to `git status --porcelain`, which is why leg 2 cannot see it and leg 3 exists", line: 188 }
readers:
  - { file: scripts/retire_worktree_lib.dart, method_or_widget: "regenerableIgnoredPaths — the exact-match list; anything absent from it is treated as precious", line: 236 }
  - { file: scripts/retire_worktree_lib.dart, method_or_widget: "isRegenerableIgnored — exact match after separator normalisation", line: 269 }
  - { file: scripts/retire_worktree_lib.dart, method_or_widget: "the KEEP message — reports a COUNT of non-regenerable ignored files, never their paths", line: 128 }
hive_key_prefix: null
hive_key_formula: "not_applicable — no Hive involvement; the marker is a plain file on disk."
sync_methods: not_applicable — operator tooling, no cloud fan-out.
restore_methods: not_applicable — nothing is restored; the hook rewrites the marker on its next fire.
cloud_table: none
cloud_columns: []
contract_test_path: test/scripts/retire_worktree_lib_test.dart
ist_handling:
  - { file: scripts/batch_close_hook.dart, line: 29, fn: "not_applicable — the marker holds a git sha, not a date; no IST surface exists in this path." }
provider_invalidations: none — no client state.
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  not_applicable, and worth stating because the surrounding rule is about isolation: §4.13's
  per-worktree index is what prevents cross-session mixing, and retirement removes a worktree only
  AFTER its branch is merged. This fix widens what may be deleted by exactly one path and does not
  touch the ownership model.
forbidden_patterns_checked: >
  - EXACT match preserved. The lib header records three review rounds that each found a P0 from
    looser matching: prefix matching let `.env` match `.envrc` and `.envs/`; basename-at-any-depth
    let it match `supabase/.env`, which a sibling suite asserts MUST be regenerable. The new test
    pins that `.batch_close_state.bak`, `settings.local.json` and a nested copy all stay BLOCKING.
  - No pattern/glob entry added — the header's own instruction for a pattern case is to keep the
    worktree instead, because inertness is recoverable and a deleted file is not.
proposed_fix: >
  Add `.claude/.batch_close_state` to `regenerableIgnoredPaths`, with a test asserting it is
  regenerable and that its neighbours are not. The marker is 41 bytes holding one sha and the hook
  rewrites it whenever it fires, so it is reconstructible by definition — it is not user work.
regression_test_planned:
  - test/scripts/retire_worktree_lib_test.dart
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "No lib/ file touched; this is scripts/ tooling." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No Hive box involved." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No rows touched." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron reads or writes the marker." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No table, no policy." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket." }
  - { tier: 10, name: secrets_api_keys, status: verified, evidence: "The marker holds a git sha and nothing else (41 bytes, inspected). The exact-match rule is preserved precisely because two prior rounds destroyed real secrets via looser matching — `.envrc`, `.envs/`, `supabase/.env`." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "Local tooling only." }
  - { tier: 12, name: client_to_server_contract, status: not_applicable, evidence: "No request shape changed." }
impact_analysis: >
  Product impact ZERO — no user-facing code path exists here. The cost is operational and
  compounding: §4.13 point 6 was written because the worktree count reached 106 directories /
  17 GB with no end-of-life rule, and its own text says "everything with a gate holds, everything
  on intention decays". This defect silently converted the gated half back into the decaying half.
  From 2026-08-25 (when the Stop hook shipped) every worktree in which a batch closed became
  permanently unretirable, and the §5 checklist row — the only trigger for retirement — would have
  reported KEEP forever while looking like it was working.

  WHY IT WAS NOT CAUGHT BY THE TOOL'S OWN TESTS. They are thorough about the PREDICATE and silent
  about the LIST: they pin that dirty trees, ignored files and unpushed commits each block, and
  that near-miss paths do not inherit regenerability. Nothing asserts the list COVERS what the
  repo's own tooling writes into a worktree. OI-128 fixed the same shape for test outputs two
  weeks earlier; this is that gap recurring for a newer writer, which suggests the durable fix is a
  test that walks `.gitignore` for paths written by `scripts/` and asserts each is classified
  deliberately — filed as an observation rather than built here, because it is a different unit of
  work with its own design questions.

  ⚠ MY OWN MISDIAGNOSIS, recorded so the next reader does not repeat it. I first reported
  `test/plan_generator/v4_diagnostic_output.md` as the blocker and as a gap in this list. It is
  NEITHER — OI-128 had already added it. The KEEP message reports a COUNT and not a PATH, and
  rather than reading the list I inferred which file it must be, deleted the wrong one (harmless:
  regenerable, and `main` held a newer copy), and re-ran to find the tool still refusing. Reading
  `regenerableIgnoredPaths` took one command and settled it immediately. Same class as
  `feedback_green_check_input_set_width`: I answered from the shape of the message instead of from
  the data behind it. It also names a cheap improvement to the tool — print the offending PATHS,
  not a count — since the count is precisely what makes the message unactionable.
---

# b4d7e9 — the Stop hook's own marker made every worktree unretirable

## What happened

`retire_worktree.dart` refused a worktree that was merged, clean and fully pushed, reporting
`1 non-regenerable ignored file(s)`. The file was `.claude/.batch_close_state`: 41 bytes holding a
single git sha, written by the §5 `Stop` hook (`batch_close_hook.dart:29`) and rewritten every time
it fires.

## Why the refusal was correct and still wrong

`retire_worktree_lib.dart` treats any gitignored file absent from `regenerableIgnoredPaths` as
precious. That rule exists because a merged worktree holding an ignored `secrets/.env` was once
removed with exit 0 and the file destroyed. The predicate did exactly what it should; the list was
one entry short.

The compounding part is that the missing entry is written by the repo's **own** hook, into
**every** worktree where a batch closes — so the refusal was not a one-off, it was permanent and
universal from the day that hook shipped.

## The fix

One exact-match entry plus a test that also pins the near-misses (`.batch_close_state.bak`,
`settings.local.json`, a nested copy) as still blocking. Mutation-proven: removing the entry
reddens the test.

**Not** widened to a glob. The lib header records three review rounds where looser matching
destroyed real secrets, and its standing instruction for a pattern case is to keep the worktree
instead — inertness is recoverable, a deleted file is not.
