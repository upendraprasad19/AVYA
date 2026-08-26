---
bug_id: e4a1b7
date: 2026-08-26
batch: oi98-notification-prefs
status: fixed
blast_radius: platform
symptom: >
  A notification the user switched OFF silently turns back ON. Two independent routes, both
  verified against live prod. (1) After a reinstall the phone has no local record, so
  `emissionMap()` emits all ten keys as `{'enabled': true}` and the daily snapshot push
  REPLACES the server's stored preferences with that default — the choice is not merely
  forgotten, it is destroyed. (2) With no reinstall at all: every server reader takes the
  user's NEWEST `user_daily_snapshots` row and never falls through to an older one, and four
  Edge Functions write that row — three of which create a preference-less row when none exists
  for the day. Live on 2026-08-26, THREE of the five users who have ever stored a preference
  are in state (2) right now.
concept: >
  Authoritative data was placed in a derived-data channel. `snapshot_json` is a materialised
  read model: rebuilt wholesale from Hive on every write, trimmed to a byte budget, and
  replaced (not merged) on upsert. That is correct for disposable, regenerable data — which is
  every other key it carries. Notification preferences are the opposite: user intent, derivable
  from nothing, and the only copy in existence. A wholesale-replaced document also cannot
  represent "I know these three settings and nothing about the other seven", which is precisely
  a reinstalled device's state — so every attempt to patch the emission inside the blob leaked
  in a different place.
sot_registry_entry: notification_preferences
sot_registry_note: >
  The concept EXISTS (docs/sot_registry.yaml:8960) and is updated by this batch, not created.
  Its `restore_methods:` was an empty list with a comment explaining that no restore path read
  the key back — that comment is the bug, written down and accepted. This batch populates it,
  re-points writers/readers at the new transport, and records the snapshot as a
  `legacy_fallback:` carrying its retirement trigger.
  (Kept as a SEPARATE field: `check_sot_registry_citations.dart` resolves
  `sot_registry_entry:` against the registry's concept set, so that field must be a BARE
  identifier. Prose there classifies as unresolvable and fails the gate — which is how this
  was found.)
writers:
  - { file: lib/features/profile/services/notification_prefs_repository.dart, method: "write — THE Hive writer; session check first, normalises, then fires unawaited(pushSnapshot()) + the user_preferences push", line: 220 }
  - { file: lib/features/profile/services/notification_prefs_repository.dart, method: "emissionMap — pads EVERY key in allKeys to {'enabled': true} when unset. Correct under the snapshot's ABSENT=>SEND contract, and the exact mechanism that manufactured the all-enabled overwrite on an unrestored device before compileDailySnapshot learned to omit the key", line: 202 }
  - { file: lib/core/services/sync_service.dart, method: "compileDailySnapshot — folds emissionMap() into snapshot_json AFTER the buildAiContext spread so the trimmer cannot drop it", line: 899 }
  - { file: lib/features/profile/screens/profile/screen.dart, method: "_loadNotificationPreferences — returns a FIVE-key default when the box is empty, and key :204 is the LEGACY SINGULAR 'workout_reminder'. :340 persists that map verbatim, so a user's first toggle stores a partial, alias-shaped blob", line: 192 }
  - { file: supabase/functions/daily-snapshot/index.ts, method: "upsert on (user_id, snapshot_date) — replaces snapshot_json WHOLESALE; the destructive step", line: 341 }
  - { file: supabase/functions/rolling-context/index.ts, method: "read-modify-write upsert — 02:30 IST nightly for EVERY user; creates a preference-less row when the day has none, which is the usual cause of route (2)", line: 442 }
  - { file: supabase/functions/future-prediction/index.ts, method: "read-modify-write upsert on today's row", line: 393 }
  - { file: supabase/functions/beat-my-coach/index.ts, method: "read-modify-write upsert on today's row", line: 330 }
readers:
  - { file: supabase/functions/_shared/notification_prefs.ts, method_or_widget: "fetchNotificationPrefs — 'first row per user wins = most recent', with NO fall-through to an older row that actually carries the key. Consumed by six functions", line: 104 }
  - { file: supabase/functions/streak-guardian/index.ts, method_or_widget: "inline snapshot read — does not use the shared helper", line: 189 }
  - { file: supabase/functions/expiry-reminder/index.ts, method_or_widget: "inline snapshot read", line: 118 }
  - { file: supabase/functions/workout-window-closing/index.ts, method_or_widget: "inline snapshot read", line: 233 }
  - { file: supabase/functions/weekly-recap-ready/index.ts, method_or_widget: "inline snapshot read", line: 55 }
  - { file: lib/features/profile/services/notification_prefs_repository.dart, method_or_widget: "read — THE Hive reader; returns {} with no session, which is indistinguishable from 'user enabled everything'", line: 170 }
hive_key_prefix: notification_preferences
hive_key_formula: "userBox['notification_preferences'] — a fixed singleton key, not a row id. Owned exclusively by NotificationPrefsRepository; the pre-Unit-C writer wrote the SHARED configBox and is gone."
sync_methods: >
  Today: compileDailySnapshot -> pushSnapshot/pushSnapshotNow -> daily-snapshot EF. This batch
  moves it to _syncUserPreferences (lib/core/services/sync/sync_profile.dart), a partial-column
  upsert on user_preferences that names only the columns it owns.
restore_methods: >
  Today: NONE. `grep -rn "restoreNotificationPrefs" lib/ test/` returns zero hits — this is the
  whole defect. This batch routes it through the EXISTING _restoreUserPreferences
  (sync_profile.dart:649), already called from all four restore paths plus the single-call
  path (sync_service.dart:1231, :1296, :1424, :1620), so no new wiring is introduced.
cloud_table: >
  Today user_daily_snapshots (as one key inside the snapshot_json blob). After this batch,
  user_preferences — one row per user, keyed on user_id.
cloud_columns: >
  Today snapshot_json->notification_preferences. After this batch,
  user_preferences.notification_preferences (jsonb, NULLABLE with no default — NULL means "no
  record" and must stay distinguishable from {}, since collapsing those two is the root of this
  bug).
contract_test_path: "must add: test/contracts/notification_prefs_round_trip_behavioral_test.dart"
ist_handling:
  - { file: lib/core/services/sync_service.dart, line: 879, fn: "istDateStr — sets snapshot_date, which is what makes the (user_id, snapshot_date) upsert key IST-day-scoped. Relevant because it decides which row a same-day push replaces; the new column is not date-scoped at all, which removes the interaction." }
provider_invalidations: >
  None new. The settings screen reads through NotificationPrefsRepository.read() on mount rather
  than a Riverpod provider, so a restore that repopulates the box is picked up on next open.
telemetry_op_types:
  success: []
  failure: [restore_user_preferences, upsert_user_preferences]
cross_account_guard: >
  Required and explicitly added at the write sink. `_hive.userBox` is `userBoxGuarded.rawBox`
  (hive_service.dart:226) and rawBox DOES call _assertOwnership (guarded_box.dart:176), so a
  box-owner mismatch throws rather than clobbering — that half is already safe. What it does
  NOT cover is the case this batch introduces: _assertOwnership compares the BOX's owner to the
  live session, while the restore leg captured `userId` at entry. After an A->B swap where Hive
  has already reopened for B, the assert passes and A's cloud preferences would land in B's box.
  `SyncService.ownerChangedSince(userId)` (sync_service.dart:517) is the helper for exactly
  this, and its own doc says to call it AT THE WRITE SINK, one statement before the write.
forbidden_patterns_checked: >
  - Emission must never assert a preference the user did not choose: the new push OMITS the
    field entirely when the local blob is empty (the putIfPresent shape already used by
    sync_coach.dart:19-32), rather than writing {} or an all-enabled default.
  - No pushSnapshot from inside a restore leg (it would publish half-restored state).
  - No cloud-wins merge: adoption is per-key local-wins per ADR-0014.
  - Alias canonicalisation on BOTH sides before the containment test, so a box holding the
    legacy singular `workout_reminder` cannot have the cloud's canonical `workout_reminders`
    adopted over it (emissionMap's `direct ?? alias` at :198-201 would then prefer the adopted
    value permanently, flipping a deliberate OFF back ON on every sign-in).
related_bugs: >
  a9d3f1 (migration 103) — same anon-executable-function trap hit again by
  migration 123's grant block. `supabase/migrations/CLAUDE.md` documents it:
  Supabase's platform default privileges GRANT EXECUTE on every new
  `public`-schema function DIRECTLY to anon+authenticated, so `REVOKE ALL FROM
  PUBLIC` is a no-op for them and static review cannot see the grant because it
  lives in no migration. Caught here by running the live post-apply check that
  entry prescribes, which is the only guard that can see it.
recurrence: >
  TWO classes recur in this batch, and both are recorded rather than treated as
  one-offs. (1) guard-without-its-mirror — per-key merge applied on the RESTORE
  side with wholesale replace left on the WRITE side (B-pass Finding 1), and the
  owner re-check added to the new call but not its sibling two lines above
  (Finding 3). Two instances inside one fix, for a bug that is itself of that
  class. (2) the anon-executable `public` function above, second instance after
  a9d3f1.
bpass_findings_folded_in: >
  The B-pass on staging hash 885ebd47f4c0 found a P0 in the FIRST version of
  this fix and it is folded in here rather than filed. Migration 122 moved the
  concept out of the wholesale-replaced snapshot blob and into its own column —
  and left the WRITE side with the identical defect, because a jsonb COLUMN is
  also replaced wholesale (PostgREST emits `SET col = EXCLUDED.col`, assignment
  not merge). The stored map is legitimately SPARSE
  (`notification_settings_screen.dart:50-56` seeds from `read()` — `{}` on a
  fresh device — and each toggle adds ONE key), so device A storing
  `{streak_alerts:false}` and device B storing `{weekly_recap:false}` would
  each delete the other's key, reverting it to ABSENT => SEND. That is OI-98
  itself reached through the new home. Closed by migration 123's
  `merge_notification_preferences` RPC — a per-key additive jsonb `||` merge,
  SECURITY INVOKER and keyed on `auth.uid()` so the caller's own RLS applies.
  Recorded plainly because it is the same guard-without-its-mirror shape this
  batch exists to close: per-key merge was applied on the RESTORE side and
  wholesale replace left on the WRITE side.
proposed_fix: >
  Move the concept out of the snapshot blob and give it a real address: a nullable jsonb
  `notification_preferences` column on the existing `user_preferences` table. The client writes
  it through `_syncUserPreferences`'s partial-column upsert (omitting the field when it has no
  local record) and reads it back through the existing `_restoreUserPreferences`, which hands
  it to a new no-push `NotificationPrefsRepository.adoptFromCloud()` performing an
  alias-canonicalised, per-key local-wins merge behind an owner re-check. The ten server
  readers move to the column, with a temporary snapshot fallback so deploy ORDER does not
  matter, and the snapshot key plus `emissionMap()` are then removed in the same batch per
  §4.6. With one row per user and a partial upsert there is no newest-row-wins, no wholesale
  replace, and no shadowing — the failure mode stops existing rather than being detected.
regression_test_planned:
  - test/contracts/notification_prefs_round_trip_behavioral_test.dart
  - test/contracts/notification_prefs_server_guard_test.dart
  - test/contracts/notification_preferences_writer_to_reader_test.dart
  - test/contracts/notification_pro_key_scoping_test.dart
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "notification_prefs_repository.dart gains adoptFromCloud + a no-push write; sync_profile.dart gains the field on both the push and restore legs; profile/screen.dart:204's legacy-singular default key is corrected." }
  - { tier: 2, name: hive_local_state, status: fixed_in_this_batch, evidence: "userBox['notification_preferences'] gains a restore writer for the first time. Round-trip behavioral test asserts Hive write -> push payload -> cloud row -> restore -> Hive read using the real functions, not a re-implementation." }
  - { tier: 3, name: postgres_schema, status: fixed_in_this_batch, evidence: "Migration 122 adds user_preferences.notification_preferences (jsonb, nullable, no default). backups/live_schema_columns.json regenerated in the same commit so check_schema_column_refs.dart validates the new refs." }
  - { tier: 4, name: postgres_data, status: verified, evidence: "126 snapshot rows / 18 users; 14 rows carry the key across 5 users; ZERO rows have any key set to false; 3 of those 5 users have a newest row lacking the key while an older row has it. Nothing to back-fill — no user's real OFF survives anywhere, so the move cannot lose data." }
  - { tier: 5, name: migrations_applied, status: fixed_in_this_batch, evidence: "backups/applied_migrations.json entry paired in the same commit per §4.5. Live apply is a separate explicit authorization per §4.3." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: fixed_in_this_batch, evidence: "_shared/notification_prefs.ts plus four inline readers move to the column; deployed version recorded post-deploy. Each function's live verify_jwt is read from the API rather than a runbook." }
  - { tier: 7, name: cron_jobs, status: verified, evidence: "Schedules read from cron.job: rolling-context-nightly 0 21 * * * UTC (02:30 IST, every user) is the writer that creates the preference-less newest row; the ten reader jobs run from every-15-min (pr-detection) through Sunday 20:00 IST (weekly-recap-ready)." }
  - { tier: 8, name: rls_policies, status: verified, evidence: "user_preferences already carries own-row policies exercised by the existing _syncUserPreferences / _restoreUserPreferences round trip; server readers use SERVICE_ROLE and scope by explicit user_id filter." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket or object involved." }
  - { tier: 10, name: secrets_api_keys, status: not_applicable, evidence: "No secret added, read, or rotated." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "OneSignal delivery is downstream of the send/don't-send decision and is unchanged; no Razorpay or Firebase surface touched." }
  - { tier: 12, name: client_to_server_contract, status: fixed_in_this_batch, evidence: "The transport for this concept changes from a snapshot key to a column. The dual-read fallback means no deploy ordering constraint between client and server." }
impact_analysis: >
  Product impact TODAY is zero, and saying so plainly matters more than the headline number.
  Every preference currently stored in production is `true` — there are no `false` values
  anywhere in the table — so although three users' toggles are genuinely being ignored, they
  have not asked for anything to be off. The damage begins the moment a user turns their first
  notification off, which makes this a fix-before-it-matters, not an incident.

  The failure direction is always MORE notifications, never silence. That is deliberate
  (decision N2, ABSENT => SEND, so nobody loses an alert to a sync gap) and it is also why this
  survived so long unreported: the symptom is a user receiving something they thought they had
  switched off, which reads as a product being pushy rather than as a data bug.

  ⚠ THREE WRONG HYPOTHESES, recorded so they are not re-derived.

  (1) "splash_screen.dart:189 pushes 14 lines before checkAndSync at :203, so the reinstall
  push poisons the row before restore runs." REFUTED for the case it was invoked for.
  AndroidManifest.xml:21 sets `android:allowBackup="false"` and
  res/xml/data_extraction_rules.xml excludes `app_flutter` from BOTH <cloud-backup> and
  <device-transfer>, so a real reinstall loses the Supabase session AND Hive together;
  pushSnapshotNow then returns at sync_service.dart:936-937 for want of a session and cannot
  poison anything. The line IS live from the SECOND cold start onward, when a session exists
  and the box may still be empty — so the claim is wrong about the reinstall specifically, not
  wrong in general. This also settles OI-98's own `Blocked on:`
  (docs/audit/open_issues.md:2352-2354), which required the reinstall ordering be established
  before a fix was designed; it resolves opposite to the board's assumption.

  (2) "Keep emitting the full padded ten-key map whenever the local blob is non-empty."
  REFUTED, and it would have caused fresh data loss. profile/screen.dart:192-209 hands back a
  FIVE-key default when the box is empty, so the first toggle any user makes persists a partial
  blob; padding it to ten would then push five FABRICATED `true` values, that row becomes the
  newest carrying the key, and another device's real OFF is adopted away. OI-98's board entry
  at :2385-2388 had already named the correct answer — distinguish "never set" from "set to
  enabled".

  (3) "daily-snapshot's wholesale upsert is destroying fitness_summary / beat_my_coach /
  future_prediction, and the 79 preference-less rows carrying fitness_summary are that damage."
  REFUTED by live data: fitness_summary is present in 93 rows — presence is evidence it was NOT
  destroyed — and 90 of those 93 values are the empty string the CLIENT writes when it has no
  summary yet. beat_my_coach and future_prediction appear in ZERO of 126 rows, which is equally
  consistent with "never ran for these users" and proves nothing either way.

  Recurrence: this is the same class as sync_coach.dart:34-39, where `coaching_notes` was 100%
  NULL for every user because the upward sync never projected it — "AI memory was lost on every
  reinstall". That fix added the missing projection; this one removes the reason a projection
  was needed. All ~68 snapshot keys were checked: notification_preferences is the ONLY
  authoritative key without a restore leg. Every other user-intent key in the snapshot (why_now,
  known_injuries, body_part_priorities, typical_wake_time, preferred_workout_time) already has
  the partial-field push + field-by-field restore pair this batch adopts.
---

# e4a1b7 — notification preferences were push-only

## What a user experiences

You open Settings, turn off Streak Alerts, and it stays off. Some days or weeks later the
alerts come back. Nothing in the app tells you why, and turning it off again works — until it
doesn't.

## The two mechanisms

**Route 1 — reinstall.** Hive is gone, `read()` returns `{}`, `emissionMap()` fills all ten
keys with `{'enabled': true}`, and `daily-snapshot` writes that over the server's row. The
record of the choice is destroyed, not just unread.

**Route 2 — no reinstall needed.** Ten server jobs each read the newest snapshot row and stop
there. `rolling-context` runs at 02:30 IST for every user and, on a day you have not opened the
app, creates that day's row before your phone writes one. The row carries no preferences, so
every job that day reads a blank and sends.

## Why the container was wrong

`snapshot_json` is a derived read model — `ai_snapshot_builder.dart` renders 7 Hive boxes into
a 9.5 KB document that is replaced wholesale on write. Correct for regenerable data. Notification
preferences are user intent with no other copy, and a wholesale-replaced document cannot express
partial knowledge, which is exactly a reinstalled device's state.

## Why this fix is small

The codebase already has the right pattern in `sync_coach.dart` — push only non-null fields,
restore field by field — and `user_preferences` already has a working two-way leg wired into
every restore path. The fix adopts both rather than inventing anything, and removes the snapshot
key so the class cannot recur through it.
