---
reviewed_at: 2026-08-21T00:40:00+05:30
staged_against: 4eea94e469e2
blast_radius: catastrophic
reviewer: claude-b-pass-self-driven
lens_set: [gate_blind_spot, guard_without_its_mirror, presence_vs_value_check, live_vs_repo_drift, writer_reader_drift, audit_trail_integrity]
findings_count: 3
verdict: accepted
---

# Code Review — 4eea94e469e2 (OI-132: reconstruct the fileless migration, re-scope Gate 31)

Reviewed the staged diff adversarially, then verified every live claim it makes against
`dedsavbjuwgarrhphgnl` rather than against the diff's own prose. Three findings, all P1-or-P2,
all fixed in this same commit before it landed. The hash moved twice during remediation
(`8b0358c9d4b6` → `4eea94e469e2`); this file is named for the final staged state.

## Finding 1 — P1 — gate_blind_spot (the re-scope reintroduced the hole it closes)

- **file:line:** `scripts/check_cron_registry.dart` — input A's `if (!migrationsDir.existsSync()) { … exit(0); }` sat ABOVE the new snapshot read.
- **claim:** Gate 31 was re-scoped precisely because a file-scanning gate cannot see a migration
  that left no file. The new input B (`backups/live_cron_jobs.json`) was added to close that. But
  it was placed *after* input A's opening early exit — `supabase/migrations` absent → `SKIP`,
  `exit(0)`. So a tree without that directory exits **green having consulted neither input**: the
  identical never-ran-so-it-passed shape, reproduced inside the edit that closes it, roughly ten
  lines below a header comment explaining why it must not happen. None of the six tests written
  with the re-scope could see it — `setUp` unconditionally creates `supabase/migrations`, so every
  test ran on a tree where the early exit never fires.
- **verification:** temp repo with `backups/`, `docs/operations/`, `scripts/` and **no**
  `supabase/migrations`; snapshot lists `live_but_unregistered`, registry does not. Pre-fix gate:
  `exit 0`, stdout `SKIP: supabase/migrations not present`. Post-fix: `exit 1`, stderr names
  `live_but_unregistered`.
- **status:** accepted — FIXED. Input B is read first (`:72`), input A's absent-dir branch demoted
  from `exit(0)` to a `NOTE`, and the ordering is now pinned by a seventh test
  (`test/scripts/cron_registry_snapshot_gate_test.dart` — "NO supabase/migrations directory at all
  still enforces input B"). **Mutation-proven**: restoring the original ordering reddens exactly
  that one test and leaves the other six green (`00:01 +5 -1`). Logged as mutation (6) in
  `docs/audit/gate_test_ledger.yaml` and as `OI132-H` in the closure YAML.
- **two smaller defects fixed alongside, same file, same class:**
  (a) `--warn-only` called `exit(warnOnly ? 0 : 1)` on a bad snapshot, so in warn-only mode a
  missing snapshot exited 0 **mid-gate and skipped input A too**; `_readSnapshot` now reports and
  returns an empty set so the rest of the gate still runs.
  (b) the failure count printed `missingFromMigrations.length + missingFromSnapshot.length`, so a
  job both declared in a migration and live in the snapshot counted twice; now a union.

## Finding 2 — P1 — audit_trail_integrity (a literal `%s` passed the ledger gate)

- **file:line:** `backups/applied_migrations.json`, the migration `121` entry's `hash:` field.
- **claim:** The field was written as the literal string `"sha256:%s"` — an unsubstituted format
  placeholder — and `scripts/check_applied_migrations_ledger.dart` reported
  `[Gate 39] PASS: ledger has 126 structured records`. Its `_requiredKeys` list (`:26`) asserts the
  four keys **exist**; nothing inspects a value. The entry that carried it is the one whose own
  note explains that 60 of the ledger's 126 hashes already match no artifact (OI-135) and that an
  unexplained hash here "would have been the 61st". It was about to become the 61st in the same
  breath.
- **verification:** `git show :backups/applied_migrations.json | python3 -c "…print(d[-1]['hash'])"`
  → `sha256:%s`, with Gate 39 green.
- **status:** accepted — FIXED. Substituted the real digest
  (`sha256:e7fbbc280063fe…`, recomputed after the file changed again for Finding 3), and recorded
  the incident in the entry's own note rather than quietly correcting it. The gate hole is filed as
  **OI-137** with a separable step 1 (require `^sha256:[0-9a-f]{64}$` or a documented sentinel —
  the `120b` entry deliberately carries one) that blocks nothing, and a step 2 (recompute and
  compare) that needs the same grandfather decision as OI-135 because it reddens 60 pre-existing
  entries on day one.

## Finding 3 — P2 — live_vs_repo_drift (the fidelity claim was asserted, not measured)

- **file:line:** `backups/applied_migrations.json` note; `docs/audit/oi132-cron-registry.closure.yaml` OI132-A/G.
- **claim:** The reconstruction described itself as "recovered VERBATIM" and "byte-faithful", but
  nothing in the commit demonstrated it, and the manifest note simultaneously conceded the hash
  "attests that the repo file matches itself, NOT that it matches what ran". For a
  DO-NOT-APPLY reconstruction of a **row-destructive** prod migration, that gap is the whole value
  of the artifact. Separately, live ACL on both functions shows a `service_role=X` grant the file
  contains no statement for — a future reader could read that as a missing GRANT and "restore" it.
- **verification (live, project `dedsavbjuwgarrhphgnl`):**
  - `schema_migrations` version `20260815155823`, `statements` array length 1, containing 2 `GRANT`,
    4 `REVOKE`, 4 `cron.schedule`, and **0** occurrences of `service_role`.
  - Comment-stripped + whitespace-normalised repo file vs the same normalisation of
    `statements[1]`: **1539 characters, identical**, byte for byte.
  - `cron.job`: all four jobs present and `active`, jobids 33–36, schedules `22/25/38/41 4 * * *` —
    exactly what `CRON_REGISTRY.md` now lists.
  - `pg_proc`: both functions `prosecdef = true`, `proconfig = {search_path=public}`, `proacl =
    postgres=X/postgres | service_role=X/postgres` — no `anon`, no `authenticated`, no `PUBLIC`.
    So the OI132-G hygiene claim holds one layer past the file, and `service_role` comes from
    Supabase's `ALTER DEFAULT PRIVILEGES`, not from this migration.
- **status:** accepted — FIXED. The measurement replaces the assertion in the manifest note and in
  OI132-A; OI132-G now carries the live ACL evidence; and the migration file gains a
  `service_role IS NOT MISSING` comment so nobody adds a GRANT that was never there.

## What this commit does NOT prove, stated rather than implied

- **Snapshot freshness.** Gate 31 proves registry-vs-snapshot parity. It cannot prove
  snapshot-vs-live freshness — CI holds zero Supabase secrets (OI-105), so a live query would
  silently skip there, which is the same failure one layer up. Regeneration is a documented step on
  any migration that schedules or unschedules a job, and the SQL is in the gate's header.
- **Cadence correctness.** Gate 31 is a presence check; the registry's IST column is unenforced.
- **Substring safety.** Both inputs test membership with `registryContent.contains(name)`, so a
  jobname that is a substring of a registered one would false-pass. Checked: of the 28 live
  jobnames, **zero** pairs stand in a substring relation, so the gap is real but currently empty.
  Not fixed here — a word-boundary match is a behaviour change to input A as well and belongs with
  OI-78's allowlist work, not smuggled into this commit.
