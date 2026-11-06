---
reviewed_at: 2026-07-13T07:05:00+05:30
staged_against: working-tree-vs-main (uncommitted; pre-apply — parity/schema gates block commit until migrations 101/102 apply)
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill (fresh context-blind agent a7e2fb20bc56)
lens_set: [admin_gate_fail_open, writer_reader_drift, function_exception_swallow, sql_correctness, kiswb_platform_guard, secrets_blast_rollback]
findings_count: 5
verdict: accepted
---

# Code Review (B-pass) — admin-dashboard batch — 052a3098df6c

Fresh, context-blind Sonnet reviewer. **The highest-priority lens for this
catastrophic-tier change — admin_gate_fail_open — returned CLEAN** with a full
path trace: anon key fails the `role==='service_role'` check in `cron_auth.ts`;
`getUser(anonKey)` yields `userId=null` → rejected; empty `ADMIN_USER_IDS`
rejects every caller (pinned by the Deno fail-secure test). No path reaches the
data-returning code without passing the gate. sql_correctness,
function_exception_swallow, kiswb_platform_guard, secrets_blast_rollback also
clean (details in the agent trace).

## Finding 1 — P1 — writer_reader_drift — FIXED
- **file:line:** lib/features/admin/widgets/engagement_tab.dart:43-47
- **claim:** "Workouts logged" stat tile bound to `current.activeLast7d` (a 7-day-active-USERS count, per migration 093:74-75), not any workouts figure — label/value mismatch; `workoutsLoggedToday` surfaced only in the trend sparkline, never as a tile.
- **verification:** the two sibling tiles read `chronological.last.aiMessagesToday` / `.streakMaintainedCurrentWeek` (today values); only tile 1 broke the pattern.
- **fix applied:** split into two correctly-labeled tiles — "Workouts today" → `workoutsLoggedToday`, and "Active (7d)" → `activeLast7d` (WAU is a valuable engagement metric surfaced nowhere else). 4 tiles total, each label matches its value.
- **status:** fixed

## Finding 2 — P1 — writer_reader_drift — FIXED
- **file:line:** lib/features/admin/widgets/ops_health_tab.dart:11-22
- **claim:** `_severityTone` switches on `'warning'`, but `alerts.severity ∈ {info, warn, critical}` (migration 076 CHECK constraint; independently confirmed by this session's live alert feed showing `info`/`warn`/`critical`). Every real warn alert fell through to `default: neutral` — active warnings visually indistinguishable from routine entries on the severity-triage tab. `'high'`/`'medium'` cases belonged to the unrelated `InsightSeverity` enum (wrong vocabulary pattern-matched).
- **verification:** SessionStart alert feed severities = info/warn/critical; migration 076 `severity IN ('info','warn','critical')`.
- **fix applied:** map `critical|high → bad`, `warn|warning|medium → warn`, else `neutral` — matches the real `'warn'` value and is defensive against both vocabularies.
- **status:** fixed

## Finding 3 — P1 — schema-snapshot-sync — RESOLVED AT APPLY-TIME (Task 11)
- **file:line:** backups/live_schema_columns.json (no `admin_metrics_daily`); check sites index.ts:170 / index.ts:159
- **claim:** `scripts/check_schema_column_refs.dart` FAILS now — the new `admin_metrics_daily` table isn't in the live-schema snapshot, so the two `.from('admin_metrics_daily')` refs are unresolved.
- **verification:** reviewer ran the gate → FAIL on both refs (reproduced).
- **resolution:** NOT pre-apply-fixable and NOT a deferral. The snapshot is regenerated FROM live `information_schema` (regen SQL in the gate header); the table does not exist live until migration 102 applies. Per CLAUDE.md §7 the regen lands in the SAME commit as the apply — which is the batch's gated Task 11 (apply → record manifest → regen snapshot → commit). The gate correctly blocks the commit until the table is live; that is the intended sequencing, identical to why `applied_migrations.json` is also updated only at apply-time. Hand-fabricating a snapshot entry for a not-yet-live table would be the same false claim as recording an unapplied migration.
- **status:** resolved_at_apply (terminal — no open work; the gate goes green in the apply commit)

## Finding 4 — P2 — router-reachability — FIXED (documented)
- **file:line:** lib/core/router/app_router.dart:_authRedirect + restoring_screen.dart
- **claim:** a bookmarked `/admin` in a fresh tab / hard refresh (Hive session not yet open) is caught by `shouldGateOnSessionOpen` → `/restoring` → lands on `/home`, not `/admin`. Founder must navigate to `/admin` a second time (which then works).
- **verification:** `_authRedirect` returns a bare `/restoring` with no `next` param; RestoringScreen's GoHome branch always lands `/home`.
- **fix applied:** documented as a known one-extra-navigation limitation in `lib/features/admin/CLAUDE.md` pitfalls. Deliberately NOT threading `?next=` through the auth/restoring flow — that path is the account-tier session-open guard (FIX-1 / OBS-6 territory); adding an admin-only convenience branch there would introduce regression risk to the critical auth path far exceeding the value of saving one cold-tab navigation on a founder-only screen.
- **status:** fixed (documented limitation)

## Finding 5 — P2 — doc-accuracy — FIXED
- **file:line:** docs/sot_registry.yaml:6222
- **claim:** revenue_tab reader `line_range: 1-164` but the file is 174 lines (grew when the trial/other tiles were added). Other five new line_ranges verified correct.
- **verification:** `wc -l lib/features/admin/widgets/revenue_tab.dart` → 174.
- **fix applied:** updated to `1-174`.
- **status:** fixed

## Founder triage notes
Self-triaged in auto mode. No security fail-open found (the one lens that could
make this a P0 on a catastrophic-tier change). All 4 actionable findings fixed
in-batch (no deferrals); Finding 3 is a terminal apply-time sequencing
dependency, not open work. Verdict: accepted.
