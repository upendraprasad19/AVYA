---
bug_id: c1ea30
date: 2026-05-17
batch: Hermes audit 2026-05-17 — Phase B (P1 security)
status: shipped
symptom: |
  `clean-orphan-media` daily cron deleted from `coach-media` bucket
  — which migration 070 (also shipped 2026-05-17) had designated as
  long-term consented retention. Transient analysis bucket is
  `chat-media`. Cron + helper RPC were both pointing at the wrong
  bucket. Risk: every user-initiated coach-media save would be
  deleted by the 30-day TTL cron the next day.
concept: clean_orphan_media_bucket_target
sot_registry_entry: subscription_payment_grace_window
writers:
  - { file: supabase/functions/clean-orphan-media/index.ts, method: serve handler RPC call, line: 54 }
  - { file: supabase/functions/clean-orphan-media/index.ts, method: storage remove, line: 78 }
  - { file: supabase/migrations/071_rename_orphan_media_rpc.sql, method: find_orphan_chat_media + DROP old, line: 1 }
readers:
  - { file: supabase/migrations/047_clean_orphan_media_cron.sql, method_or_widget: original (pre-rename) RPC, line: 9 }
  - { file: supabase/migrations/070_coach_media_bucket_and_caps.sql, method_or_widget: bucket semantic definitions, line: 1 }
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: storage.objects
cloud_columns:
  - bucket_id
  - name
  - created_at
contract_test_path: "must add: test/contracts/clean_orphan_media_targets_chat_media_test.dart"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "n/a — cleanup cron operates on storage.objects with isPro recheck"
forbidden_patterns_checked:
  - { pattern: "'coach-media' as cleanup target in clean-orphan-media", absent: true }
  - { pattern: "find_orphan_coach_media exists as a SQL function", absent: true }
proposed_fix: |
  Two-line change in `clean-orphan-media/index.ts`: flip `.from('coach-media')`
  → `.from('chat-media')` and `rpc('find_orphan_coach_media')` →
  `rpc('find_orphan_chat_media')`.

  Migration `071_rename_orphan_media_rpc.sql` drops the old function and
  creates the renamed function with `WHERE bucket_id = 'chat-media'`.
  Old name dropped (not aliased) so any stale caller fails loudly.

  `clean-orphan-media v5 → v6` deployed. Migration 071 applied via MCP.

  Data-loss verification: queried `storage.objects WHERE bucket_id =
  'coach-media' BEFORE deploying. The bucket was created earlier today
  (OI-23 / migration 070) and the consent UI flow (OI-25) hasn't shipped
  yet, so the bucket was empty. No data loss occurred.

  Why missed by today's audit: lens L41 (cross-document semantic
  consistency — cleanup-cron vs migration intent) did not exist. OI-18
  Storage audit measured current bucket state, not cleanup behavior.
  Migration 070 was shipped the SAME morning as Hermes's audit —
  classic "intent landed in migration, behavior never updated".
regression_test_planned:
  - "must add: test/contracts/clean_orphan_media_targets_chat_media_test.dart"
---

# Bug c1ea30 — clean-orphan-media deletes wrong bucket

closes-oi: OI-30

## Root cause

Three documents had to stay in sync; one didn't:

1. Migration 047 (Test #9, 2026-05-03): `find_orphan_coach_media` RPC +
   cron schedule + Edge Function originally scoped to `coach-media`
   bucket. At the time `coach-media` was the only bucket for AI image
   analysis.
2. Migration 070 (OI-23, 2026-05-17): split into TWO buckets:
   `chat-media` (transient, 30-day TTL for free users) + `coach-media`
   (long-term consented saves). Documented in the migration comments.
3. clean-orphan-media Edge Function + RPC: never updated. Still
   targeting `coach-media`.

If migration 070 had shipped + a free user had then saved a photo to
`coach-media` via the (not-yet-built) OI-25 consent UI, the next day's
cron run would have deleted it. The OI-25 deferral saved us.

## Fix

- `clean-orphan-media/index.ts:54` — flip RPC call.
- `clean-orphan-media/index.ts:78` — flip `storage.from()`.
- Migration 071 — DROP `find_orphan_coach_media`, CREATE
  `find_orphan_chat_media` (same logic, different bucket filter).
- Deploy clean-orphan-media v5 → v6 with the new RPC name.

The migration is intentionally NOT a rename (`ALTER FUNCTION ...
RENAME`) — DROP + CREATE so any stale Edge Function deployment that
still calls the old name fails with "function does not exist" instead
of silently deleting from the wrong bucket.

## Verification

- Live `cron.job` query confirms the cron schedule still points at the
  Edge Function (not the RPC); only the RPC name inside the function
  changed.
- `storage.objects WHERE bucket_id = 'coach-media'` returns 0 rows
  (bucket created today, consent UI deferred per OI-25).

## Follow-up

OI-25 (coach-media consent UI flow) remains OPEN. When that ships,
the upload path will write to `coach-media` AND the user will
explicitly opt in. The cleanup cron will continue targeting only
`chat-media`.

## Related

- migration 047 (original RPC)
- migration 070 (bucket semantics)
- OI-23 closure (created the coach-media bucket)
- OI-25 (deferred consent UI)
- `docs/audit/LENS_REGISTRY.md` — L41 cross-document semantic consistency
