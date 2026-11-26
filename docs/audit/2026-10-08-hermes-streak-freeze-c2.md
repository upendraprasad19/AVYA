---
hermes_pass_id: 2026-10-08-hermes-streak-freeze-c2
ran_at: 2026-10-08T22:30:00+05:30
batch_scope: Slice C2 working tree (staged, uncommitted) plus docs/plans/streak-freeze-restore-ownership-addendum-a.migration-draft-c2.sql; covers the whole merge diff together with the accepted C1 report docs/audit/2026-10-08-hermes-streak-freeze-c1.md
lens_set: [L1, L14, L15, L16, L22, L23, L35]
agents_dispatched: 3
findings_total: 14
findings_by_severity: { P0: 0, P1: 1, P2: 5, P3: 8, false_alarm: 0 }
verdict: accepted
---

# Hermes Pass - Slice C2 (the weekly-streak marker goes to the cloud)

Catastrophic tier by content (a new `SECURITY DEFINER` function). Three Sonnet seats (founder's standing Sonnet-only rule; a recorded deviation from this skill's Opus default), one wave: L1 + L14; L15 + L16 + L23; L22 + L35. No database access for any seat. This report is the one `hermes_report` cited by the plan-review record for the merge diff; the C1 report stays as the record for migration 156.

## Summary
- 0 P0, 1 P1 (resolved as `verified_clean` with measured evidence), 5 P2, 8 P3.
- Ship-blockers: none. Every finding has a terminal state below.

## Findings by lens

### L35 - rollout (seat 3)
- **P1: an older client's restore copies the new cloud column into its Hive progress map** (`mergeCloudProgress` copies every non-monotonic key verbatim), and the column has the same name as the Hive key `last_counted_week_key`. Terminal state: `verified_clean`, ledger `OLD-APK-MARKER-COPY`. Evidence (coordinator, `git grep` on `origin/main`, 2026-10-08): no client on main reads or writes that key (shipped clients use `last_streak_week`), so a copied value is never read; the only reader is Slice D, unpushed and shipping in the same pull request as C2, merged only after the C2 apply. Rule recorded: never build an APK from the intermediate D commit.
- P2: the existing harness is not the A1 text (it is `BEGIN ... ROLLBACK` with an embedded function copy). Terminal state: `closed_in_commit` when the A1 text is built: one `execute_sql` holding an always-aborting `DO`, `EXECUTE` of the exact file bytes under a distinct dollar tag, seed rows asserted, the cross-account case last, the transcript recorded in the diagnose doc.
- P2: the minted slug must contain `raise_streak_week_marker` or the migration-text test silently reads the stale draft. Terminal state: `closed_in_commit` (the mint step uses that slug and the draft is deleted after the copy).
- P2: the post-apply anon probe can misread PostgREST schema-cache lag. Terminal state: `closed_in_commit` in the A7 step: probe `pg_proc` / `has_function_privilege` first, then retry the HTTP probe over about 30 s.
- P3: `lock_timeout` leaks only on a non-transactional apply that fails before the closing `RESET` (safe direction). Terminal state: `verified_clean`, with the one-line failure procedure "run `RESET lock_timeout;` first" added to the read-only probe.
- P3: the closing assertion fails closed if a platform default grant adds a role. Terminal state: `verified_clean`, closed by A1 (it exercises exactly this creation path on prod).
- P3: the Hermes C2 section would have contradicted the C1 report's frontmatter verdict if appended to it. Terminal state: `closed_in_commit` (this is a separate file).
- Clean: draft is complete for migration use (no preamble to strip; diagnose id and the four header tags present); idempotent re-run; rollout order apply, then merge, then web deploy; CI stays green before the snapshot is regenerated.

### L15 / L16 / L23 - restore, cross-account, privilege (seat 2)
- **P2 (stale memory half):** the pushed-marker memory could suppress the push forever after an out-of-band cloud reset. Terminal state: `closed_in_commit`, ledger `C2-STALE-PUSHED-MEMORY`: the memory is `<userId>:<marker>:<IST day>`, so it heals within a day (test + mutant M15).
- **P2 (direct-write half):** RLS lets a user PATCH their own `last_counted_week_key`, bypassing the clamp and GREATEST. Terminal state: `verified_clean`, ledger `C2-DIRECT-WRITE-NOT-AN-INTEGRITY-BOUNDARY` (own row only, self-harm only, same posture as C1; stated in the diagnose doc, the registry and the services CLAUDE row).
- P3: the `auth.uid() IS NULL` pass-through trusts a missing `sub`, not the role; anon cannot reach the function and the closing assertion pins the grantees. Terminal state: `verified_clean` (identical to the C1 guard).
- P3: a device whose clock is a week ahead has its current week clamped to this IST Monday in the cloud. Terminal state: `verified_clean` (bounded to one week, self-heals).
- P3: the wider kill switch `disable_progress_restore_monotonic_merge` restores cloud-wins for the marker. Terminal state: `verified_clean` (one re-count, same trade-off as every max-wins field).
- Clean (exploit attempts failed): no path to another user's row; `search_path` pinned and every name qualified; ACL names every role; a NULL or negative key can never be stored; the conditional UPDATE writes nothing when unchanged and cannot invalidate another device's optimistic lock; A to B with an in-flight push is stopped by the server guard and by both client owner checks.

### L1 / L14 - writer-reader and schema (seat 1)
- No P0-P2. P3: `backups/live_schema_columns.json` lacks the column until the apply (terminal state: `blocked_on_user`, lands in the apply commit with the ledger entry; no gate is red before it). P3: stale memory after a cloud reset (closed above). P3: a failed marker push is retried on the next progress push (documented best effort). P3: stored marker is not an integrity boundary (closed above).
- Clean: the only production writers of the column are `completeWorkout` (Hive) and `raise_streak_week_marker`; no whole-row upsert (weekly-recalc, bootstrapper, restore completeness, sync_workout, sync_service) can null the column; the snapshot RPC does not know the column; all restore readers `select()` the whole row; no trigger, CHECK or realtime publication touches it.

## Founder triage
Nothing for the founder in the findings themselves. The live steps still need the founder's per-action word (CLAUDE.md 4.3): the migration number (A2), the always-aborting dry-run (A1), the apply, and the commit.
