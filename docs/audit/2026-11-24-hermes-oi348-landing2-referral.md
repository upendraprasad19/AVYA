---
hermes_pass_id: 2026-11-24-hermes-oi348-landing2-referral
ran_at: 2026-11-24T20:15:00+05:30
batch_scope: staged diff of branch oi348-landing2-referral on origin/main 0759f7e5, after the B-pass fixes (migration 186 not yet applied)
lens_set: [L1, L2, L14, L35]
agents_dispatched: 4
findings_total: 11
findings_by_severity: { P0: 0, P1: 0, P2: 6, P3: 4, false_alarm: 1 }
verdict: accepted
---

# Hermes Pass — OI-348 Landing 2 PR B (B2 referral codes, migration 186)

Migration / schema batch, catastrophic by content (a SECURITY DEFINER function): lens set L1, L2, L14,
L35 (skill table "Migration / schema batch", L22 replaced by L2 because no column changed and the
risk is the definer function's privileges). One context-blind Sonnet seat per lens (founder rule:
Sonnet only), read-only, briefed with the recorded decisions. Consolidated by the coordinator.

## Summary
- 0 P0, 0 P1, 6 P2, 4 P3, 1 false_alarm. No ship-blocker.
- All findings fixed in the tree before the commit, or verified clean / recorded as an accepted
  consequence with its reason (below).

## Findings by lens

### L1 — writer_reader_drift
1. **P2 REAL** — the registry reader manifest missed `supabase/functions/restore-user-snapshot/restore_reads.ts:131-134` (the single-call restore read of the own live code). **Fixed:** added to `docs/sot_registry.yaml` `referral_code_issue` and to the diagnose readers.
2. **P2 REAL** — the writer manifest read as closed while builds before PR B still INSERT a first code through the INSERT-own policy until M2. **Fixed:** the registry description names these transitional writers and why they cannot overwrite each other with the function (old UPDATE refused; the function's `DO UPDATE ... WHERE expired` keeps a live row).
3. **P3 PARTIAL** — once a referrer regenerates, a friend holding the OLD link gets "We don't recognize that code." instead of "This code has expired...". **Accepted, recorded** in the diagnose impact analysis: the old code was refused either way; keeping expired rows would need a schema change (one row per user, UNIQUE(user_id)), out of the recorded design.
4. **P3 PARTIAL** — expiry edge differs at exact equality (function, restore EF, client restore: strict `>`; redeem-referral refuses only on `<`). **Recorded** in the registry description: a sub-millisecond window with no effect.

### L2 — RLS / privileges / SECURITY DEFINER
5. **P2 PARTIAL** — `extensions.gen_random_bytes` has no precedent in the repo. **Verified clean and pinned:** the dry runs exercise the mint path (13/13), and live verify case C4 now asserts `to_regprocedure('extensions.gen_random_bytes(integer)')` exists (true live).
6. **P3 REAL** — the service_role ACL entry is never shown. **Fixed:** C1 prints every grantee; dry run: `authenticated, postgres, service_role` (service_role bypasses RLS already; benign).

### L14 — ON CONFLICT arbiter
7. **P3 REAL** — live verify C3 joined `pg_attribute`, so an expression unique index (`lower(code)`) would be invisible. **Fixed:** C3 compares the full `pg_get_indexdef` of every unique index; true live.
   Checked clean: the `user_id` arbiter is a plain UNIQUE constraint (035), `DO UPDATE ... WHERE` false = no row, no error, then EXIT and the final re-select; a code clash reports `referral_codes_code_key` in both arms; no other ON CONFLICT on the table.

### L35 — migration reversibility / forward-compat
8. **false_alarm** — "the code format changed": the old client already minted `AVYA-` + 8 `[A-Z0-9]`. It corrected one claim of ours: the deleted `test/referral_code_test.dart` mirrored an even older name-prefix builder; the diagnose doc now says so.
9. **P2 REAL** — an old client racing the function after the apply can show an empty sheet once. **Recorded** in the diagnose impact analysis (testing accounts; the next open reads the live code).
10. **P2 REAL** — no rollback stated for M2. **Fixed (ledger):** `B2-M2-PR-C` now requires PR C to carry its own rollback (re-grant INSERT, re-create the INSERT-own policy).
11. **P3 REAL** — the ledger's `reopen_when` did not state who M2 breaks. **Fixed:** builds before PR B can no longer create a first code after M2 (testing accounts only).

## Founder triage
Triaged by the coordinator under the founder's standing instruction ("build it properly, no shortcuts"); no finding reverses a recorded decision.

## Action items
- [x] 1, 2, 6, 7, 10, 11 fixed in this batch (registry, diagnose doc, live verify, closure ledger).
- [x] 5 verified_clean (dry runs + C4).
- [x] 3, 4, 9 recorded as accepted consequences with their reasons (diagnose doc, registry).
- [x] 8 false alarm; the claim it corrected is fixed.

## Self-evolution
- 2026-11-24 / oi348-landing2-referral / L1, L2, L14, L35 / 11 findings (10 real or partial, 1 false alarm) / 4 Sonnet seats / ~1.5 min each.
- Signal: L1 found the only manifest gaps; L14 found the expression-index blind spot in a check a B-pass seat had proposed (a fix to a check is itself a check with a mirror).
