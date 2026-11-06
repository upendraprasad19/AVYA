# Plan — Unit 4: SAVED calorie calc honors body-fat (Katch-McArdle) + heal the fabricated 18.0

> Founder-confirmed (2026-06-14): "fix + heal as described." Blast-radius = **account** (core calorie calc
> for every user + a heal touching existing profiles) → ×2 independent plan review (§4.12) + self-initiated
> B-pass (§4.3) + a kill-switch flag (§4.6). NO silent `daily_calories` backfill (founder-locked).

## Root cause (code-verified)
The calculator is correct: `BmrCalculator.calculateBmr` uses Katch-McArdle when `bodyFatPercent` is valid
(1–69%), Mifflin-St Jeor otherwise (null → Mifflin). The bug is in the CALLERS:
- **Onboarding ignores body-fat.** `completeOnboarding` (`onboarding_provider.dart:305-314`) and the plan
  preview `_computeTargets` (`plan_screen.dart:610-621`) BOTH deliberately omit `bodyFatPercent` → always
  Mifflin. AND `plan_screen.dart:522` saves a **fabricated** `body_fat_percent: 18.0` for every skip-user
  (`(widget.data['body_fat_pct'] as num?)?.toDouble() ?? 18.0`).
- **Profile-edit recompute already honors body-fat.** `profile_provider.recalculateTargets` (`:84-97`) reads
  `body_fat_percent` and passes it to `calculateTargets` → Katch. So an existing skip-user (saved `18.0`)
  who edits ANY profile field gets calories recomputed from a made-up 18% — **a live bug today.**
- `activity_level` is already honored (f1b6d4 — `lifestyleFromActivityLevel → resolveActivityLevel`).

## Fix
### A. Onboarding — pass the real body-fat, drop the fabricated default
0. **`stats_screen.dart:435` — THE ROOT fabrication (review #1 P0, verified):** `'body_fat_pct': bodyFat`
   (remove `?? 18.0`). The Stats CONTINUE writes the route extras that flow Stats → Details → Plan, so
   `widget.data['body_fat_pct']` is ALREADY 18.0 for skip-users before `plan_screen` ever reads it. WITHOUT
   this drop, steps 2-3 would feed the fabricated 18.0 into Katch (Katch-on-fake-18 — strictly WORSE than
   today's Mifflin). `bodyFat` is null when the field is blank. Add a test that a blank-body-fat flow
   persists `body_fat_percent == null`.
1. `plan_screen.dart:522` — `notifier.setAnswer('body_fat_percent', (widget.data['body_fat_pct'] as num?)?.toDouble())`
   (remove `?? 18.0` — defense-in-depth; the real source is step 0). Skip → null.
2. `plan_screen._computeTargets` — pass `bodyFatPercent: bodyFatHonored ? bf : null` where
   `bf = (widget.data['body_fat_pct'] as num?)?.toDouble()` (remove the "do NOT pass bodyFatPercent" line).
3. `completeOnboarding` (`onboarding_provider.dart`) — move `final bodyFatPercent = _parseDouble(a['body_fat_percent'])`
   ABOVE the `calculateTargets` call (currently at `:327`, after the calc at `:305`) and pass
   `bodyFatPercent: bodyFatHonored ? bodyFatPercent : null`. Preview + commit MUST pass the SAME value (the
   behavioral test asserts VALUE parity with body-fat, not just arg-name parity — review #1 P2: the existing
   `plan_screen_targets_match_completeOnboarding_test` is name-only).
   Result: a user who enters body-fat → Katch; a skip-user → null → Mifflin (unchanged from today). The only
   NEW-user behavior change is body-fat-providers get the (more accurate) Katch path the founder chose.

### B. Heal existing fabricated 18.0 (client-side, no backfill)
A symptom-gated Hive migrator (new `BodyFatDefaultHealer`, run after `HiveUserSession.openForUser` in the
profile-load path — mirror `UserConfigMigrator.runIfNeeded`'s call site). For the current user's
`userBox['profile']`: if `body_fat_percent == 18.0` AND `body_fat_assessed_at == null` → set local
`body_fat_percent = null` AND **explicitly clear the cloud column** via a targeted
`client.from('user_profile').update({'body_fat_percent': null}).eq('user_id', uid)` — NOT the omit-null
`syncProfileNow` (review #1 P0, verified: `sync_profile.dart:101` gates the field behind `_hasNumber`, so a
null sync leaves the cloud 18.0, and `_restoreUserProfile`'s `if (e.value != null)` merge at `:276` would
re-hydrate it on the next restore → the heal would NOT be durable). After the explicit cloud-null, restore
skips the null and the local null wins. **Order (review #2 P2): CLEAR THE CLOUD FIRST, then null local** — a
partial failure then leaves a consistent 18.0/18.0 pair that retries next session, never a local-null/cloud-18
split that re-hydrates. **Use a fresh-token client** (the heal runs boot-adjacent; a stale web token 401s the
update — §2.31; route via `SupabaseService`/`ensureFreshToken`). On write failure: telemetry + leave 18.0
(retry next session). `body_fat_range` is **confirmed ABSENT** from the live schema (only `body_fat_percent` +
`body_fat_assessed_at`) — no sibling to clear. (The `user_stat_snapshots` row also holds a historical
`body_fat_pct: 18.0` copy — a snapshot artifact, NOT a calc input; left as-is, self-corrects for new users.)
- **Body-fat consumers (review #1 — name all in the diagnose-doc):** four `calculateTargets` callers read
  `body_fat_percent` — `profile_provider.recalculateTargets` (the named trap), `user_repository.recomputeTargets`
  (no live caller — latent re-arm), and the READ-TIME recomputes `nutrition_provider:88` +
  `nutrition_repository:571` (consume body-fat when stored `daily_calories` is absent/0). All degrade to
  Mifflin gracefully once body-fat is null (post-heal). **No server cron/EF recomputes targets from body-fat**
  (verified absent) — so the client heal suffices ONCE the cloud column is cleared (the cloud row is the
  restore + AI-snapshot source). Display readers degrade on null (`body_stats.dart:49` → '—').
- **Discriminator rationale:** onboarding never stamps `body_fat_assessed_at` (only the AI body-fat
  scan/Edit does — `edit_profile_screen.dart:1487`). So `18.0 + assessed_at==null` = the fabricated default
  (plus the rare user who genuinely typed exactly 18 at onboarding — they revert to Mifflin and can re-enter;
  acceptable, recoverable).
- **NO `daily_calories` recompute** — the user's onboarding-saved target (Mifflin-based) stays as-is; their
  next explicit profile edit recomputes correctly (null body-fat → Mifflin). Users who ALREADY edited before
  the heal keep a slightly-off Katch-18% target until their next edit (the founder-accepted no-backfill cost).
- Kill-switch: `configBox['disable_bodyfat_heal']`. Idempotent (once `body_fat_percent` is null it no longer
  matches). Telemetry `recordNonFatal` on the rare write failure.

### C. Kill-switch flag for the onboarding calc change
`configBox['disable_bodyfat_calc']` (default off → body-fat honored). When SET, A.2 + A.3 pass `null`
(revert to Mifflin onboarding — the pre-fix state). Scoped to the onboarding calc; `recalculateTargets`
stays as-is (it already honors body-fat and, post-heal, gets correct null/real input).
**Pin `bodyFatHonored` to ONE shared expression** — `HiveService.instance.configBox.get('disable_bodyfat_calc') != true`
— used IDENTICALLY by `_computeTargets` AND `completeOnboarding` (review #2 P2: divergent resolution would
re-introduce preview≠saved drift under the kill-switch). The behavioral value-parity test exercises the flag
ON in BOTH sites.

**Founder note (review #2):** after the heal nulls a skip-user's fabricated 18.0, the profile-completeness
nudge will re-surface "Body Fat %" for them (truthful — they never provided it; recoverable via Edit/AI-scan).
The AI snapshot does NOT embed body-fat, so coaching is unaffected by the heal (only the un-recomputed
`daily_calories` carries any indirect effect).

## Discipline artifacts
- **Diagnose-doc** `docs/diagnoses/2026-06-14-onboarding-calc-ignores-bodyfat-<id>.md`, `blast_radius: account`,
  `touched_layers_checked` (client code tier 1; client→server tier 12 — the synced body_fat null + the saved
  target). Names the live profile-edit-recompute trap.
- **Tests:** behavioral `onboarding_bodyfat_calc_test.dart` — (i) body-fat entered → Katch-based
  `daily_calories` (differs from Mifflin), (ii) skip → null → Mifflin, (iii) preview `_computeTargets` ==
  `completeOnboarding` saved (no drift) WITH body-fat, (iv) flag set → reverts to Mifflin. `body_fat_default_heal_test.dart`
  — 18.0+unassessed → nulled; 18.0+assessed → kept; 22.0+unassessed → kept; idempotent.
- **SoT:** update the onboarding `Plan-screen preview targets` concept (now passes body-fat) + register the
  heal. Update `lib/features/onboarding/CLAUDE.md` (body-fat now honored in the saved calc) +
  `lib/features/profile/CLAUDE.md` (recalculateTargets + the heal).
- **Self-evolution:** debugging skill — "fabricated default fed into a downstream calc that DID consume the
  field (onboarding writes 18.0 but ignores it; profile-edit recompute consumes it)" — a writer/reader
  semantic-drift variant (the field is written-but-fabricated on one path, consumed-as-real on another).

## Sequence
1. Branch `unit4-bodyfat-calc` from `main` (+ copy `.env`).
2. Gate-first: ship the heal behind `disable_bodyfat_heal` + the calc behind `disable_bodyfat_calc` (both
   default-active) — they ARE the rollback levers, so no warn-only phase needed; but land the tests first.
3. A (onboarding) + B (heal) + C (flag) — coherent commit.
4. `flutter analyze` + targeted tests green.
5. Diagnose-doc + tests + docs.
6. Self-initiated B-pass (account tier) → merge `--no-ff` → push → CI. (APK = founder's call.)

## Open questions — RESOLVED by review #1 (Opus, context-blind; the 2 P0s re-verified by me against code)
- **A:** Four `calculateTargets` callers read body-fat: `recalculateTargets` (the trap), `recomputeTargets`
  (no live caller — latent), `nutrition_provider:88` + `nutrition_repository:571` (read-time recomputes when
  `daily_calories` absent/0). All degrade to Mifflin once body-fat is null. NO server cron/EF recompute
  (verified absent). Folded into Fix B's consumer bullet.
- **B:** Onboarding (stepped + legacy chat) NEVER stamps `body_fat_assessed_at` (only the AI scan
  `edit_profile:1487` + save passthrough). The `assessed_at==null` discriminator cleanly isolates fabricated
  rows. SAFE.
- **C:** `UserConfigMigrator.runIfNeeded` runs from `auth_provider._ensureLocalUser`, post-`openForUser` +
  cross-account guard — the correct once-per-session site to mirror. The heal must run BEFORE any
  `recalculateTargets`; session-open ordering holds (edits are post-boot) — pin with a test. The heal uses its
  OWN idempotency (null no longer matches), not the shared `config_to_user_migration_v2_done` flag.
- **D:** **NO — and this was a P0.** The omit-null sync leaves cloud 18.0; restore re-hydrates. FIXED in Fix B
  (explicit `update({body_fat_percent: null})`).
- **E:** Display readers degrade on null (`body_stats.dart:49` → '—'; edit_profile → ''). SAFE.
- **F:** The existing parity test is arg-name-only — the NEW behavioral test must assert VALUE parity with
  body-fat. Folded into Fix A.3.
- **G:** `configBox` device kill-switches are fine (match `disable_bg_restore` precedent).

Review #1 verdict: PLAN-NEEDS-HARDENING — 2 P0 (the `stats_screen:435` root 18.0 + the non-durable cloud
clear, both verified + fixed above) + P1 consumer enumeration + a value-parity test. All folded in.
