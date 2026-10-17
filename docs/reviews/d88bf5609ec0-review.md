---
reviewed_at: 2026-06-12T00:00:00Z
staged_against: d88bf5609ec0 (git diff --cached: delete-account/index.ts + test)
blast_radius: catastrophic
reviewer: claude-sonnet-bpass
triaged_by: claude-opus
findings_count: 1 P1 (→fixed), 2 P2 (1 fixed / 1 acknowledged), 4 false_alarm
verdict: accepted
---

# B-pass — delete-account non-fatal Razorpay-cancel (a2c8e6, catastrophic)

Fresh context-blind Sonnet review of the catastrophic-tier change to the DPDP §17
delete-account Edge Function. Full triage below; all findings resolved.

## F1 — P1 — audit-insert failure silently swallowed → a failed cancel could vanish → **FIXED**
- **file:line:** supabase/functions/delete-account/index.ts (the `account_deletion_log` insert `.catch`)
- **claim:** The `account_deletion_log` row is the ONLY durable out-of-band record of a FAILED Razorpay cancel. The insert was `.catch((e) => console.warn(...))` — silently swallowed. In a CORRELATED outage (Supabase degraded at the same moment Razorpay is unreachable): cancel fails → erasure proceeds → user deleted → audit insert fails silently → **no trace anywhere that this user has an active billing subscription needing manual cancellation**, and the user has no account to dispute the charges.
- **fix applied:** the catch now logs at `console.error` (not warn), AND when `razorpayStatus` indicates a failed cancel (`cancel_failed:*` / `lookup_failed`) it emits a distinctive, greppable `ORPHAN_BILLING request_id=… user=… razorpay_cancel_status=…` line — the function logs survive independently of the table row, so the billing obligation is recoverable even in the worst case.
- **verification:** `grep -n "ORPHAN_BILLING\|audit insert failed" supabase/functions/delete-account/index.ts` + test `delete_account_razorpay_cancel_nonfatal_test.dart` (the F1 assertion).
- **status:** accepted (fixed in this commit)

## F3 — P2 — stale file-header comment ("MUST succeed or 502 abort") → **FIXED**
- **file:line:** supabase/functions/delete-account/index.ts:9 (header flow comment)
- **fix applied:** header step 4 now reads "best-effort/NON-FATAL (a2c8e6): cancel-first … a failure is RECORDED … and the erasure PROCEEDS …".
- **status:** accepted (fixed in this commit)

## F2 — P2 — test is source-grep only (no Deno behavioral harness) → **ACKNOWLEDGED**
- **claim:** the regression test scans the `.ts` as text; no runtime path is exercised (CLAUDE.md §4.4 rule 21 prefers behavioral).
- **triage:** the EF runs in Deno; the repo has NO Deno behavioral harness for Edge Functions, so source-grep + a post-deploy live smoke is the established pattern for EF tests here (cf. `schedule_completion_duration_writer_to_reader_test`, `security_definer_revoke_migration_test`). The behavioral check for this change is the **live smoke after the HELD deploy** (per the founder's go). Accepted as a known Deno-EF limitation, not a fixable-here defect.
- **status:** acknowledged (Deno-EF limitation; live smoke is the behavioral gate)

## F4–F7 — false_alarm (reviewer-confirmed clean)
- Cancel-first preserved (healthy cancel still runs before the auth delete);
  loop continues on a per-sub failure (other subs still attempted); the final
  `cancel_failed` status is set AFTER the loop so a later success can't erase a
  recorded failure; auth.users delete still happens after the cancel block;
  `razorpay_cancel_status` is `text` (live-verified, no length issue); no injection
  (only the Razorpay sub id + numeric status are interpolated).

## Verdict
**accepted** — P1 + the actionable P2 fixed in this commit; F2 acknowledged as a
Deno-EF tooling limitation. The change removes a DPDP §17 erasure blocker while
preserving cancel-first AND a durable (table + last-resort log) record of any
failed cancellation. Live deploy HELD for the founder's separate go (§4.3).
