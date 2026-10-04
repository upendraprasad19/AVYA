---
bug_id: d4e8b2
date: 2026-07-27
batch: notif-prefs-cdefg
status: fixed
blast_radius: account
symptom: >-
  Every notification toggle in Settings was decorative. Verified live: 0 of 91
  user_daily_snapshots rows carried a notification_preferences key, so every
  server-side check fell through to its permissive default and no toggle ever
  stopped a send. Separately, the preferences lived in the SHARED configBox, so
  on a shared device the last saver silently set them for whoever signed in next.
concept: notification_preferences_emission
recurrence: >-
  Two known classes at once. The storage half is the cross-account leak class
  closed for 31 other keys by Test #10.1 / #11.1 — this key was simply never
  added to the sweep. The emission half is writer/reader drift: a client writer
  existed, a server reader existed, and nothing connected them, so the read
  always fell through to a default that looked like working software.
related_bugs: none
sot_registry_entry: notification_preferences_emission
writers:
  - { file: lib/features/profile/services/notification_prefs_repository.dart, method: write, line: 168 }
  - { file: lib/core/services/user_config_migrator.dart, method: purgeDeleteOnlyKeys, line: 225 }
readers:
  - { file: lib/core/services/sync_service.dart, method_or_widget: compileDailySnapshot, line: 842 }
  - { file: lib/features/profile/services/notification_prefs_repository.dart, method_or_widget: emissionMap, line: 150 }
  - { file: lib/features/profile/screens/profile/screen.dart, method_or_widget: _loadNotificationPreferences, line: 191 }
hive_key_prefix: notification_preferences (userBox, user-scoped)
hive_key_formula: single key in the per-user box — no date or id suffix
sync_methods: [compileDailySnapshot]
restore_methods: []
cloud_table: user_daily_snapshots
cloud_columns: [snapshot_json]
contract_test_path: test/contracts/notification_preferences_writer_to_reader_test.dart
ist_handling:
  - { file: lib/core/services/sync_service.dart, line: 821, fn: istDateStr_for_snapshot_date_unchanged }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [notification_prefs_read, notification_prefs_write]
cross_account_guard: true
forbidden_patterns_checked:
  - { pattern: "notification_preferences written to the shared configBox", absent_after_fix: true }
  - { pattern: "notification_preferences read via MigratedKey (configBox fallback)", absent_after_fix: true }
  - { pattern: "notification_preferences emitted inside the trimmed aiContext", absent_after_fix: true }
proposed_fix: >-
  Add NotificationPrefsRepository as the single session-gated reader/writer of
  the user-scoped key; purge the legacy shared-box copy delete-only (never
  copy); emit all 10 registry keys from compileDailySnapshot AFTER the
  buildAiContext spread so the snapshot trimmer cannot drop them; read the
  legacy singular alias so an existing OFF survives.
regression_test_planned:
  - test/contracts/notification_prefs_rescope_behavioral_test.dart
  - test/contracts/notification_preferences_writer_to_reader_test.dart
touched_layers_checked:
  - { tier: 1_client_code, status: fixed_in_this_batch, evidence: "repository + migrator purge + emission; flutter analyze clean; 10/10 rescope + 6/6 emission tests pass" }
  - { tier: 2_hive, status: fixed_in_this_batch, evidence: "key moves from shared configBox to per-user userBox; behavioral open->write->close->open-as-a-different-user test proves user B does not inherit user A value, and that A's value survives the round-trip" }
  - { tier: 3_postgres_schema, status: verified, evidence: "no schema change — the key rides inside the existing snapshot_json jsonb column" }
  - { tier: 4_postgres_data, status: verified, evidence: "live baseline 0 of 91 rows carry the key; this is the number the arc must move" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no SQL migration; the Hive-side purge is flagged in migrationBox" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "server guards are Unit E; no Edge Function changed here" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron involvement in C/D" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS path" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage objects" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: not_applicable, evidence: "OneSignal delivery path untouched until Unit E" }
  - { tier: 12_client_server_contract, status: fixed_in_this_batch, evidence: "the client now emits the key the server already reads; the parity of the two key lists is pinned by the registry constant and will be asserted against the server vocabulary in Unit G" }
impact_analysis: >-
  Two distinct user-visible harms. First, every toggle was a no-op: a user who
  turned off streak alerts kept receiving them, with no feedback that their
  choice was ignored — the worst shape of settings bug, because the UI actively
  asserts the opposite of the truth. Second, on a shared device the preferences
  crossed accounts: user A's OFF became user B's OFF permanently, and user B had
  no way to discover why their notifications had stopped. The fix direction is
  fail-safe throughout — absent, malformed, unreadable and no-session all
  degrade to SEND (decision N2), so no one loses a notification to a storage or
  sync gap; the only thing that can silence a push is an explicit stored false.
  C and D do not yet stop any send on their own: four of the ten keys have no
  server-side guard until Unit E, which is why this doc's tier-6 is
  not_applicable rather than fixed.
---

# Notification preferences: stored in the wrong box, and never emitted at all

## What was wrong

Two independent defects that together made the whole feature theatre.

**(c) Device-global storage.** `profile/screen.dart` wrote straight to
`HiveService.instance.configBox` — the SHARED box, which carries no owner. On a
shared device the last saver set preferences for whoever signed in next.

**(d) Never emitted.** Nothing put the key into the daily snapshot. Verified
live: **0 of 91** `user_daily_snapshots` rows carried it. Six server functions
read it; all six fell through to their permissive default, forever.

The combination is why this survived: the toggles *looked* wired, because the UI
round-tripped through Hive correctly. The break was one layer further out.

## Three traps, and why each is load-bearing

**Trap 1 — the trimmer.** `buildAiContext()` returns an already-trimmed map
(`ai_snapshot_builder.dart:420`). `notification_preferences` is not in the
trimmer's keep-set, so emitting it *inside* that map would let it be dropped —
and a dropped key reads to the server as absent, which means SEND. The users
who'd lose their preferences are exactly those with the biggest snapshots. So
emission happens **after** the spread in `compileDailySnapshot`, outside the
trimmed map.

The regression test proves the hazard rather than asserting it: it builds a
snapshot whose *keep-set* content alone exceeds the budget, so the trimmer can
never reach its target and goes on halving every non-keep key — including this
one. (My first version of that test used a single large non-keep blob and
passed for the wrong reason: the trimmer shrank the blob and never touched the
preferences. Rewritten to the shape that actually bites.)

**Trap 2 — the rename.** The client historically stored `workout_reminder`
(singular); every server reader expects the plural. Emitting only the plural
orphans the stored value → absent → SEND → a user who deliberately turned the
reminder OFF starts getting it again. A read-time alias preserves the choice.

**Trap 3 — the default.** Any key emitting something other than `enabled: true`
for an untouched user darkens that notification for everyone at once. Pinned by
a test that walks all ten keys.

## Why not `MigratedKey`, and why the purge is delete-only

`MigratedKey` is the obvious tool and the wrong one: **both** its paths fall back
to `configBox` (`migrated_key.dart:46-48` read, `:93-100` write), which is bug
(c) re-created through a helper. The repository does its own session check and
never touches the shared box.

The legacy value is **purged, not migrated**. `userScopedKeys` copies-then-
deletes, which is right when the value provably belongs to the person signed in.
Here it does not: the migration runs once per *device*, for whoever happens to be
signed in, and a shared-box value carries no owner. Copying would hand user A's
preferences to user B permanently — the exact bug. Ownership is unknowable by
construction, so the only safe action is to drop it, and dropping is harmless
because absent means SEND.

The purge uses its own flag (`notif_prefs_purge_v1_done`) rather than bumping
`_flagKey` to v3, which would re-run the completed 31-key copy sweep on every
existing device to reach one key.

## Verification

| Check | Result |
|---|---|
| `notification_prefs_rescope_behavioral_test.dart` | **10/10** |
| `notification_preferences_writer_to_reader_test.dart` | **6/6** |
| Rescope (the load-bearing one) | user A writes OFF → user B signs in on the same device → reads `{}`; A's value still intact when A returns |
| No shared-box write | `configBox` never contains the key after a write, including a signed-out write |
| Trap 2 | an OFF stored under the legacy singular key still emits `enabled: false` |
| Trap 1 | the trimmer demonstrably does not preserve the key, justifying the emission point |
| Malformed value | emits `enabled: true` and does not throw — a throw here would kill the user's entire daily snapshot |

## Not closed by C+D

The four new keys have **no server-side guard yet** — that is Unit E, and until
it lands those toggles still do not stop a send. Stated plainly because a reader
seeing "0/91 → non-zero" could otherwise conclude the feature is finished.
