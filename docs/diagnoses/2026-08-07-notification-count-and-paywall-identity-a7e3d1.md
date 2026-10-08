---
bug_id: a7e3d1
date: 2026-08-07
batch: oi-unit1
status: fixed
blast_radius: feature
symptom: |
  Two defects on the same surface, both filed as OI-76.

  (1) COUNT. The Profile tab's Notifications row subtitle reads "N/M enabled".
  It counted all 10 registry keys, including `protein_alerts` and
  `plateau_alert`, which are PRO-only. A free user cannot toggle them (the rows
  render a lock, not a switch) and their server functions PRO-gate independently,
  so the subtitle read at least 2/10 "enabled" permanently, for notifications
  that could never fire for that user.

  (2) PAYWALL IDENTITY — worse than the board described, and user-visible.
  Tapping a locked PRO notification row called
  `showPaywallSheet(context, feature: AppConstants.featureProgressPhotos)`. That
  constant is the literal string `progress_photos`. `PaywallSheet` renders its
  `feature` argument verbatim into the letterhead — `'${widget.feature} is a PRO
  feature'` — so the user was shown the raw identifier:

      "progress_photos is a PRO feature"

  `_featureSubtitle` switches on DISPLAY STRINGS ('Progress Photos',
  'Photo Analysis', …), so a snake_case id matched no case and fell to the
  generic default copy, and the `paywall_shown` telemetry emitted
  `feature=progress_photos`, splitting this surface off from every sibling in
  the conversion funnel.

  (3) Found while fixing the above, same surface, fixed here: all three
  NOTIFICATIONS rows in `settings_screen.dart` pushed
  `/profile/notification-settings` with no `extra`, so the route's
  `extra['isPro'] as bool? ?? false` defaulted a PAYING PRO user to free and
  showed them a lock on the two PRO rows. The screen's own `initState` comment
  names "show a paying PRO user a lock" as a harm it fixed, but that fix only
  self-healed the prefs map, never `isPro`.
concept: notification_preferences
sot_registry_entry: notification_preferences
writers:
  - { file: lib/features/profile/services/notification_prefs_repository.dart, method_or_widget: "write (THE writer; unchanged by this fix)", line: 205 }
  - { file: lib/features/profile/services/notification_prefs_repository.dart, method_or_widget: "proOnlyKeys (NEW — display-only PRO-key set, single source for the isProFeature flags)", line: 78 }
  - { file: lib/features/profile/services/notification_prefs_repository.dart, method_or_widget: "controllableKeys (NEW — tier-scoped denominator for the subtitle)", line: 90 }
readers:
  - { file: lib/features/profile/screens/profile/profile_content.dart, method_or_widget: "build — 'N/M enabled' subtitle, now scoped via controllableKeys", line: 72 }
  - { file: lib/features/profile/screens/profile/profile_content.dart, method_or_widget: "onProLockedTap — now forwards the tapped row's display title", line: 506 }
  - { file: lib/features/profile/screens/notification_settings_screen.dart, method_or_widget: "onProLockedTap (VoidCallback? -> ValueChanged<String>?)", line: 21 }
  - { file: lib/features/profile/screens/notification_settings_screen.dart, method_or_widget: "_NotificationRow lock GestureDetector — passes its own title", line: 396 }
  - { file: lib/features/profile/screens/notification_settings_screen.dart, method_or_widget: "isProFeature flags now read from proOnlyKeys instead of `true` literals", line: 231 }
  - { file: lib/features/profile/screens/settings_screen.dart, method_or_widget: "_notifSettingsExtra — supplies isPro + onProLockedTap the bare pushes omitted", line: 22 }
  - { file: lib/shared/widgets/paywall_sheet.dart, method_or_widget: "_featureSubtitle — new 'Protein Alerts' / 'Plateau Check' cases", line: 100 }
  - { file: lib/core/router/app_router.dart, method_or_widget: "notification-settings builder — extra cast widened to ValueChanged<String>?", line: 545 }
hive_key_prefix: "notification_preferences"
hive_key_formula: "literal key on userBox (per-user scoped via HiveUserSession)"
sync_methods: [write, emissionMap, compileDailySnapshot]
restore_methods: [read]
cloud_table: user_daily_snapshots
cloud_columns: [snapshot_json]
contract_test_path: test/contracts/notification_pro_key_scoping_test.dart
ist_handling:
  - "Not applicable — this fix touches a display denominator and a paywall label. No date key, no counter reset, no cloud `date` column is read or written. `write`/`emissionMap` are unchanged."
provider_invalidations: []
telemetry_op_types:
  success: [paywall_shown]
  failure: []
cross_account_guard: |
  Untouched and verified still intact. `notification_preferences` lives on the
  per-user `userBox` behind `HiveUserSession`; the repository does its own
  session check and NEVER falls back to the shared `configBox` (that fallback
  was Unit C bug (c)). This fix adds only a `const Set` and a pure function over
  `allKeys` — neither reads storage — plus UI-layer plumbing. The regression
  test opens a real user session via `HiveUserSession.openForUser` and exercises
  write -> emissionMap through the guarded box rather than asserting on source
  text.
forbidden_patterns_checked:
  - { pattern: "proOnlyKeys subtracted from allKeys", absent: true }
  - { pattern: "proOnlyKeys filtered inside emissionMap()", absent: true }
  - { pattern: "feature: AppConstants.feature* passed to showPaywallSheet (any call site in lib/)", absent: true }
  - { pattern: "isProFeature: true as a bare literal on a notification row", absent: true }
proposed_fix: |
  (1) Add `proOnlyKeys` + `controllableKeys({required bool isPro})` to the
  repository and scope ONLY the profile subtitle's numerator and denominator
  through it.

  The load-bearing constraint: `allKeys` and `emissionMap()` are deliberately
  NOT narrowed. The server's rule is ABSENT => SEND (repository header, decision
  N2), so dropping a PRO key from the emitted snapshot would turn that
  notification ON for free users — the exact inverse of the intent, and a live
  regression rather than a cosmetic one. This is the obvious wrong
  implementation, so it is pinned by an explicit test rather than a comment.

  (2) Pass display strings, not ids, to `showPaywallSheet`, and make the
  callback carry WHICH row was tapped (`VoidCallback?` ->
  `ValueChanged<String>?`) so 'Plateau Check' shows plateau copy instead of
  protein copy. Two `_featureSubtitle` cases added. This aligns the call site
  with the convention every other call site already follows, visible in one
  place at `profile_content.dart:345-349`: the id goes to
  `gateAndVerify(AppConstants.featureX, …)` and the display string goes to
  `showPaywallSheet(context, feature: 'Display Name')`. The bug was passing the
  GATE id into the PAYWALL display slot.

  (3) `settings_screen.dart` passes `isPro` (already in scope at its `build`
  from `ref.watch(subscriptionInfoProvider)`) plus a paywall callback, via one
  `_notifSettingsExtra` helper shared by all three rows.
regression_test_planned:
  - test/contracts/notification_pro_key_scoping_test.dart
  - test/contracts/paywall_feature_label_test.dart
touched_layers_checked:
  - { tier: 1, name: client_code, status: fixed_in_this_batch, evidence: "flutter analyze (3.41.4, CI-pinned) — 0 errors / 0 warnings, 44 pre-existing infos, unchanged from the pre-edit baseline. flutter test test/contracts/ test/router/ -> 2832 passed." }
  - { tier: 2, name: hive_local_state, status: verified, evidence: "notification_pro_key_scoping_test.dart opens a real HiveUserSession, writes a partial prefs map through NotificationPrefsRepository.write, and asserts emissionMap() still returns all 10 keys with the user's one explicit `false` preserved. Negative-controlled: filtering proOnlyKeys inside emissionMap fails the test." }
  - { tier: 3, name: postgres_schema, status: not_applicable, evidence: "No schema change. The prefs travel inside the existing user_daily_snapshots.snapshot_json blob; no column added, dropped or renamed." }
  - { tier: 4, name: postgres_data, status: not_applicable, evidence: "No data migration. Stored per-user prefs are read and emitted exactly as before — emissionMap is byte-identical in behaviour, which is the point of the tier-2 test." }
  - { tier: 5, name: migrations_applied, status: not_applicable, evidence: "No migration authored in this fix." }
  - { tier: 6, name: edge_function_code_vs_deploy, status: not_applicable, evidence: "No Edge Function touched by a7e3d1. The 10 server-side readers of notification_preferences consume the snapshot blob, whose shape is unchanged (tier-2 evidence). The sibling OI-82 fix in this same batch does touch an Edge Function and carries its own deploy record." }
  - { tier: 7, name: cron_jobs, status: not_applicable, evidence: "No cron schedule or dispatch touched. The notification crons keep reading the same 10 keys." }
  - { tier: 8, name: rls_policies, status: not_applicable, evidence: "No table, policy or grant touched." }
  - { tier: 9, name: storage, status: not_applicable, evidence: "No bucket or object touched." }
  - { tier: 10, name: secrets, status: not_applicable, evidence: "No secret read, added or rotated." }
  - { tier: 11, name: external_services, status: not_applicable, evidence: "OneSignal delivery is driven server-side off the snapshot, which is unchanged. No OneSignal, Razorpay or Firebase configuration touched." }
  - { tier: 12, name: client_server_contract, status: verified, evidence: "The client->server contract for this concept is the snapshot's `notification_preferences` map. Its producer (emissionMap) is unchanged and pinned by the tier-2 test; the 10 server readers were re-enumerated by grep for the SoT registry entry landed alongside this fix (6 via _shared/notification_prefs.ts, 4 reading snapshot_json inline). Nothing this fix changes crosses the wire — the count is display-side and the paywall label is client-render-side." }
impact_analysis: |
  USER-VISIBLE, both directions.

  Free users: the Notifications subtitle now reads out of 8 rather than 10 and
  can reach 0/8, which it previously could not. Tapping a locked row now shows a
  branded paywall naming the actual feature instead of the string
  "progress_photos is a PRO feature".

  PRO users entering via Settings: previously shown a lock on two features they
  had paid for; now shown working toggles. This is the (3) half and is the most
  consequential user-facing change in the fix, despite not being what OI-76
  filed.

  NOT affected, by construction: what the server sends. `emissionMap()` still
  emits all 10 keys for every tier, so no user's notification delivery changes.
  That invariant is the single thing most likely to be broken by a future
  "simplification" of this code, which is why it has its own negative-controlled
  test rather than a comment.

  Scale today: 18 users. This is a correctness-and-trust fix landed before
  growth, not an outage — stated so the closure does not overclaim.
related_bugs: []
recurrence: |
  NOT a recurrence of a known class, stated explicitly so a future audit can
  verify rather than assume.

  It is, however, a second instance of the shape `feedback_source_grep_false_
  confidence.md` warns about, from the other end: OI-76's own board text
  asserted "§4.4 r19 keys server-side verification off that id", which is FALSE.
  `showPaywallSheet` (paywall_sheet.dart:23) is display + telemetry only and
  never reaches `gate()` or `verifyFromServer()`; r19 keys off `gateAndVerify`'s
  positional first argument, a different call. Acting on the board's claim
  without re-deriving it would have produced a fix aimed at a server-side
  contract that does not exist. The false claim is corrected on the board in the
  same commit as this doc.

  The near-miss worth recording: the first-drafted fix was "swap the constant
  for a new AppConstants.featureNotifications". That would have changed nothing
  — `_featureSubtitle` switches on display strings, so any snake_case constant
  still falls through to the generic default. The bug was only visible by
  reading what PaywallSheet does with the argument, not by reading the argument.
---

# a7e3d1 — notification count counted un-toggleable PRO keys; paywall showed a raw feature id

## Writers and readers, named before the fix (§4.1)

The concept is `notification_preferences`. Its writer is
`NotificationPrefsRepository.write` (`:205`); its emission point into the daily
snapshot is `SyncService.compileDailySnapshot` (`sync_service.dart:842`, calling
`emissionMap()` at `:187`). Neither is modified here.

The readers that were wrong:

- `profile_content.dart:72` — counted `allKeys` (10) rather than the keys the
  signed-in tier can toggle.
- `profile_content.dart:506` — handed `PaywallSheet` a feature **id** where
  every other call site hands it a **display string**.
- `settings_screen.dart:132,139,146` — pushed the settings route bare, so the
  route defaulted `isPro` to false.

## Why the count fix must not touch the emission

Documented in the repository header (decision N2) and re-stated here because it
is the whole risk of this change: the server tests `=== false`, so a key ABSENT
from the snapshot means SEND. Narrowing `emissionMap()` by tier — the intuitive
way to implement "free users have 8 notifications" — would make the two PRO keys
absent for free users and therefore SENT to them.

`test/contracts/notification_pro_key_scoping_test.dart` pins this by writing a
partial prefs map through the real repository against a real `HiveUserSession`
and asserting all 10 keys survive into `emissionMap()`. Negative control: adding
`.where((k) => !proOnlyKeys.contains(k))` to the `emissionMap` loop fails the
test with a set-difference mismatch. Verified by execution, not by reading.

## Negative controls run (all three reverted after)

| Reverted to | Test | Result |
|---|---|---|
| `controllableKeys => allKeys` | `notification_pro_key_scoping_test.dart` | FAILS — `Expected: <8> Actual: <10>` |
| `emissionMap` filtered by `proOnlyKeys` | same | FAILS — emitted key set mismatch |
| `feature: AppConstants.featureProgressPhotos` | `paywall_feature_label_test.dart` | FAILS — offender listed |

## What was NOT changed, deliberately

- `allKeys` — `notification_prefs_parity_test.dart:59` hard-asserts its length
  is 10 and pins it set-equal to the server's `ProactiveType` vocabulary.
  Touching it would break the client/server toggle contract.
- `emissionMap()` — see above.
- The `_featureSubtitle` default arm. Five other labels ('PRO', 'PRO Upgrade',
  'AI Body Composition Assessment', 'Readiness Trends', 'AI Weekly Report') also
  fall through to generic copy. That is a real but separate gap on call sites
  this fix does not touch; filed as its own board entry rather than expanded
  into here.
