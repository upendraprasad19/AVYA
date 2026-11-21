---
reviewed_at: 2026-11-05T09:00:00+05:30
staged_against: a60ec2e4 plus the staged plan, OI-470 and ledger-note edits
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, blast_radius_mismatch, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 2
verdict: accepted
verdict_note: no P0/P1; both P2s resolved in the batch
---

# Code Review (B-pass) - weight-logs-publication-drop

One context-blind Sonnet reviewer read the whole branch diff against `origin/main` plus the staged index
(migration 168, ledger entry, log-client-error payload archive v5, OI-464/OI-465 closure, OI-470, the plan).
It ran no gate or test (read-only brief).

## Finding 1 - P2 - asserted_fixture_value
- **file:line:** backups/applied_migrations.json (entry 168, `applied_at`)
- **claim:** `2026-11-05T07:20:00+05:30` has a round seconds value and looks approximated; the live apply cannot be re-read.
- **status:** accepted, fixed: the entry's note now says `applied_at` is approximate to the minute.

## Finding 2 - P2 - missing_input
- **file:line:** docs/plans/weight-logs-publication-drop.md ("v20 -> v21", `ezbr_sha256`)
- **claim:** live version numbers and the HTTP 201 cannot be verified from the repo; only the v5 archive is checkable.
- **status:** accepted: the plan cites the Management API response and the archive; the archive was verified byte for byte
  against `supabase/functions/log-client-error/index.ts` and `_shared/error.ts` by the reviewer.

## Checked and clean (reviewer evidence)
- Migration 168 is valid Postgres (`pg_publication_tables` columns, DO block, idempotent), four-tag header present, ASCII, no CR.
- Ledger hash equals `migration_ledger_hash.dart 168`; JSON valid; append-only; required keys present.
- Payload archive retention is the last 3 (v3, v4, v5); closed_issues.md changes are append-only plus the one intended line.
- OI-464/OI-465 are gone from open_issues.md; OI-470 is well formed and reserved on origin.
- Commit message trailers `closes-oi: OI-464` and `closes-oi: OI-465` are real trailers; no test or gate asserts publication membership.

## Tuning entry
- **2026-11-05** - blast-radius platform - 2 findings; 0 false_alarm; tuning: none (a read-only brief that forbids running gates still found nothing the pre-commit loop missed; both P2s were unverifiable-live-state notes).
