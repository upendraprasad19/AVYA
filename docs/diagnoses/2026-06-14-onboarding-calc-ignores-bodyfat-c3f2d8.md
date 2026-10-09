---
bug_id: c3f2d8
date: 2026-06-14
batch: unit4-bodyfat-calc
status: fixed
blast_radius: account
symptom: >
  Live web (test2) + audit. The SAVED onboarding calorie target ignored the
  user's body-fat: a user who typed 12% got the SAME daily_calories as a
  skip-user, because both the onboarding COMMIT
  (onboarding_provider.completeOnboarding) and the PREVIEW
  (plan_screen._computeTargets) called BmrCalculator.calculateTargets WITHOUT
  bodyFatPercent — so the calc silently ran Mifflin-St Jeor even when body-fat
  was available (Katch-McArdle was never reached at onboarding). Worse, a
  skip-user did not just get "no body-fat" — onboarding FABRICATED a body-fat of
  18.0 (stats_screen `bodyFat ?? 18.0`) and SAVED it. The profile-edit recompute
  (profile_provider.recalculateTargets) DOES consume body_fat_percent via
  Katch-McArdle, so any skip-user who later edited ANY profile field had their
  calories silently recomputed from a made-up 18% lean mass — and body_stats.dart
  displayed a fabricated "18%".
concept: onboarding_bodyfat_calc_input
sot_registry_entry: onboarding_bodyfat_calc_input
writers: >
  Root fabrication — lib/features/onboarding/screens/stats_screen.dart
  (`body_fat_pct`: was `bodyFat ?? 18.0`, now the raw nullable `bodyFat`). Calc
  feed — lib/features/onboarding/screens/plan_screen.dart (_computeTargets
  preview + _onReportForDuty setAnswer) and
  lib/features/onboarding/providers/onboarding_provider.dart (completeOnboarding)
  now both feed body-fat through the single shared selector
  BmrCalculator.bodyFatForCalc(bf, disabled:) in lib/core/utils/bmr_calculator.dart;
  completeOnboarding parses with the new nullable _parseDoubleOrNull so a skip
  SAVES null (not 0.0). Heal — lib/core/services/body_fat_default_healer.dart
  (BodyFatDefaultHealer.runIfNeeded) nulls a legacy fabricated 18.0, wired into
  lib/features/auth/providers/auth_provider.dart _ensureLocalUser (after the
  cross-account guard + UserConfigMigrator).
readers: >
  lib/features/profile/providers/profile_provider.dart recalculateTargets
  consumes body_fat_percent via Katch on every profile edit (the live bug surface
  — fed the fabricated 18.0). lib/features/profile/screens/profile/body_stats.dart
  _buildBodyStatsInner displays body_fat (null -> em-dash, 18.0/0.0 -> a
  fabricated "18%"/"0%"). The onboarding preview card reads _computeTargets;
  completeOnboarding writes daily_calories the Nutrition/Profile/Diet screens read.
hive_key_prefix: userBox['profile']
hive_key_formula: not_applicable (profile map fields body_fat_percent + body_fat_assessed_at; not a prefixed key)
sync_methods: []
restore_methods: []
cloud_table: user_profile
cloud_columns: body_fat_percent, body_fat_assessed_at (both confirmed present in backups/live_schema_columns.json; body_fat_range confirmed ABSENT)
contract_test_path: test/contracts/onboarding_bodyfat_calc_test.dart
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure:
    - bodyfat_default_heal
cross_account_guard: true
forbidden_patterns_checked:
  - "fabricated body-fat default fed into a CONSUMING calc — `bodyFat ?? 18.0` (stats_screen) saved a made-up 18% that profile_provider.recalculateTargets later consumed via Katch. FIXED: forward the raw nullable body-fat; calc treats null as Mifflin."
  - "skip-user saving 0.0 instead of null — the 0-flooring _parseDouble would persist 0.0 (renders 'body_stats 0%'). FIXED: _parseDoubleOrNull saves null on skip; calc + display both degrade correctly on null."
  - "preview vs saved drift on the body-fat arg — two hand-copied `bodyFatHonored ? bf : null` ternaries could drift. FIXED: single shared BmrCalculator.bodyFatForCalc helper both sites call (parity by construction); pinned by the existing arg-set parity test + the new behavioral test."
  - "heal that writes a synced-null — sync_profile omits null body_fat + _restoreUserProfile re-hydrates a non-null cloud value, so a synced-null would silently revert to 18.0. FIXED: heal clears the CLOUD column FIRST (explicit update + ensureFreshToken) then local, so a partial failure stays consistently 18.0 and retries next session."
proposed_fix: >
  (A) Onboarding stops fabricating: stats_screen forwards the raw nullable
  body-fat; plan_screen + completeOnboarding feed it through the shared
  BmrCalculator.bodyFatForCalc(bf, disabled:) selector (Katch when provided +
  not disabled, else Mifflin); completeOnboarding uses a nullable parse so a skip
  SAVES null. Kill-switch disable_bodyfat_calc reverts every site to Mifflin in
  one expression. (B) BodyFatDefaultHealer heals existing installs at boot
  (post-auth, cross-account-safe): where body_fat_percent == 18.0 AND
  body_fat_assessed_at == null (the fabricated-default signature; onboarding never
  stamps assessed_at, only AI-scan / Edit do), null the CLOUD column first
  (fresh-token explicit update) then local. Idempotent + kill-switched
  (disable_bodyfat_heal). No daily_calories backfill (founder-locked: no silent
  recompute).
regression_test_planned: >
  test/contracts/onboarding_bodyfat_calc_test.dart — bodyFatForCalc flag-gating
  (4 cases); body-fat materially changes daily_calories (Katch != Mifflin) +
  kill-switch fully reverts; source-grep (comment-stripped) that no onboarding
  site defaults body-fat to 18, completeOnboarding uses _parseDoubleOrNull, and
  BOTH sites call bodyFatForCalc. test/contracts/body_fat_default_heal_test.dart —
  Hive write->read: 18.0+unassessed nulled, 18.0+assessed kept, 22.0+unassessed
  kept, already-null no-op, idempotent, kill-switch. The existing
  plan_screen_targets_match_completeOnboarding_test.dart still pins the identical
  arg-set (verified green after the bodyFatForCalc refactor).
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "stats_screen no-fabrication + plan_screen/onboarding_provider feed bodyFatForCalc + nullable parse + BmrCalculator.bodyFatForCalc helper + BodyFatDefaultHealer wired in auth_provider. flutter analyze clean on all 8 touched files; 16 new tests + bmr + parity tests green." }
  - { tier: 2, layer: hive_local_state, status: fixed_in_this_batch, evidence: "heal nulls userBox['profile']['body_fat_percent'] surgically (other keys preserved); body_fat_default_heal_test round-trips all 6 cases. Skip-user now saves null (not 0.0/18.0)." }
  - { tier: 3, layer: postgres_schema, status: verified, evidence: "user_profile.body_fat_percent + body_fat_assessed_at present in backups/live_schema_columns.json; body_fat_range absent (grep -c = 0). user_stat_snapshots.body_fat_pct is a DIFFERENT column, untouched." }
  - { tier: 4, layer: postgres_data, status: not_applicable, evidence: "no bulk SQL backfill — the heal is per-user at boot (cloud-first update, founder-locked no-silent-server-recompute); existing fabricated 18.0 rows clear as users next sign in." }
  - { tier: 12, layer: client_server_contract, status: fixed_in_this_batch, evidence: "heal clears the cloud body_fat_percent via a direct user_profile.update under a fresh token (ensureFreshToken, §2.31) BEFORE nulling local, so the omit-null sync + re-hydrating restore cannot silently revert it; no EF, no migration." }
impact_analysis: >
  Account-tier — a broad-blast calorie calc that changes saved daily_calories for
  body-fat users AND a heal touching existing profiles. Risk contained by the
  disable_bodyfat_calc + disable_bodyfat_heal kill-switches (CLAUDE.md §4.6) and
  by the heal's exact-18.0-AND-unassessed discriminator (a genuinely-assessed
  18.0 or any other value is left alone; the rare user who typed exactly 18 at
  onboarding reverts to Mifflin and can re-enter via Edit). Calc parity preserved:
  preview == saved by construction (single shared selector). Plan independently
  reviewed TWICE (CLAUDE.md §4.12) — review #1 caught the stats_screen second
  fabrication site (passing 18.0 into Katch = worse) + the synced-null heal
  durability hole; review #2 caught the fresh-token + clear-cloud-before-local
  ordering. Both folded in BEFORE code. A third defect (skip saving 0.0 via the
  0-flooring _parseDouble → fabricated "0%") was caught during implementation
  verification and fixed (nullable parse).
  related: b2e9d3 (kIsWeb native-on-web, sibling unit); f1b6d4 (preview-vs-saved
  activity drift — same preview/commit parity surface, the parity test this batch
  extends); debugging skill new bug-class 2.40 (fabricated-default-fed-into-calc).
---

# SAVED onboarding calorie calc ignored body-fat + fabricated an 18% default (c3f2d8)

## What happened
Two coupled defects on the onboarding calorie path:

1. **The calc never used body-fat.** `BmrCalculator.calculateTargets` supports
   Katch-McArdle (lean-mass based) when `bodyFatPercent` is supplied, falling back
   to Mifflin-St Jeor otherwise. But both onboarding callers —
   `plan_screen._computeTargets` (preview) and
   `onboarding_provider.completeOnboarding` (commit) — passed **no** `bodyFatPercent`.
   So a user who entered 12% body-fat got Mifflin calories identical to a
   skip-user: the entered body-fat was silently discarded.

2. **A skip fabricated 18%.** `stats_screen` forwarded `body_fat_pct` as
   `bodyFat ?? 18.0`, so a skip-user SAVED `body_fat_percent: 18.0`. That value is
   harmless to the onboarding calc (it never read it) but
   **`profile_provider.recalculateTargets` DOES** — it reads `body_fat_percent`
   and feeds it into Katch on **any** profile edit. So a skip-user who later edited
   their goal/weight/anything recomputed their target from a made-up 18% lean mass,
   and `body_stats.dart` displayed a fabricated "18%".

The root class: **a fabricated default persisted into a field that a *different*,
later code path consumes as real input.** The fabrication was invisible at the
write site (onboarding's own calc ignored it) and only bit at the downstream
consumer (profile recompute).

## Fix
- **Stop fabricating** — `stats_screen` forwards the raw nullable body-fat.
- **Honor it in the calc** — preview + commit both feed body-fat through the new
  shared `BmrCalculator.bodyFatForCalc(bf, disabled:)` selector (Katch when
  provided and not disabled, else null → Mifflin). One helper → the preview and
  the saved value cannot drift on this arg. Kill-switch `disable_bodyfat_calc`.
- **Save null on skip** — `completeOnboarding` parses with `_parseDoubleOrNull`
  (not the 0-flooring `_parseDouble`), so a skip persists `null` → `body_stats`
  renders "—" and the profile recompute correctly runs Mifflin.
- **Heal existing installs** — `BodyFatDefaultHealer` (boot, post-auth) nulls a
  legacy fabricated 18.0 (exactly 18.0 AND `body_fat_assessed_at == null`),
  clearing the **cloud column first** (fresh-token explicit `update`) then local,
  so the omit-null profile sync + re-hydrating restore cannot silently revert it.
  Idempotent + kill-switch `disable_bodyfat_heal`. No `daily_calories` backfill.

## Verification
- `test/contracts/onboarding_bodyfat_calc_test.dart` (calc + flag + source) +
  `test/contracts/body_fat_default_heal_test.dart` (Hive round-trip, 6 cases).
- `test/bmr_calculator_test.dart` + `plan_screen_targets_match_completeOnboarding_test.dart`
  still green after the `bodyFatForCalc` refactor (arg-set parity preserved).
- `flutter analyze` clean on all 8 touched files.

## See also
- lib/core/utils/bmr_calculator.dart (bodyFatForCalc), lib/core/services/body_fat_default_healer.dart
- lib/features/onboarding/screens/stats_screen.dart, .../plan_screen.dart, .../providers/onboarding_provider.dart
- lib/features/profile/providers/profile_provider.dart (recalculateTargets — the consuming reader)
- docs/sot_registry.yaml (concept onboarding_bodyfat_calc_input)
- debugging skill §2.40 (fabricated-default-fed-into-consuming-calc)
