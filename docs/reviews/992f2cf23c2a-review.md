---
reviewed_at: 2026-09-28T14:35:00+05:30
staged_against: 992f2cf23c2a
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, ledger_integrity, blast_radius_mismatch, secrets_in_tree, guard_without_its_mirror, asserted_fixture_value, missing_input, function_exception_swallow]
findings_count: 2
verdict: accepted
---

# Code Review — 992f2cf23c2a (Task 34: migration 149 lands with its ledger entry)

The commit adds `supabase/migrations/149_sync_noop_suppress_completed_guard_sync_epoch.sql`
(applied live 2026-09-28, cloud version 20260928083027), its `backups/applied_migrations.json`
entry, `user_progress.sync_epoch` in `backups/live_schema_columns.json`, the live-verify SQL and
the trigger-table contract test, plus the 148→149 renumber across docs and comments.

One context-blind Sonnet reviewer read the staged diff (hash c212aaed81b0 at dispatch). Both
findings were fixed before the commit, which moved the hash to 992f2cf23c2a.

## Finding 1 — P1 — writer_reader_drift (closure ledger stale)
- **file:line:** docs/audit/day-swapper-sync-load.closure.yaml (entry `BUG-a9d3f6`)
- **claim:** The entry kept `terminal_state: blocked_on_user` and a reason saying the migration was
  drafted and awaiting the founder's go, while the same commit records the live apply (ledger
  `applied_at`, diagnose-doc `status: fixed`). The ledger contradicted its own commit.
- **verification:** `grep -n "BUG-a9d3f6" -A 12 docs/audit/day-swapper-sync-load.closure.yaml`
- **suggested-fix:** close the entry in this commit.
- **status:** fixed — `BUG-a9d3f6`, `H-h3F1`, `H-h3F2` and `H-h7F3` all moved to
  `closed_in_commit` with a labelled branch-state `commit:` (the validator's documented form for
  the commit that is itself closing them) and live evidence; OI-237 stays open until the §10 IO
  snapshot 3, per plan deviation D17. Gate 40 PASS.

## Finding 2 — P2 — writer_reader_drift (stale status claim)
- **file:line:** docs/sot_registry.yaml (A-fix-1 superseded note)
- **claim:** The renumber edit kept "(Task 7, NOT yet applied live as of this commit)", which this
  commit's ledger entry falsifies.
- **verification:** `grep -n "NOT yet applied live as of this" docs/sot_registry.yaml` → 0 hits after fix
- **suggested-fix:** state the live apply.
- **status:** fixed — now "(Task 7; applied live 2026-09-28, cloud version 20260928083027)";
  SoT parity gate PASS.

## Clean lenses (reviewer's own record, verified by the coordinator where numeric)
- Path drift: no live-path reference to 145/147/148 remains; only plan/spec history prose.
- Ledger: `sha256sum` of the migration = `117ad48b…5d3a5b`, equal to the ledger hash (coordinator
  re-ran it). Both JSON files parse.
- Header: all four tags present; `Rollback strategy: inline` with the commented reverse block.
- Secrets: none.
- Mirror: the 19-table list is identical across migration, contract test and live-verify SQL; the
  contract test's `equals()` would fail on a dropped table; the guard has positive, negative and
  discrimination cases.
- Fixture values: case 16's `v_wl_id` is assigned once from the case-3 insert and never
  reassigned; no other case reads a stale variable; only the labelled controls pass without the
  migration.
- Missing input: every referenced path exists.
- Dart: both touched Dart files carry comment-only hunks.

## Founder triage notes
Both findings were doc-state drift created by landing the apply and the renumber in one commit,
fixed before commit. No behavioural finding.
