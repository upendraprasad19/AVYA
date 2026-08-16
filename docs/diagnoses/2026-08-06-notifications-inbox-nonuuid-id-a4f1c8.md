---
bug_id: a4f1c8
date: 2026-08-06
batch: post38-auth-fixes (Unit 5 class 3 — welcome notification could never sync)
status: fixed
blast_radius: platform
symptom: >
  client_errors shows 6 × PostgrestException 22P02 "invalid input syntax for
  type uuid: local-welcome-1786019702890010" against
  sync_notifications_inbox_entry in one 1.0.0+38 session. Nobody reported it —
  it is silent to the user. The welcome notification simply never reached the
  cloud, on every install, since the inbox feature shipped, and retried forever.
concept: notifications_inbox_id_contract
sot_registry_entry: notifications_inbox_id_contract
writers: >
  lib/features/profile/services/notification_inbox_service.dart:181
  _seedWelcomeIfFirstLaunch minted id: 'local-welcome-${now
  .microsecondsSinceEpoch}' — a deliberately human-readable local id, and not a
  uuid. (The suffix in the observed row, 1786019702890010, decodes to
  2026-08-06 12:35:02 UTC, i.e. the new Google account's first launch.)
readers: >
  lib/core/services/sync/sync_restore_completeness.dart:254-278
  syncNotificationsInboxEntry reads entry['id'] and forwards it VERBATIM as the
  'id' key of an upsert into notifications_inbox with onConflict: 'id'. The
  cloud column notifications_inbox.id is uuid (migration 048), so the cast fails
  in Postgres before any row is written.
hive_key_prefix: "notificationsBox, keyed by AppNotification.id"
hive_key_formula: >
  notificationsBox[<AppNotification.id>] -> AppNotification.toJson(). The id was
  'local-welcome-<microsecondsSinceEpoch>'; it is now a v4 uuid. The seeded-once
  guard is a SEPARATE key (configBox['notifications_inbox_seeded_v1']), so
  changing the id format cannot re-seed an existing install.
sync_methods: SyncService.syncNotificationsInboxEntry (sync_restore_completeness.dart)
restore_methods: >
  _restoreNotificationsInbox (declared sync_restore_completeness.dart:441 in the
  pre-fix tree / :460 post-fix — an earlier draft said :427, which matches
  neither) pulls rows back from notifications_inbox. Unchanged — it was never
  reached for this row, because the row never made it to the cloud at all.
cloud_table: notifications_inbox
cloud_columns: "id uuid, user_id, notif_type, title, body, payload, created_at, read_at"
contract_test_path: test/contracts/notifications_inbox_uuid_id_behavioral_test.dart
ist_handling: >
  not_applicable — no date key or counter. created_at is a UTC ISO timestamp on
  both sides and is unchanged by this fix.
provider_invalidations: >
  None. The notification is already recorded into Hive before the sync fan-out
  fires; the inbox screen reads Hive and never depended on the cloud round-trip.
telemetry_op_types: >
  Existing sync_notifications_inbox_entry and
  sync_service_sync_notifications_inbox_entry. This fix REMOVES a recurring
  source of both rather than adding an op_type — those 6 rows per session were
  the bug reporting itself, repeatedly, with nobody reading it.
cross_account_guard: >
  Unaffected. The writer already early-returns when
  _supabase.currentUser?.id is null (sync_restore_completeness.dart:256-257) and
  stamps the live uid as user_id. The new guard runs after that, purely on id shape.
forbidden_patterns_checked: >
  No raw Hive.box; no setState; no inline isPro; no secrets; no
  Container(color:+decoration:). The new skip is NOT a silent data drop —
  see impact_analysis for why skipping is the correct semantic here.
proposed_fix: >
  Fix BOTH ends, because either alone leaves a live population broken.
  WRITER: mint const Uuid().v4() so new installs produce an id that can cast.
  SEAM: sync_restore_completeness.dart adds isUuidShaped(id) and skips a
  non-uuid id instead of posting it. Without the seam half, every install that
  ALREADY holds a 'local-welcome-…' row in Hive would keep retrying a write that
  is guaranteed to fail, forever — the writer fix alone helps only future
  installs.
  REJECTED alternative — coercing the legacy id into a uuid (e.g. hashing it):
  it would invent a cloud identity for a row whose whole purpose is to be local,
  and the deterministic-id class already caused a cross-user row-stealing bug in
  this codebase (f7e3a1, same file's nutrition sibling).
regression_test_planned: >
  test/contracts/notifications_inbox_uuid_id_behavioral_test.dart — 4 cases,
  green. The assertion is TWO-SIDED by construction: it pins that the exact
  observed legacy id ('local-welcome-1786019702890010') is rejected AND that a
  real v4 uuid is accepted, so neither an always-true nor an always-false
  predicate survives. A near-miss table (right group count/wrong widths,
  trailing junk, non-hex final group) blocks a lazy contains('-') implementation.
  The writer half is bound to the PRODUCTION mint
  (NotificationInboxService.newLocalNotificationId) and MUTATION-PROVEN:
  reverting it to 'local-welcome-<micros>' turns that case red. An earlier
  version minted its own uuid inside the test, which was circular — the
  mutation left all four green (round-1 review, P1-4).
  HONEST LIMIT, NARROWED: the seam IS wired — isUuidShaped is called at
  sync_restore_completeness.dart:278, in the real forwarding path. What no test
  asserts is that CALL SITE's presence; a refactor deleting the guard would not
  turn any of these red.
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze -> 0 errors, 0 warnings; 4/4 cases green" }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "the seeded-once guard is configBox['notifications_inbox_seeded_v1'], NOT the id, so changing the id format cannot re-seed or duplicate on an existing install" }
  - { tier: 3, name: postgres_schema, status: verified, evidence: "notifications_inbox.id is uuid (migration 048) — the column is correct; the client was wrong, so no schema change is warranted" }
  - { tier: 4, name: postgres_data, status: verified, evidence: "6 × 22P02 rows in client_errors, all in the 1.0.0+38 session, all naming the same local-welcome id — SPLIT 4 under op_type sync_notifications_inbox_entry and 2 under sync_service_sync_notifications_inbox_entry (the recordNonFatal twin). An earlier version attributed all 6 to the first op_type; total 6 was right, attribution was not." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "no migration — the fix is entirely client-side" }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "direct PostgREST upsert, no Edge Function" }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "no cron path" }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "RLS never evaluated — the uuid cast fails first" }
  - { tier: 9, name: storage, status: not_applicable, evidence: "no storage access" }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "no secret involved" }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "no third-party service" }
  - { tier: 12, name: client_server_contract, status: fixed_in_this_batch, evidence: "the contract is 'the id the client mints must be storable in a uuid column'; writer and seam now agree, and the seam refuses anything that would violate it" }
impact_analysis: >
  User-invisible and permanent, which is the worst combination for a defect's
  life expectancy: it produced no symptom, only telemetry noise, and so nothing
  ever prompted a look. The functional cost is narrow — the welcome notification
  is seeded locally and reads from Hive, so the inbox screen was always correct;
  only its cloud copy was missing, meaning it would not survive a reinstall.
  The larger cost was diagnostic: 6 identical failures per session added noise to
  exactly the table used to spot real regressions, and they count toward the
  alert (op_type is failure-shaped and 087 re-includes those).
  On why SKIPPING is correct rather than lossy: these are locally-seeded rows
  with no cloud counterpart to reconcile against. The alternative — continuing to
  POST them — is not "trying harder", it is issuing a request whose outcome is
  known in advance to be a 400.
related_bugs: f7e3a1, d4b8e2
recurrence: >
  Same family as f7e3a1 (a client-minted id colliding with a cloud key
  contract, in the sibling nutrition writer of this very file). The
  generalisable rule: an id that crosses the client/cloud seam is a TYPED
  contract, not a label — if the column is uuid, every writer that can reach it
  must mint uuids, and the seam should refuse what it knows cannot cast.
---

# Welcome notification could never sync (a4f1c8)

A one-line format choice on the writer met a `uuid` column on the reader, and
the disagreement was permanent, silent, and retried on every sync pass.

## Why both halves are needed

| Fix | Helps |
|---|---|
| writer mints a v4 uuid | new installs only |
| seam refuses non-uuid ids | every install already carrying a legacy row |

Shipping only the writer half would have left the existing population failing
forever while the diff looked like a complete fix.
