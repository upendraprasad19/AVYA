---
bug_id: b7c1e4
date: 2026-10-05
batch: progress-screen-pro-gate
status: fixed
blast_radius: feature
symptom: >-
  A free user could reach and USE the Progress Photos screen by editing the address of an already-open web tab to
  `#/profile/progress-photos`. The screen had no PRO check of its own: the only gate was the Photos hub's Progress row
  (`gateAndVerify(featureProgressPhotos)`), so a way in that never touches the hub got a working screen that listed the
  user's photos and uploaded with the free allowance (2 a day, 2048/85), although `progress_photos` is a server-verified
  PRO feature (CLAUDE.md rule 19). Founder decision 2026-10-05: the screen enforces PRO itself.
concept: subscription_state
sot_registry_entry: subscription_state
writers:
  - { file: lib/features/profile/screens/user_photos_screen.dart, method: "Progress row onTap: gateAndVerify(featureProgressPhotos, onPro: push, onFree: paywall), the ONLY place the PRO decision was made, and it was made at the door", line: 104 }
  - { file: lib/core/services/subscription_service.dart, method: "gateAndVerify: local isPro(), then verifyFromServer() for a high-value feature", line: 729 }
readers:
  - { file: lib/features/profile/screens/progress_photos_screen.dart, method_or_widget: "_ProgressPhotosScreenState._enter (the screen's own gate on entry) and _onAddPhoto (the Storage-writing action's gate); both are new", line: 74 }
  - { file: lib/core/router/app_router.dart, method_or_widget: "GoRoute progress-photos, no redirect: any way in reaches the screen", line: 533 }
hive_key_prefix: isPro
hive_key_formula: "MigratedKey.readWithDefault<bool>('isPro', false)"
sync_methods: []
restore_methods: []
cloud_table: "subscriptions (verify-subscription reads it); progress_photos and the progress-photos Storage bucket (what the screen reads and writes)"
cloud_columns:
  - user_id
  - plan
  - status
  - end_date
contract_test_path: test/contracts/progress_photos_screen_gate_test.dart
ist_handling: []
provider_invalidations:
  - subscriptionInfoProvider
  - messageLimitProvider
telemetry_op_types:
  success:
    - subscription_gate_routed
  failure:
    - subscription_gate_callback_threw
    - subscription_gate_verify_failed
cross_account_guard: "n/a -- the gate reads the signed-in user's own PRO state through SubscriptionService; no per-account client state is added"
forbidden_patterns_checked:
  - { pattern: "configBox\\.get\\('isPro'\\)", absent: true }
  - { pattern: "SubscriptionService\\.instance\\.isPro\\(\\)\\s*\\?\\s|isPro\\s*==\\s*true\\b", absent: true }
  - { pattern: "ProgressPhotosScreen reachable with no gate of its own (checked for THIS screen only: git grep over lib/ for ProgressPhotosScreen finds the router, the hub and the screen itself). The other gate-then-navigate doors in lib/ were swept separately: Reports and Graduation, ledger rows S1 and S2, both verified_clean", absent: true }
  - { pattern: "feature: 'progress_photos' (the feature id passed to the paywall; the letterhead reads the display string)", absent: true }
proposed_fix: >-
  The screen runs the same gateAndVerify the door runs, on entry (`_enter` from initState: locally-free answers
  synchronously with a locked card, locally-PRO awaits the server verify and only then shows the gallery and reads the
  photos) and again on its Storage-writing Add button (`_onAddPhoto`, with a re-entrancy guard and a busy spinner
  because a stale 5-minute verify cache plus a slow network makes the gate wait up to 10 s). A user the gate refuses
  sees the design system's PRO locked card (ProLockedOverlay, hardened: it scrolls in a short window or at a large text
  scale, and its CTA is a keyboard-operable 44 dp button) and a user who then upgrades gets the gate re-run from a
  ref.listen on subscriptionInfoProvider. The hub's gate stays (a free user still gets the paywall over the hub). The
  repository's free branch stays as a backstop. A test seam, ProgressPhotoRepository.debugOnListForTests, lets a test
  prove a refused user triggers no photo read. Docs, comments and reason strings that said the hub row is the only
  gate are repointed; ledger row R1-04 of the Photos-hub batch is closed.
regression_test_planned: >-
  test/contracts/progress_photos_screen_gate_test.dart (34 tests: FREE card / first frame / no read / Upgrade by tap
  and by keyboard (Tab reaches it) / a sweep of every tappable widget on the locked screen / button semantics /
  centring / the pill / short windows and 2x text; upgrade re-gate; PRO spinner first frame, gallery, no re-gate on a
  refresh, no second gate for a write while the entry gate is pending; lapse; Add opens the picker; two quick taps open
  one sheet; busy spinner and recovery; leaving inside either verify; lapse then pay again; through the hub; source
  pins that count references). It lives in test/contracts/ (root section 4.1); a first version sat in test/profile/.
  Existing pins that must stay green: test/profile/user_photos_hub_test.dart, user_photos_gate_behavioral_test.dart,
  profile_share_grow_order_test.dart, test/contracts/audit_2026_06_07_batch5_regression_test.dart,
  test/subscription/high_value_features_test.dart.
mutation_proof: >-
  Rule 21, three rounds in sandbox copies (each mutant confirmed applied by a marker count, restored and cmp-checked).
  Round 1 (21 mutants against the first tests): 17 RED, 1 driver error (its edit pattern missed the guard; rebuilt),
  2 expected-equivalent, and ONE REAL SURVIVOR (the locked card showing another feature label: the label was asserted
  nowhere) -> assertion added. Round 2 (40 against the post-round-1 code): 37 RED, 2 expected-equivalent by
  construction (one was NOT equivalent: checking falling through showed an earlier PRO period's gallery during a
  re-check after lapse then pay; a test was added and the mutant went RED; the other, a dead mounted guard in _enter,
  was deleted) and one that first read NOT-APPLIED because its marker counted the field initializer (marker fixed,
  re-run RED x3). The round-2 plan review then named mutants that survive: a picker or _load tear-off, a direct
  repository call, a listener that reacts while checking, no button semantics, no centring, no widthFactor, and a probe
  that would go silent if SubscriptionInfoData gained an ==. Round 3 (49 mutants against the final code and the 34
  tests: the 39 live ones of round 2 plus ten for those survivors, N01-N10): 49 RED. The per-mutant table, with the
  edit and the tests it reddened, is at the end of this document.
impact_analysis: >-
  Before: a free user in an already-open web tab who edited the address reached a working Progress screen and could
  upload and list photos with the free allowance. After: that user sees a locked card with an Upgrade button (the
  paywall), no photo is read, no upload button exists, and a subscription that lapses while the screen is open is
  caught at the Add button. A fresh load of that address is unaffected either way: the session gate sends it through
  /restoring to Home before any screen builds. A PRO user passes the same server-verified gate the hub row already ran
  (cached 5 minutes after a 200 answer), so the normal case costs nothing; with a stale cache and a slow network the
  screen waits up to 10 s on the spinner per verify (about 20 s through the hub when the hub's own verify timed out).
  Not fixed here, and named: the server has no PRO rule for this table or bucket (RLS is own-row only; the bucket
  policies are not in the repo), so a determined client calling the API directly is not stopped (row C5, needs a
  migration and a live apply and the founder's go); a lapsed user cannot view or delete old photos in the app at entry (row C7,
  Delete Account is the only in-app erasure, the same as the hub row already behaved), and a screen that is already open
  when the subscription lapses keeps showing and deleting until the next Add tap.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "progress_photos_screen.dart (entry gate, write gate, guard, listener, locked state), pro_locked_overlay.dart (scrolls, keyboard-operable CTA), progress_photo_repository.dart (a null test seam and a comment); 34 new tests, the whole suite green on the final tree (the count is in the commit message), flutter analyze lib/ with no new finding" }
  - { tier: 2, name: "Hive (local state)", status: verified, evidence: "no Hive write added; the gate reads isPro through SubscriptionService (MigratedKey); tests drive the real local state with MigratedKey.write" }
  - { tier: 3, name: "Postgres schema", status: not_applicable, evidence: "no schema change, no migration" }
  - { tier: 4, name: "Postgres data", status: not_applicable, evidence: "no data touched and no live query made; the R1-04 facts were read from the repo" }
  - { tier: 5, name: "Migrations applied", status: not_applicable, evidence: "no migration" }
  - { tier: 6, name: "Edge Function code vs deploy", status: not_applicable, evidence: "no Edge Function changed; verify-subscription is called exactly as before" }
  - { tier: 7, name: "Cron jobs", status: not_applicable, evidence: "no cron involvement" }
  - { tier: 8, name: "RLS policies", status: not_applicable, evidence: "no policy changed; the absence of a PRO rule on progress_photos is recorded as ledger row C5 (blocked_on_user), not fixed here" }
  - { tier: 9, name: "Storage buckets + objects", status: not_applicable, evidence: "no bucket or object touched; the bucket policies are not in the repo (recorded in C5)" }
  - { tier: 10, name: "Secrets / API keys", status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11, name: "External services", status: not_applicable, evidence: "no external service touched; the web app redeploys on merge" }
  - { tier: 12, name: "Client -> server contract", status: verified, evidence: "the branch both gates take is the server-verified one (reason=verify_pro in the PRO tests, so dropping progress_photos from the high-value list turns them red); the HTTP round trip itself is not exercised by unit tests (Supabase is not initialized there) and no live call was made" }
recurrence: "none found (INDEX grep for progress photo, ungated, gate bypass, PRO gate, paywall: 7b3eaf is gate callbacks, 40c401 the purchase path, c2b8e5 the paywall label; none is a PRO-only screen reachable around its door). First instance: row R1-04 and B-pass findings B1, B05, B11 of the profile-share-grow-order batch"
related_bugs: []
---

# The Progress Photos screen had no PRO check of its own: the gate was on its door only

## What was wrong

PRO gating for Progress Photos lived in ONE place, the Photos hub's Progress row
(`user_photos_screen.dart`, `gateAndVerify(featureProgressPhotos, onPro: push, onFree: paywall)`).
`ProgressPhotosScreen` itself never asked: `initState` called `_load()`, which read the photo list, and its
floating button opened the picker and uploaded. The route (`app_router.dart`, `progress-photos`) has no `redirect`.
So any way in that did not go through the hub row got a working screen. The way that exists today is the part of the
address after `#` edited in a web tab that is already open and signed in (a fresh load goes through `/restoring`
and lands on Home, so only a warm tab reaches it; read from `app_router.dart`, `restoring_screen.dart` and
`main.dart`, not tried in a browser). The Photos-hub batch recorded it as ledger row R1-04 and several review
findings, and left the decision to the founder. The founder decided on 2026-10-05 that the screen enforces PRO
itself, because rule 19 lists `progress_photos` as server-verified PRO (it writes to a user-scoped Storage bucket).

## Writer and reader

- Writer of the PRO decision: the hub row, `user_photos_screen.dart:104`, through `SubscriptionService.gateAndVerify`
  (`subscription_service.dart:729`). It decided at the door.
- Reader that needed it and did not ask: `ProgressPhotosScreen` (the base `initState` read photos at once; the base
  button uploaded), reachable through `app_router.dart:533` with no redirect.

## The fix (see `proposed_fix` above, and `docs/plans/progress-screen-pro-gate.md`)

Two locks, on purpose: the hub keeps giving a free user the paywall, and the screen gates itself on entry and on its
write action. Round-1 review of the plan (a context-blind reviewer, 13 findings) added four behaviours that the first
draft lacked, each with a test: a re-entrancy guard and busy spinner on the Add button (a second tap inside a pending
verify opened a second picker); a re-run of the gate when a locked user upgrades (the card never reacted); a locked
card that scrolls and has a keyboard-operable 44 dp button; and a null test seam so that "a refused user triggers no
photo read" is proven by behaviour, not only by a source pin. It also corrected the premise: the door is a warm tab,
not a cold load. Round 2 of the review (a second reviewer, 8 findings, no P0 or P1) found proof gaps, not behaviour gaps: a
test pin that counted calls but not tear-offs, a ledger row citing a test that was never written, and three of the
overlay's claims with no test; all are closed (see the ledger rows RV2-01 to RV2-09) and the regression test now lives in
test/contracts/ as root section 4.1 asks for a fix.

## What is NOT fixed, named so it is not read as done

- **C5 (blocked on the founder):** the server has no PRO rule for `progress_photos` (RLS is own-row only; the bucket
  policies are not in the repo). A screen check stops honest users and the typed address; a direct API call is not
  stopped. The real lock is a database rule (a migration and a live apply), which needs the founder's separate go.
- **C6 (blocked on the founder):** the repository's free branch (2/day, 2048/85) is now a backstop, reachable only if
  PRO lapses between the Add button's gate and `capture`'s own read. Deleting it is a product call.
- **C7 (blocked on the founder):** a lapsed user cannot view or delete old photos in the app (entry is blocked at both
  locks; the hub row already behaved this way). Delete Account is the only in-app erasure. Whether a lapsed user should
  be able to view and delete is a product and DPDP call.


## Mutation table (rule 21; round 3, against the final code and the 34 tests; all 49 red)

Round 1 (21 mutants against the first tests) and round 2 (40 against the post-round-1 code) are summarised in
`mutation_proof` above; this is round 3, run after round 2's review on the tests as they ship. It carries round 2's list
(M20 dropped: its mounted guard was dead and is deleted; M17 is now red; M26 re-run with its fixed marker) and ten new
mutants for the round-2 findings (N01-N10). A mutant is red when at least one of the 47 tests in the two covering files
(this file's 34 and F40's file) fails. Per-mutant outcomes were read from the runner's JSON, not from a summary.

| ID | The edit (one literal change in a sandbox copy, confirmed applied by a marker count, restored and cmp-checked) | Red | First tests that went red |
|---|---|---|---|
| M01 | no entry gate: initState grants and loads | 27 | FREE then PRO: a purchase from the card re-runs the gate and the card gives w…; FREE: no tappable widget on the locked screen reads photos or opens a picker (+25 more) |
| M02 | PRO user locked out (entry onPro sets denied) | 13 | FREE then PRO: a purchase from the card re-runs the gate and the card gives w…; PRO lapses while the screen is open: Add photo shows the paywall, never the C… (+11 more) |
| M03 | free user granted (entry onFree sets granted) | 15 | FREE then PRO: a purchase from the card re-runs the gate and the card gives w…; FREE: no tappable widget on the locked screen reads photos or opens a picker (+13 more) |
| M04 | entry onPro without the mounted guard | 3 | PRO: leaving the screen inside the server verify drops the callback without a…; pin: _load() runs only from the entry gate's onPro (and the retry / post-capt… (+1 more) |
| M05 | entry onFree without the mounted guard | 1 | pin: every gate callback opens with the mounted check |
| M06 | write onPro without the mounted guard | 3 | PRO: leaving the screen inside the Add button's verify drops the callback wit…; pin: every gate callback opens with the mounted check (+1 more) |
| M07 | write onFree without the mounted guard | 1 | pin: every gate callback opens with the mounted check |
| M08 | write gate removed (button opens the picker directly) | 7 | PRO lapses while the screen is open: Add photo shows the paywall, never the C…; PRO, lapses, then pays again: the re-check shows the spinner, not the gallery… (+5 more) |
| M09 | entry gate uses another feature constant | 8 | FREE then PRO: a purchase from the card re-runs the gate and the card gives w…; FREE: the locked card with its label, no photo read, no Add button (+6 more) |
| M10 | write gate uses another feature constant | 3 | PRO lapses while the screen is open: Add photo shows the paywall, never the C…; PRO: Add photo opens the Camera / Gallery sheet, through the server-verified … (+1 more) |
| M11 | Add button shown while denied | 4 | FREE: the locked card with its label, no photo read, no Add button; FREE: the very first frame already shows the locked card (no spinner flash) (+2 more) |
| M12 | entry onFree also reads the photos | 5 | FREE then PRO: a purchase from the card re-runs the gate and the card gives w…; FREE: no tappable widget on the locked screen reads photos or opens a picker (+3 more) |
| M13 | locked card Upgrade button does nothing | 4 | FREE: no tappable widget on the locked screen reads photos or opens a picker; FREE: the Upgrade button is a real button: 44 dp tall and operable from the k… (+2 more) |
| M14 | write onFree shows no paywall | 2 | PRO lapses while the screen is open: Add photo shows the paywall, never the C…; pin: the paywall is shown by the locked card, the refused write and the quota… |
| M15 | write onFree does not lock the screen | 2 | PRO lapses while the screen is open: Add photo shows the paywall, never the C…; PRO, lapses, then pays again: the re-check shows the spinner, not the gallery… |
| M16 | body ignores the denied state (gallery path) | 17 | FREE then PRO: a purchase from the card re-runs the gate and the card gives w…; FREE: no tappable widget on the locked screen reads photos or opens a picker (+15 more) |
| M17 | checking falls through to the gallery path (round 2 recorded this as equivalent; it was not: after a lapse and a new purchase it showed the earlier PRO period's gallery state during the re-check) | 1 | PRO, lapses, then pays again: the re-check shows the spinner, not the gallery… |
| M18 | write gate callbacks swapped (PRO gets the paywall, free gets the picker) | 5 | PRO lapses while the screen is open: Add photo shows the paywall, never the C…; PRO: Add photo opens the Camera / Gallery sheet, through the server-verified … (+3 more) |
| M19 | initState also reads the photos | 13 | FREE then PRO: a purchase from the card re-runs the gate and the card gives w…; FREE: no tappable widget on the locked screen reads photos or opens a picker (+11 more) |
| M21 | locked card shows a different feature label | 1 | FREE: the locked card with its label, no photo read, no Add button |
| M22 | checking renders the LOCKED card (a PRO user would see the lock while it verifies) | 3 | PRO, lapses, then pays again: the re-check shows the spinner, not the gallery…; PRO: a subscription write while the entry gate is still pending starts no sec… (+1 more) |
| M23 | initial state is granted | 1 | PRO: the very first frame is the spinner: no locked card, no Add button, no p… |
| M24 | the Add button shows while checking | 2 | PRO, lapses, then pays again: the re-check shows the spinner, not the gallery…; PRO: the very first frame is the spinner: no locked card, no Add button, no p… |
| M25 | no re-entrancy guard in _onAddPhoto | 1 | PRO: two taps on Add photo inside one gate open ONE sheet |
| M26 | _gating is never cleared (first run NOT-APPLIED because the marker counted the field initializer; re-run with the fixed marker) | 4 | PRO, lapses, then pays again: the re-check shows the spinner, not the gallery…; PRO: Add photo opens the Camera / Gallery sheet, through the server-verified … (+2 more) |
| M27 | the finally clears _gating without the mounted check | 1 | PRO: leaving the screen inside the Add button's verify drops the callback wit… |
| M28 | the Add button is not busy while its gate is pending | 1 | PRO: the Add button is the busy spinner while its own gate is pending, and wo… |
| M29 | no upgrade listener at all | 2 | FREE then PRO: a purchase from the card re-runs the gate and the card gives w…; PRO, lapses, then pays again: the re-check shows the spinner, not the gallery… |
| M30 | listener without the denied condition (re-gates a granted screen) | 2 | PRO: a provider refresh does not re-run the gate or re-read the photos; PRO: a subscription write while the entry gate is still pending starts no sec… |
| M31 | listener without the isPro condition (re-gates a still-free user) | 1 | FREE then PRO: a purchase from the card re-runs the gate and the card gives w… |
| M32 | listener goes to checking but never runs the gate | 2 | FREE then PRO: a purchase from the card re-runs the gate and the card gives w…; PRO, lapses, then pays again: the re-check shows the spinner, not the gallery… |
| M33 | listener grants without re-running the gate | 3 | FREE then PRO: a purchase from the card re-runs the gate and the card gives w…; PRO, lapses, then pays again: the re-check shows the spinner, not the gallery… (+1 more) |
| M34 | a new ungated caller of the picker | 1 | pin: every method that touches Storage has exactly one caller, and the picker… |
| M35 | the repository test seam is not wired | 7 | FREE then PRO: a purchase from the card re-runs the gate and the card gives w…; PRO, lapses, then pays again: the re-check shows the spinner, not the gallery… (+5 more) |
| M36 | overlay CTA no longer 44 dp tall | 1 | FREE: the Upgrade button is a real button: 44 dp tall and operable from the k… |
| M37 | overlay CTA is a bare GestureDetector again (no keyboard focus) | 3 | FREE: the Upgrade button is a real button: 44 dp tall and operable from the k…; FREE: the Upgrade pill hugs its label (not stretched to the card's width) (+1 more) |
| M38 | overlay column no longer scrolls | 3 | FREE: the card also lays out on a desktop platform (the scroll view gets a de…; FREE: the locked card fits a short window at 2x text; the Upgrade button stay… (+1 more) |
| M39 | overlay reverted to the BASE file (all of D12) | 7 | FREE: the Upgrade button is a real button: 44 dp tall and operable from the k…; FREE: the Upgrade button is announced as a button (+5 more) |
| M40 | entry gate deferred to a post-frame callback (D2 reverted) | 2 | FREE: the very first frame already shows the locked card (no spinner flash); pin: initState starts the entry gate and does nothing else |
| N01 | AppBar tear-off to the picker: IconButton(onPressed: _pickAndCapture) | 2 | FREE: no tappable widget on the locked screen reads photos or opens a picker; pin: every method that touches Storage has exactly one caller, and the picker… |
| N02 | AppBar tear-off to the refresh: IconButton(onPressed: _load) | 2 | FREE: no tappable widget on the locked screen reads photos or opens a picker; pin: _load() runs only from the entry gate's onPro (and the retry / post-capt… |
| N03 | AppBar action that goes straight to the repository (a second handle) | 2 | FREE: no tappable widget on the locked screen reads photos or opens a picker; pin: every method that touches Storage has exactly one caller, and the picker… |
| N04 | listener also reacts while the screen is CHECKING (not only when LOCKED) | 1 | PRO: a subscription write while the entry gate is still pending starts no sec… |
| N05 | overlay CTA no longer announced as a button (Semantics without button: true) | 1 | FREE: the Upgrade button is announced as a button |
| N06 | overlay column no longer fills the card (no minHeight): content jumps to the top | 1 | FREE: the card's content is centred while it fits |
| N07 | overlay column no longer centred (Center replaced by a top-left Align) | 1 | FREE: the card's content is centred while it fits |
| N08 | overlay CTA pill stretches to the card width (no widthFactor) | 1 | FREE: the Upgrade pill hugs its label (not stretched to the card's width) |
| N09 | SubscriptionInfoData gains == (a no-op write stops notifying: the probe must notice) | 1 | FREE then PRO: a purchase from the card re-runs the gate and the card gives w… |
| N10 | a retry that opens the picker (one allowed reference swapped for another) | 2 | pin: _load() runs only from the entry gate's onPro (and the retry / post-capt…; pin: every method that touches Storage has exactly one caller, and the picker… |

Not mutated, and why: replacing the `try/finally` around the write gate with straight-line code is equivalent while
`gateAndVerify` cannot throw (its callbacks run through `_runCallback`, which catches a synchronous throw).
