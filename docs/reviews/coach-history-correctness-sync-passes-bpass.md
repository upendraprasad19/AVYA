---
reviewed_at: 2026-10-09T23:30:00+05:30
staged_against: coach-history-correctness-sync-passes at commit c73dded9 (M1 skip-index delta merge, M2 restore fingerprints) vs main fdf06564
blast_radius: platform
reviewer: 2 fresh context-blind Sonnet reviewers on one commit (A: unit M1 SyncSkipIndex.commit; B: unit M2 push-bundle extraction and restore fingerprints), read-only, exhaustive command allow-list (Read, Grep, Glob, git show, git diff, git log; no scripts, no tests, no database)
lens_set: [writer_reader_drift, guard_without_its_mirror, missing_input, concurrency_atomicity, asserted_fixture_value]
findings_count: 10
verdict: accepted
---

# Code Review (B-pass) — L1a-3 skip-index merge and restore fingerprints (`coach-history-correctness-sync-passes`)

Plan `docs/plans/coach-history-correctness-sync-passes.md` (v3); diagnose-docs `a8c4e5`, `f3d2a7`. Production was not touched by any reviewer or fix.

**Outcome:** no P0, no P1. The design-level finding was B-F3: the restore fingerprinted the push-shaped bundle of the restored log, which can equal what the push would send while the cloud holds different content (gapped set numbers the push renumbers, a summary count the per-set rows do not back, legacy NULL columns). Fixed with a pure guard so such a row simply pushes once. 0 false alarms.

## Reviewer A (M1, `SyncSkipIndex.commit`)

| Id | Sev | Claim | Disposition |
|---|---|---|---|
| A-F1 | P2 | Nothing tests the `every(...)` half of the unchanged short-circuit (same-size replace of a fingerprint). | Fixed: test added; mutant (clause replaced by `true`) RED. |
| A-F2 | P2 | The confirmed/forgotten exclusivity is untested (fail then succeed on one key). | Fixed: both directions tested; mutant (drop `_forgotten.remove` on confirm) RED. The sibling mutant (`_confirmed.remove` in `_forget`) is equivalent, noted. |
| A-F3 | P2 | A key confirmed this pass but absent from `liveKeys` is untested. | Fixed: test added; mutant (prune skips confirmed) RED. |
| A-F4 | P3 | Last-commit-wins on a shared key can name the wrong fingerprint if server arrival order differs from commit order (missed push, not extra). | Recorded residual: the old whole-snapshot write had the same exposure and a wider one. |
| A-F5 | P3 | `clearAll` between construction and commit: the merge re-adds this pass's own confirmed rows. | Recorded: strictly better than the old code (which resurrected the whole snapshot); one line in the diagnose-doc. |

## Reviewer B (M2, bundle extraction and restore)

| Id | Sev | Claim | Disposition |
|---|---|---|---|
| B-F1 | P2 | The builder and `exlogPayloadFingerprint` run bare inside the restore's single outer `try`; a throw aborts the restore of every later log. | Fixed: own `try/catch` that fails open (telemetry `sync_restore_exlog_fingerprint`). No behavioral test: a throwing value cannot be injected through the stub (the restore's own casts throw first); presence-only, stated. |
| B-F2 | P3 | The extraction is not verbatim: an inner per-set `continue` became `return null`. | Fixed: back to `continue`. |
| B-F3 | P3 | The fingerprint can equal the push bundle while the cloud differs (a: gapped sets, b: summary count, c: legacy NULLs, d: exercise_id / day id). | Fixed: `restoredBundleEqualsCloud` (pure, `exlog_restore_rules.dart`) gates the recording; tests: pure divergence table, gapped-sets behavioral, over-count behavioral; guard-bypass mutant RED. |
| B-F4 | P3 | Narrow race: a record written after the user deleted the restored row. | Recorded: pruned at the next commit; a re-log changes `completed_at`, so its fingerprint differs. |
| B-F5 | P3 | The builder's telemetry events now also fire during restore. | Recorded: same events, same rows; noise only. |
| B-gaps | - | No test for edit-after-restore, owner-changed early return, over-count. | Fixed: all three added; owner-check mutant RED. |

Mutation proof of the B-pass fixes: 5 of 5 RED (every-clause, forgotten.remove, prune-confirmed, owner check, guard bypass); source restored after each run.
