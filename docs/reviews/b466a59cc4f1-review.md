---
reviewed_at: 2026-11-05T14:10:00+05:30
staged_against: b466a59cc4f1
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 6
verdict: accepted
verdict_note: every finding fixed or answered in this batch; reviewed at hash 1d65664bb896 (before the fixes), file renamed to the final staged hash after them
---

# Code Review - b466a59cc4f1 (OI-179, migration 169 retention 7 -> 10 days)

Reviewer: one fresh Sonnet subagent, exhaustive read-only command list, lens 6 allowed to mutate ONE file
(`test/helpers/cron_call_log_windows.dart`) with a backup and sha256 proof of restoration (done: sha256 before and
after equal, `git status` identical). Migration 169 was already applied live and is immutable; the reviewer found no
correctness defect in it (body identical to migration 110 except the interval, grants complete).

## Finding 1 - P2 - writer_reader_drift (stale "pending" wording against the ledger)
- **file:line:** docs/operations/CRON_REGISTRY.md:45,:52; docs/audit/open_issues.md OI-179; the diagnose-doc status and tier-5 row
- **claim:** the docs said the live apply was pending while the same diff carried the ledger entry for the applied migration.
- **verification:** `grep -n "live apply pending" docs/operations/CRON_REGISTRY.md docs/audit/open_issues.md`
- **suggested-fix:** say "applied 2026-11-05"; close OI-179.
- **status:** accepted - fixed: registry rows, diagnose status `fixed` and tier-5 evidence reworded; OI-179 moved to `closed_issues.md` (append only, 0 deletions) with the live read-back recorded; the not-completed production run of the SQL pin is stated plainly.

## Finding 2 - P2 - guard_without_its_mirror (lookback equality untested)
- **file:line:** test/helpers/cron_call_log_windows.dart `violations` (`if (t >= l)`)
- **claim:** a `>=` to `>` mutant survived all 15 tests; the threshold-equals-lookback case had no test.
- **verification:** reviewer applied the mutant (grep -c 1), 15 passed; restored by sha256.
- **suggested-fix:** `expect(violations(win([8],[8]), 10), isNotEmpty)`.
- **status:** accepted - fixed: test added; the same mutant now reddens 1 test (M10).

## Finding 3 - P3 - guard_without_its_mirror (false-green surface)
- **file:line:** test/helpers/cron_call_log_windows.dart (`_silent`, `_subselectEnd`)
- **claim:** (a) a threshold spelled other than `days_silent`/`hours_silent >= N` yields an empty list and a silent green for a NEW alert; (b) `_subselectEnd` ignores string literals, so a `)` in a literal ends the scan early; (c) only three named jobs are covered.
- **verification:** reviewer mutated the regex to `_silentX`: 3 reds (live pins do catch a reader that finds nothing).
- **suggested-fix:** fail when a cron_call_log reader yields no threshold without an allowlist; skip literals.
- **status:** accepted - fixed: `_subselectEnd` now skips single-quoted literals (fixture + mutant M11 red); a tripwire test lists every migration that has an alert body reading `cron_call_log` and fails on a new one (mutant M12, a probe migration, red). Note: a per-job scan was tried first and rejected: 13 of 36 cron jobs (including the live `alert_cron_silence`) are unreadable by `latestCronJobBody`, so the file-level tripwire is the honest check.

## Finding 4 - P3 - writer_reader_drift (stale doc)
- **file:line:** supabase/functions/_shared/cron_telemetry.ts:16
- **claim:** header says "Retention: 7 days ... currently not scheduled".
- **verification:** `sed -n 10,22p supabase/functions/_shared/cron_telemetry.ts`
- **suggested-fix:** comment edit plus `deno check`.
- **status:** accepted - fixed: now "10 days (migration 169) ... called by db_maintenance_nightly (069, 141, 144)"; `deno check --node-modules-dir=none` clean; platform tier, comment-only, no redeploy (deployed code is behaviourally identical).

## Finding 5 - P3 - asserted_fixture_value (SQL pin can flake; header wrong about locks)
- **file:line:** test/sql/cleanup_cron_call_log_retention_live_verify.sql header and Scenario B
- **claim:** under READ COMMITTED a fleet insert committed mid-run becomes the newest row and falsely reddens the keep-set checks; the header said the table is locked.
- **verification:** read of the file; `cron_call_log` has no triggers or RLS.
- **suggested-fix:** `SET TRANSACTION ISOLATION LEVEL REPEATABLE READ`.
- **status:** accepted - fixed: REPEATABLE READ added, header corrected (row-level locks only; rerun on a serialization failure). Re-proved on a fresh disposable Postgres: old 7-day body 1 of 5 FAIL, new body ALL OK (5).

## Finding 6 - P3 - blast_radius_mismatch (rollback block is a stub)
- **file:line:** supabase/migrations/169_cron_call_log_retention_10d.sql:56-58
- **claim:** header says `Rollback strategy: inline` but the block is a description, not runnable DDL; the catastrophic tier comes from content (SECURITY DEFINER) only.
- **verification:** `grep -n "migrations" docs/blast_radius.yaml`; `sed -n 52,60p` of the migration.
- **suggested-fix:** none for the applied, immutable file; state it in the diagnose-doc.
- **status:** accepted - stated in the diagnose-doc tier-5 evidence (a revert is a NEW forward migration restoring the 110 body); the applied file is not edited.

## Lenses returning clean
- Migration 169 against 110, line by line: identical except the interval; grants identical; ledger sha256 equals the file.
- Lens 1: no other 7-vs-8 assumption in lib/, scripts/, test/, supabase/functions/ beyond Findings 1 and 4; `/cron` 7-day gte window unaffected.
- Lens 2: no `.functions.invoke(` in the diff. Lens 4: no credential-shaped literal. Lens 5: no `unawaited(`.
- Lens 7: migration 109 exists and its `$job$` body has the shape the test reads. Lens 8: every asserted literal (14 d / 8 d, 2 h / 6 h, {30, 60, 360} minutes, retention 10) recomputed from the migration text; the pre-fix pin makes the test fail if the feature did nothing.
- Item (d): no other test asserts 7-day retention for `cron_call_log`.

findings_count: 6

## Founder triage notes
All six accepted and fixed in this batch (no deferral); the founder's explicit go to apply, commit, push and open the PR was given in chat 2026-11-05.

## Tuning entry
- **2026-11-05** - blast-radius catastrophic - 6 findings; 0 false_alarm; tuning: none for the lens set. Instance worth remembering: a "must not redden" mutant list is not evidence (the lookback-equality mutant survived 15 tests); and `latestCronJobBody` refuses a job named inside a string literal in another job's migration, so a per-job generic scan is unreadable for 13 of 36 jobs and a file-level tripwire is the check that works.
