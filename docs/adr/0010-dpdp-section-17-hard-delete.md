---
adr_id: 0010
title: DPDP §17 hard-delete via delete-account Edge Function
status: accepted
date: 2026-05-04
deciders: Upendra
---

# ADR-0010: DPDP §17 hard-delete via `delete-account` Edge Function

## Context

The **Digital Personal Data Protection Act, 2023 (DPDP)** is India's
data-protection law. Section 17 grants every data principal (user)
the right to **erasure** of their personal data.

ICANBEFITTER stores user data across:
- Hive (on-device) — workout logs, food logs, profile, coach memory
- Supabase Postgres — backup of all user data (47 tables, many with
  `user_id` FK)
- Supabase Storage — progress photos (PRO), exercise media uploads
- Razorpay (external) — payment records (subject to RBI 8-year
  retention; can't be deleted)
- Telegram Bot (external on OpenClaw VPS) — `telegram_chat_id`
  linkage
- AI logs — `ai_coach_interactions` rows containing user-authored
  prompts

A user requesting deletion must have ALL of the above (except
RBI-mandated retained records) hard-deleted within DPDP-compliant
window.

Two architectural options:
1. **Soft-delete** (set `deleted_at = now()`, hide from queries).
2. **Hard-delete** (cascade `DELETE` across all user-scoped rows +
   purge Storage objects).

## Decision

**Hard-delete via `delete-account` Edge Function v1+.** When user
confirms deletion in the Profile screen:

1. Client posts to `delete-account` Edge Function.
2. Function (running with service-role) executes ordered cascading
   `DELETE` statements across all 47 tables in dependency order.
3. Function purges Storage objects under the user's prefix.
4. Function calls Razorpay subscription-cancel (records retained at
   Razorpay's end per RBI; we delete OUR pointer rows).
5. Function calls `auth.admin.deleteUser(user_id)` — final step.
6. Client wipes all Hive boxes + clears tokens + restarts to
   onboarding.

Pseudonymization migration applied where hard-delete would break
foreign-key referential integrity for anonymous aggregates (e.g.,
ranked_user leaderboards keep historical entries but the user_id
becomes a synthetic anonymous id).

DPDP-compliant retention exception: payment audit rows in `subscriptions`
table with `razorpay_payment_id` are retained per RBI's 8-year rule;
PII columns within those rows are pseudonymized.

Encoded in `supabase/functions/delete-account/` (CATASTROPHIC tier
in `docs/blast_radius.yaml`).

## Alternatives considered

1. **Soft-delete (`deleted_at`).** Rejected.
   - DPDP §17 calls for erasure, not concealment. A `deleted_at`
     timestamp with the row intact does NOT satisfy the law on a
     plain reading.
   - Audit risk if regulators inspect.
   - 47-table soft-delete cascade is its own complexity; not actually
     simpler than hard-delete.

2. **Client-only delete (wipe Hive, leave cloud).** Rejected.
   - Cloud is backup; deleting client without cloud means cloud
     becomes orphan PII.
   - Violates DPDP §17 trivially.

3. **Delete via direct SQL run by founder.** Rejected.
   - Founder MUST NOT be the bottleneck for every deletion.
   - Audit trail (who deleted, when, why) is inconsistent.
   - Doesn't scale past hundreds of users.

4. **Anonymization instead of deletion** (replace PII with random
   strings; keep aggregates). Considered for SOME tables — the
   ranked_user leaderboards retain pseudonymous entries so the
   leaderboard doesn't develop "holes" where deleted users were.
   But the primary user record + PII columns are HARD-deleted, not
   anonymized.

5. **External delete-as-a-service** (Privado, Transcend). Rejected
   at this time. Vendor overhead + cost not justified at our scale;
   our table count is bounded; hand-rolling the cascade is finite
   work.

## Consequences

Good:
- **DPDP §17 compliance** in the affirmative — a user's request
  produces actual erasure, not concealment.
- **Single Edge Function** (`delete-account`) is the auditable
  surface. Logs go to `ai_coach_interactions` (repurposed for
  delete-events) + Edge Function logs.
- **Client wipe is straightforward** — close + delete all Hive
  boxes, clear secure tokens, restart app.
- **Pseudonymization migration handles aggregates** without leaking
  PII into long-lived rows.

Bad:
- **Catastrophic blast radius.** A bug in `delete-account` deletes
  the wrong user's data. Mitigations:
  - `requires: hermes_pass` (in `docs/blast_radius.yaml`)
  - Service-role check + explicit `user_id` parameter validated
    against authenticated session
  - Dry-run mode for testing
  - Backup verification: every user's data should be backed up before
    deletion in a "tombstone" table for 7-day grace? (Deferred —
    DPDP doesn't grant grace, and a tombstone could itself violate
    erasure. Current design: no grace.)
- **External-system gaps.** Razorpay retains payment records by law;
  we can't delete those. Telegram chat history on the bot side
  requires a separate delete-call to the bot service. Documented in
  privacy policy.
- **No undo.** A user who deletes by mistake has no recovery path.
  Mitigation: confirmation dialog with explicit "this cannot be
  undone" copy + 24-hour cooldown after first request before
  finalize? (Not yet implemented — open question.)
- **Cascade order must be maintained** as schema evolves. New tables
  with `user_id` FK MUST be added to the delete-account cascade.
  Gate exists: `check_delete_account_table_coverage.dart`.

## Status

Active. Delete-account Edge Function v1 deployed Test #11
(2026-05-04). Catastrophic-tier; modifications require Hermes audit.

Open follow-ups (NOT deferrals — tracked as discoverable issues):
- 24-hour cooldown UX (per "no undo" risk above)
- Periodic cascade-coverage audit gate (Gate exists; ensure it runs
  on every new migration)

## See also

- CLAUDE.md §2a (Supabase project identity)
- `supabase/functions/delete-account/` (CATASTROPHIC tier)
- `docs/blast_radius.yaml` — `delete-account` glob entry
- `docs/architecture/payment.md` — DPDP §17 + delete-account flow
- `project_apk_test_11_batch.md` — original delete-account v1 ship
- ADR-0005 (Razorpay) — payment retention exception
