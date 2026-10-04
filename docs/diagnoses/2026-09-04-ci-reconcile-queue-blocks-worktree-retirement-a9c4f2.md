---
bug_id: a9c4f2
date: 2026-09-04
batch: ci-reconcile-retire
status: fixed
blast_radius: feature
related_bugs: [b4d7e9, f2a9c7, d7b3e9]
recurrence: >
  FOURTH instance in `regenerableIgnoredPaths`, and the THIRD in the unretirable direction.
  d7b3e9 (2026-08-10) built the list and the exact-match rule. f2a9c7 (2026-08-25, OI-128) found
  test outputs made any worktree that RAN the suite unretirable. b4d7e9 (2026-08-27) found the
  Stop hook's own marker did the same for any worktree that CLOSED a batch. This is the same
  shape for any worktree that has ever PUSHED.
symptom: >
  `dart run scripts/retire_worktree.dart` reports
  `KEEP readiness-flip [2 non-regenerable ignored file(s)]` for a worktree that is merged,
  tracked-clean and has nothing unpushed. The message states a COUNT and never a path, so the
  operator is told the worktree is unsafe to remove without being told what makes it unsafe. One
  of the two is `docs/mockups/`, which is genuinely precious and correctly blocks. The other is
  `.claude/.ci_reconcile_pending.jsonl` — a 222-byte queue holding two entries armed 2026-09-01,
  for a branch that has since merged with CI green.
concept: >
  A tool that WRITES INTO the worktree made the worktree permanently unretirable, for the third
  time. `safe_push.sh`'s LANDED path calls `arm_ci_reconcile.sh`, which appends one JSON line to
  `.claude/.ci_reconcile_pending.jsonl` in whatever worktree the push came from.
  `retire_worktree_lib.dart` treats any gitignored file absent from its exact-match
  `regenerableIgnoredPaths` list as PRECIOUS and refuses — correct by the predicate, wrong in
  effect.

  What makes this instance worse than its two predecessors is that the queue cannot self-clean.
  `reconcile_ci.dart` drains it at SessionStart and deletes the file when nothing survives, but
  `_statePath` is RELATIVE, so the drain only ever runs inside the worktree that armed the entry.
  A finished worktree is precisely the one no session reopens. The primary worktree holds no such
  file for the mirror-image reason: sessions start there constantly, so it drains every time.
sot_registry_entry: not_applicable
sot_registry_note: >
  Worktree retirement is operator tooling, not a data concept — no writer/reader pair in
  `docs/sot_registry.yaml`, no Hive key, no cloud column. §4.13 point 6 is its contract.
writers:
  - { file: scripts/arm_ci_reconcile.sh, method: "appends one branch/sha/armed_at line to .claude/.ci_reconcile_pending.jsonl; called from safe_push.sh's LANDED path, || true-wrapped", line: 47 }
  - { file: scripts/reconcile_ci.dart, method: "_writeState — writes the .tmp sibling then renameSync()s it over the queue; a crash between the two leaves the .tmp behind", line: 194 }
  - { file: .gitignore, method: "the two entries that make both files invisible to git status --porcelain, which is why leg 2 cannot see them and leg 3 exists", line: 86 }
readers:
  - { file: scripts/retire_worktree_lib.dart, method_or_widget: "regenerableIgnoredPaths — the exact-match list; anything absent is treated as precious", line: 236 }
  - { file: scripts/retire_worktree_lib.dart, method_or_widget: "isRegenerableIgnored — exact match after separator normalisation", line: 310 }
  - { file: scripts/retire_worktree_lib.dart, method_or_widget: "the KEEP message — reports a COUNT of non-regenerable ignored files, never their paths", line: 128 }
  - { file: scripts/ci_reconcile_state_lib.dart, method_or_widget: "keeps — true for stillPending ALONE, so every resolved or stale entry is dropped on the next drain", line: 105 }
hive_key_prefix: null
hive_key_formula: "not_applicable — no Hive involvement; the queue is a plain JSONL file on disk."
sync_methods: not_applicable — operator tooling, no cloud fan-out.
restore_methods: not_applicable — nothing is restored; safe_push.sh re-arms an entry on the next landed push.
cloud_table: none
cloud_columns: []
contract_test_path: test/scripts/retire_worktree_lib_test.dart
ist_handling:
  - { file: scripts/arm_ci_reconcile.sh, line: 45, fn: "not_applicable — armed_at is deliberately UTC because it is compared against GitHub Actions timestamps and a 48h staleness bound, never rendered as a user-facing date key. §4.5's IST rule governs date KEYS and counter resets; this is neither." }
provider_invalidations: none — no client state.
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  not_applicable, and worth stating because the surrounding rule is about isolation: §4.13's
  per-worktree index is what prevents cross-session mixing, and retirement removes a worktree only
  after its branch is merged. This fix widens what may be deleted by exactly two paths and does
  not touch the ownership model.
forbidden_patterns_checked: >
  - EXACT match preserved. The lib header records three review rounds that each found a P0 from
    looser matching. The new test pins that the .bak sibling, a nested backup/.claude/ copy, and
    the bare .claude/ directory all stay BLOCKING.
  - The kill switch `.claude/.reconcile_ci.disabled` is asserted to stay PRECIOUS. It lives in the
    same directory and has a near-identical name, but it exists only when a human deliberately
    created it, so destroying it would silently re-enable a subsystem someone turned off.
  - No pattern/glob entry added. `.claude/_payload_*.json` and `test/goldens/**/failures/` remain
    unclassifiable by an exact-match list, and the header's instruction for that case is to keep
    the worktree — inertness is recoverable, a deleted file is not.
proposed_fix: >
  Add BOTH `.claude/.ci_reconcile_pending.jsonl` and `.claude/.ci_reconcile_pending.jsonl.tmp` to
  `regenerableIgnoredPaths`. Neither is precious: retirement already requires the branch merged
  (leg 1) and nothing unpushed (leg 4), so any surviving entry is either resolved — which the
  drain drops saying nothing — or past the 48h bound on a branch CI never ran on, which
  `ci_reconcile_state_lib.dart:79` drops silently as well. The most that can be destroyed is a
  warning that was already unreachable.
regression_test_planned:
  - test/scripts/retire_worktree_lib_test.dart
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "No lib/ file touched; scripts/ tooling only." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No Hive box involved." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No rows touched." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron reads or writes the queue." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No table, no policy." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket." }
  - { tier: 10, name: secrets_api_keys, status: verified, evidence: "The queue holds branch names, git shas and UTC timestamps and nothing else — the live file was inspected in full (222 bytes, 2 lines). The exact-match rule is preserved precisely because two prior rounds destroyed real secrets via looser matching (.envrc, .envs/, supabase/.env), and the new test re-pins it." }
  - { tier: 11, name: external_services, status: verified, evidence: "GitHub Actions is the only external service in this path and is read-only via gh. Deleting a queue entry cannot affect a run; it only removes a local intent to ask about one." }
  - { tier: 12, name: client_to_server_contract, status: not_applicable, evidence: "No request shape changed." }
impact_analysis: >
  Product impact ZERO — no user-facing code path exists here. The cost is operational and
  compounding, and it is the same cost b4d7e9 measured: §4.13 point 6 exists because the worktree
  count reached 106 directories / 17 GB with no end-of-life rule, and its own text says
  "everything with a gate holds, everything on intention decays". Every worktree that has landed a
  push since the reconciler shipped is in the decaying half. Two are already affected
  (readiness-flip, debugging-stuck-issue-89b2e9); the second is currently masked behind an
  unmerged branch and would have surfaced the moment it merged.

  WHY IT WAS NOT CAUGHT. The tool's tests are thorough about the PREDICATE and silent about the
  LIST: they pin that dirty trees, ignored files and unpushed commits each block, and that
  near-miss paths do not inherit regenerability. Nothing asserts the list COVERS what the repo's
  own tooling writes into a worktree.

  b4d7e9 IDENTIFIED THIS EXACT DURABLE FIX AND IT WAS NEVER TRACKED. Its impact_analysis closes
  with "the durable fix is a test that walks .gitignore for paths written by scripts/ and asserts
  each is classified deliberately — filed as an observation rather than built here". It appears on
  no board: grep of docs/audit/OPEN_INDEX.md for gitignore/regenerab/retire/worktree returns
  OI-134/138/139/141, none of which is this. That is the
  feedback_spawn_task_chip_not_durable.md class — calling something filed without filing it — and
  it is the direct cause of this fourth instance.

  BUILT IN THIS BATCH on founder approval, rather than filed a second time.
  test/scripts/gitignore_classification_test.dart partitions every literal entry of every tracked
  .gitignore across `regenerableIgnoredPaths` and an explicit precious ledger, and fails when an
  entry belongs to neither. A new gitignored path that nobody has classified now reddens the suite
  at the moment it is ADDED — which is the moment all four instances were born, and the only point
  at which the author still has the context to answer the question. Scope is stated in the file
  header rather than implied: globs are out (an exact-match list can never accept one) and so are
  bare names in a NESTED .gitignore (git matches them at any depth, so no single exact path
  represents them).
mutation_evidence: >
  Rule 21 mutate-it-and-run-it, run twice because the fix has two independent legs and a single
  mutation would only have proven one. M1 deleted the `.jsonl` entry alone (verified applied:
  exact-match grep count 1 -> 0, with the .tmp entry confirmed still present at 1) — suite went
  36 passed -> 35 passed / 1 failed. M2 restored it and deleted the `.tmp` entry alone (verified
  applied the same way, counts inverted) — again 35 passed / 1 failed. Restored both and
  re-ran: 36/36 green, entry counts back to 1 and 1. Both mutations were confirmed to have
  actually applied before the run, per §4.4 rule 21's warning that a regex silently matching
  nothing makes a green run read as proof of nothing.

  The class-fix test was mutated three more times, because it was written by the same author as
  the fix and 5/5 green on a first run proves nothing on its own. M3 appended one unclassified
  literal to .gitignore — the exact shape of all four historical instances — and the completeness
  test reddened, naming the path. M4 deleted `deno.lock` from .gitignore, orphaning a precious
  ledger entry, and the orphan test reddened. M5 added `mockups/` to `regenerableIgnoredPaths`,
  which reddened BOTH the disjointness and matcher-agreement tests as predicted (-2). Each was
  reverted and the pair re-run: 41/41 green (36 + 5).

  ⚠ Worth recording because it nearly inverted a verdict: the applied-check for M3 was written as
  `grep -c '_some_new_tool_state'` when the literal was `.some_new_tool_state`, so it reported 0
  and read as "the mutation never applied". The mutation HAD applied — the test named the path in
  its failure message. Had the run gone the other way, that same wrong pattern would have made a
  green result read as proof. This is the precise failure §4.4 rule 21 warns about, met in the
  field, and the lesson is that the applied-check must be verified as carefully as the mutation.
---

# a9c4f2 — the CI-reconcile queue made every worktree that ever pushed unretirable

## What happened

`readiness-flip` was merged, tracked-clean and fully pushed, and `retire_worktree.dart` still
reported `KEEP readiness-flip [2 non-regenerable ignored file(s)]`. The message gives a count and
no paths, so the blocker had to be found by hand with
`git status --porcelain --ignored=matching`.

Two files. `docs/mockups/` holds two HTML design mockups and is genuinely precious — that half of
the refusal is correct and stays. The other is `.claude/.ci_reconcile_pending.jsonl`: two entries
armed on 2026-09-01 by `safe_push.sh`, for a branch that merged the same week with CI green on all
seven jobs.

## Why the refusal was correct and still wrong

The predicate did exactly what it was written to do. `git status --porcelain` excludes ignored
files and `git worktree remove` does not refuse on them, so leg 3 exists specifically to stop the
tool destroying gitignored work — a real P0 found in round 1 of d7b3e9. Anything not on the
exact-match list is precious by default, which is the correct direction to fail.

What was wrong is the list's coverage. It was enumerated from two producers — what
`new-worktree.sh` copies in, and Flutter build products — and later extended twice, each time
after a THIRD producer was discovered the same way this one was: by a worktree that would not
retire. `arm_ci_reconcile.sh` is the fourth such producer and nobody added its path.

## Why this instance cannot heal itself

The other three producers rewrite their file on the next run, so a stale copy is merely stale. The
reconcile queue is different: it is drained by `reconcile_ci.dart` at SessionStart, and the drain
deletes the file outright when no entry survives. So the queue would clean itself up — except
`_statePath` is relative, so the drain only runs in the worktree that armed the entry, and a
finished worktree is exactly the one no session reopens.

The primary worktree demonstrates the mirror: it holds no queue file at all, because sessions
start there constantly and drain it every time. The bug is not that the queue is never cleaned; it
is that it is only ever cleaned where it does not matter.

## The fix

Two entries, not one. `_writeState` writes `<path>.tmp` and then renames it, so a process dying
between the two leaves a gitignored file with the identical blocking property. Fixing only the
file that was reported would have left the same bug reachable by a narrower path — the
`guard_without_its_mirror` shape the review lens exists to catch.

The exact-match rule is untouched, and the new test pins the neighbour that must NOT inherit
regenerability: `.claude/.reconcile_ci.disabled`, the reconciler's kill switch. It sits in the
same directory under a near-identical name, but it exists only because a human deliberately
created it. Destroying it would silently re-enable a subsystem someone had turned off.
