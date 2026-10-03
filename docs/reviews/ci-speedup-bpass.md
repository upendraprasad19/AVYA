---
reviewed_at: 2026-08-10T17:40:00+05:30
staged_against: main...ci-speedup (0adffbd5 + the CI commit)
blast_radius: platform
reviewer: claude-sonnet-via-skill (fresh, context-blind)
lens_set: [yaml_correctness, job_name_breakage, sharding_correctness, precommit_shell, new_worktree_predicate, citation_replacement, secrets_in_tree, gate_self_consistency]
findings_count: 1
verdict: accepted
---

# Code Review (B-pass) — ci-speedup (platform)

Self-initiated before the `--no-ff` merge per §4.3. Required at ≥platform
(`check_plan_review_record_exists.dart:14-19` makes `bpass: accepted` unconditional there).

**No P0. No P1. One P2 — a real regression this batch INTRODUCED**, verified independently by the
main thread before acceptance and **fixed in this batch** (§4.2), with a test and a mutation proof.

## Finding 1 — P2 — new_worktree_predicate — FIXED

- **file:line:** `scripts/new-worktree.sh` (BASE-selection block)
- **claim:** The new logic guards `origin/main`'s existence but **not** local `main`'s. With
  `origin/main` present and local `main` absent, `LOCAL_SHA="$(git rev-parse main)"` exits 128 and
  `set -e` aborts the whole script — raw git error, no worktree created, no diagnostic. **The
  pre-diff code had no local-ref dependency at all** and handled that case fine, so this is a
  regression the fix introduced, not a pre-existing gap.
- **independently verified** (not accepted from the reviewer): a `set -e` script running
  `LOCAL_SHA="$(git rev-parse main)"` in a repo with no `main` branch exits **128** and never
  reaches the following line. A first attempt at this check redirected stderr into the variable,
  which masked the failure and made it look benign — re-run cleanly before accepting.
- **why it survived both plan-review rounds:** both caught the *remote*-missing asymmetry and
  neither considered the mirror case. The five original tests all assume a local `main` exists.
- **fix:** symmetric existence guard. No local `main` → use `origin/main` when reachable, else fall
  through and let `git worktree add` emit its own clear error rather than crashing on a bare
  `rev-parse`.
- **regression test:** `new_worktree_base_test.dart` — "NO LOCAL main (but origin/main exists)
  falls back to origin/main". 6/6 green.
- **mutation proof:** remove the local-`main` guard → **1 test red**.
- **severity rationale, accepted as stated:** P2 not P1 because `new-worktree.sh` resolves and `cd`s
  to the primary worktree root first, which by construction has always had a local `main` — so it
  cannot fire on the documented happy path. It is still a reproducible crash with a cryptic message
  if that invariant is ever violated.
- **status:** fixed

## Lenses clean — what was actually checked

- **YAML / Actions contexts.** `strategy.job-total` and `job-index` are documented contexts;
  `job-total` is a count, matching `--total-shards`' semantics. A job-level `env:` **can** read
  `secrets`, and a step's own `env:` is **not** visible to that step's `if:` — so hoisting is the
  technically correct repair for the supabase-tests bug, not a workaround. `yaml.safe_load` parses
  the file.
- **Job-name breakage.** `required_status_checks.contexts` confirmed `[]` live, so renaming
  `analyze-and-unit-test` → `analyze` + `unit-test (0..2)` cannot break a required check. No
  `needs:` anywhere; remaining name hits are historical prose.
- **Sharding correctness — the one that mattered most.** Read `test_core-0.6.16/runner.dart:496-508`
  at the pinned Flutter version: `shardEnd(i) == shardStart(i+1)` by construction, so every test
  lands in exactly one shard, no gaps or overlaps, including a 1-test/3-shard suite. Tag filtering
  is the argument to `_shardSuite`, so exclusion precedes partitioning.
- **pre-commit shell.** `if ! dart run …; then` is errexit-exempt. The gate is invoked explicitly
  AND still case-skipped in the loop, so no double-run. Counts recounted by hand: 86 files, 15 arms,
  71 in the loop, +2 explicit = 73 real coverage. Ran the gate flagless: PASS, exit 0.
- **Citations.** Both replacement anchors verified to exist in their target files.
- **Secrets.** Every hit is the `secrets` context keyword, never a value.
- **Gate self-consistency.** Gate 33 PASS (96 covered), Gate 40 PASS (24 closure files including
  this batch's), `check_gate_test_ledger` PASS, `check_no_deferral_euphemism` PASS. Confirmed
  `check_apk_release_signed.dart` really was absent from CI's old skip-list via
  `git show main:…`, and that bare-running it is harmless (`SKIP — APK not found`, exit 0) — so the
  batch's "cosmetic, not functional" characterisation is not overstated.

## Founder triage notes

Single finding accepted and closed in-batch with a regression test and a mutation proof. Nothing
carried forward. Verdict flipped to `accepted` on that basis.

Worth recording: this is the **third** consecutive review in this session where the fix for one
round's finding introduced the next round's finding — the symmetric-guard miss here is the same
shape as the gate-registry batch's three consecutive `isRegenerableIgnored` P0s. The pattern is
specific: adding a guard for the case you just hit, without asking what the *mirror* of that case
is.
