---
bug_id: 7ad038
date: 2026-05-11
batch: audit-2026-05-11
status: shipped
symptom: H-38 disposition — Path 1 (dedupe SELECT policies). Supabase advisor flagged `public_bucket_allows_listing` on storage buckets `avatars` + `banners`. Inspection found 3 duplicate SELECT policies per bucket (6 redundant rows in pg_policies). Founder elected Path 1 cosmetic cleanup + accept the public-bucket UX trade-off (avatars need anonymous `<img src>` rendering for app UI).
concept: storage_policy_dedupe
sot_registry_entry: storage_bucket_policies
writers: []
readers: []
hive_key_prefix: "n/a"
hive_key_formula: "n/a"
sync_methods: []
restore_methods: []
cloud_table: storage.objects
cloud_columns: []
contract_test_path: "n/a"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: ["duplicate_select_policy_same_bucket"]
proposed_fix: Migration 059 drops 2 of 3 SELECT dupes per bucket. Keeps `Allow public read avatars` and `Allow public read banners` (canonical names matching the INSERT/UPDATE naming on the same buckets). Public-bucket setting unchanged — UX requirement for anonymous avatar rendering.
regression_test_planned:
  - "n/a (cosmetic dedupe; advisor flag persists by design)"
---
# H-38 — Storage SELECT policy dedupe (Path 1 / ACCEPTED)

## Decision

**Disposition:** ACCEPTED. Public-bucket `avatars` + `banners` are
intentional UX. The advisor flag `public_bucket_allows_listing` is
known and acknowledged; we will not flip `public=false` because that
breaks `<img src>` rendering everywhere in the app.

**Path chosen:** Path 1 (cosmetic dedupe). Path 2 (LIST-role denial)
and Path 3 (CDN migration) are deferred indefinitely. Revisit only if
the bucket ever stores anything sensitive.

## What was actually broken

`pg_policies` had 18 rows for avatars + banners across SELECT/INSERT/
UPDATE. Each (bucket, cmd) had 3 identical policies created by
multiple manual Dashboard tweaks over time:

| Bucket | Cmd | Duplicates |
|--------|-----|-----------|
| avatars | SELECT | `Allow public read avatars`, `Anyone can view avatars`, `Avatars are publicly accessible` |
| avatars | INSERT | `Allow authenticated uploads to avatars`, `Users can upload own avatar`, `Users can upload their own avatar` |
| avatars | UPDATE | `Allow users to update their own avatars`, `Users can update own avatar`, `Users can update their own avatar` |
| banners | SELECT | `Allow public read banners`, `Anyone can view banners`, `Banners are publicly accessible` |
| banners | INSERT | (3 identical, mirror of avatars) |
| banners | UPDATE | (3 identical, mirror of avatars) |

Functionally harmless (Postgres evaluates `OR` across same-cmd policies
for the same role; 3 identical clauses produce the same result as 1).
But noisy — every `EXPLAIN` on storage queries shows 3 policy filters,
and the advisor warning sticks regardless of which one runs.

## Scope of this fix

Path 1 = SELECT only. Drop 4 rows (2 dupes × 2 buckets), keep 2 rows
(1 canonical per bucket). INSERT + UPDATE dupes left in place — out of
scope for Path 1 and not adding any security surface beyond the
already-acknowledged public-bucket exposure.

If a future batch wants to clean up the INSERT/UPDATE dupes, the
pattern is the same: keep `Allow authenticated uploads to <bucket>`
and `Allow users to update their own <bucket>`, drop the rest.

## What ships

```sql
-- supabase/migrations/059_storage_select_policy_dedupe_h38.sql
DROP POLICY IF EXISTS "Anyone can view avatars" ON storage.objects;
DROP POLICY IF EXISTS "Avatars are publicly accessible" ON storage.objects;
DROP POLICY IF EXISTS "Anyone can view banners" ON storage.objects;
DROP POLICY IF EXISTS "Banners are publicly accessible" ON storage.objects;
```

Verified post-apply: `SELECT policyname FROM pg_policies WHERE
schemaname='storage' AND tablename='objects' AND cmd='SELECT' AND
(policyname ILIKE '%avatar%' OR policyname ILIKE '%banner%')` returns
exactly `Allow public read avatars` + `Allow public read banners`.

## Why no regression test

Source-grep would have nothing to grep — the duplicates lived only in
prod's `pg_policies`, not in source migrations. A pg_policies count
assertion is not portable across branches/environments (some old test
branches still have the dupes). The migration is idempotent
(`DROP POLICY IF EXISTS`); re-applying is a no-op.

## Related

- 7ad0c1 (audit C-1 — `subscriptions` RLS lock-down, same audit batch)
- 7ad054 (audit H-30/H-40 — broader RLS policy cleanup)
- 7ad035 (audit H-35/H-36/H-37 — SECURITY DEFINER hardening)
- Audit doc §11 (H-38) — disposition recorded as ACCEPTED.
