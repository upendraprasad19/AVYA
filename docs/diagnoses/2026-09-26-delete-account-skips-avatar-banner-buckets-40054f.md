---
bug_id: 40054f
date: 2026-09-26
batch: single-owner-a1 (single-owner remediation, audit docs/audit/2026-09-26-single-owner-audit-pass2.md P0 #6)
status: fixed
blast_radius: catastrophic
symptom: |
  delete-account's Storage purge (`delete-account/index.ts:398` before this
  fix) looped over a hard-coded list of three buckets —
  progress-photos, chat-media, coach-media — while the client also uploads
  user-owned objects into two more: avatars (`profile_provider.dart:119`) and
  banners (`profile_provider.dart:197`), both through
  `UserRepository.uploadImage` under `<userId>/…`. Both of those buckets are
  PUBLIC. So an account deletion (DPDP §17) left the user's profile photo and
  banner behind, still reachable by URL.
  Live on 2026-09-26: avatars and banners held 7 objects each; 6 of each sat
  under folders of users who no longer exist, created 17–29 April. Exactly
  five buckets exist in the project, matching the five the client names.
concept: user_owned_storage_buckets
sot_registry_entry: user_owned_storage_buckets
writers:
  - { file: lib/features/profile/providers/profile_provider.dart, method_or_widget: "avatar upload (bucket avatars)", line: 119 }
  - { file: lib/features/profile/providers/profile_provider.dart, method_or_widget: "banner upload (bucket banners)", line: 197 }
  - { file: lib/features/profile/repositories/progress_photo_repository.dart, method_or_widget: "_bucket = 'progress-photos'", line: 40 }
  - { file: lib/features/ai_coach/screens/ai_coach/media_picker.dart, method_or_widget: "chat-media upload", line: 232 }
  - { file: lib/features/ai_coach/repositories/coach_media_repository.dart, method_or_widget: "_sourceBucket chat-media / _destBucket coach-media", line: 27 }
readers:
  - { file: supabase/functions/_shared/purge_user_storage.ts, method_or_widget: "purgeUserStorage — recursive list + chunked remove per bucket (extracted; a failed list keeps listed paths since Hermes L37-F1)", line: 55 }
  - { file: supabase/functions/delete-account/index.ts, method_or_widget: "serve handler — purgeUserStorage(admin.storage, userId, USER_OWNED_BUCKETS, requestId)", line: 357 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: storage.objects (buckets progress-photos, chat-media, coach-media, avatars, banners)
cloud_columns: []
contract_test_path: test/contracts/delete_account_purges_all_user_buckets_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  - "delete-account purge logs per bucket (unchanged text) and account_deletion_log.storage_purge_status, which now carries avatars and banners counts"
cross_account_guard: Not applicable — the purge is scoped to the JWT-derived user id's own `<userId>/` prefix, unchanged.
forbidden_patterns_checked:
  - "adding avatars and banners to the literal array in delete-account — rejected: that keeps two lists (client, EF) with nothing tying them; the next new bucket drifts the same way. One exported list, tied to the client by a contract test."
  - "SQL DELETE on storage.objects for the 12 orphans — rejected: bypasses the Storage API and leaves the files; cleanup goes through the Storage dashboard or a service-role one-shot, founder's explicit go."
proposed_fix: |
  - `_shared/user_owned_buckets.ts` `USER_OWNED_BUCKETS` — the five buckets.
  - `_shared/purge_user_storage.ts` `purgeUserStorage` — the recursive
    OI-32 purge extracted verbatim, testable against a fake storage client.
  - delete-account calls it with the one list.
  - test/contracts/delete_account_purges_all_user_buckets_test.dart ties
    every bucket the client names in code to the list.
  - The 12 existing orphans: removed by the founder from the Storage
    dashboard (path list supplied) or a service-role one-shot — explicit go.
  - Hermes (docs/audit/2026-09-26-hermes-single-owner-a1.md) L37-F1: a
    failed `.list()` of one page or subfolder THREW out of the listing and
    discarded every path already collected, so nothing in that bucket was
    removed — a public avatar listed fine included — while the deletion
    still returned 200. The behaviour predates this batch (OI-32's purge) and
    the extraction copied it to five buckets. The listing now records the
    failure as `<bucket>_list:<path>: <msg>`, moves on to the next folder, and
    every listed path is still removed. The residual gap (an object missed or
    re-uploaded after the purge, with no reader of storage_purge_status and no
    sweep outside chat-media) is written in the module header and is unit a4
    of the batch plan, not left implicit as the removed call-site comment
    left it.
regression_test_planned:
  - supabase/functions/_shared/purge_user_storage_test.ts (new, 7 tests) — every listed bucket purged, nested paths included, other users' objects untouched; an error in one bucket is recorded and the rest still purged; empty bucket reports 0; (Hermes) a failed subfolder list still removes every listed path; a remove error is recorded, not counted, and other buckets still purge; folders of exactly 1000 and 1001 objects purge across pages.
  - test/contracts/delete_account_purges_all_user_buckets_test.dart (new, 5 tests) — positive control (discovery finds the five live buckets); every bucket argument in lib/ resolves or the test fails (fail closed), and every pass-through allowance is still in use; the resolver reads constants by VALUE and flags a call, a qualified name and an aliased storage handle; every client bucket is on USER_OWNED_BUCKETS; delete-account uses the list, not a literal array.
  - test/contracts/phase_c_oi_closures_test.dart — OI-32 group repointed to the extracted module, plus a wiring assertion; the recursive-call pin is whitespace-tolerant and comment-stripped since the L37-F1 fix destructures the result across lines (reverting the loop to a flat top-level list reddens it, 1 / 16).
  - "Mutations run (rule 21): see the Mutation proof section below."
impact_analysis: |
  - Account deletion now also removes the user's avatar and banner. Same
    recursion, same chunking, same non-fatal error handling. One deliberate
    change (Hermes L37-F1): a failed list no longer discards what was
    already listed, and is recorded as `<bucket>_list:…` instead of
    `<bucket>_exception:…` (nothing reads that string — grep of supabase/,
    lib/, scripts/).
  - Existing orphans (6 avatars + 6 banners of already-deleted users) are not
    touched by this code; they need the one-off cleanup above.
  - Deploy: delete-account. No migration.
  - No kill switch, deliberately (B-pass c5d659f52986 Finding 4; CLAUDE.md
    §4.6 and the catastrophic tier's `feature_flag`): the only "old path" is
    the DPDP §17 defect itself — skipping two buckets — so a switch back to it
    would be a switch to non-compliance. The change is additive to a loop
    whose per-bucket errors were already non-fatal. Rollback is a redeploy of
    the previous delete-account version (the deploy script snapshots it first).
related_bugs: [a2d0e1, b4e2a9, d5b2f8]
recurrence: >-
  Third incomplete-erasure bug in delete-account: a2d0e1 (OI-32) purged only
  top-level entries; b4e2a9 and d5b2f8 were never-run paths. Same class as
  a2d0e1 — the purge's reach smaller than what the client writes — now closed
  structurally by tying the client's buckets to the list in a test.
touched_layers_checked:
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "deno check delete-account — Check OK. Deploy pending founder go + a fresh Management API token." }
  - { tier: 9, name: "Storage buckets + objects", status: verified, evidence: "storage.buckets: exactly progress-photos, chat-media, coach-media, avatars, banners. avatars 7 / banners 7 objects, 6 of each under deleted users' folders, created 17–29 Apr (read-only query 2026-09-26)." }
  - { tier: 1, name: "Client code", status: verified, evidence: "Client bucket names: profile_provider.dart:119,197; progress_photo_repository.dart:40; coach_media_repository.dart:27-28; media_picker.dart:232 — exactly the five." }
---

# delete-account left avatars and banners behind

## Mutation proof (rule 21)
Each mutation applied by exact-string replacement with the match count checked
(= 1) before running, then reverted. Counts are failed / total.

| Mutation | Red |
|---|---|
| M6 purge skips the first bucket (`buckets.slice(1)`) | 3 / 4 `purge_user_storage_test.ts` |
| M7 `"avatars"` removed from USER_OWNED_BUCKETS | 1 / 4 Deno + 1 / 3 `delete_account_purges_all_user_buckets_test.dart` |
| M8 delete-account passes the old 3-bucket literal instead of the list | 2 / 19 (`delete_account_purges_all_user_buckets_test.dart` + `phase_c_oi_closures_test.dart`) |

M8 was run against a strengthened assertion: the first draft of the new test
checked `contains('USER_OWNED_BUCKETS')`, which the import line alone satisfies
while the call passes a literal. It now matches the call's argument list.

### B-pass c5d659f52986 — Finding 3 (the discovery could be defeated)
The first version found client buckets by three regexes, one of which only
recognised a constant whose NAME ended in `bucket`/`Bucket`. The reviewer added
a file writing to `user-exports` through `_exportsLocation` and all 3 tests
stayed green — the same drift this fix closes, one refactor away. Discovery
now resolves every bucket argument (`storage.from(X)`, `bucket: X`,
`destinationBucket: X`) by value through same-file string constants, and fails
closed on anything it cannot read: an expression, a qualified name, or a
`.storage` handle used any way other than `.storage.from(`. One enumerated
pass-through — `UserRepository.uploadImage`'s `bucket` parameter, whose
callers the named-argument form covers — and the test fails if that allowance
stops matching anything.

| Mutation | Red |
|---|---|
| Mb9 the reviewer's probe: a new `lib/` file writing through `_exportsLocation = 'user-exports'` | 1 / 5 |
| Mb10 resolver keyed on names ending in `bucket` again | 1 / 5 |

### Hermes L37-F1 (partial-list failure)

| Mutation | Red |
|---|---|
| Mh11 the listing throws on a list error again (the pre-fix behaviour) | 2 / 7 `purge_user_storage_test.ts` |
