# Plan: flip `enable_body_measurements` to default ON (L2b flag flip)

Branch `measurements-flag-flip`, base `745bdc95`. Tier: platform (`lib/core/services/measurement_flags.dart` has an exact-path platform rule, `docs/blast_radius.yaml:535`). Execution mode: inline, one worktree, no subagent builders (the change is one function plus tests and docs). Reviews: full x2 plus a B-pass (CLAUDE.md 4.12.1, 4.12.4: the flip commit of a ship-dark flag).

## 0. What and why

Landings A (bounds, PR #103), B (the entry sheet, Home banner, Weight-sheet link, PR #110) and C (the Progress comparison card E3 and the chat chip E4, PR #113) shipped DARK behind `enable_body_measurements`, default OFF. The founder wants to test the measurements in a release AAB; a release build cannot reach the dev panel (`/dev` is registered only under `kDebugMode`, `lib/core/router/app_router.dart:380`), so the only way to see the surfaces in a release build is a default-ON flag. Gates stated by the Landing B/C plans for the flip, all answered by the founder in chat on 2026-10-16:

| Gate | Answer |
|---|---|
| OQ-L2a (stale-overwrite / null-sending old clients) | option 1, accept; L2c not built; the app is in testing and no earlier measurement data exists (the last cloud count, 0 rows, was read 2026-10-11 and is re-read by the `CLOUD-ROWS-RECHECK` row below). The ledger edits that record it (`L2B-ENTRY` verified_clean, `LEGACY-PUSH` reopened) are on PR #117 (branch `founder-decisions-l2b`), NOT yet on `main`. |
| `LEGACY-PUSH` (out-of-range finite values still pushed) | accepted by the founder for the same reason (internal testers only); this batch's ledger row `LEGACY-PUSH-ACCEPTED` records it. |
| OI-310 (privacy policy) | the founder published the updated policy at the existing icanbefitter.com/privacy link on 2026-10-16; the links in the app are unchanged. Fetched and read on 2026-10-16 (ledger `POLICY-CHECK`, verified_clean): it names AVYA Fit, body measurements as health data, Gemini and the other processors, retention, in-app deletion, a grievance officer, and says users must be 13 or older with a date of birth asked at sign-up. |
| OI-305 (age) | the founder decided on 2026-10-16 to make the floor 13 and acknowledged the age status quo for measurement entry. **The code is not in this batch and NOT yet true of the build:** onboarding still accepts 10 (`identity_screen.dart:82`). The published policy says 13 or older and a date-of-birth check at sign-up, so the flip must not reach production before branch `age-floor-signup-consent` (floor 13, consent text, stored policy version) is merged. **Merge order, binding:** (1) PR #117, (2) the age-floor and consent batch, (3) this flip. |
| D8-D10 | confirmed as built (recorded on PR #117, merged as aa7a1586). |

## 1. The change (writer and reader named)

**Writer of the key:** `lib/features/dev/dev_panel_screen.dart:275-276` (`_toggleBodyMeasurements` declared at :274, debug builds only) puts a `bool` into `configBox['enable_body_measurements']`. No other writer exists in `lib/` (`git grep -n "enable_body_measurements" lib`).

**Readers:** `MeasurementFlags.bodyMeasurementsEnabled` (`lib/core/services/measurement_flags.dart`) is read by `measurementsEnabledProvider` (`lib/features/profile/providers/measurement_flag_provider.dart:16`), `ConversationalLogHandler` (`lib/features/ai_coach/services/conversational_log_handler.dart:171`) and the dev panel (`dev_panel_screen.dart:275,487,508`). The Home slot, the Weight-sheet link, the Progress frame, the chat chip slot and the prompt provider read the Riverpod provider.

**New getter:** `stored = configBox.get('enable_body_measurements')`; `return stored is bool ? stored : true;` inside the existing `try`; the `catch` (no Hive / unopened box) still returns `false`. Meaning: absent or any non-bool value is ON; a stored `bool false` is the kill switch; an unopened box is OFF (the safe side, which also keeps every pure unit test that never opens Hive on its old path).

**Kill switch limits, stated (round 1, lens B):** a release build has no UI writer of `false`; the switch is reachable by the dev panel in a debug build only, and a stored `false` is erased by sign-out (`UserRepository.clearAllData` clears `configBox`, `user_repository.dart:1211`), after which the flag reads ON again. There is no remote switch: turning the surfaces off for released users needs a new build. **Audience, on the record:** merging this to `main` exposes the surfaces to every signed-in user of the production web app (app.icanbefitter.com) and of any release build, and nothing in the code enforces "internal testers only". The founder stated on 2026-10-16 that the app is in testing and every row is an internal tester's, so this exposure is accepted; if the build is ever sent to a wider audience before OI-345, a remote switch (RemoteConfig) is a founder decision to make first. The OFF path stays for exactly this reason (OI-345 removes it after the founder's device check). The dev panel row and its toast now read `KILLED` for a stored `false`, like the equipment-exclusions row. **Web, stated (round 2, lens B):** the web app (app.icanbefitter.com) is built from `main` and has the same flag with the same default, so merging this to `main` makes the surfaces live on the production web app for every signed-in user as soon as that deploy lands (the Vercel production deploy follows `main`; UNVERIFIED here whether it is automatic). Turning them off on the web needs a rebuild and redeploy, the fastest rollback path. The founder merges this PR knowing that.

## 2. What every user of the next build sees (the exposure)

HOME-24 (banner due/baseline), the Weight-sheet link, PROF-21 (card on Progress comparison), COACH-21 (chip). The entry sheet writes through `HealthWriteService.logMeasurement` into `healthBox` `measurement_<IST date>`; sync pushes it with the merge-safe body (`sync_health.dart`, L2a). All of that code merged earlier and is exercised by the Landing A/B/C suites with the flag forced ON; this change alters only the DEFAULT.

## 3. Tests

Four rows assumed absent means OFF and are rewritten, in three files (the day-rollover one is a one-line fixture edit): `measurement_flag_off_identity_test.dart` (absent -> ON; only a stored `false` is OFF; non-bool values -> ON; the prompt-provider OFF test now stores `false`) and `user_scoped_provider_rebuilds_on_auth_change_test.dart` (absent -> ON; a stored `false` is re-read on a token change). New cases pin: absent ON, `false` OFF, `'false'`/`0`/`'off'` ON (not truthy-OFF), `delete` returns to ON; the unopened-box OFF case already existed and is unchanged. `day_rollover_provider_invalidation_behavioral_test.dart` (flag-OFF rollover row) now stores `false` itself instead of relying on an absent key (it passed vacuously: `runRolloverNow` only invalidates). Mutations to run: `is bool ? stored : true` -> `: false`; catch `false` -> `true`; `stored is bool` -> `stored == true`; each must redden.

## 4. Docs

`default OFF` wording updated in the three nested CLAUDE.md files that carried it (`ai_coach`, `home`, `profile`), `functionality-flow.md` (HOME-24, COACH-21, PROF-21), `sot_registry.yaml`, and the provider doc comment. The registry rule for the flag file STAYS (the file is the kill switch of a default-ON flag; it goes with the flag under OI-345) and its comment is rewritten; the Landing B note said the flip deletes the rule, and `ship_dark_pending_review.yaml` now says why it does not. OI-345 (minted) tracks the OFF-path removal after the device check (CLAUDE.md 4.6 step 4: the founder schedules the roll, so it is tracked, not intended).

## 5. Ledger (`docs/audit/measurements-flag-flip.closure.yaml`)

Rows: `FLIP-CODE`, `TESTS`, `MUTATION`, `DOCS`, `REGISTRY-RULE-STAYS`, `REVIEWS` (this plan's record and the B-pass file), `LEGACY-PUSH-ACCEPTED` (founder, 2026-10-16), `POLICY-CHECK` (the page was fetched and read on 2026-10-16; `verified_clean`), `CLOUD-ROWS-RECHECK` (a read-only count of `body_measurements` rows, `blocked_on_user` because live SQL is the founder's go), `MERGE-ORDER` (the three-step order in §0), `FLIPPED-BUILD-CHECK` (founder-owned device and web check of the flipped release build: the card, the chip, the banner, the sheet, the dev-less release path; this row, not the Landing C rows, unblocks OI-345), `OFF-PATH-REMOVAL` (OI-345, `blocked_on_user`).

## 6. Rollback

Revert the flag-file commit (a new build). Locally, a debug build can store `false`. No schema, no Edge Function, no migration.

## 7. Out of scope

The age floor and sign-up consent (own batch), the privacy-policy text, L2c, OI-304, and any code change to the entry sheet, the card or the chip (the flip changes who sees them, not what they do).
