# OI-348 Landing 3a — "all phases" wording + numerals (P1), email-confirm progress + timing (B6)

Status: revised after plan review round 1 (19 findings, 3 P1, all folded in; see "Round 1 log" at the end). For plan review round 2. Branch `oi348-landing3a` off main `def815d7` (2026-11-25).
Blast radius: **platform** (`blast_radius_from_diff.dart` on the touched paths). Full ×2 plan review, B-pass before merge.
Execution mode (decided at start, §4.12.7): **inline**, one worktree, one coordinator.

Founder decisions (2026-11-22 walk + 2026-11-25 in chat):
- P1: phases keep coming after XII; the copy says "all phases". Include fixing the numerals past XII.
- B6: "show progress + measure". After the link is verified, the confirm screen says the email is confirmed and the account is being set up. Add per-step timing so the next sign-up shows which cloud call is slow. **No background load** (see B6 finding 2).

---

## B6 — email-confirm spinner (walk A1)

### Symptom
A1 (Chintamani, AAB +50, 2026-11-22 15:32Z): after tapping the confirm link the screen showed "Confirming your account..." with a spinner for ~10 s, then moved on. Not endless, but nothing says the link worked.

### Evidence (live `client_errors`, read 2026-11-25)
| time (UTC) | op_type | note |
|---|---|---|
| 15:32:07.950 | `auth_user_ensured` | entry of `_ensureLocalUser` |
| 15:32:08.084 | `hive_session_reopen_noop` | `openForUser` done, +0.13 s |
| 15:32:17.982 | `auth_signed_in` | `method=email_confirm`, +9.9 s after open |

Web sample (another account, +49, 2026-11-13): 2.6 s for the same span. So the verify call is not the slow part; ~9.9 s is the six migrators + `hydrateFromCloud` (network). Which call inside is slow is NOT known (no per-step timing exists).

### Writers / readers
- Writer of the loading state: `AuthNotifier.confirmEmail` `auth_provider.dart:729-821` (sets `AuthStatus.loading` at :730) and `_performConfirmEmail` `:905-924` (verifyOTP :906, `_ensureLocalUser` :919, `auth_signed_in` :920, `AuthStatus.success` :923).
- Error mapping: `confirmEmailErrorState` `:875-901` (timeout message :877-882).
- Reader: `ConfirmEmailScreen.build` `confirm_email_screen.dart:80-130`; loading UI `_buildLoadingState` `:132-174` (text "Confirming your account..." :156); success routing `ref.listen` `:104-110` (status `success` -> `/restoring`).
- The slow span: `_ensureLocalUser` `auth_provider.dart:1145-1404`: open + cross-account guard `:1160-1222`, migrators `:1228-1312`, terms stamp `:1322-1331`, `hydrateFromCloud` `:1350-1369`, binds `:1375-1403`.
- `AuthSessionBootstrapper.hydrateFromCloud` `auth_session_bootstrapper.dart:777-1119`: users upsert/last_active/name/terms `:784-861`, user_profile read + branch `:864-1089`, stub + tail `:1096-1117`.

### Finding 2 — why not "move on, load in the background"
`hydrateFromCloud` (:779) and `resolveDestination` (:507-508) share `_withLock(userId)` (:1293-1306). `RestoringScreen` calls `resolveDestination`, so a backgrounded hydrate just moves the wait onto `/restoring`. And diagnose a9c4e2 forbids bounding or skipping the open + cross-account guard. Rejected.

### Bug history (§4.1.5)
- a9c4e2 (2026-08-13): sign-in spinner with no ceiling -> `signInTimeout` 40 s + `boundSignIn`. Same span; this batch does not change the ceiling.
- 42a98d (2026-09-23): `ensureSupabaseReady()` in `confirmEmail`. Ordering kept.
- f6c2a9, f92d17, d4a8f6, 9c4e1a: confirm-link routing / resend / sign-out CTA. Not touched.
- Not a recurrence of those: none is "slow but no progress shown".

### Fix
1. `AuthState2` gets `final bool emailVerified` (default `false`). **Not sticky** (R1-5): `copyWith` sets `emailVerified: emailVerified ?? false`, the same reset `errorMessage` already has, so every later emit (success, any other flow, `resetState` `:1022`, `signOut` `:1126`) drops it. Only the stage emit passes `true`. Readers of `AuthState2` (verified): the confirm screen and `sign_in_screen.dart:185-231` (status + errorMessage only).
2. `confirmEmail`'s first line is unchanged (`copyWith(status: loading, errorMessage: null)` now also yields `emailVerified: false`).
3. `_performConfirmEmail`: right after `response.user != null`, unless the kill switch is on, `state = state.copyWith(status: AuthStatus.loading, emailVerified: true)`. Status stays `loading`, so routing (`ref.listen` on `success`) and every other reader are unchanged.
4. `confirmEmailErrorState`: when `state.emailVerified == true`, every error EXCEPT `StateError` (the cross-account guard already signed out: its message stays) maps to `confirmedButSlowMessage` = "Email confirmed. Setting up your account is taking longer than usual. Tap GO TO SIGN IN to continue." (R1-6, R1-7: the link is spent, so "invalid or expired" or "try again" is false; GO TO SIGN IN lands an authenticated user on `/onboarding` or `/home` via `_authRedirect` `app_router.dart:801-820`, so the copy names the button, not a sign-in.) Not verified: all mappings unchanged.
5. `ConfirmEmailScreen._buildLoadingState(emailVerified)`: when true, the text reads "Email confirmed. Setting up your account…". Spinner and the always-visible GO TO SIGN IN escape stay.
6. Kill switch `configBox['disable_confirm_verified_stage']` (+ `@visibleForTesting static bool? confirmVerifiedStageDisabledForTest`, the `signInTimeoutDisabled` pattern, fails to the fix ON when configBox is closed). ON = no intermediate state, byte-identical to today.
7. Test seams on `AuthNotifier` (the `rpcEmailIsRegistered` pattern): `@visibleForTesting Future<AuthResponse> verifyConfirmToken(String tokenHash)` (wraps the `verifyOTP` call) and `@visibleForTesting Future<void> ensureLocalUserAfterConfirm(User user)` (calls `_ensureLocalUser(user)`). `_performConfirmEmail` calls both. No behavior change.

### Timing telemetry
8. New pure `lib/core/utils/step_timings.dart` `StepTimings`: a `Stopwatch` plus ordered laps; `lap(name)` records ms since the previous lap (a repeated name adds); `summary()` -> `name=ms ... total=ms`. Name shape checked by `assert` only (debug); release never throws from it.
9. `_ensureLocalUser(user, {..., StepTimings? timings})`: uses the passed `StepTimings` or makes one. Laps: `open` (after `openForUser`), `guard` (after the guard block), `migrators` (after `ScheduleHybridRepairMigrator`), `terms` (after the stamp), then `hydrateFromCloud` adds its own `h_*` laps (NO outer `hydrate` lap: one stopwatch, it would read ~0, R1-9), `binds` (end).
10. **Verify is measured too (R1-10):** `_performConfirmEmail` creates the `StepTimings`, laps `verify` after `verifyConfirmToken`, passes it on. `_performEmailSignIn` does the same with `sign_in` after `signInWithPassword` (the walk also saw 4.8 s / 7.6 s on sign-in). Other `_ensureLocalUser` callers (sign-up, phone OTP) pass none.
11. **Runner, behaviorally tested (R1-11):** `@visibleForTesting static Future<T> runTimed<T>(StepTimings t, Future<T> Function() body, void Function(String line) log)`: runs `body`; in `finally` calls `log('outcome=<ok|threw> ${t.summary()}')` exactly once, inside its own `try/catch` (a log failure never masks the body's result or error); rethrows. `_ensureLocalUser` wraps its whole body in it; `log` = `unawaited(ErrorTelemetry.logEvent('auth_ensure_timing', message: 'userId=<8> $line'))`. `logEvent` is async with a catch-all, LOW priority, droppable, capped at 500 chars (`error_telemetry.dart:374`, R1-16), so the timing path cannot throw into auth (§4.6 justification for no kill switch on the telemetry, R1-15). An `ok` row can land after the user already saw the 40 s timeout (the ceiling raises in the caller; `_ensureLocalUser` keeps running): stated in the diagnose doc.
12. `hydrateFromCloud(User user, {StepTimings? timings})` laps (R1-9 widened): `h_lock` (first line inside `op`: wait for `_withLock`), `h_users_upsert` (:793), `h_users_active` (:798), `h_users_name` (:816), `h_terms_sync` (:835, either the update or `ensureTermsConsentFallback`), `h_profile_read` (:870), then in the cloud-has-data branch `h_profile_merge` (:903), `h_progress_read` (:938), `h_terms_read` (:960), `h_plan_gen` (:1043); in the other branches `h_profile_branch` (:1079); `h_stub` (:1105), `h_tail` (end of op). Laps in a branch not taken simply do not appear. The only caller passes its `StepTimings`; null = no laps.
13. One `client_errors` row per sign-in / confirm (rare). Not swept, not high priority. Glossary entry in `docs/naming_conventions.md`.

What this does NOT do: it does not make the account load faster. The next confirm or sign-in names the slow step; speeding it up is the next landing once the number exists (recorded on the OI-348 board and the closure ledger as `upstream_blocked: reopen_when: first auth_ensure_timing row from a phone`).

### Tests (B6)
- `test/contracts/confirm_email_verified_stage_behavioral_test.dart` (NEW). Two seams only (R1-8): subclass `AuthNotifier`, override `ensureSupabaseReady` -> true (`SupabaseService.isAuthenticated` is false while uninitialized, `supabase_service.dart:121-124`, so the real OI-205 guard passes, as in `confirm_email_readiness_behavioral_test.dart`), `verifyConfirmToken` -> a fake `AuthResponse` with a user, `ensureLocalUserAfterConfirm` -> waits on a `Completer`. Drives the REAL `confirmEmail`. Assert: (a) while pending, `loading && emailVerified`; (b) after complete, `success && !emailVerified`; (c) kill switch ON -> while pending `!emailVerified`; (d) null user -> "invalid or has expired", `!emailVerified`; (e) `fakeAsync`: a never-completing ensure, elapse 41 s -> the REAL ceiling fires and the message is `confirmedButSlowMessage` (proves the stage was set when the ceiling hit; a pure-function test alone stays green if the emit is removed); (f) the same with the kill switch ON -> the old timeout message; (g) ensure throws a generic `Exception` while verified -> `confirmedButSlowMessage`; throws `StateError` -> the cross-account message. Telemetry captured via `ErrorTelemetry.debugOnRecordNonFatalForTests`. `tearDown` resets the static kill-switch override.
- `test/contracts/confirm_email_error_mapping_test.dart` (EXTEND): pure `confirmEmailErrorState` table for verified × {Timeout, StateError, AuthException, other}.
- `test/auth/confirm_email_screen_test.dart` (EXTEND): state `loading + emailVerified` renders "Email confirmed. Setting up your account…" and still shows GO TO SIGN IN; `!emailVerified` renders "Confirming your account...".
- `test/core/step_timings_test.dart` (NEW): lap order, repeat-name adds, total, `summary()` shape.
- `test/contracts/auth_ensure_timing_runner_test.dart` (NEW, behavioral): `runTimed` logs exactly once with `outcome=ok` on success, `outcome=threw` and rethrows on failure, a throwing `log` does not change the body's result or error.
- `test/contracts/auth_ensure_timing_presence_test.dart` (NEW, presence for the WIRING only, reason stated): comments stripped; every lap name appears in source order in `_ensureLocalUser` / `hydrateFromCloud`; `_ensureLocalUser`'s body is inside `runTimed(`; the `auth_ensure_timing` literal sits in that call's `log`. Reason: `_ensureLocalUser` needs a live Supabase + Hive session.
- Repoint: `test/contracts/auth_provider_error_surfacing_test.dart:23-34` slices 11000 chars from `_ensureLocalUser(`; `recordNonFatal` sits ~10787 in (R1-3). Bump the window to 16000 with a dated comment, as earlier bumps did. Avoid re-indenting the body: `runTimed` wraps a closure that calls a renamed private `_ensureLocalUserBody` (the old body, unindented), so the window test is repointed to `_ensureLocalUserBody(`; decide by measuring after the edit.
- Mutations (rule 21): drop the stage emit; flip the kill-switch default; make `emailVerified` sticky in `copyWith`; drop the verified branch for generic errors; move the `runTimed` log out of `finally`; delete one lap.

---

## P1 — "all phases" (walk decision P1) + numerals past XII

### Facts (verified 2026-11-25)
- Code is uncapped: `workout_schedule_read_service.dart:678-687` removed the `>= 12` end on 2026-05-31; the generator names phase 13+ "Deployment N" and recycles focuses (`plan_engine/plan_generator.dart:457-497`, archetype `(phase-1) % 4`, `periodization_engine.dart:20`). No test drives phase 13.
- Stale copy (client): `paywall_sheet.dart:139` benefit "(phases 2-12)", `:155` switch case `'Phases 2-12'`; `paywall_sheet_phase_variant.dart:26,140` feature token, `:44` "Auto-generate Phases II–XII…", `:88` "Phases II–XII unlock automatically…"; `phase2_preview_card.dart:218` "Phases 2-12 unlock full 48-week journey"; feature token at `graduation_screen.dart:347`, `phase_unlock_card.dart:83`, `plan_expired_card.dart:114`.
- Stale copy (server): `supabase/functions/_shared/captain_manual.ts:115` "Phases II–XII auto-generated". Imported by `ai-proxy` and `weekly-report`. Redeploy of both = own founder go, from main after merge (`edge-function-deploy-rollback` skill).
- The feature token is also the paywall letterhead (`paywallLetterheadTitle` `paywall_sheet.dart:67-69` -> "Phases 2-12 is a PRO feature") and the `paywall_shown` telemetry value (`:205` and siblings). Nothing server-side reads it (git grep outside lib/test: docs only). The GATE key `phases_2_to_12` (`app_constants.dart:42`, `graduation_screen.dart:346,354` telemetry) is NOT renamed.
- Numerals: three private 1-12 maps fall back to arabic past 12: `hold_week_labels.dart:156-162` `phaseRoman`, `week_selector.dart:987-993` `_phaseRoman` (labels :192, :209, :218, :230, :495: a PRO user in Phase XI sees "PHASE 13" for the phase two ahead), `hold_roadmap_strip.dart:28-32` `_roman`. Parse: `preview_plan_provider.dart:181-187` `_romanToInt` (unknown -> 1). The preview is reached only by free users for II/III (`train/screen.dart:301-304`, `phase_roadmap_screen.dart:121,134`), so the parse defect is latent, not live. (Corrected in chat 2026-11-25: an earlier message said the preview was wrong from Phase XI on.)

### Fix
1. New `lib/core/utils/roman_numeral.dart`: `String toRoman(int n)` (standard subtractive form for 1..3999, `'$n'` otherwise) and `int? fromRoman(String s)` (strict: only canonical forms; `toRoman(fromRoman(s)) == s`, else null).
2. `hold_week_labels.dart` `phaseRoman` delegates to `toRoman` (name kept; callers unchanged). **`week_selector.dart` `_phaseRoman` and `hold_roadmap_strip.dart` `_roman` stay as one-line delegates** (`=> phaseRoman(phase)`), only their maps go (R1-1: Gate `scripts/check_week_selector_phase_labels.dart:32` and `week_selector_reads_current_phase_test.dart:25`, `week_selector_past_phases_test.dart:102,112-114`, `week_selector.dart:165` comment and `docs/sot_registry.yaml` all pin `_phaseRoman(widget.currentPhase`). `_phaseRoman` call sites :192, :209, :218, :230, :495, :646 are unchanged. `preview_plan_provider.dart` `_romanToInt(x)` -> `fromRoman(x) ?? 1` (fallback kept; latent only).
2a. **Profile journey card past XII (R1-4, verified):** `journey_timeline.dart:129` draws `List.generate(12, …)` dots (`:130-131` completed/current, `:134` `phase < 11`), so from Phase 13 all 12 read completed and none current; `:19-21` names phase 13 "Phase 13", so `:113` reads "Phase 13 — Phase 13". Fix: a pure `journeyDotWindow(currentPhase)` returns the 12-phase block containing the current phase (start = `((p-1) ~/ 12) * 12 + 1`), dots labelled from that start; the name past 12 is `'Deployment ${p - 12}'` (the generator's own name for 13+, `plan_generator.dart:490`). Phases 1-12 byte-identical. Test `test/features/profile/journey_dot_window_test.dart` (p = 1, 12, 13, 24, 25) + a widget pump at phase 13 (exactly one current dot, the first). (Phase-name lists differ across journey / generator / `phaseNameFor`: pre-existing, not widened; recorded in the diagnose doc.)
3. Copy (Wardroom voice, terse):
   - Feature token `'Phases 2-12'` -> `'Phase Progression'` at all 5 call sites + the `:155` case (letterhead "Phase Progression is a PRO feature"; subtitle unchanged). One constant `PaywallSheet.phaseProgressionFeature` so the five sites and the switch cannot drift.
   - `paywall_sheet.dart:139` -> `'Generate new plans after Week 4 (all phases, no end point)'`.
   - variant `:44` -> `'Auto-generate all phases after Phase I as you complete each block'`; `:88` -> `'All phases after Phase I unlock automatically when you finish each block — your AI coach generates the next 4 weeks the moment you\'re ready.'` (keep the existing `\'` escape, R1-18).
   - `phase2_preview_card.dart:218` -> `'All phases unlock, with no end point'`.
   - `captain_manual.ts:115` -> `'- All phases after Phase I auto-generated, with no end point (free locks at Phase I after 4 weeks)'`.
4. Telemetry: `paywall_shown feature=` value changes from `Phases 2-12` to `Phase Progression`. `paywall_sheet.dart:84-96` (Hermes L1) protects funnel continuity, so this is DELIBERATE and stated: pre-launch, testing accounts only (root CLAUDE.md §1); the constant's doc comment names the old value and the date. Other reader: `paywall_play_body.dart:71` (telemetry only).
5. Other stale "2-12" text, same commit (R1-18): `README.md:23,223`, `docs/architecture/business-rules.md:34`, `lib/shared/repositories/plan_engine/CLAUDE.md:51`, `.claude/memory/feature_decisions.md:55`, `lib/features/dev/simulation_service.dart:8` (comment). Re-grep at implementation time for `2-12`, `2–12`, `II–XII`, `48-week`.

### Tests (P1)
- `test/core/roman_numeral_test.dart` (NEW): known values (1 I, 4 IV, 9 IX, 12 XII, 13 XIII, 14 XIV, 19 XIX, 40 XL, 49 XLIX, 90 XC, 400 CD, 3999); round trip 1..200; `fromRoman` rejects `IIII`, `VX`, `IC`, `''`, `xiii` lower-case (decide: reject), `XIII ` with space; 0 / negative -> arabic.
- `test/contracts/phase_roman_single_source_test.dart` (NEW, source): no other `'XII'` numeral map under `lib/` (comments stripped); `phaseRoman` body calls `toRoman`; `week_selector.dart` and `hold_roadmap_strip.dart` call `phaseRoman(`. Plus a widget-free behavioral: `phaseRoman(13) == 'XIII'`.
- `test/contracts/phase_13_generation_behavioral_test.dart` (NEW, **characterization**, R1-14: the generator already does this, so it cannot fail "without the fix"; it guards the promise the new copy makes): the `cross_phase_variety_behavioral_test.dart` setup; `generateV4(phase: 13)` -> blob `name == 'Deployment 1'`, 4 week plans, every week has ≥1 workout day with ≥1 exercise; `phase: 14` -> `Deployment 2`. Mutation: change the generator's `'Deployment ${phase - 12}'` fallback in a scratch copy only -> red (plan_generator.dart itself NOT edited, rule 14; the mutation is reverted and `git diff` empty). The DISPLAYED name comes from `WorkoutScheduleReadService.phaseNameFor` (3-name cycle), unaffected.
- **Stale-copy ban (R1-12):** `test/contracts/phase_copy_no_end_point_test.dart` (NEW): comments stripped, no `\b2\s*[-–]\s*12\b`, `II\s*[-–]\s*XII`, `48-week` in any `lib/**/*.dart` string or in `supabase/functions/_shared/captain_manual.ts`. Deno: extend `captain_manual_limits_test.ts` (or the nearest `captain_manual_*_test.ts`) to assert the manual has no `II–XII` and has the new "no end point" line.
- Repoint (never loosen): `paywall_phase_variant_mode_none_test.dart:105` (expect `'${PaywallSheet.phaseProgressionFeature} is a PRO feature'`), `paywall_generic_upgrade_title_behavioral_test.dart:93`, `audit_2026_06_07_batch5_regression_test.dart:111`, `phase_c_oi_closures_test.dart:247` (all to the constant). **Invert** `hold_week_labels_test.dart:265` (`phaseRoman(13)` was pinned to `'13'`; now `'XIII'`; keep the `0` case) — stated in the diagnose doc as an inversion (R1-2).
- Mutations: revert `toRoman` to the 1-12 map; re-add a private map in `week_selector.dart`; restore the old token at one call site; re-add "Phases II–XII" in the variant; journey window back to `List.generate(12`.

---

## Docs / ledgers (same commit)
- Diagnose docs: `docs/diagnoses/2026-11-25-confirm-email-no-progress-<id>.md` (B6), `docs/diagnoses/2026-11-25-phase-numeral-past-xii-<id>.md` (P1 numerals). P1 copy is a decision, recorded in the second doc.
- Closure ledger `docs/audit/oi348-landing3a.closure.yaml` (6 items: B6 stage, B6 timing, P1 copy, P1 numerals, journey card past XII, captain_manual deploy; plus the account-load speed-up as `upstream_blocked`, reopen when the first `auth_ensure_timing` phone row exists).
- `docs/sot_registry.yaml`: `confirm_email_verified_stage` (writer `_performConfirmEmail`, reader `ConfirmEmailScreen`, behavioral test above); `phase_roman_numeral` (writer `toRoman`, readers the 4 label sites).
- `docs/naming_conventions.md`: `auth_ensure_timing`, `disable_confirm_verified_stage`, `StepTimings`, `Phase Progression`.
- `lib/features/auth/CLAUDE.md`: confirm-screen row (verified stage + kill switch); `lib/features/train/CLAUDE.md` if it cites the numeral maps.
- OI-348 board artifact + `docs/audit/open_issues.md` OI-348 entry: Landing 3a status.

## Order
1. Gate loop baseline. 2. P1 numerals + tests. 3. P1 copy + repointed pins. 4. B6 stage + seams + tests. 5. Timing + tests. 6. Mutations. 7. Docs. 8. `flutter analyze --no-fatal-infos` (whole project), pre-commit gate loop, commit, PR, `land_pr`-equivalent CI wait. 9. B-pass. 10. Record, merge. 11. EF redeploy (`ai-proxy`, `weekly-report`) on the founder's go.

## Round 1 log (reviewer #1, Sonnet, context-blind, 2026-11-25; every cited line re-read by the coordinator)
P1: R1-1 `_phaseRoman` pinned by a gate + 3 tests -> delegates kept. R1-2 `hold_week_labels_test.dart:265` pins `'13'` -> inverted. R1-3 `_ensureLocalUser` 11000-char window -> repointed/bumped.
P2: R1-4 journey card caps at 12 -> fixed (2a). R1-5 sticky flag -> non-sticky. R1-6 verified generic errors -> mapped. R1-7 "Sign in to continue" false -> copy names the button. R1-8 seams -> two, real `confirmEmail`, fakeAsync ceiling. R1-9 laps -> no outer `hydrate`, finer `h_*`. R1-10 verify unmeasured -> `verify` / `sign_in` laps. R1-11 presence-only `finally` -> `runTimed` runner tested. R1-12 no stale-copy ban -> ban test + Deno. R1-13 funnel continuity -> stated.
P3: R1-14 phase-13 test is characterization -> said so + scratch mutation. R1-15 §4.6 for timing -> justified (cannot throw). R1-16 `finally` vs ceiling -> safe, late `ok` row noted. R1-17 lock narrower -> B6 finding 2 stands. R1-18 other stale refs + `\'` -> added. R1-19 :646 call site, registry ranges stale-ungated, blast radius platform, EF list ai-proxy + weekly-report -> confirmed.

## Round 2 log (reviewer #2, Sonnet, context-blind, on the post-round-1 plan; verdict converged, 0 P0/P1). Amendments below are BINDING and override the text above where they differ.
- R2-1 (P2) Journey dots are in a private `part of` extension nobody pumps. -> Extract public `JourneyPhaseDots({required int currentPhase, required bool isPro})` in `lib/features/profile/widgets/journey_phase_dots.dart`; `journey_timeline.dart` renders it. Free-dim check uses the ABSOLUTE phase (`absolutePhase == 1`, was window index `phase == 0` at `:140`). Widget test pumps 1, 12, 13, 24, 25: exactly one current dot at the right index, completed count right, free-dim right.
- R2-2 (P2) "Deployment N" is never shown elsewhere and "deployment" means the 12-week block (`plan_header.dart:47`). -> Past 12 the journey name CYCLES the card's own list: `phaseNames[(p - 1) % 12]` ("Phase 13 — Foundation"). Drop the "generator's own name" claim. The name-list drift between journey / `phaseNameFor` / generator is pre-existing and recorded, not widened.
- R2-3 (P2) A throw skips laps and its time lands in the next lap. -> Lap at the head of each catch: `h_users_failed`, `h_profile_failed`, `h_progress_failed`, `h_plan_gen_failed`.
- R2-4 (P2) Seam signature: `ensureLocalUserAfterConfirm(User user, StepTimings timings)`.
- R2-5 (P3) Tests set `ErrorTelemetry.debugOnLogEventForTests` too; every `Completer` completed in `tearDown`; (d) limitation noted.
- R2-6 (P3) Message order: `outcome=<..> total=<ms> <laps>` (500-char cap keeps the head). LOW priority + the anon-lane loss for the `StateError` case are accepted and stated in the diagnose doc (one row per sign-in; not worth a HIGH op type + server twin).
- R2-7 (P3) Also update `lib/features/train/CLAUDE.md:92`, `docs/architecture/train-detail.md:90,97`, `supabase/functions/_shared/hold_week.ts:6` (comment only), README en-dash "2–12". `sign_in_screen.dart:341` "Twelve months. We change the man." is brand time copy, not a phase cap: unchanged, ledger `verified_clean`. `ward_phase_dots.dart` (`totalPhases = 12`) is unused in `lib/` (only exported): ledger `verified_clean` with that evidence. `phase2_preview_card.dart:270-286` past-12 fallback is latent (card shows II/III only): `verified_clean`. Ellipsis: use `...` like the sibling string.
- R2-8 (P3) Ban-test stripper limits noted in the test's doc comment.
- R2-9 (P3) Closure ledger has 7 entries (`total_findings`/`closed_count` computed); captain_manual redeploy is `blocked_on_user` until the founder's go, then `closed_in_commit` in a follow-on ledger edit. SoT entries carry `semantic: display-only`, `reader_manifest_complete`, `behavioral_test_path`. Re-baseline the context budget if a tracked CLAUDE.md grows.
- R2-10 (P3) Add `package:icanbefitter/core/utils/hold_week_labels.dart` imports; remove the stale doc at `hold_week_labels.dart:150-155`. The overloaded `StateError` mapping is pre-existing and unchanged by this batch.

## Implementation notes (2026-11-25, deviations from the text above, all stated in the diagnose docs)
- `runTimed` is a top-level function in `lib/core/utils/step_timings.dart` (tested alone), not a static on `AuthNotifier`. `StepTimings` takes an optional `elapsedMs` clock for tests (a `Stopwatch` ignores fake time).
- The phase-13 characterization test was NOT mutated: its only target is `plan_generator.dart` (rule 14, not even temporarily).
- The journey free-dim rule keys on the absolute phase, but absolute vs block index cannot be told apart on screen (a block's first dot is never a future phase); no test claims otherwise.
- Message shape: `outcome=<..> total=<ms> <laps>` (R2-6).

## Out of scope (named, not deferred)
- Speeding up the account load: needs the first `auth_ensure_timing` number (upstream_blocked on data).
- Landing 3b/3c/3d (B4+P5, P2, P3): separate founder calls pending.
