---
bug_id: 8f3e35
date: 2026-10-21
batch: hook-cwd-fail-open (OI-384)
status: fixed
tier: l_fix
blast_radius: platform
related_bugs: [f2a9c7, b4d7e9, a9c4f2, d7b3e9]
recurrence: >
  Two halves, one new and one recurring. The retirement half is the FIFTH instance of "a tool
  writes a gitignored file into a worktree, and retirement refuses it": f2a9c7 (test output,
  OI-128), b4d7e9 (`.claude/.batch_close_state`), a9c4f2 (`.claude/.ci_reconcile_pending.jsonl`),
  and the `.gate_failures.log` entry (recorded in the lib as the fourth, no id of its own).
  d7b3e9 built the exact-match rule all of them were fixed under, and this fix keeps it (one exact
  entry). The hook half is NEW: docs/diagnoses/INDEX.md has no entry for hooks and the working
  directory (searched by token: `settings.json`, `hook`, `CLAUDE_PROJECT_DIR`, `cwd`; and by
  concept: fail open, guard did not run, exit 255).
symptom: >
  `retire_worktree.dart` reported `KEEP oi341-piece-b2-door [1 non-regenerable ignored file]` for
  a merged, clean, pushed worktree. The file was
  `supabase/functions/.dart_tool/native_assets.yaml`. Tracing who wrote it found the bigger defect:
  the Claude Code hooks in `.claude/settings.json` were all relative (`dart run scripts/<name>.dart`)
  and the harness runs a hook in the session's CURRENT directory. From any subdirectory, `dart`
  could not find the script, exited 255 (a NON-blocking error), and the tool call went ahead. So
  every hook, including the PreToolUse git-safety guard that blocks raw `git commit` / `git push`,
  silently did not run while the shell sat in a subdirectory. dartdev also wrote
  `<cwd>/.dart_tool/native_assets.yaml` each time, which is the file that blocked retirement.
concept: >-
  hook_command_root_resolution - a hook command resolves its script from the checkout root, never the
  shell's cwd; a hook that cannot start exits non-2, which the harness reads as allow.
note_external_reader: >
  The primary reader is external and has no file:line here: the Claude Code harness runs each command
  via `sh -c` in the session's current directory, and treats exit 2 as block and any other non-zero
  as non-blocking.
sot_registry_entry: not_applicable
sot_registry_note: >
  Harness wiring and operator tooling, not a data concept: no Hive key, no cloud column, no
  writer/reader pair in docs/sot_registry.yaml. The contract lives in docs/architecture/hooks.md.
writers:
  - { file: .claude/settings.json, method: "the nine hook command strings (SessionStart x3, UserPromptSubmit, PreToolUse Bash / Write|Edit / Skill, Stop, SessionEnd); each now resolves the checkout root before `dart run`", line: 12 }
  - { file: scripts/git_safety_hook.dart, method: "the advisory plan-review precheck: existence check and workingDirectory now use precheckRoot(cwd), not the payload cwd", line: 222 }
  - { file: scripts/git_safety_lib.dart, method: "precheckRoot — pure: the git toplevel when it holds the script, else cwd; null or empty toplevel keeps cwd", line: 412 }
  - { file: scripts/retire_worktree_lib.dart, method: "regenerableIgnoredPaths gains the exact entry supabase/functions/.dart_tool/", line: 256 }
readers:
  - { file: scripts/git_safety_hook.dart, method_or_widget: "the block path, exit(2); only reachable if the hook process starts", line: 80 }
  - { file: scripts/retire_worktree.dart, method_or_widget: "git status --porcelain --ignored=matching, counts every !! path isRegenerableIgnored rejects", line: 288 }
  - { file: scripts/retire_worktree_lib.dart, method_or_widget: "isRegenerableIgnored — exact match", line: 330 }
  - { file: test/scripts/reconcile_ci_wiring_test.dart, method_or_widget: "contains('scripts/reconcile_ci.dart') on the SessionStart command; still satisfied by the new form", line: 47 }
hive_key_prefix: null
hive_key_formula: "not_applicable — no Hive involvement."
sync_methods: not_applicable — operator tooling, no cloud fan-out.
restore_methods: not_applicable — nothing is restored.
cloud_table: none
cloud_columns: []
contract_test_path: test/scripts/claude_hooks_cwd_independent_test.dart
ist_handling:
  - { file: .claude/settings.json, line: 12, fn: "not_applicable — no date keys or counters." }
provider_invalidations: none — no client state.
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: >
  not_applicable (no user data). The nearest analogue is cross-CHECKOUT: after the session `cd`s
  into any checkout that holds `scripts/<hook>.dart`, the hooks run that checkout's copy. That was
  already true at such a checkout's root; it now also holds from its subdirectories. Stated as an
  exposure note in docs/architecture/hooks.md. CLAUDE_PROJECT_DIR-first would avoid it but would
  make a worktree session run the PRIMARY's copy, which §4.13's flow relies on not happening.
forbidden_patterns_checked: >
  - `cd "$r" && dart …`: REJECTED. /bin/sh here is dash, and dash's failed `cd` exits 2, which
    the harness reads as BLOCK, so a missing root would block every tool call. The form uses
    `cd "$r" || exit 1;` (non-blocking). Pinned by C6 and mutant M4b (red under dash).
  - `|| true` after dart, or `</dev/null`: REJECTED. The first swallows the guard's exit 2, the
    second starves the hook of its stdin payload. Mutants M3 and M9.
  - Root from `--git-common-dir` (the primary): REJECTED. A linked worktree must run its OWN copy.
    Mutant M5b.
  - A glob or `endsWith('/.dart_tool/')` retirement rule: REJECTED (d7b3e9's exact-match rule; three
    review rounds each found a P0 from looser matching). Mutant M7. `vendor/.dart_tool/` and
    `supabase/functions/x/.dart_tool/` stay precious.
  - Making a CRASHING hook fail closed: out of scope and deliberate. A compile error would then block
    every Bash call, including the fix (hooks.md fail-open rule).
proposed_fix: >
  (1) Every hook command becomes
  `r=$(git rev-parse --show-toplevel 2>/dev/null); [ -n "$r" ] && [ -f "$r/scripts/<x>.dart" ] || r="${CLAUDE_PROJECT_DIR:-.}"; cd "$r" || exit 1; dart run [--verbosity=error ]scripts/<x>.dart`.
  The checkout root wins (a linked worktree resolves to the worktree); a nested repo without the
  script, no git, or a directory outside any repo falls back to CLAUDE_PROJECT_DIR, then `.`; a
  missing root exits 1 (non-blocking); dart is the last command so its exit 2 still blocks; the
  stdin payload reaches dart. Cost measured 2.3 ms per call (20 runs). Needs a POSIX shell: on
  Windows without Git Bash the harness falls back to PowerShell, which does not parse this form
  (non-blocking, hooks skipped); the repo's git hooks already require Git Bash (hooks.md,
  FRESH_CLONE.md), so the dependency is not new, and an OI-348 founder check confirms it on the
  Windows clone. (2) `git_safety_hook.dart`'s plan-review precheck had the same defect internally
  (it used the payload cwd): it now resolves the root through the pure `precheckRoot`. (3)
  `supabase/functions/.dart_tool/` joins `regenerableIgnoredPaths` as one exact entry; with (1),
  dartdev no longer writes there from hooks, and the entry clears worktrees that already carry it.
regression_test_planned:
  - test/scripts/claude_hooks_cwd_independent_test.dart
  - test/contracts/git_safety_lib_test.dart
  - test/contracts/git_safety_hook_integration_test.dart
  - test/scripts/retire_worktree_lib_test.dart
touched_layers_checked:
  - { tier: 1, name: client_code, status: not_applicable, evidence: "No lib/ file touched; .claude/settings.json and scripts/ tooling only." }
  - { tier: 2, name: hive_local_state, status: not_applicable, evidence: "No Hive box involved." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No DDL." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No rows touched." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "supabase/functions/ is only the directory the stray cache landed in; no function changed." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No table." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket." }
  - { tier: 10, name: secrets_api_keys, status: verified, evidence: "native_assets.yaml is a dartdev build cache (no secret); the retirement entry is exact, so supabase/.env and other precious ignored files stay blocking (near-miss tests)." }
  - { tier: 11, name: external_services, status: verified, evidence: "The external dependency is the Claude Code harness: its hook contract (cwd, sh -c, exit 2 = block, CLAUDE_PROJECT_DIR, stdin cwd) was read from code.claude.com/docs/en/hooks on 2026-10-21 and measured on this VPS (mtime test 17:09 UTC; exit 255 by hand)." }
  - { tier: 12, name: client_to_server_contract, status: fixed_in_this_batch, evidence: "Harness -> hook contract: every command now starts from the checkout root; C3-C9 and C11 in test/scripts/claude_hooks_cwd_independent_test.dart run each real command under sh (dash) and /bin/bash from subdirectories, a linked worktree, a nested repo and outside any repo." }
impact_analysis: >
  Product impact zero (no app code path). Process impact high: while the shell sat in a
  subdirectory, the git-safety guard, the memory write guard, the discipline hot-set, the §5 Stop
  checklist and the session-release hook were all silently off. Transcript audit
  (scratchpad hook_cwd_audit.py, heuristic over `cd` tokens, not a proof): 19 transcripts, 253 Bash
  calls issued from a project subdirectory, 2 matching a risky git pattern (commit, push,
  reset --hard, clean -f, rebase, merge, the bypass flag, gh pr merge), both Python heredocs whose
  TEXT mentions `git commit` (session 8bb48e85, 2026-09-29, migration-ledger-integrity); neither ran
  git. No raw git landed through the unguarded window. `.opencode/plugins/discipline.ts` invokes
  its own scripts with an explicit root cwd and is unaffected. WHY IT WAS NOT CAUGHT: no test ever
  ran a hook command as the harness does (from a directory other than the root); the hook unit
  tests call the Dart entry points directly from the root.
mutation_proof: >
  18 mutants applied to the REAL files by mutate_hookcwd.py (scratchpad), each an exact-one-match
  replace computed before any write, applied=True checked by re-reading, restored in a finally,
  byte-compared after (OK). 18/18 red, 0 survivors: settings M1 relative form, M2 drop the
  CLAUDE_PROJECT_DIR arm, M3 `|| true`, M4 `;` after cd, M4b `&&` after cd (red under dash), M5
  fallback only, M5b --git-common-dir root, M8 drop the [ -f ] check, M9 `</dev/null`, M11 swap the
  Bash and Write|Edit scripts, M12 unquoted $r; precheck M10 precheckRoot returns cwd (2 red), M10a
  existence check on cwd, M10b workingDirectory cwd, M10c no trim, M10d no empty rejection;
  retirement M6 entry removed, M7 endsWith (2 red). The new hook test also kills the same mutants as
  META cases inside the suite. Equivalent and stated, not claimed: M2b (drop `:-.`; `cd ""` stays
  put under dash and bash) and C10 (empty toplevel; the real filesystem has no /scripts).  B-pass fixes (docs/reviews/hook-cwd-fail-open-bpass.md), proven the same way: C11's payload cwd moved to the
  non-repo fixture (B-pass P1: the real hook waives a raw commit while MERGE_HEAD exists in the payload cwd, so C11
  pointed at the live repo went red mid-merge, when pre-commit's regression-catalog walk runs it); with a MERGE_HEAD
  written into this worktree's git dir the fixed C11 is green and the old cwd 1 red (MERGE_HEAD removed after).
  N1 (no newline check) and N2 (no lone-& check) in the safety rule: 1 red each. N3 (precheck with an absolute
  script path but workingDirectory cwd), against the now end-of-line anchored ROOT assertion: 1 red. Self-attested.
---

# 8f3e35 — Claude Code hooks did not run when the shell sat in a subdirectory

## What happened

`oi341-piece-b2-door` was merged, clean and pushed, and retirement still refused it over one
ignored file, `supabase/functions/.dart_tool/native_assets.yaml`. That file is a dartdev cache. The
question was who ran `dart` from `supabase/functions`.

The answer was the harness. Claude Code runs every hook in the session's current directory, and the
Bash tool's `cd` persists between calls. Every hook in `.claude/settings.json` was
`dart run scripts/<name>.dart`, relative. From `supabase/functions`, dart printed
``Could not find file `scripts/git_safety_hook.dart` `` and exited 255. The harness treats only
exit 2 as a block; 255 is a non-blocking error, so the tool call went ahead. dartdev had already
written `<cwd>/.dart_tool/native_assets.yaml`. Measured 2026-10-21 17:09 UTC: a `cd` call, then the
next call's PreToolUse hook rewrote that file 0.4 s before the call's own output.

## Why it matters more than the retirement block

Every hook was off from any subdirectory, including the guard that blocks raw `git commit` and
`git push`. The audit found no raw git that went through the gap, but nothing would have stopped it.

## The fix

1. Each hook command resolves the checkout root first (git toplevel when it holds the script,
   else `CLAUDE_PROJECT_DIR`, else `.`), `cd`s there with a non-blocking `|| exit 1`, then runs dart
   as the last command so its exit code is the hook's.
2. The git-safety hook's own plan-review precheck had the same defect against the payload cwd; it
   now uses the pure `precheckRoot`.
3. Retirement accepts the exact path `supabase/functions/.dart_tool/`.

## Tests

`test/scripts/claude_hooks_cwd_independent_test.dart` runs every real command under dash and bash
with a stub `dart` against fixtures: a repo, a decoy `CLAUDE_PROJECT_DIR`, a linked worktree, a nested
repo, and a non-repo directory, all under paths with spaces. C11 runs the real git-safety guard
from `supabase/functions` and sees it block a raw commit, and shows the old form exited 255.
