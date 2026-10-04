---
bug_id: a2f6c9
date: 2026-09-22
batch: next-aab-decision-d1227b (merge-integration review of origin/main into this branch)
status: fixed
blast_radius: catastrophic
symptom: |
  Merging origin/main into claude/next-aab-decision-d1227b raised the staged
  diff's blast-radius to catastrophic (origin/main brought in migrations
  containing SECURITY DEFINER). The self-triggered merge-integration
  /code-review (B-pass), dispatched per CLAUDE.md §4.3, found two P1s that
  neither branch's own prior review could have seen because each finding
  spans a file this branch touched and a file origin/main touched
  independently:
    1. The live `ops_alerts_30min` cron job's `alert_cron_failures` sub-block
       is running the UNBOUNDED pre-140 stuck-job form in production right
       now (confirmed live via `SELECT command FROM cron.job WHERE jobname =
       'ops_alerts_30min'`, jobid 42, active=true — byte-for-byte matches
       migration 141's file, not migration 140's bounded form).
    2. `lib/core/constants/app_constants.dart` and `pubspec.yaml` (both
       inherited from origin/main commit 65bee5d5) carry a UTF-8 BOM plus
       mojibake corruption (`â€"`-family byte sequences replacing em-dashes
       and arrows in comments) — silently merged in because both branches
       happened to bump `appVersion`/`version` to the identical `1.0.0+45`,
       producing no line-level conflict for git to flag.
  Review file: the review under docs/reviews/ whose `staged_against:` frontmatter
  matches this commit's staging hash (agent a4ebe34013f443b0a authored the
  original findings; the file was renamed at least once as fix commits shifted
  the hash — see .claude/skills/code-review/SKILL.md's tuning-history entry for
  this batch, keyed by content not by filename, for the stable pointer).
concept: alert_cron_failures_stuck_job_bound, source_file_encoding
sot_registry_entry: not_applicable
writers:
  - { file: supabase/migrations/140_hermes_pass_fixes_138_139.sql, method_or_widget: "cron.schedule('alert_cron_failures', ...)", line: 77 }
  - { file: supabase/migrations/141_disk_io_audit_cleanup_batch.sql, method_or_widget: "cron.schedule('ops_alerts_30min', ...) — alert_cron_failures sub-block", line: 137 }
readers:
  - { file: supabase/migrations/143_restore_alert_cron_failures_stuck_job_bound.sql, method_or_widget: "cron.schedule('ops_alerts_30min', ...) — restored alert_cron_failures sub-block, verified against live cron.job.command for jobname='ops_alerts_30min' (jobid 42) before drafting", line: 21 }
  - { file: test/contracts/alert_cron_failures_sync_test.dart, method_or_widget: "setUpAll — reads alerts/_thresholds.yaml's defined_in_migration pointer", line: 30 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: "cron.job (command text), public.cron_call_log (read by the alert query)"
cloud_columns: [command, status, started_at]
contract_test_path: test/contracts/alert_cron_failures_sync_test.dart
ist_handling:
  - "Unaffected — the stuck-job bound operates on relative `now() - interval` windows, not IST-anchored day boundaries."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "Not applicable — an internal ops-paging cron job with no per-user data path."
forbidden_patterns_checked:
  - "N/A — this is a migration-drift + encoding-corruption fix, not a forbidden-pattern gate."
proposed_fix: |
  Finding 1 (live regression): Migration 140 introduced the `[1h, 6h)` bound
  on alert_cron_failures's stuck-job branch (fixing a real live incident —
  diagnose h1a2b3, a job stuck 2.5 days re-paged every 15 minutes
  indefinitely with no bound). Migration 141 (disk-IO audit cleanup, same
  day) consolidated three standalone alert jobs — alert_edge_function_health,
  alert_client_errors_spike, and alert_cron_failures — into one combined job
  renamed `ops_alerts_30min`. 141 was authored from a branch snapshot that
  predated 140: its header explicitly notes awareness that migration 139
  created alert_cron_failures on a separate in-flight branch, but has no
  awareness that 140 later patched it on that same branch. So 141's copy of
  the alert_cron_failures sub-query carries the pre-140 unbounded form. Both
  migration files are immutable and individually correct against their own
  intent — 140 never changed, and 141's OWN header reasoning about 139 is
  accurate — but the LIVE cron.job row is the union of whichever migration
  scheduled it LAST, and 141 ran after 140 chronologically in the applied
  sequence relevant to this branch. Fixed by migration
  143_restore_alert_cron_failures_stuck_job_bound.sql: unschedules and
  re-schedules `ops_alerts_30min` reproducing 141's alert_edge_function_health
  and alert_client_errors_spike sub-blocks VERBATIM (out of scope for this
  fix) and restoring only the alert_cron_failures sub-block's `[1h, 6h)` bound
  and matching summary/context text.

  Regression-test blind spot closed: `alert_cron_failures_sync_test.dart`
  previously read only the ONE migration file named by
  `alerts/_thresholds.yaml`'s `defined_in_migration` field — which stayed
  green forever because migration 140's file itself never changed, even
  though the live database had moved on. Added a new test that scans every
  migration file for the literal alert-emitting INSERT (`'alert_cron_failures',
  ... 'critical'`, matched with commented-out rollback lines stripped first)
  and asserts the YAML names the numerically LAST one — the one actually
  live-authoritative — rather than trusting a hand-maintained pointer that
  can go stale exactly the way it did here. Mutation-proven: reverting the
  YAML pointer back to "140_hermes_pass_fixes_138_139.sql" reddens this new
  test with a message naming the correct migration (143); restoring it passes.

  Finding 2 (encoding corruption): `git show <last-known-clean-sha>:<path>`
  restored both files' original UTF-8 content (no BOM, no mojibake), then
  the `version`/`appVersion` bump to `1.0.0+45` was re-applied as the only
  intentional diff — confirmed via `diff` against the clean commit that the
  version line is now the ONLY difference. Root cause: `git merge` cannot
  flag a byte-encoding change as a textual conflict when both sides change
  the identical line (the version bump) to the identical value, so origin/main's
  BOM+mojibake corruption inherited from an earlier commit passed through
  silently. Not treated as a recurring class needing a new gate — a one-off
  provenance defect in origin/main's own history, not this branch's or this
  merge's.
regression_test_planned:
  - test/contracts/alert_cron_failures_sync_test.dart
impact_analysis: |
  Finding 1 fix requires a LIVE migration apply (cron.unschedule +
  cron.schedule against production project dedsavbjuwgarrhphgnl) — deferred
  pending explicit founder authorization per CLAUDE.md §4.3 ("Live prod apply
  needs its own explicit go... EVEN WHEN the batch plan was approved").
  Verified via live query (SELECT status, started_at FROM
  public.cron_call_log WHERE status='started' AND started_at < now() -
  interval '1 hour') that the regression is NOT actively mis-paging at this
  instant (0 currently-stuck rows) — it is an armed regression that will
  reproduce the original 2026-09-19 incident the next time any cron job
  crashes mid-run and leaves a stranded 'started' row, not a live-firing one
  right now. Finding 2 fix is file-content only, no live-apply, no runtime
  behavior change (both files' actual Dart/YAML values are unchanged except
  restoring the intended non-corrupted characters).
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "lib/core/constants/app_constants.dart encoding restored; no logic change." }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "No schema (table/column) change — cron.job body only." }
  - { tier: 5, name: "Migrations applied", status: deferred, evidence: "Migration 143 drafted, NOT yet applied — awaiting explicit founder live-apply authorization per §4.3." }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "No Edge Function touched." }
  - { tier: 7, name: "Cron jobs", status: verified, evidence: "Live query confirmed jobid 42 'ops_alerts_30min' currently runs the unbounded pre-140 form, byte-for-byte matching migration 141's file. Live query for currently-stuck rows (>1h) returned empty at verification time." }
mutation_proven:
  mutated: "Set alerts/_thresholds.yaml's cron_failures.defined_in_migration back to '140_hermes_pass_fixes_138_139.sql' (the exact stale-pointer shape of the original regression)."
  result: "Ran flutter test test/contracts/alert_cron_failures_sync_test.dart: RED on the new 'defined_in_migration names the LATEST migration' test, correctly naming the full migration chain [139, 140, 141, 143] and asserting the YAML must point at 143. Restored the correct value; re-ran: GREEN, 8/8 passed."
  confirmed_applied: "Read the file after the mutation and after the restore to confirm exact content; test output quoted the mutated value verbatim in its failure message."
---

## Summary

A self-triggered merge-integration `/code-review` (required because merging
`origin/main` raised this branch's staged blast-radius to `catastrophic`)
found a real, live production regression that neither branch's own prior
review could see, plus a real encoding-corruption defect silently inherited
from `origin/main`.

## Root cause

**Finding 1:** Two migrations authored on parallel branches both legitimately
touch the same cron job. Migration 140 fixed a real live incident by bounding
`alert_cron_failures`'s stuck-job branch to `[1h, 6h)`. Migration 141,
authored from an earlier snapshot for an unrelated disk-IO cleanup, folded
`alert_cron_failures` into a new consolidated `ops_alerts_30min` job using the
pre-140 unbounded logic — with no way to know 140 existed. Migration
immutability means neither file is "wrong" on its own; the live cron.job row
is simply whichever migration scheduled it last, and that ended up being 141.

**Finding 2:** `git merge` resolves a line-level conflict only when both
sides differ; both branches bumped the version to the identical `1.0.0+45`,
so origin/main's pre-existing BOM+mojibake corruption in the surrounding
comment lines merged through with zero conflict markers.

## Fix

- Migration `143_restore_alert_cron_failures_stuck_job_bound.sql`: restores
  the `[1h, 6h)` bound to `ops_alerts_30min`'s `alert_cron_failures`
  sub-block only, reproducing the other two sub-blocks verbatim.
- `alerts/_thresholds.yaml` repointed to migration 143; its description
  comment now explains why the pointer must move with every re-scheduling.
- `test/contracts/alert_cron_failures_sync_test.dart` widened with a new test
  that scans ALL migrations for the alert-emitting literal and requires the
  YAML to name the numerically last one — structurally closing the blind
  spot instead of just hand-patching today's value.
- `lib/core/constants/app_constants.dart` and `pubspec.yaml` restored from
  last-known-clean content, with the `1.0.0+45` bump re-applied as the only
  intended diff.
- `docs/operations/CRON_REGISTRY.md` updated (`ops_alerts_30min` and the
  deprecated `alert_cron_failures` rows) to record the regression and fix.

## Verification

- `flutter test test/contracts/alert_cron_failures_sync_test.dart`: 8/8
  green.
- Mutation proof: reverting the YAML pointer to migration 140 reproduces a
  failure naming the correct fix (143); restoring it passes.
- `diff` against the last-known-clean commit confirms `app_constants.dart`
  and `pubspec.yaml` now differ ONLY in the intended version bump line.
- Live query confirmed the regression is armed but not actively firing at
  verification time (no cron_call_log row currently stuck past 1h).

## Files changed

- Created: `supabase/migrations/143_restore_alert_cron_failures_stuck_job_bound.sql`
- Modified: `alerts/_thresholds.yaml`, `test/contracts/alert_cron_failures_sync_test.dart`,
  `docs/operations/CRON_REGISTRY.md`, `lib/core/constants/app_constants.dart`,
  `pubspec.yaml`
- Created: this diagnose-doc.

## Outstanding — requires separate explicit authorization

Migration 143 has NOT been applied to production. Per CLAUDE.md §4.3, a live
prod apply needs its own explicit per-action founder go, independent of this
batch's own approval. Awaiting that before running
`mcp__supabase__apply_migration` against project `dedsavbjuwgarrhphgnl`, after
which `backups/applied_migrations.json` must be updated in the same commit
per the migration-apply-record pairing rule.
