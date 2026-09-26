---
bug_id: c8d5b2
date: 2026-09-23
batch: discipline-v3-phase3
status: fixed
blast_radius: platform
symptom: |
  scripts/discipline_hook.dart's SessionStart hook is supposed to warn when
  the harness MEMORY.md index exceeds its soft byte/line cap, nudging
  /consolidate-memory. Live-tested 2026-09-23 while building an unrelated
  memory write-guard hook that needed the SAME path-resolution logic: the
  nudge's path derivation used `Directory.current.path`, which in this
  worktree resolves to
  ".../.claude/worktrees/supabase-outage-check-e79200" — not the harness's
  actual memory directory, which is keyed on the PRIMARY repo root
  ("C--Upendra-Claude-Code-Fitness-App", no worktree suffix). Every session
  works in a linked worktree per CLAUDE.md §4.13, so this mangled to a
  directory that never exists, `File(path).existsSync()` was always false,
  and the nudge silently never fired from ANY worktree session. No founder
  report triggered this — found by code inspection while building unrelated
  functionality, not by a live symptom.
concept: discipline_hook_memory_index_nudge
sot_registry_entry: |
  Not a new concept. scripts/batch_close_lib.dart already solved this exact
  class for scripts/batch_close_hook.dart (see that file's own header, "the
  --show-toplevel-vs-git-common-dir bug"), and its `primaryRootFrom` /
  `mangleProjectPath` functions are the fix — this diagnose is discipline_
  hook.dart adopting a fix that already existed elsewhere in the repo but was
  never applied here. No SoT registry entry needed (this is harness-internal
  path resolution, not a Hive/cloud writer-reader contract).
writers:
  - { file: scripts/discipline_hook.dart, method_or_widget: "resolveMemoryIndexPath", line: 163 }
readers:
  - { file: scripts/discipline_hook.dart, method_or_widget: "_memoryIndexNudge — calls resolveMemoryIndexPath, then File(path).existsSync()", line: 182 }
hive_key_prefix: "N/A — infra/tooling fix, no Hive involvement"
hive_key_formula: "N/A"
sync_methods:
  - "N/A — no cloud sync involved"
restore_methods:
  - "N/A"
cloud_table: "N/A — no cloud table involved"
cloud_columns:
  - "N/A"
contract_test_path: test/scripts/discipline_hook_memory_path_test.dart
ist_handling:
  - "Not applicable — no date offsets within this fix."
provider_invalidations:
  - "N/A — no Riverpod providers involved"
telemetry_op_types:
  success:
    - "N/A"
  failure:
    - "N/A"
cross_account_guard: "N/A — this is a harness-local SessionStart hook with no per-user data access."
forbidden_patterns_checked:
  - { pattern: "mangling Directory.current.path (the worktree path) instead of --git-common-dir's derived primary root", absent: true }
proposed_fix: |
  Extracted the path derivation into a new, pure, public function
  `resolveMemoryIndexPath({override, home, gitCommonDirOutput})` that:
  1. Honours the DISCIPLINE_HOOK_MEMORY_PATH override (unchanged behaviour).
  2. Otherwise resolves the PRIMARY repo root via
     `batch_close_lib.dart`'s `primaryRootFrom(gitCommonDirOutput)` — the
     same function `scripts/batch_close_hook.dart` already uses correctly —
     then mangles it with `mangleProjectPath`, matching the harness's own
     directory-naming convention exactly.
  `_memoryIndexNudge()` now calls `git rev-parse --path-format=absolute
  --git-common-dir` (mirroring `_worktreeWarning()`'s existing pattern in the
  same file) and passes its output through the new pure function, instead of
  mangling `Directory.current.path` directly.
regression_test_planned:
  - "Pure unit test asserting the PRIMARY-root path is derived correctly
    from a linked-worktree-shaped `--git-common-dir` output, distinct from
    what mangling the worktree path directly would have produced."
  - "Mutation-proof: reverting `primaryRootFrom(gitCommonDirOutput)` to a
    bare pass-through (skipping the `/.git` strip) reddens 2 of 5 tests."
impact_analysis: |
  Scoped entirely to scripts/discipline_hook.dart's SessionStart hook. No
  product code, no Hive schema, no cloud table, no migration. The MEMORY.md
  size nudge is advisory (never blocks a session per this file's own
  NEVER-break-the-session contract) — its prior silence meant the founder
  never saw a nudge to run /consolidate-memory from ANY worktree session,
  which is exactly how the memory-consolidation retrospective
  (memory/project_memory_consolidation_2026_09_07.md) describes the index
  regrowing 3KB in one day undetected. No other caller of the old inline
  logic existed (it was private to this file), so no other site needed
  updating. batch_close_hook.dart / batch_close_lib.dart already used the
  correct pattern and needed no change.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "scripts/discipline_hook.dart:157-186 — resolveMemoryIndexPath extracted and used; verified via test/scripts/discipline_hook_memory_path_test.dart (5 tests) plus a live mutation proof (reverting primaryRootFrom to a pass-through reddens 2 tests)." }
  - { tier: 2, name: "Hive (local state)", status: not_applicable, evidence: "No Hive access in this fix." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema access." }
---

## Summary

`scripts/discipline_hook.dart`'s MEMORY.md size nudge derived the harness
memory directory's mangled name from `Directory.current.path` — the
WORKTREE path in every session, per CLAUDE.md §4.13's mandate that every
session work in a linked worktree. The harness keys the memory directory
name on the PRIMARY repo root, not the worktree, so the mangled path never
matched any real directory and the nudge silently never fired.

## Root Cause

`scripts/batch_close_lib.dart`'s own header comment already documents this
exact bug class by name: *"⚠ `--show-toplevel` is WRONG here and must not
come back: in a linked worktree it returns the WORKTREE path, and §4.13
makes every session work in one, so the derived harness directory never
matched and every batch was reported UNVERIFIED."* That fix
(`primaryRootFrom` + `mangleProjectPath`) was written for
`batch_close_hook.dart` and never carried over to `discipline_hook.dart`'s
own, independently-implemented path derivation — a second implementation of
the same problem that inherited the same defect the first one already fixed.

Found while building an unrelated memory-write-guard hook for the same
discipline-v3-phase3 batch, which needed the identical harness-memory-dir
resolution logic and required checking how the EXISTING nudge derived it.

## Fix

Extracted `resolveMemoryIndexPath` as a pure, testable, public function
(scripts/discipline_hook.dart:163) that imports and reuses
`batch_close_lib.dart`'s `primaryRootFrom` + `mangleProjectPath` — the same
functions `batch_close_hook.dart` already relies on — instead of
re-deriving (and re-breaking) the path a third time in this codebase.

## Related

Same bug class as the one `batch_close_lib.dart`'s own header already
documents and fixed for a sibling hook. No prior diagnose-doc exists for
THIS file's instance because the bug was silent (an advisory nudge that
never fires produces no symptom a founder would report) — found by code
inspection, not a live failure.
