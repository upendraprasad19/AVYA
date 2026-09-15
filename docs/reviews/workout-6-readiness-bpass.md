---
review: workout-6-readiness B-pass (W2.3 readiness + W3.7 trends, cloud-durable)
branch: workout-6-readiness
date: 2026-07-17
reviewer: context-blind adversarial subagent (B-pass, §4.3)
blast_radius: platform
verdict: accepted
---

# B-pass — Batch 6 (readiness check-in + session adjustment + PRO trends)

Context-blind adversarial review of the implemented three-commit branch diff
(`git diff main -- lib test supabase docs backups`, commits 6-A `21d155f1` /
6-B+W3.7 `cc3f2276` / 6-C `2cf7a2c0`), verified against the actual code + live
cloud state (not the plan-review prose). PLATFORM tier (`sync/**` + `plan_engine/**`).

## Verdict: ACCEPTED — no P0/P1 issues

All four ×2-review P0 fixes verified CONFIRMED-OK in code + live state:
1. **P0-A restore on ALL 3 paths** — `_restoreReadiness` fires in `restoreFromCloud`,
   `restoreFromCloudForUser` Step B, AND the default fast path
   `_attemptSingleCallRestore` (standalone `await` before its success return) —
   so readiness is never synced-but-never-restored on a reinstall. `restore_completeness_test`
   pins ≥3 call-sites.
2. **Migration 105 live-verified** against `dedsavbjuwgarrhphgnl` — `readiness_daily`
   present with RLS own-rows policy, PK `(user_id, date)` arbiter, `created_at`
   default, `ON DELETE CASCADE`. `applied_migrations.json` + `live_schema_columns.json`
   + SoT `cloud:` block all updated in the 6-C commit.
3. **Load cut = min()** — `effectiveLoadFactor(ex)` returns the larger cut (smaller
   factor) of the ⑦b gap-cut and the readiness compound cut; compound-only; no
   double-dip; the schema-gate `.from('readiness_daily')` literal committed only
   AFTER the migration+regen (P0-1 sequencing honored).
4. **Flag-OFF byte-identical** — `enable_readiness` default OFF → `readinessLevel`
   null → no sheet / no read / no set-drop / `effectiveLoadFactor == sessionDetrainingFactor`.
   Behavioral `readiness_checkin_behavioral_test.dart` proves it.

## Three P2 (ship-dark, non-blocking) findings — ALL FIXED IN THIS BATCH (not deferred, §4.2)

All three sit behind `enable_readiness` (OFF), so zero production impact today —
but each is a real defect in the readiness path and was fixed in-branch (verified
against the actual file:lines, per the subagent-claim rule) before the merge:

- **P2-1 (overload indicator + "TRY:" hint blind to the readiness cut):**
  `exercise_card.dart` cut the prefill via `effectiveLoadFactor` (6-B) but the
  `_OverloadIndicator` callsite (`:687`) and the "TRY:" suppression gate (`:572`)
  still passed the raw `sessionDetrainingFactor`. On a Red/Yellow day with no ⑦b
  gap (`sessionDetrainingFactor == 1.0`) that rendered a shaming red ↓ "Recovery" +
  "TRY: +2.5kg" against a target the prefill deliberately undercut — the exact
  "never shame" violation ⑦b guarded. FIXED: renamed the indicator param
  `sessionDetrainingFactor → loadFactor` and threaded
  `widget.data.effectiveLoadFactor(widget.exercise)` into both the indicator and the
  TRY gate. `sessionDetrainingFactor` is now fully absent from `exercise_card.dart`;
  a comment-stripped source-grep wiring lock (`effectiveLoadFactor(` ≥3 sites; no raw
  factor; `_OverloadIndicator` takes `loadFactor`) pins it against silent drift.
- **P2-2 (inline `isPro()` + dead gate-key, rule 5):** the W3.7 trend gated on
  `SubscriptionService.instance.isPro()` (an inline widget-layer isPro check) and
  the `AppConstants.featureReadinessTrends = 'readiness_trends'` key was declared
  but never referenced (0 `gate()` callsites). FIXED: the teaser now gates on
  `ref.watch(subscriptionInfoProvider).isPro` (rule-5 compliant + reactive — an
  upgrade reveals the strip without a manual rebuild); the dead feature-KEY constant
  was removed, matching the E.8 `featureActiveWorkoutMode` / `featureVoiceNotes`
  removals (a synchronous teaser can't use the async void `gate()`, and the paywall
  `feature:` param is a display label, not the key — so `gate()` was the wrong
  mechanism the B-pass suggestion assumed).
- **P2-3 (no periodic full-sync backstop for readiness):** `_syncReadiness` fired
  only from `syncReadinessNow()` (per check-in) — an offline-failed push only
  retried on the NEXT check-in. FIXED: added `_safeRestoreOp('sync_readiness',
  _syncReadiness(userId))` to `weeklyFullSync`'s `Future.wait`, giving every other
  domain's periodic backstop parity.

Post-fix: `flutter analyze` clean on the touched trees; `readiness_checkin_behavioral_test.dart`
(now incl. the P2-1 wiring lock) + `session_detraining_cut_test.dart` all green (+31).
No open issues.
