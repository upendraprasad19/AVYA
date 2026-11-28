---
reviewed_at: 2026-11-25T14:30:00+05:30
staged_against: d3a7572413ed
blast_radius: catastrophic
reviewer: claude-sonnet-via-skill (2 context-blind seats) + coordinator
lens_set: [writer_reader_drift, blast_radius_mismatch, secrets_in_tree, guard_without_its_mirror]
findings_count: 7
verdict: accepted
verdict_note: "Seats ran on staged hash b2edd3fa2f3a; every fix below is in the staged state. First written for e25fd57f0d28; renamed to d3a7572413ed when staging moved after the 189 apply (ledger row, closure ledger, diagnose tier 5), plus the Hermes report and its one registry fix (EXECUTE wording). No P0/P1."
---

# Code Review — OI-348 B2 PR C (migration 189, referral_codes server-only writes)

Two context-blind Sonnet seats on staged hash `b2edd3fa2f3a`: seat A the SQL (migration 189, the
live verify), seat B the Dart pin, the docs and registry, and repo fallout. Both read-only; seat A
ran the DDL plus the verify cases inside one always-aborting request on `dedsavbjuwgarrhphgnl`.
Clean results the seats verified: no client-role writer of `referral_codes` anywhere (lib/,
supabase/functions/, scripts/, integration_test/, test/, .claude/skills/; live functions, views,
cron, triggers, publications); the function keeps writing on both paths (owner postgres, RLS not
forced); W2/W3 cannot pass for the wrong reason; the rollback block is a faithful inverse of the
live pre-189 state; header tags correct; no secrets; the 186 function pin still passes; SoT parity
and diagnose validation pass; every `line_range` of `referral_code_issue` opens on its method.

## Finding 1 — P2 — guard_without_its_mirror
- **file:line:** test/contracts/referral_codes_server_only_writes_pin_test.dart (`_reopensReferralCodes`)
- **claim:** the tripwire missed real re-open spellings, measured with a scratch copy of the helper: a GRANT listing several tables with referral_codes not first; a `--` inside a string literal hiding the rest of the line; `ALTER TABLE ... OWNER TO authenticated`; dynamic SQL (`EXECUTE format('GRANT ...', 'referral_codes')`); `GRANT service_role TO authenticated`; `ALTER ROLE authenticated BYPASSRLS`; `RENAME`.
- **status:** fixed. Rewritten per statement and fail-closed (a statement naming referral_codes with GRANT / POLICY / OWNER / ROW LEVEL SECURITY / RENAME / EXECUTE, REVOKE and DROP POLICY exempt; bulk schema grants; ALTER ROLE anon/authenticated; role-membership grants); comments stripped outside literals only; every spelling above is a control. Mutants Q2, Q4, H1, H2 red.

## Finding 2 — P3 — guard_without_its_mirror (false positives)
- **claim:** block comments were never stripped (a commented-out GRANT flagged); several harmless spellings flag.
- **status:** fixed for block comments (control added). The remaining harmless flags (a grant to service_role, ENABLE ROW LEVEL SECURITY) are kept on purpose: fail-closed, stated in the test header.

## Finding 3 — P3 — guard_without_its_mirror
- **claim:** timestamp-named migrations were never scanned (`supabase migration new` / dashboard names).
- **status:** fixed. Timestamp names dated 2026-11-25 or later are scanned, and any other `.sql` name except the legacy `all_migrations_combined.sql`. Mutants Q3, H3 red.

## Finding 4 — P3 — doc accuracy
- **claim:** the diagnose doc stated the pin's test count wrong (25; the run said 26).
- **status:** fixed; the count is re-derived from the rewritten file's run (49).

## Finding 5 — P3 — guard_without_its_mirror (pin)
- **claim:** only the self-check's RAISE line was pinned; deleting any check kept the Dart test green.
- **status:** fixed. The 13 messages are pinned in order (one per check), plus the predicates a message cannot carry (the SELECT policy's roles and condition, the RLS state). Mutants Q1, Q1b, Q1c red.

## Finding 6 — P3 — blast_radius_mismatch (self-check)
- **claim (seat A):** the self-check never asserted that service_role and postgres keep their rights; `REVOKE ALL ... FROM service_role` passed it (only verify C1 caught it).
- **status:** fixed. SELECT/INSERT/UPDATE/DELETE required for both (effective privileges). Live mutant M14 raises. M15 (`REVOKE INSERT FROM postgres`) survives correctly: postgres inherits service_role, so the function still writes; stated in the migration.

## Finding 7 — P3 — guard_without_its_mirror (self-check)
- **claim (seat A):** the SELECT policy was checked by name and command only; `USING (true)` passed (verify R1 caught it).
- **status:** fixed. Roles `{public}` and the condition text are required. Live mutants M12, M13 raise.

## Founder triage notes
No P0/P1; every finding fixed in the staged state. Re-verified after the fixes: live dry run 12/12, 15 live self-check mutants (M15 correct survivor), 11 pin mutants red, pin 49/49.

## Tuning entry
- **2026-11-25** - blast-radius catastrophic - 7 findings; 0 false_alarm; tuning: a tripwire over LATER files must be measured against a spelling table (multi-object lists, literals hiding comment markers, dynamic SQL, role-level grants, other filename schemes), and a self-check pinned only by its RAISE line is unpinned: pin one message per check.
