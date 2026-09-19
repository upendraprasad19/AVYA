---
branch: gate-integrity
blast_radius: platform
review_rounds: 3
mechanical_only: true
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/gate-integrity-bpass.md
tier: standard
date: 2026-09-19
---

# Plan review — `gate-integrity` (OI-220 · OI-155 · OI-195 · OI-181)

Batch A of the 2026-09-19 sequence A → B (OI-204 delta sync) → C (OI-154 profile tombstone).
Four gate fixes with zero file overlap, one platform-tier batch. Spec:
`docs/superpowers/specs/2026-09-19-gate-integrity-design.md` (v4, D1–D17). Plan:
`docs/superpowers/plans/2026-09-19-gate-integrity.md` (v4). Closure ledger:
`docs/audit/gate-integrity.closure.yaml` (U1–U5 + I1, Gate 40 `--strict` PASS).

`mechanical_only: true` refers to ROUND 3 (the round that closed the record): every one of its
eight findings was count drift or wording. Rounds 1 and 2 were material. `mechanical_only` is
read by `scripts/batch_process_telemetry_lib.dart:51` only; the keystone gate reads
`review_rounds` (3 ≥ 2), `ground_truth_verified`, `verdict`, `bpass`, `bpass_review`.

## Review rounds (context-blind, `docs/agent_brief_preamble.md` prefixed)

| Round | Scope | Findings | Material | Result |
|---|---|---|---|---|
| 1 | plan v1 (`d271c898`), two reviewers: registry units 220+195 / hook units 155+181 | 23 | 2 P0 | `not-converged` → v2 `6b879e60` |
| 2 | plan v2, same split | 19 | 1 (registry rule) | hooks units converged; registry rule corrected → v3 `6582c78e` |
| 3 | scoped to the v2→v3 diff, one reviewer | 8 | 0 (all mechanical) | `converged` → v4 `b2435ef5` |

**Round-1 P0s, both caught before a line of implementation was written:**
- **Recursion (hooks).** `test/scripts/pre_push_analyze_always_e2e_test.dart` runs the REAL
  `pre-push.sh` with a POSIX-form stub `flutter` on PATH; the sweep's Dart
  `Process.runSync('flutter', …, runInShell: true)` goes through cmd.exe, which cannot execute an
  extensionless stub and runs the REAL flutter → nested `flutter test` → the e2e → the hook → the
  sweep → … `Process.runSync` blocks the isolate so `@Timeout` cannot fire. Fix: `CONTRACT_SWEEP_NESTED=1`
  set on the sweep's own spawn + `CONTRACT_SWEEP_SKIP=1` kill switch set by that e2e (D4/D5).
- **Inert registry regex (registry).** The v1 lib matched `^\s+file:\s*(\S+)`; the real registry has
  896 `- file:` list items + 176 `- { file: … }` inline maps and ZERO bare `file:` lines, so arm (a)
  selected nothing. Fix: `(?:^|[\s{-])file:\s*([^\s,}]+)`, `grep -c`-proven against the real file
  (memory `feedback_mistake_plan_code_never_compiled`, instance 2).

**Round-2 material correction (registry):** round 1's directory→extension change to `isDocLike`
re-created the class it fixed — it dropped the board readers (`open_issues.md` → 10 test files,
`sync.md` → 29). v3 exempts `docs/audit/` and `docs/architecture/` from the `.md` exclusion. Round 2
also probed and DISPROVED a round-1 claim v2 had adopted ("a cherry-pick runs pre-commit" — a
clean pick runs none; `--continue` does), and measured the sweep's cost line (1.9 s / 17 tests on
15 files; 18.5 s / 505 on 366).

**Round 3 (mechanical, eight):** `sync.md` reader count 39→29 and `closed_issues.md` 7→8
(re-measured by the coordinator: `git grep -l -F <name> -- test/ | wc -l`); the stated reason for
excluding `CLAUDE.md` was wrong (77 test files reference it — the real reasons are over-selection
and its platform pin); `unmapped` semantics for prose inside the contract-doc dirs pinned by a
`buildSelection` case; Task 2 Step 7(b) spelled against `mergedBoardStatuses`' real non-nullable
signature; Step 9(b) named the `:142` placement scenario; Step 12's expected mutation sum (≥ 9)
stated; intra-document v2 drift cleared; `GIT_EDITOR=true` on the cherry-pick recipe.

## Ground truth

Every file:line in spec §1 was read from the worktree by this session or re-measured by a
reviewer with the command shown; corrections are marked ⚠ in the spec. Coordinator re-measured
before folding round 3: `sync.md` 29, `closed_issues.md` 8, `CLAUDE.md` 77, `docs/audit/*.md`
61 with 56 zero-reader, `functionality-flow.md` / `subscription.md` 0. Counts re-derived on the
INTEGRATED tree for CLAUDE.md: `ls scripts/check_*.dart | wc -l` = 97; pre-commit case-skip block
13 entries (loop 84; 86 of 97 with the two explicit invocations; 87 on a merge); test.yml skip
block 11; `grep -cE '^\s+presence_only:\s*true' docs/sot_registry.yaml` = 17; safe_merge tests 15.

## Execution (§4.12.7 — decided at batch start: subagent-driven)

Four forks, `isolation: worktree`, one per unit, each committing on its own branch via
`safe_commit.sh`; coordinator integrated by cherry-pick (INDEX.md conflicts on the 2nd/3rd fix
picks resolved by `build_bug_index.dart` regen + `GIT_EDITOR=true git cherry-pick --continue`,
which ran the full gate loop each time) and was the single writer of every shared file. Two forks
(OI-155, OI-181) were terminated by an API rate limit mid-contention-run — AFTER their commits and
mutation cycles, with clean worktrees; their ledgers are in their commit messages / diagnose-docs
and the contention totals come from the coordinator's own run below.

## Mutation ledgers (observed reds, not expected)

| Unit | Mutations | Reds | Coordinator re-ran by hand |
|---|---|---|---|
| OI-220 (`feat`, rule-21 proof; no ledger entry by design) | 6 lib/runner + 1 un-wiring | 1+2+2+1+2+1 = 9, +2 | null-grep → `continue`: 1 red |
| OI-155 (`b3e7a1`) | 5 lib + 2 real-gate | 5+1+1+1+1 = 9 of 22; both real-gate → FAIL exit 1 | OI-9999 target → FAIL naming it; CLOSED→NEVER: 1 red / 21 green |
| OI-195 (`c7d2e4`) | 4 + M5 (hardening) | 7+1+1+2 = 11, +1 | sibling-key regex: 1 red; M5 revert to `File.existsSync`: 1 red / 9 green |
| OI-181 (`b7e2d4`) | 3 | 1+2+1 = 4 | three-dot → two-dot: 1 red / 14 green |

Every mutation: `grep -c` proved it applied, the file compiled, restore left a 0-line diff. No
zero-red and no compile-error reds. The OI-195 test count rose 9 → 10 at integration (directory
citation, written RED first: `[file-missing] eta: presence_only cites `test/contracts/` which does
not exist`).

## Tests

Targeted: `contract_sweep_lib_test` 10 · `contract_sweep_e2e_test` 7 · `contract_sweep_wired_test`
1 · `pre_push_analyze_always_e2e_test` 3 · `gate_e2e_env_hermetic_test` 12 (sweep e2e registered;
Gate 42 test deliberately not — its fixture calls no git) · `gate_scripts_wired_runners_test` 22 ·
`gate_wiring_args_required_test` 5 · `apk_release_signed_gate_test` 12 ·
`sot_behavioral_test_paths_gate_test` 10 · `safe_merge_test` 15. Real-tree gates: Gate 33 PASS,
Gate 42 PASS (`138 + 4 paths resolved on disk`), ledger PASS (97 gates), Gate 40 `--strict` PASS,
citations PASS, context-artifact budget PASS (3 within band). Contention:
`flutter test test/scripts/` on the integrated branch = **739 passed, 0 failed** (55 files, 7m29s).
Full suite: platform-tier pre-push + CI at the merge/push.

## B-pass

`docs/reviews/gate-integrity-bpass.md` — fresh context-blind Sonnet, own worktree, against
`a566f94c`. **SHIP-WITH-FIXES → both findings fixed in `e993a345`, `verdict: accepted`, 0
false_alarm.** 8 skill lenses + 7 batch lenses (L24/L37/L52/L25/L20/L8/L54), every clean lens
listed with the command that cleared it; the reviewer ran the full pre-commit loop and every
touched test file itself and re-derived every cross-document count.
- **F1 (P2)** `invokesGate` treated printed text (heredoc body, invoker-less prose) as an
  invocation — the hardening `extractCaseSkips` carried one function above had not travelled.
  Fixed: invoker-prefixed match + heredoc-body skipping; two RED-first tests + two mirrors (22 →
  26); two mutations each redden exactly their own test; Gate 33 still PASS on the real tree.
- **F2 (P3)** `0768a0ce` dated 09-18 in three documents (it is 2026-09-19 00:34 IST). Fixed in
  all three plus spec and plan; `git grep 0768a0ce | grep 09-18` → 0.
Closure ledger: U1–U5, I1, BP-1, BP-2 — `total: 8`, `closed_count: 8`, Gate 40 `--strict` PASS.
Skill tuning entry: `.claude/skills/code-review/SKILL.md` **2026-09-19 (b)** (five tunings).
