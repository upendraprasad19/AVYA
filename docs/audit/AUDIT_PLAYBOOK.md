# Audit Playbook

> **When to use this file:** at the start of any multi-pass audit (live DB, schema drift, telemetry, sync, security). Captures the process discipline that the 2026-05-12 dual-pass audit (Master + Codex) refined.

## Lens registry

**Before dispatching agents, pick the lens set from [LENS_REGISTRY.md](LENS_REGISTRY.md).** That file is the canonical 41-lens checklist with charter, trigger, and precedent for each. Modes: `--all` (quarterly), `--security` (pre-launch), `--p0-blockers` (emergency triage).

## The shape

1. **Run TWO independent passes** (different framing, different agent teams).
   - One agent team focused on **inventory** (tables, columns, cron jobs, deployed Edge Functions, telemetry counts).
   - Another focused on **causal claims** (what code does, why a value is NULL, where data drifts).
   - Don't merge into one audit. The two passes catch different classes.
2. **Save raw output to `docs/audit/<date>/<source>-audit.md`.** Never act on a raw audit; always run the dedup pass first.
3. **Produce a consolidated report** at `docs/audit/<date>/consolidated-audit-report.md` with:
   - Overlap matrix (items both passes flagged)
   - Items unique to each pass (with severity tagging)
   - **All causal claims marked "unverified" until live SQL or file:line read confirms**
4. **Verify EVERY finding via live SQL or file:line read** before writing code. Cite the verification in the diagnose-doc.
5. **Close false alarms in the report.** Don't silently delete; mark `CLOSED — false alarm (verified via …)` so future audits see the lesson.

## Heuristics for spotting false-alarm patterns

These are the shapes that recurred on 2026-05-12 (3 of 21 Master Audit findings):

- **Table-name conflation.** Audit says "column X missing on table Y" but it's actually on table Z (sibling table). Fix: query `information_schema.columns` directly with the column name + see WHERE it actually lives.
- **Stale telemetry citation.** Audit says "N errors in 24h" but the errors are clustered in a 2-day window that ended 2 weeks ago. Fix: check `MAX(created_at)` on the citation before believing the audit's "ongoing."
- **Code-fix-already-applied.** Audit cites an old bug that's been fixed in a recent batch. Fix: grep the cited file:line + check git log for prior fix commits matching the file.
- **Causal vs symptomatic.** Audit says "X is NULL because of RLS." Actually X is NULL because the cron sent Bearer null. Fix: never accept causal claims without a repro.

## Verification SQL snippets

Schema claim:
```sql
SELECT column_name, data_type FROM information_schema.columns
WHERE table_schema='public' AND table_name='<table>'
  AND column_name IN ('<claimed_col_1>','<claimed_col_2>')
ORDER BY column_name;
```

Constraint claim:
```sql
SELECT conname, contype, pg_get_constraintdef(oid)
FROM pg_constraint
WHERE conrelid = 'public.<table>'::regclass
ORDER BY conname;
```

Cron claim:
```sql
SELECT jobname, schedule, active, substring(command, 1, 200)
FROM cron.job WHERE jobname ILIKE '<pattern>';
```

Telemetry claim:
```sql
SELECT op_type, error_code, COUNT(*), MIN(created_at), MAX(created_at)
FROM client_errors
WHERE op_type IN ('<claimed_op>') OR error_message ILIKE '%<phrase>%'
GROUP BY op_type, error_code
ORDER BY MAX(created_at) DESC LIMIT 20;
```

Edge Function deploy status:
```bash
$token = (Get-Content -Raw -Path 'supabase\.supabase\supabase access token.txt').Trim()
$headers = @{ Authorization = "Bearer $token" }
Invoke-RestMethod -Method Get -Uri 'https://api.supabase.com/v1/projects/<project>/functions' -Headers $headers |
  Select-Object slug, version, status, verify_jwt | Format-Table
```

## Fix-order rule

**Same-day batch** (per `feedback_no_deferrals.md`):

1. P0 fixes (production-breaking, data-loss, security) — code change + contract test + diagnose-doc + same-day commit.
2. Migrations — apply via MCP `apply_migration`, update `backups/applied_migrations.json` in the SAME commit (per `feedback_migration_apply_record_pair.md`).
3. P1 fixes batched into ONE code commit + ONE doc commit. The pre-commit hook is expensive; minimize hook invocations.
4. P2 + P3 in the same commits if cohesive, separate if cross-cutting.
5. Edge Function deploys: use `.claude/emit_payload.js` + `.claude/deploy_via_api.js` (per CLAUDE.md §0). Pass `--yes` for unattended.
6. CLAUDE.md updates + memory files + skill docs in the FINAL commit.

## Discipline at end of run

- Update `CLAUDE.md §19` with one entry per new bug class.
- Write a `feedback_<topic>.md` for any recurring pattern.
- Write a `project_audit_<date>.md` memory file with: what shipped, false alarms closed, non-obvious decisions, follow-ups deferred (with rationale).
- Update `MEMORY.md` index with one-line pointers.
- Update `docs/sot_registry.yaml` if any SoT writer/reader moved or any schema claim changed.

## Anti-patterns to avoid

- ❌ Trusting an audit's causal claim without a repro.
- ❌ Applying a fix without reading the cited file:line.
- ❌ Splitting `apply_migration` from `applied_migrations.json` update.
- ❌ Skipping the dedup pass when two audits run.
- ❌ Marking false alarms as "low priority" instead of CLOSED — they come back next audit.
- ❌ One commit per finding (kills the day with pre-commit hook runs). Batch by domain.

## Historical reference

| Date       | Audits run                      | Findings | False alarms | Notes |
|------------|---------------------------------|----------|--------------|-------|
| 2026-05-12 | Master (4-agent) + Codex        | 25       | 3            | Vault root cause caught by Master only; admin Edge Functions caught by Codex only. Both needed. |
