---
adr_id: 0008
title: Single-tester direct-to-main workflow (no feature-branch PRs)
status: accepted
date: 2026-05-10
deciders: Upendra
---

# ADR-0008: Single-tester direct-to-main workflow

## Context

ICANBEFITTER is built by a solo founder (Upendra) with Claude as
pair-coder. There is no second human reviewer. APKs are tested by
the founder on a single device before "shipping" (which currently
means: install on personal device + use it).

Pre-paying-user phase. No paying customers depend on a clean
release line yet.

The standard industry workflow — feature branch → PR → review →
merge → CI → deploy — has overhead. The "review" step is the same
brain that wrote the code. The CI step is the same `flutter test` +
`flutter analyze` that runs locally on pre-commit.

## Decision

**Direct-to-main commits with pre-commit hook gating + mega-commit
batches at end of work session.**

- All work happens on `main` directly OR on a short-lived feature
  branch that merges back via `git merge --no-ff` within hours, not
  days.
- The pre-commit hook is the gate that other teams' code review +
  CI replace:
  - `flutter analyze --no-fatal-infos` must pass
  - `flutter test` must pass
  - Diagnose-doc validator must pass on any matching commit
  - `scripts/check_*.dart` gates (~60 of them) must pass
- APKs build from `main` ONLY. Feature branch → merge → `/build-apk`.
  Never APK from a feature branch.
- A "batch" lands as one mega-commit (per
  `project_drift_fix_batch_2026_05_24` precedent) when the work spans
  multiple related changes.

Encoded in CLAUDE.md §4.3 + rule 20.

## Alternatives considered

1. **Feature-branch PR workflow.** Rejected for now.
   - PR review is the same brain. The "second pair of eyes" doesn't
     exist; it's me reading my own code 30 seconds later.
   - PR overhead (branch + PR + review + merge) for solo work adds
     coordination cost without coordination benefit.
   - When we hire engineer #2, this ADR gets superseded.

2. **Trunk-based with feature flags.** Partially adopted (CLAUDE.md
   §4.6) — risky changes go behind `kDebugMode` / Hive flag /
   RemoteConfig gates. But the underlying "commit direct to main"
   pattern is the trunk-based core, so this is the regime we're in,
   not an alternative.

3. **GitFlow (develop + release branches).** Rejected. Massive
   overhead. Designed for multi-team coordination; we have one
   developer and no parallel release cycles.

4. **CI service (GitHub Actions / CircleCI).** Considered. Not yet
   adopted.
   - Pro: catches "passes on my machine" issues.
   - Con: pre-commit hook covers ~95% of what CI would catch;
     remaining 5% is "device-specific" which CI cloud runners don't
     replicate well anyway.
   - May adopt for the device-CI runner (`docs/operations/DEVICE_TESTING.md`)
     when paid users arrive.

5. **Code reviewer = subagent on every commit.** Just adopted in
   this batch (Track 1 of the six-gap closure, 2026-05-28). B-pass +
   E-pass (Hermes) reviewer skills bring "second eyes" without
   requiring a human. Compatible with this ADR — the workflow stays
   direct-to-main; the reviewer is automated.

## Consequences

Good:
- **Fast iteration.** Bug fix → commit → APK in hours, not days.
- **Low coordination overhead.** No branch management, no PR queue,
  no "waiting for review."
- **Pre-commit hook is THE quality gate.** Investment in gates is
  high-leverage; one good gate replaces every future "I forgot to
  check X" mistake.
- **Mega-commit batches preserve history readability.** A reader of
  `git log` sees "fix delightful-cascade drift" not 12 fixup commits.

Bad:
- **No human catches stupid mistakes.** A commit that breaks the
  build, leaks a secret, or misroutes a Supabase call relies
  entirely on automation to catch it.
  - Mitigation: layered defense (pre-commit + diagnose-doc +
    SoT registry + 60+ gates + new code-review skill).
- **Force-pushes are extremely dangerous.** No PR history protects
  against "I rewrote main." Mitigation: never force-push main
  unless explicitly approved.
- **No deferred work**, since "I'll come back to this in a follow-up
  PR" doesn't exist as a structure. Codified as the "no deferrals"
  rule (CLAUDE.md §4.2).
- **Onboarding engineer #2 will require workflow migration.** When
  that day comes: switch to feature-branch PRs, code-review skill
  becomes "required reviewer," device-CI runs on every PR.

## Status

Active for solo-founder phase. **Will be superseded when engineer #2
joins** (currently NO in next 12 months per
`project_wedge_thesis_2026_05_20.md`). The successor ADR will
introduce feature-branch PRs + CI; this ADR will be marked
`superseded by NNNN`.

## See also

- CLAUDE.md §4.3 (build / commit / push gates)
- CLAUDE.md rule 20 (no deferred test failures)
- `feedback_main_is_source_of_truth.md`
- `feedback_bulk_commit_hook_bypass.md`
- ADR-0006 (Wardroom) — context for "solo-founder phase tooling cost"
