---
bug_id: d8f3a2
date: 2026-06-14
batch: unit3-web-ux
status: fixed
blast_radius: feature
symptom: >
  Live web (test2). (obs 2b) Tapping CONNECT on the Health Sync card "got stuck
  on the Health Connect page" — on web there is no Health Connect / HealthKit
  binding, so the native permission flow dead-ends. (obs 2 — sibling) The
  post-workout share card showed a "lat" (pull) quote for a custom-named
  template that wasn't a pull workout — the quote was keyed to the workout NAME,
  which carries no muscle signal for a generic/custom name.
concept: client_web_platform_gating
sot_registry_entry: not_applicable
writers: >
  obs 2b — lib/core/services/health_sync_service.dart (kIsWeb early-return in
  requestPermissions / fetchStepsToday / fetchLatestWeight / syncToHive) +
  lib/features/profile/widgets/biometric_sync_card.dart (CONNECT toggle disabled
  on web). obs 2 — lib/features/train/services/quote_picker.dart
  (categoryForExercises helper) + lib/features/train/widgets/workout_receipt_card.dart
  (_pickTagline + FutureBuilder fed exercise names).
readers: >
  obs 2b — profile Health Sync sheet / settings row; home step counter (reads
  already-synced Hive data, shows -- on web). obs 2 — the post-completion share
  card + the "View Card" sheet (both render the same deterministic quote).
hive_key_prefix: not_applicable
hive_key_formula: not_applicable (client UI gate + quote derivation; no Hive key)
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: not_applicable (client-only — no schema touched)
contract_test_path: test/contracts/unit3_web_ux_gates_test.dart
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - health_sync_request_permissions
cross_account_guard: false
forbidden_patterns_checked:
  - "native-plugin entry (Health()/requestAuthorization) reachable on web → MissingPluginException dead-end. FIXED: kIsWeb early-return in all 4 HealthSyncService native methods + the profile CONNECT toggle disabled (onTap: kIsWeb ? null) so the flow is inert on web."
  - "share-card quote derived from the workout NAME only — a custom/generic name yields a mismatched or odd category. FIXED: QuotePicker.categoryForExercises votes on the actual exercise names (shared by the async pool + the sync _pickTagline fallback), falling back to the name, then general."
  - "PWA install banner touching dart:js_interop on the Android/iOS build. AVOIDED: web-only conditional import keyed dart.library.js_interop (stub returns canInstall=false off-web); the banner is kIsWeb-gated → never renders / references web libs in the app build."
proposed_fix: >
  obs 2b: kIsWeb early-return in HealthSyncService.requestPermissions (false),
  fetchStepsToday (null), fetchLatestWeight (null), syncToHive (no-op) — the
  native seam; AND disable the BiometricSyncCard CONNECT GestureDetector on web
  with a dimmed "APP ONLY" / "Available in the mobile app" state (single UI
  gate). obs 2: add QuotePicker.categoryForExercises(exerciseNames, workoutName)
  — most-common specific category from the exercise names, else the workout
  name, else general — and feed it to BOTH the async pool path and the sync
  _pickTagline fallback (shared category derivation; closes a pre-existing
  full_body/arms loading-vs-settled mismatch). obs 6 (feature): a web-only PWA
  install banner (beforeinstallprompt capture in index.html + dart:js_interop
  conditional import + a kIsWeb-gated Home banner + iOS-Safari hint).
regression_test_planned: >
  test/contracts/unit3_web_ux_gates_test.dart (source-grep, comment-stripped):
  all 4 HealthSyncService native methods early-return on kIsWeb; the CONNECT
  toggle is kIsWeb-disabled; index.html exposes the PWA hooks; the banner is
  kIsWeb-gated + uses the js_interop conditional-import key; the dismiss flag is
  registered intentionally-shared. PLUS the pure behavioral
  test/contracts/quote_picker_category_from_exercises_test.dart (exercise-name
  list → expected category, majority vote, empty-list + name fallback, general).
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "HealthSyncService 4-method kIsWeb gate + biometric_sync_card CONNECT disabled-on-web + QuotePicker.categoryForExercises + workout_receipt_card both call sites + PWA banner (web-only conditional import). flutter analyze clean on all changed files (kIsWeb-undefined import miss caught + fixed); 2 contract tests green." }
  - { tier: 12, layer: client_server_contract, status: not_applicable, evidence: "client-only UI gate + quote derivation + a web install prompt; no Edge Function, no schema, no cloud contract touched. Web build is verified at deploy (Vercel) + preview." }
impact_analysis: >
  Feature-tier (web-only UX + a cosmetic quote; no auth/payment/sync/migration).
  obs 2b is the one clear current-code bug — the native Health Connect flow had
  no web binding and dead-ended; now inert on web with a clear "mobile app only"
  affordance. obs 2 keys the motivational quote to what the user actually
  trained (exercise names) rather than a custom workout name. obs 6 adds a
  web-install on-ramp. Sibling obs 5 (profile image refresh) + obs 3b (weight
  graph) were investigated and found ALREADY FIXED in main (+34 ProfileImageUrl;
  the date-aware WeightTrendChart) — resolved on the live web via Git-integrated
  auto-deploy on push; obs 3a (green-before-log) is the expected onboarding-seed
  behavior and was left as-is per founder. Plan independently reviewed TWICE
  (CLAUDE.md §4.12); review #1 caught the 4-method enumeration + the _pickTagline
  signature change, review #2 caught the single-UI-gate + the js_interop key + a
  mandatory quote test — all folded in before code.
  related: 2026-06-13-crashlytics-web-guard b2e9d3 (sibling kIsWeb native-on-web
  class); debugging skill §2.37/§2.39.
---

# Health Connect dead-ends on web + share-card quote keyed to name not exercises (d8f3a2)

## What happened
**obs 2b:** on the live web, tapping CONNECT on the Health Sync card dead-ended
("stuck on the Health Connect page"). `BiometricSyncCard.onToggleSync` →
`profile_provider.toggleSync` → `HealthSyncService.requestPermissions()` →
`_ensureConfigured()` instantiates the native `Health()` plugin, which has no web
binding (`MissingPluginException`). The boot auto-sync was already `kIsWeb`-guarded
(`splash_screen.dart:136`, `sync_service.dart:519`) — only the profile toggle path
was not.

**obs 2 (sibling):** the post-workout share card derived its quote category from
the workout NAME via loose `.contains()` substring matching. The ACTUAL root
cause of the founder's "lat" quote (surfaced by the new contract test):
`categoryForWorkout("test template")` → `name.contains('LAT')` matched
"tem**plat**e" (…p-**LAT**-e) → `'pull'` → a lat/pull quote. The same loose
matching mis-maps "Lateral Raise"→pull, "warm-up"→arms, "leverage"→legs. Keying
off the workout NAME (not the exercises) also meant a custom-named template
ignored what was actually trained.

## Fix
**obs 2b — two layers.** (1) `HealthSyncService`: `if (kIsWeb) return …` at the top
of all four native-touching methods (`requestPermissions`/`fetchStepsToday`/
`fetchLatestWeight`/`syncToHive`); `isEnabled()` (static Hive) needs none. (2)
`BiometricSyncCard`: `onTap: kIsWeb ? null : onToggleSync` + a dimmed "APP ONLY"
chip and an "Available in the mobile app" subtitle on web.

**obs 2 — two parts.** (a) `categoryForWorkout` now WORD-BOUNDS the short
ambiguous keywords (`\bLATS?\b`, `\bROWS?\b`, `\bLEGS?\b`, `\bABS?\b`, `\bRUN`,
`\bARMS?\b`) so "template"/"lateral"/"warm-up"/"leverage" no longer mis-map —
this is the real "lat" fix. (b) `QuotePicker.categoryForExercises(names, workoutName)`
returns the most-common specific category from the exercise NAMES (which carry
the muscle signal), else `categoryForWorkout(workoutName)`, else `'general'`. Fed
to BOTH the async `pickForCategory` path and the sync `_pickTagline` fallback
(shared derivation; `_pickTagline` signature `(List<String>, String, int)`), so
loading and settled taglines agree and a custom-named workout matches what was
trained.

## Verification
- `test/contracts/unit3_web_ux_gates_test.dart` + `quote_picker_category_from_exercises_test.dart`.
- Web verify via the dev-server preview (health CONNECT disabled, the corrected
  quote on a receipt, the PWA banner). Founder live-web confirmation post-deploy.

## See also
- lib/core/services/health_sync_service.dart, lib/features/profile/widgets/biometric_sync_card.dart
- lib/features/train/services/quote_picker.dart, lib/features/train/widgets/workout_receipt_card.dart
- lib/shared/widgets/pwa_install/ (obs 6 PWA banner) + web/index.html
- docs/superpowers/plans/2026-06-13-unit3-web-ux.md (plan + 2 review rounds)
