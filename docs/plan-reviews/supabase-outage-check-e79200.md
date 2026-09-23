---
branch: claude/supabase-outage-check-e79200
date: 2026-09-23
blast_radius: platform
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/c19c4efc482f-review.md
---

# Plan-review record — discipline v3 Phase 3 round-1/round-2 hardening (platform)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`). Platform-tier
because the diff touches `CLAUDE.md` and adds/changes gate scripts that fire on every future
commit (`check_hive_first_pattern.dart`, `check_hooks_installed.dart`) and every Write/Edit tool
call (`memory_write_guard_hook.dart`) — per `docs/blast_radius.yaml`'s own platform-tier rows for
exactly this class of file. Not catastrophic → no Hermes.

## Scope

This record covers the SECOND session's worth of work on the discipline-v3 Phase 3 batch: fixing
the findings from an internal review round conducted earlier in the same session (against the
work landed in commit `aca0237a`), plus a second independent context-blind review round on the
hardened result, plus the self-triggered B-pass required at platform tier.

1. **`scripts/check_hive_first_pattern.dart`** — widened the Supabase-call detection regex from
   2 aliases (`supabase|client`) to 3 (`supabase|supa|client`) after a live grep of `lib/` found
   `supa.from(` as a real, unmatched third alias in `lib/core/services/rank_service.dart` (already
   inside an allowed dir, so a detector coverage gap, not a live violation).
2. **`scripts/memory_write_guard_lib.dart`** — added `isMemoryArchivePath` as its own no-op
   dispatch branch so `MEMORY_ARCHIVED.md` (append-only, no frontmatter contract) stops falling
   through to the topic-file frontmatter validator and warning on every edit.
3. **`scripts/memory_write_guard_hook.dart`** — documented the hook's measured per-call cost
   (~1.5-1.7s via the `flutter/bin/dart` wrapper, ~540-800ms via the SDK exe) as a code comment,
   flagging the `_dart_bin.sh` wiring as a real, open follow-up rather than silently accepting or
   unilaterally changing the invocation shape.
4. **`docs/blast_radius.yaml`** — added 4 platform-tier entries for the new/changed scripts
   (`memory_write_guard_hook.dart`, `memory_write_guard_lib.dart`, `check_hive_first_pattern.dart`,
   `check_edge_function_scope.dart`), placed before the generic `scripts/**` catch-all so
   first-match-wins actually promotes them.
5. **`scripts/check_hooks_installed.dart`** (Gate 32) — closed THREE unguarded file-read call
   sites, one per review round: round 1 found the two reads inside the per-hook freshness-
   comparison loop (installed-hook content, source content); round 2 found the third — the
   installer file's own read at the top of `main()` — the exact same failure class the round-1
   fix existed to close, left unguarded in the one remaining call site. All three now degrade to
   a WARN/UNDETERMINED message + `exit(0)` instead of throwing uncaught, matching the gate's own
   documented "never hard-fail unexpectedly" contract.
6. **`docs/audit/gate_test_ledger.yaml`** — corrected imprecise mutation-count prose for
   `check_hive_first_pattern.dart` ("2-3 of 19 tests" → the exact per-mutation breakdown against
   21 tests) and added the third mutation leg (alias-widening).
7. **`docs/audit/open_issues.md` / `closed_issues.md`** — closed OI-243, a title-only stub
   accidentally introduced into the open-issues board by an earlier broad `git add -A` sweep in
   this same session (it described exactly the work this batch ships, and was never a separately
   scoped ask — confirmed via `git log -S "OI-243"` that it was authored in this session's own
   commit `aca0237a`).

Tests: `test/scripts/check_hive_first_pattern_lib_test.dart` (21, +2 this round),
`test/scripts/check_hooks_installed_e2e_test.dart` (7, +1 this round),
`test/scripts/memory_write_guard_lib_test.dart` (31, +1 earlier this batch, unchanged this round).

## Root cause (why this exists)

Two rounds of self-driven review on a batch whose most severe defect class — a "never
hard-fail" gate that CAN throw uncaught — recurred THREE times in the same file, caught only
because each review round deliberately re-read the whole file rather than trusting the prior
round's "fixed" claim. Round 1 fixed 2 of the 3 unguarded reads and reasonably assumed the class
was closed; round 2, dispatched fresh with no memory of round 1's reasoning, re-grepped every
`readAsStringSync()` call site in the file rather than re-reading round 1's diff, and found the
one round 1 missed sitting nine lines above the first fix.

## Review rounds

**Round 1 — internal review earlier in this session (findings processed and fixed before this
record was written; not separately re-litigated here, but summarized for completeness): 6
findings.**
- P1: `MEMORY_ARCHIVED.md` fell through to the topic-file frontmatter validator and warned on
  every edit — the single most routinely-written memory file in the `/consolidate-memory`
  workflow. Fixed with a dedicated no-op dispatch branch.
- P1: the Write|Edit PreToolUse hook's per-call cost was unmeasured. Measured directly
  (1.5-1.7s wrapper / 540-800ms SDK exe) and documented rather than silently accepted or changed.
- P1: 4 new/changed scripts had no `blast_radius.yaml` entry, so this very batch would have
  under-classified its own tier. Added, verified via the real classifier.
- P2: `check_hooks_installed.dart`'s per-hook freshness comparison read two files with no
  try/catch — an unreadable installed hook would crash the gate. Fixed; the fix's own regression
  test design was corrected mid-flight after discovering `File.existsSync()` returns `false` for
  a directory path (verified empirically before committing to the test), so invalid-UTF-8 bytes
  were used instead to reach the read-failure path without a directory-shaped detour.
- P2: `check_hive_first_pattern.dart`'s alias regex missed a real, live third alias (`supa.from(`
  in `rank_service.dart`) confirmed via `grep -rnoE '\b\w+\.from\(' lib/`. Widened; the first test
  draft used `_supa.from(` (with a leading underscore) which does not match the real call shape
  or the widened regex's `\b` word-boundary, caught by running the test and observing it fail for
  the wrong reason, then corrected to the real bare-`supa` shape.
- P2: `gate_test_ledger.yaml`'s mutation-count prose for `check_hive_first_pattern.dart` was
  imprecise ("2-3 of 19 tests") and self-contradictory against its own second bullet.

**Round 2 — fresh context-blind subagent dispatch on the round-1-hardened diff, per §4.12.1: 1
confirmed finding, 1 plausible (not pursued — see below).**
- **CONFIRMED, P1:** `check_hooks_installed.dart:104`, `installerFile.readAsStringSync()` — the
  ONE remaining unguarded read in the file, the exact failure class round 1 had just fixed at the
  other two sites, sitting nine lines above them. An unreadable `scripts/setup-hooks.sh`
  (permission error, bad encoding, or a delete-race after the `existsSync()` check) would throw
  uncaught and crash a gate whose entire documented contract is "never hard-fail unexpectedly."
  Fixed with the same try/catch → WARN/UNDETERMINED + `exit(0)` pattern as the other two sites;
  regression test added (`test/scripts/check_hooks_installed_e2e_test.dart`, "an unreadable
  (invalid-UTF-8) installer script degrades to UNDETERMINED, never crashes"); mutation-proven
  (reverting the try/catch reddens exactly this test with exit code 255 — an uncaught crash —
  confirmed applied, then reverted back to green).
- **PLAUSIBLE, not pursued:** the reviewer separately suggested that `check_hooks_installed.dart`
  should adopt `check_hive_first_pattern.dart`'s structural pattern of wrapping the entirety of
  `main()` in one blanket try/catch, rather than three point-patched try/catch blocks, on the
  reasoning that a structural fix would have caught finding 1 "for free." Not applied: the three
  point patches each degrade to a DIFFERENT, already-established message shape specific to what
  failed (installer unreadable vs. per-hook content unreadable vs. per-hook source unreadable),
  which a single blanket catch at the top of `main()` would collapse into one generic message,
  losing the diagnostic specificity the gate's own comments say is deliberate (see the
  "UNDETERMINED (passing)" messages throughout the file, each naming exactly what could not be
  determined and why). The three-read-sites shape is now provably closed (all three guarded,
  verified via `grep -n "readAsStringSync"` returning exactly 3 hits, all inside try/catch); a
  structural rewrite is a larger, separate refactor with no open defect motivating it today.

**B-pass (self-triggered per §4.3, required at platform tier) — 1 finding, cosmetic, fixed
in-batch:** a copy/paste artifact from the round-2 fix's own mutation-revert cycle left an
8-line explanatory comment duplicated verbatim in `check_hooks_installed.dart`. Fixed
immediately; re-verified `flutter analyze` clean and all 7 e2e tests still green after removal.
Full lens-by-lens results in `docs/reviews/c19c4efc482f-review.md`.

## Convergence

Round 2's one confirmed finding was in the SAME bug class round 1 had just fixed (an unguarded
read in the identical file, in the identical function), not a new class of defect introduced by
round 1's own corrections — the §4.12.1 signal for "the unit is too large, split it" did not
fire here; this was round 1 correctly narrowing its own fix's scope one read-site short, not a
sign of design churn. The B-pass's single finding was cosmetic and had zero behavioral
consequence. Converged.

## Verification

- `flutter analyze lib/` — 45 pre-existing info-level issues, zero warnings/errors (163s).
- Full-repo `flutter analyze --no-fatal-infos` — zero warning/error lines (confirmed via
  `grep -cE "^\s+(warning|error) -"` returning 0, not merely "no output printed").
- All touched unit/e2e test files green: `check_hive_first_pattern_lib_test.dart` (21),
  `check_hooks_installed_e2e_test.dart` (7), `memory_write_guard_lib_test.dart` (31),
  `discipline_hook_memory_path_test.dart` (5), `memory_write_guard_hook_e2e_test.dart` (7) — 71
  tests total across the files this session touched or re-verified.
- Blast-radius reclassified correctly after each staging change, verified via the real
  classifier with the correct `--name-only` stdin form (`git diff --cached --name-only | dart
  run scripts/blast_radius_from_diff.dart -`) — an earlier attempt in this same session
  mis-piped the full diff content instead of just filenames, which is the exact
  `feedback_mistake_blast_radius_positional_mode.md` pitfall this repo's own memory already
  documents; caught and corrected before relying on the (wrong) result.
- Mutation-proven: `check_hive_first_pattern.dart`'s widened regex (narrow it back, confirm
  exactly the new `supa.from(` test reddens, revert, confirm green) and
  `check_hooks_installed.dart`'s new installer try/catch (remove it, confirm exactly the new
  test reddens with exit 255, revert, confirm green).

## Residual, stated rather than hidden

- The reviewer's structural-refactor suggestion (blanket `main()` try/catch) is noted above as
  considered and declined with reasoning, not silently dropped.
- No baseline-raising mechanism exists yet for `check_hive_first_pattern.dart` or
  `check_edge_function_scope.dart` (both report-mode only) — documented in each file's own
  header and in CLAUDE.md's §7 pointer row; explicitly out of scope for this batch.
