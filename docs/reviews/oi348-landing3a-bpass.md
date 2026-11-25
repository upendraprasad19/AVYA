---
reviewed_at: 2026-11-25T18:40:00+05:30
staged_against: 5b11f7ad
blast_radius: platform
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink, guard_without_its_mirror, missing_input, asserted_fixture_value]
findings_count: 6
verdict: accepted
verdict_note: "Triaged by the author 2026-11-25: F1-F4 and F5a fixed in the B-pass fix commit, F5b and F6 no change (reasons below). Platform tier: advisory verdict."
---

# Code Review — oi348-landing3a at 5b11f7ad (vs origin/main 18540ef8)

PR #344, OI-348 Landing 3a (B6 confirm-email stage + timing, P1 "all phases" + numerals past XII). One fresh
Sonnet seat, read-only, given the plan's rejected alternatives and the founder's decisions. No P0 or P1. The
seat ran 13 test files (110 tests, green); no mutation was run by the seat; the author ran M15-M19 below.

## Finding 1 — P2 — writer_reader_drift (inserted-lines sub-check)
- **file:line:** `docs/sot_registry.yaml` cites of `auth_provider.dart`, `auth_session_bootstrapper.dart`, `week_selector.dart`, `paywall_sheet.dart` (11 listed by the seat), plus `:14068` "Phases 2-12" prose.
- **claim:** the diff inserted/removed lines above those cites; `check_sot_registry_parity` checks bounds only, so they passed while pointing at other text.
- **verification:** `git diff -U0 origin/main HEAD -- <file>` hunk mapping of each base cite; parity gate.
- **suggested-fix:** shift each cite; reword the prose.
- **status:** accepted. The author swept EVERY structured cite (`line_range:` / `line:`) of every file the branch changed through the `-U0` hunks, not only the 11 listed: 30 moved (whole-file `1-9999` sentinels kept), then 5 more after the fix commit's own edits; `_performConfirmEmail` and the preview parse re-cited by hand (the cite fell inside a hunk). "Phases 2-12 write their own weeks" -> "Phases 2 and up". Parity and Gate 42 PASS.

## Finding 2 — P2 — guard_without_its_mirror (verified stage vs the 40 s ceiling)
- **file:line:** `lib/features/auth/providers/auth_provider.dart` stage emit in `_performConfirmEmail`, against `boundSignIn` (`run().timeout(...)`) and the `TimeoutException` catch in `confirmEmail`.
- **claim:** `Future.timeout` does not cancel the body. When the ceiling fires DURING the link check and the check then returns, the stage emit replaced the timeout error with "Email confirmed. Setting up..."; a late load failure then left a spinner. Pre-fix, the error screen stayed.
- **verification:** read the three sites; no test held the link check past the ceiling.
- **suggested-fix:** a per-call token flipped on timeout; skip the stage write when abandoned; mirror test.
- **status:** accepted. `_confirmAttempt` is bumped per `confirmEmail` and again in the `TimeoutException` handler; the stage emit runs only for the live attempt. A late success still lands (pre-fix behaviour, now pinned). Test `(i)` x2 in `test/contracts/confirm_email_verified_stage_behavioral_test.dart` (fakeAsync, held link check, late load failing / succeeding: no verified emit ever). M15 (check removed) 2 red, M16 (bump removed) 2 red. (The seat's "unhandled zone error" detail is wrong: `Future.timeout` drops a late error; the stuck state was real.)

## Finding 3 — P3 — guard_without_its_mirror (confirmEmailErrorState verified branch)
- **file:line:** `auth_provider.dart` `confirmEmailErrorState`.
- **claim:** with `emailVerified`, every non-`StateError` (a Hive or open failure) said "taking longer than usual", which a deterministic failure never resolves.
- **verification:** throw sites between the open and the binds in `_ensureLocalUserBody`.
- **suggested-fix:** "taking longer" for `TimeoutException` only; a neutral message otherwise.
- **status:** accepted. New `confirmedContinueMessage` = "Email confirmed. Tap GO TO SIGN IN to continue." for any other non-`StateError`; `confirmedButSlowMessage` for the ceiling only. Mapping table and `(g1)` updated; M17 (branch widened back) 3 red.

## Finding 4 — P3 — missing_input (fromRoman on the preview route)
- **file:line:** `lib/features/train/providers/preview_plan_provider.dart` parse; route `app_router.dart` `previewWorkout`.
- **claim:** `?phase=MMMCMXCIX` reached `generateV4(phase: 3999)` (old parse: 1).
- **verification:** read the route and the provider (week and day are clamped, so nothing breaks).
- **suggested-fix:** clamp.
- **status:** accepted. `previewPhaseFromRoman` (public, behaviour-tested): canonical numerals I..XCIX (`kPreviewMaxPhase = 99`), else Phase I. M18 (cap removed) 1 red.

## Finding 5 — P3 — guard_without_its_mirror (numeral-table grep; journey card block view)
- **file:line:** `test/contracts/phase_roman_single_source_test.dart`; `lib/features/profile/widgets/journey_phase_dots.dart`.
- **claim:** (a) the "no other table" test needed a quoted `'XII'`, so a map stopping at `'X'` passed. (b) at Phase 13 the dots show only phases 13-24.
- **verification:** the seat's mutation (a 1-10 map in `week_selector.dart`).
- **suggested-fix:** (a) a wider rule; (b) optional block label.
- **status:** (a) accepted: the rule is now 4+ DISTINCT quoted numerals per `lib/` file outside `roman_numeral.dart` (legitimate maximum today is 3, the I/II/III rows; measured), with the rule's own controls in the test; the seat's mutation is M19, 1 red. (b) no change: the 12-phase block view is the plan's round-2 decision (R2-1/R2-2), and the card's line already prints the phase ("Phase 13 — Foundation").

## Finding 6 — P3 — unawaited_no_error_sink (runTimed outcome)
- **file:line:** `lib/core/utils/step_timings.dart` `runTimed`; the swallowed hydrate catch in `_ensureLocalUserBody`.
- **claim:** `outcome=ok` also when `hydrateFromCloud` threw and was swallowed.
- **verification:** read both.
- **suggested-fix:** `outcome=degraded` or `failed=hydrate`.
- **status:** no change. The same line carries the `hydrate_failed` lap, which is how the swallowed failure is meant to be read (the load DID finish, as the user saw it); nothing filters on `outcome` (no dashboard or alert reads `auth_ensure_timing`; it exists for the B6-SPEEDUP read). The seat confirmed exactly-once logging on ok and throw.

## Lenses checked clean (seat's record, condensed)
- L1 paywall token: `git grep` of the old strings across lib/test/supabase/scripts/registry/web: one comment hit; no analytics, EF or test reads the old token; the server gate key `phases_2_to_12` is unchanged by design.
- L1 numeral call sites: 8, all on the converter; `fromRoman` rejects IIX/IC/VX/IIII/empty/lower case.
- L2: no new `functions.invoke`. L3: kill switch present, fails to the fix ON; EF redeploy is a recorded `blocked_on_user` step. L4: no credential-shaped literal. L5: the only new `unawaited` sits on `ErrorTelemetry.logEvent`.
- L6: `emailVerified` does not leak to sign-in, sign-up, OAuth or sign-out; `copyWith` clears it; `hydrateFromCloud` catch laps never return early, repeated names add.
- L7: every new file exists. L8: numerals, block starts (12->1, 13->13, 24->13, 25->25), cycled names and message texts recomputed by hand; `plan_generator.dart` untouched.

## Founder triage notes
Author triage (platform tier, advisory). No finding re-opened a recorded decision.

## Tuning entry
- **2026-11-25** - blast-radius platform - 6 findings; 0 false_alarm; tuning: lens 1 inserted-lines — the author now maps EVERY structured registry cite of every diffed file through `git diff -U0` hunks (35 moved against 11 the seat listed); lens 6 — a state write after an `await` inside a body bounded by `Future.timeout` still runs after the caller's timeout handler (added to SKILL.md as the orphaned-body sub-check).
