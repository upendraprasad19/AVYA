---
adr_id: 0013
title: Tier local-gate intensity by blast radius; CI is the full-suite source-of-truth
status: accepted
date: 2026-06-01
deciders: Upendra
---

# ADR-0013: Blast-radius-tiered local gating

## Context

The local git hooks gated every change identically. The full `flutter test` suite
(~7 min, ~2500 tests) ran on **every push** via `scripts/pre-push.sh` — and CI
(`.github/workflows/test.yml`) ran the **same** full suite again on every push. So a
trivial data-only commit (e.g. the `backups/apk_sizes.json` build-ledger entry — 5
lines, zero code) paid the full 7-min local suite *plus* a full CI run, identical to a
payment-code change.

The repo already computes a change's **blast-radius tier**
(`feature`/`account`/`platform`/`catastrophic`) from the diff via
`scripts/blast_radius_from_diff.dart` (registry: `docs/blast_radius.yaml`), and
`scripts/prepare-commit-msg.sh` already stamps it into every commit body — but the
hooks never *consumed* the tier. The gates were risk-blind.

Two facts make leaning safe: **CI runs the full suite on every push regardless** (an
always-on backstop ~2 min after push), and the project is **solo** (a momentarily-red
push reaching GitHub before CI flags it has no blast radius to other developers).

> **Correction 2026-08-11 (ADR-0018).** The first of those two facts is FALSE, and it is
> load-bearing here — it is one of the two stated justifications for the tiering decision.
> `.github/workflows/test.yml` triggers on `push: [main, develop]` **and `pull_request`
> targeting them**, not on every push. Counted live: `git ls-remote --heads origin` = 29 refs
> (28 non-main); 8 have an open PR and so do get CI on every push; the other ~20 — including
> most `claude/*` working branches — get none. The same false claim was propagated into
> `CLAUDE.md` §0, `scripts/pre-push.sh` and
> `docs/handbook/process/tiered-gating-by-blast-radius.md`, and is corrected in all of them.
>
> The tiering DECISION still stands: the second fact (solo project) carries it, and ADR-0018
> closes the exposed gap by making `flutter analyze` unconditional at pre-push, so a PR-less
> branch push is compile-checked locally before it leaves the machine. What does not stand is
> reading "CI backstops it" as a reason to skip a local gate on a branch.
> Refined by ADR-0018 (see the end of this file); this ADR is not superseded.

## Decision

**Tier local-gate intensity by the change's blast radius; treat CI as the full-suite
source-of-truth.** Concretely:

- **`pre-push` (tiered):** run the full `flutter test` locally only when the pushed
  range's blast-radius is ≥`account`. `feature`-tier pushes (docs, `scripts/`,
  `.claude/`, `backups/`, profile-only UI) **skip** the local full suite — CI is the
  backstop. **Fail-safe:** an empty/undetermined range, an absent `origin/main`, or any
  non-`feature` tier RUNS the suite — the hook never skips on uncertainty.
  `PRE_PUSH_FULL=1` forces it.
- **`pre-commit` reminder:** since git hooks cannot invoke Claude skills, pre-commit now
  PRINTS a non-blocking `run /code-review (B-pass)` nudge when the staged tier is
  ≥`account` (correcting the code-review skill's prior, never-wired "auto-trigger" claim).
- **`pre-commit` gate loop:** the ~28 `check_*.dart` gates run with **bounded**
  concurrency (`PRE_COMMIT_GATE_JOBS`, default 4) — never 28 Dart VMs at once.
- **`/build-apk --from-green`:** an opt-in fast-path that skips re-running the gates CI
  already passed (analyze + full suite + dart gates) when building a pushed, CI-green
  commit — keeping the clean build + size + on-main/versionCode/.env gates.
- **Behavioral (CLAUDE.md §4.3):** batch commits + push once per logical batch; don't
  manually re-run the full suite when the hooks/CI will.

## Alternatives considered

1. **Drop the local pre-push full suite entirely; trust CI for everything.** Rejected —
   loses the "catch a red suite before it leaves the machine" property for *real code*
   changes, where a 7-min local gate is worth it. The tiered approach keeps that for
   ≥account while dropping it only for low-risk pushes.
2. **Conservative skip — only when zero `lib/`/`test/`/`supabase/functions/` files
   changed.** Rejected by founder in favour of the blast-radius tier (more leverage:
   profile-only UI + scripts + docs all skip locally, CI backstops).
3. **Per-test impact selection (run only tests affected by the diff).** Rejected —
   Flutter has no built-in test-impact selection; a hand-rolled file→test heuristic is
   fragile and risks skipping cross-cutting tests. Tiering the *whole* suite on/off is
   simpler and safe (CI always runs everything).
4. **Speed the suite itself (shared/faster Hive fixture for the ~68 Hive-heavy tests +
   concurrency tuning).** Out of scope for this batch (founder choice) — an optimization,
   not a punted bug; revisit if the suite/commit feels slow.

## Consequences

Good:
- Low-risk pushes (docs/data/scripts/.claude/profile) are near-instant locally; CI still
  gates them. Real-code pushes keep the full local gate.
- Bounded-parallel gates shave commit wall-time without an OOM risk.
- The ≥account reminder makes the B-pass trigger real (a printed nudge) instead of
  fictional.

Bad / watch:
- `feature` tier includes `lib/features/profile/**` (real UI code), so a profile-only
  push skips the local full suite. Accepted: CI runs it ~2 min later, and profile is
  feature-tier by the registry's own design.
  **(Correction 2026-08-11 / ADR-0018: "CI runs it ~2 min later" holds only for a push to
  `main`/`develop` or a branch with an open PR — see the Context note. For a PR-less branch
  push the suite next runs at the merge-to-`main` push; `flutter analyze` does now run
  unconditionally at pre-push, so such a push is still compile-checked.)**
- The hooks are the safety net — a tier mis-computation could skip a risky push.
  Mitigated by the fail-safe-to-running default, `PRE_PUSH_FULL=1`, the always-on CI
  backstop, and the two pinning tests
  (`test/contracts/pre_push_blast_radius_failsafe_test.dart`,
  `test/contracts/pre_commit_gate_loop_parallel_test.dart`).
- The parallelized gate loop MUST preserve the `scripts/check_*.dart` glob + the
  `case "$GATE_NAME" in … esac` allowlist that `check_gate_scripts_wired.dart` (Gate 33)
  parses — pinned by the gate-loop test.

## Status

Active. Shipped 2026-06-01 (lean-workflow batch). Platform blast radius (edits
`CLAUDE.md` + the hooks) → carried a `/code-review` B-pass before commit.

## See also

- `scripts/pre-push.sh`, `scripts/pre-commit.sh` (the tiered hooks)
- `scripts/blast_radius_from_diff.dart` + `docs/blast_radius.yaml` (the tier source)
- `scripts/prepare-commit-msg.sh` (the proven preamble-tolerant tier-extraction pattern)
- `scripts/check_gate_scripts_wired.dart` (Gate 33 — the wiring detector the loop must satisfy)
- `.claude/commands/build-apk.md` (`--from-green` fast-path)
- `.claude/skills/code-review/SKILL.md` §0 (reminder, not auto-trigger)
- `docs/handbook/process/tiered-gating-by-blast-radius.md` (the durable rule)
- ADR-0004 / the 2026-05-28 six-industry-gap batch (introduced blast_radius.yaml + the gates)
- **ADR-0018** — moves `flutter analyze` + `flutter test` off pre-commit, makes analyze
  unconditional at pre-push, and corrects this ADR's "CI runs the full suite on every push"
  premise (see the Correction note in Context). Refines this decision; does not supersede it.
