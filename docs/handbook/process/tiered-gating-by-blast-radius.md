---
title: Tier local-gate intensity by blast radius; CI is the full-suite source-of-truth
category: process
source: ADR-0013, lean-workflow batch 2026-06-01
last_reviewed: 2026-06-01
---

# Tier local-gate intensity by blast radius; CI is the full-suite source-of-truth

## The rule

Local git hooks scale their cost to the **blast-radius tier** of the change being
committed/pushed; **CI is the full-suite source-of-truth** that always runs everything.
Don't gate a docs/data push as hard as a payment-code push.

- **`pre-push`** runs the full `flutter test` locally only when the pushed range is
  ≥`account` blast-radius. `feature`-tier pushes (docs, `scripts/`, `.claude/`,
  `backups/`, profile-only UI) **skip** the local suite — CI backstops them ~2 min later.
- **`pre-commit`** stays fast (analyze + `test/contracts/` + bounded-parallel gates) and
  PRINTS a `/code-review` (B-pass) reminder at ≥`account` (hooks can't invoke skills).
- **`/build-apk --from-green`** skips re-running gates CI already passed for a pushed,
  CI-green commit.

## How to apply

1. **Fail toward running, never toward skipping.** Any uncertainty — empty/undetermined
   push range, absent `origin/main`, unrecognized tier — RUNS the full suite. A skip
   happens only on a *positively-determined* `feature` tier. `PRE_PUSH_FULL=1` forces the
   suite any time.
2. **Compute the tier with the existing helper**, never hand-roll it:
   `scripts/blast_radius_from_diff.dart` (registry `docs/blast_radius.yaml`). Extract its
   output with the preamble-tolerant pattern from `scripts/prepare-commit-msg.sh:41-43`
   (`dart run` prepends a build-hooks line — match the token, don't anchor `^`).
3. **Batch commits; push once per logical batch.** Each push re-runs the tiered pre-push
   + a fresh CI run — commit→push→commit→push triples the cost on the same code.
4. **Don't manually re-run the full `flutter test`** when the hooks/CI will. Run targeted
   tests during dev; pre-push (≥account) + CI are the full-suite gates.
5. **When parallelizing the gate loop, preserve the Gate-33 markers** — the literal
   `scripts/check_*.dart` glob + the `case "$GATE_NAME" in … esac` allowlist. Bound
   concurrency (`PRE_COMMIT_GATE_JOBS`, default 4) so you don't fork 28 Dart VMs.

## Why it's safe (solo + CI backstop)

CI (`.github/workflows/test.yml`) runs analyze + the full suite + all gates + a debug-APK
compile on **every** push regardless of the local tier. Solo project ⇒ a momentarily-red
push reaching GitHub before CI flags it harms no one else. The local suite's only unique
value is catching a red suite *before* it leaves the machine — worth ~7 min for real code
(≥account), not worth it for docs/data.

## Anti-patterns

- **Skipping on uncertainty.** A blank/failed tier computation must RUN the suite, not skip.
- **Dropping the Gate-33 textual markers** when refactoring the gate loop → every gate
  silently reads as "unwired" (enforcement evaporates). Pinned by
  `test/contracts/pre_commit_gate_loop_parallel_test.dart`.
- **Trusting `--from-green` blindly.** Confirm CI-green via `gh` when available; abort on a
  red CI conclusion; never skip the clean build + size + on-main/versionCode/.env gates.
- **Manual full-suite reruns** stacked on top of the hooks + CI (this batch's founding
  observation — the same suite ran 3–4× on identical code).

## Companion rules

- ADR-0013 (the decision + alternatives).
- `test/contracts/pre_push_blast_radius_failsafe_test.dart` +
  `test/contracts/pre_commit_gate_loop_parallel_test.dart` (the pinning contracts).
- CLAUDE.md §0 (hook semantics + `PRE_PUSH_FULL`) + §4.3 (batch-commits / don't-rerun rules).
- [`secrets-pattern-audit.md`](secrets-pattern-audit.md) — sibling pre-first-push discipline.
