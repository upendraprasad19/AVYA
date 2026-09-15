---
title: Source-grep contract tests count for presence, not semantics
category: testing
source_memory: feedback_source_grep_false_confidence.md
last_reviewed: 2026-05-28
---

# Source-grep contract tests count for presence, not semantics

## The rule

A contract test that asserts a specific string appears in a source file (via `File('lib/...').readAsStringSync().contains(...)`) provides ZERO evidence about runtime behavior. It tests PRESENCE, not SEMANTICS.

Every concept in `docs/sot_registry.yaml` must have a `behavioral_test_path:` (Hive-write → Hive-read assertion, or `fakeAsync` race harness, or end-to-end flow) ALONGSIDE any source-grep test.

## Why source-grep alone is dangerous

A tech-debt audit analyzed 170 contract tests; 73% (~125) were source-greps (~451 `readAsStringSync` calls vs ~22 runtime-behavioral files). Those greps caught ZERO of the writer/reader drifts in three consecutive batches.

Worse: 170 contract tests can be the proudest project-discipline number, and it's misleading. Source-grep tests give *false confidence* — you read "we have 170 contract tests!" and stop looking. The class is **presence ≠ correctness**.

## How to apply

- When proposing a contract test, ask: "Would this fail if the runtime path was broken but the source text remained intact?" If no, it's a presence-only check.
- Source-grep is fine as a *complement* to a behavioral test (catches accidental deletion). Source-grep ALONE is not.
- For new SoT registry entries: require `behavioral_test_path:` in the YAML schema. Add a `flutter test` step that loads Hive in-memory, writes via the canonical WriteService, reads via every documented reader, and asserts equality.
- For race conditions: use `fakeAsync` to fire two writes at controlled timestamps. Source-grep cannot test ordering.
- Audit existing source-grep tests: walk `docs/sot_registry.yaml`, identify entries without a paired behavioral test, write them in priority order (writer/reader drift > restore completeness > sync fanout > others).

### Comment-stripping for absent-pattern greps

Absent-pattern source-grep tests MUST strip `/* */` + `//` comments first; otherwise a commented-out illustration of the forbidden pattern produces a false positive. Canonical helper in `phase_c_oi_closures_test.dart`.

## Anti-pattern (banned)

Closing a writer/reader drift bug by adding a source-grep "the canonical writer method exists" test and considering the regression covered. That has already happened 9+ times. The next time, the answer is: write the behavioral test now or revert the fix.

## Instance — the refactor recovery batch

A batch's refactor work split 5 services / repositories (1970-LOC → 4 services + shim; 2127-LOC → 3 services + shim, etc.) and relocated a splash screen. EVERY behavioral invariant was preserved — the shim/forwarder files kept the runtime path correct — but every grep that pinned a literal file path landed in the now-thin-shim and saw the "THIN SHIM" comment instead of the assertion's target pattern.

53 stale source-grep tests caught ZERO actual bugs (every one was a false positive), but they BLOCKED the pre-commit hook for any new commit on main.

Recovery cost: ~3 hours, 21 test file re-points + 49 `sot_registry.yaml` stale entry fixes.

Compare to the cost a behavioral-test-paired contract would have had: zero — it would have stayed green across the refactor.

This is the canonical instance that justifies the SoT behavioral-test gate flipping from WARN to FAIL once every concept has a `behavioral_test_path`. Until then, every refactor that moves a watched pattern produces a similar mini-recovery batch.

## References

- CLAUDE.md §4.4 rule 21 (contract tests pin semantics, not just presence; SoT entries need `behavioral_test_path:`).
- Gate 42: `scripts/check_sot_behavioral_test_paths.dart`.
- Debugging skill §2.21.
- Related: [`writer-reader-drift.md`](../bug-classes/writer-reader-drift.md), [`monotonic-recompute-demotion.md`](../bug-classes/monotonic-recompute-demotion.md).
