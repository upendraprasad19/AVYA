---
reviewed_at: 2026-10-24T14:30:00+05:30
staged_against: 83b0e3c919aa
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value, L1, L2, L13]
findings_count: 12
verdict: accepted
---

# Code Review — 83b0e3c919aa (branch promo-codes-server-only, OI-406, migration 163)

Fresh Sonnet reviewer, context-blind, exhaustive command list (no DB, no scripts). No P0: the migration's two
statements are correct and complete against the measured live ACL. Every finding below was re-checked by the
author against the files before it was accepted, and every accepted fix is mutation-proven (scratchpad
`u4/mutate_u4.py`, 23 mutants, all red; M15-M18 and M23 were GREEN before these fixes). The diff after the fixes
differs from the reviewed hash; the fixes are tests, the verify SQL, a new rehearsal file and docs only (the
migration text is unchanged).

## Finding 1 — P1 — guard_without_its_mirror
- **file:line:** test/contracts/promo_codes_server_only_writer_to_reader_test.dart (group 6)
- **claim:** the service-role pin was a whole-text `contains`, satisfied by a header comment or by a kept constant while a call site switched keys.
- **verification:** mutants M15 (one call site on the anon key, constant kept) and M23 (key named only in a comment) were green on the reviewed tree.
- **suggested-fix:** strip comments; tie the key to every client.
- **status:** accepted — fixed: comments stripped (`_tsCode`, keeps `https://`), every `createClient(` second argument must be the service-role key, the constant must be read from the service-role env var, no `SUPABASE_ANON_KEY` in code. M15, M23 now red.

## Finding 2 — P1 — guard_without_its_mirror
- **file:line:** test/contracts/promo_codes_server_only_writer_to_reader_test.dart (group 7)
- **claim:** the re-open regex missed `GRANT ... ON ALL TABLES IN SCHEMA public`, `promo_codes` second in a list, and quoted identifiers (measured by the reviewer).
- **verification:** mutants M16, M17, M18.
- **suggested-fix:** widen the regex.
- **status:** accepted — fixed: all three shapes matched; M16-M18 now red.

## Finding 3 — P2 — asserted_fixture_value
- **file:line:** test/sql/promo_codes_no_client_access_live_verify.sql (P1, P2)
- **claim:** `insufficient_privilege` also catches a refused `SET ROLE`, so P1/P2 could pass vacuously.
- **verification:** read of the handler (no message check).
- **suggested-fix:** accept only the table's message.
- **status:** accepted — fixed: `ok` only when the message is `permission denied for table promo_codes...`; anything else is a fail naming the reason.

## Finding 4 — P2 — asserted_fixture_value
- **file:line:** test/sql/promo_codes_no_client_access_live_verify.sql (P10, P11)
- **claim:** `has_table_privilege` is blind to RLS; with no policy left only BYPASSRLS keeps the payment functions reading, and nothing proved it.
- **verification:** grep for `rolbypassrls` / `ROLE service_role`: none.
- **suggested-fix:** a real `SET LOCAL ROLE service_role` read plus `rolbypassrls`.
- **status:** accepted — fixed: P13 reads as service_role and requires the count to equal postgres' (and > 0) plus `rolbypassrls`. Pre-apply live run: P13 ok, 3 of 3 rows.

## Finding 5 — P2 — guard_without_its_mirror
- **file:line:** test/sql/promo_codes_no_client_access_live_verify.sql (P3, P4, P7, P9)
- **claim:** membership-inherited privileges and other client-callable definer functions were not checked.
- **verification:** read of the file.
- **suggested-fix:** `has_table_privilege` for every privilege; a `pg_proc` scan.
- **status:** accepted — fixed: P14 (`has_table_privilege` over all eight privileges, both roles) and P15 (definer functions whose source names the table and that anon/authenticated can EXECUTE). Pre-apply: P14 fail (grants present, as predicted), P15 ok.

## Finding 6 — P2 — writer_reader_drift (process)
- **file:line:** docs/plans/2026-10-24-payment-hardening.md (whole file staged on this branch)
- **claim:** the full plan staged on both branches risks an add/add conflict once the copies drift.
- **verification:** `cmp` of the two copies.
- **suggested-fix:** commit it on one branch only.
- **status:** accepted — resolved by procedure: the plan is COMMITTED only on this branch (U4 ships first); the payment-hardening worktree keeps its copy uncommitted and identical, and that branch (no commits yet) is rebased onto `main` after this merges, so its later plan edits are modifications, never an add/add.

## Finding 7 — P2 — writer_reader_drift (docs)
- **file:line:** docs/plans/2026-10-24-payment-hardening.md section 0.4 and F-3
- **claim:** the plan said SELECT/INSERT/UPDATE (live: all eight privileges); F-3 still asked the founder a question already answered; the diagnose-doc did not name the out-of-repo bot.
- **verification:** the plan lines vs the live read.
- **suggested-fix:** correct both; one sentence in the diagnose-doc.
- **status:** accepted — fixed in both plan copies and the diagnose-doc (bot disabled per the founder, OI-278, stated as not verified from the repo).

## Finding 8 — P2 — blast_radius_mismatch (procedure)
- **file:line:** plan U4 dry-run step; the verify's final RAISE
- **claim:** a `BEGIN; ...; ROLLBACK;` rehearsal never reaches its ROLLBACK, and the aborted session could keep DROP POLICY's ACCESS EXCLUSIVE lock on a payment-read table (the progress-photos verify header records this execute_sql behaviour).
- **verification:** read of the plan step and the verify.
- **suggested-fix:** one statement; a `pg_locks` check after.
- **status:** accepted — fixed: `test/sql/promo_codes_server_only_rehearsal.sql` is the verify block with the two statements run first inside it (one DO, no explicit BEGIN), pinned byte-equal to verify + migration by contract group 8 (M20-M22 red); its header names the after-checks (verify still `ok=10 fail=6`, `pg_locks` empty).

## Finding 9 — P3 — blast_radius_mismatch
- **file:line:** test/contracts/... group 4; docs/blast_radius.yaml:27,88
- **claim:** the change drops an RLS policy yet lands at platform because the slug and text avoid the catastrophic triggers; worth an explicit founder sentence.
- **verification:** `sed -n 27p docs/blast_radius.yaml`.
- **suggested-fix:** record the founder's "platform is intended".
- **status:** accepted — put to the founder with the apply go; the answer is recorded in `docs/plan-reviews/promo-codes-server-only.md`.

## Finding 10 — P3 — writer_reader_drift (recurrence)
- **file:line:** docs/diagnoses/2026-10-24-promo-codes-anon-readable-a6c2e9.md `recurrence:`
- **claim:** 7ad054 (migration 054 promo_code_uses policy cleanup) and 7ad035 are the same family; the "only hit" sentence was wrong.
- **verification:** `grep -n -i promo docs/diagnoses/2026-05-11-rls-cleanup-7ad054.md`.
- **suggested-fix:** add both; fix the sentence.
- **status:** accepted — fixed.

## Finding 11 — P3 — asserted_fixture_value
- **file:line:** test/sql/promo_codes_no_client_access_live_verify.sql P3, P4, P9
- **claim:** `ORDER BY 1` inside an aggregate orders by a constant; P9 lacked `refclassid`.
- **verification:** read of the lines.
- **suggested-fix:** order by the expression; add the filter.
- **status:** accepted — fixed.

## Finding 12 — P3 — missing_input / docs lag
- **file:line:** docs/architecture/database.md ACCESS bullets; contract group 5 extension filter
- **claim:** no doc states promo_codes is server-only until the other branch lands; group 5 scanned five extensions only.
- **verification:** grep of database.md; read of group 5.
- **suggested-fix:** a database.md bullet; scan every file.
- **status:** accepted — fixed: database.md line added on this branch; group 5 reads every text file under lib/ and web/ (M19 `.mjs` red).

## Lenses returned clean
Reported by the reviewer with commands (kept in the session transcript): Q1 every reader of `promo_codes` is the
service role or the definer counter (no client reader; the `promo_code_uses` FK needs no client privilege on
`promo_codes`); Q2 the REVOKE is complete for the measured grantor `postgres`; Q3 the rollback block restores the
measured state exactly; Q4 the verify SQL is valid PostgreSQL, read-only, and its predictions match the pre-apply
run; function_exception_swallow, unawaited_no_error_sink, secrets_in_tree: no hits; counts, paths and line
numbers verified.

## Founder triage notes
Self-triaged by the author (platform tier: the verdict is advisory, CLAUDE.md 4.3); Finding 9 goes to the founder.

## Tuning entry
- **2026-10-24** - blast-radius platform - 12 findings; 0 false_alarm; tuning: none (the guard_without_its_mirror lens found both P1s by mutating the pins, as its method says).
