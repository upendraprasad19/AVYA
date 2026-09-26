---
branch: email-confirm-ux
date: 2026-09-16
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/email-confirm-ux-bpass.md
---

# Plan-review record — Email-confirm UX (spam hint + Android App Links)

Keystone record for the §4.12 merge gate (`check_plan_review_record_exists.dart`).

**Tier `account`**, computed via `git diff --name-only <merge-base> HEAD` (plus the
round-2 fix's uncommitted changes) piped into `scripts/blast_radius_from_diff.dart -`:
`auth_provider.dart`, `app_router.dart`, `confirm_email_screen.dart`,
`AndroidManifest.xml` are all `auth`-domain / native-manifest paths per
`docs/blast_radius.yaml`. No `SECURITY DEFINER` migration, no payment/AI-proxy path
involved, so the tier stays `account` rather than escalating to `platform` or
`catastrophic` — `hermes: accepted` is therefore not required (only `bpass`, which is
present below).

## Origin

A real user (chintamani78987@gmail.com) never received their signup-confirmation
email. Diagnosis found two independent problems: Brevo SMTP was configured correctly
but a first-send from a new domain/shared IP with zero sender reputation likely landed
in spam, and separately — by design, not a bug — the confirmation link opened a
browser instead of the native Android app (no Android App Links were ever configured).
Founder approved both remediations: a spam-folder hint in the confirmation copy, and
real Android App Links so the link opens the app directly.

## Rounds

**Round 1 — context-blind review of the initial 2-commit implementation**
(`592df7b0` signup-confirmation-lands-in-app + `41163a42` B-pass hardening).
1 material finding: OI-205's "Scope note" and the `lib/features/auth/CLAUDE.md`
pitfall row both asserted `/confirm`'s already-authenticated silent-account-switch
risk was "the same shape `/reset` has always had, just extended to a second entry
point" — implying symmetric, equally-low stakes. Independently re-grepped the whole
`AndroidManifest.xml` and found `/reset` has **no** Android App Link registered
anywhere (never did — password reset moved to an in-app 6-digit code in 2026-08,
diagnose `c9e2b7`), so a `/reset` link, on the rare occasion one exists, only ever
opens in a browser — structurally unable to touch the native app's live session.
`/confirm`, by contrast, is a brand-new `autoVerify="true"` App Link added by this very
branch: tapping it from ANY app hands control directly to the already-running Activity
via `onNewIntent`/`singleTop`, no precondition required. The router-guard SHAPE really
is identical (`_authRedirect`'s `isOnReset`/`isOnConfirm` both pass through
unconditionally, above the `isAuthenticated` check) but the real-world reachability is
not — `/confirm`'s exposure is materially broader and more automatic. Finding 2
(informational only): independently verified via a live fetch of the pre-merge
production URL that the `vercel.json` `.well-known` rewrite fix is empirically
necessary (the old catch-all really does swallow `/.well-known/assetlinks.json` in
production today) despite appearing to contradict Vercel's own documentation, and that
the new negative-lookahead regex matches Vercel's own documented idiom. B-pass:
`docs/reviews/email-confirm-ux-bpass.md` — 7 findings, 0 false alarms, all fixed
(including the `pathPrefix` → `path` exact-match fix, the `initState`/`didUpdateWidget`
re-entrancy guard, the missing success→`/restoring` navigation test, and the
`vercel.json` `.well-known` rewrite Finding 2 above independently re-verifies).

Fix (`ae59174e`): corrected both docs' "Scope note"/pitfall-row bodies to state the
real asymmetry. Founder then chose, via `AskUserQuestion`, to also add a simple
interim code guard now (rather than leave the risk fully deferred to a future UX
redesign): `AuthNotifier.confirmEmail` now refuses outright — via the new pure,
`@visibleForTesting` `confirmEmailAuthGuardState` function — and never calls
`verifyOTP` at all when `SupabaseService.instance.isAuthenticated`, showing "You're
already signed in. Sign out first to confirm a different account." instead of
silently switching sessions. `/reset` is unchanged (already much lower exposure per
the corrected risk picture).

**Round 2 — fresh, context-blind review of the round-1-hardened branch**, per §4.12's
requirement that review #2 run on the corrected plan, not the original. 1 material
finding (Finding 1, P2): the interim guard's only on-screen recovery action
(`_buildSignInLink`'s `context.go('/sign-in')`, shared with every other error state on
this screen) is a **deterministic no-op for the guard's error state specifically** —
`_authRedirect`/`postSessionRedirect` bounce an already-authenticated, onboarded user
straight back to `/home` (or `/onboarding`) before `SignInScreen` ever renders, so the
button's promised "sign out first" never actually happens; the user lands back in
their existing session having done nothing resembling a sign-out. 2 minor findings
(P3, non-blocking per the report's own convergence assessment): stale "is silently
switched" phrasing survived unqualified in OI-205's H2 title and the CLAUDE.md pitfall
row's leftmost column even though both bodies were already correctly qualified
(Finding 2); no test pins that the guard is checked *before* the loading-state write,
only that the pure decision function itself is correct in isolation (Finding 3).

Fix: gave the guard's error state its own distinct `_buildAlreadySignedInState`
widget with a real "SIGN OUT" CTA that calls `AuthNotifier.signOut()` before
navigating to `/sign-in` (mirroring the pre-existing `reset_password_screen.dart`
pattern per diagnose `c8f1d3`: a screen that signs out in place must navigate
explicitly afterward, since GoRouter has no `refreshListenable` tied to auth state) —
closing Finding 1. Retitled OI-205's H2 and the CLAUDE.md pitfall row's leftmost
column to correctly scope "silently switched" to `/reset` only, qualifying `/confirm`
as "partially guarded" — closing Finding 2. Added an honest in-code comment at the
guard's call site in `confirmEmail` acknowledging Finding 3's gap is real but not
closeable without a new test seam on a shared core service (`SupabaseService`'s
`_initialized` flag has no fake-seam, and adding one is a separate, real change, not a
one-line addition to slip into this batch) — documenting it as a known, accepted
residual rather than silently leaving it unaddressed, consistent with round 2's own
verdict that Finding 3 is a coverage gap on correct-as-written code, not a live bug.
New mutation-proven test (`confirm_email_screen_test.dart`, "the already-signed-in
guard state actually signs out before navigating") pins that tapping SIGN OUT calls
the real `AuthNotifier.signOut()` and that the generic "GO TO SIGN IN" button is never
shown for this state; reverting the button to a bare `context.go('/sign-in')` reddens
exactly this test on the `signOutCalled` assertion, mirror-safe (all 5 other tests in
the file stay green).

**Convergence.** 7 (B-pass) → 1 material (round 1) → 1 material (round 2) findings.
Each round's fix introduced the next round's material finding as new surface, not a
defect surviving from before the prior round — the expected shape per §4.12 point 1
(round 1's doc-only correction plus the founder-approved interim guard created the new
error state that round 2's Finding 1 then found had a broken CTA). No round surfaced a
genuinely new mechanism class after round 2 — both of round 2's remaining findings
(2, 3) are minor/textual/coverage-only and don't reopen round 1's material finding or
the B-pass's 7. The unit did not need splitting.

## Ground truth (verified live / against installed package source, not subagent prose)

- `gotrue-2.27.1/lib/src/gotrue_client.dart:661-727` (`verifyOTP`'s full body) read
  directly from the installed pub-cache package: no `code_challenge`/`code_verifier`/
  PKCE artifact anywhere, unlike the neighboring `signInWithOtp` email-link path a few
  lines above it. Confirms `verifyOTP(tokenHash:, type: OtpType.signup)` is completable
  on any device, independently re-derived by both round 1 and round 2 (not trusted from
  the B-pass's own citation).
- `go_router-17.2.3/lib/src/match.dart:220-296` read directly, twice, by two
  independent reviewers: `pageKey: ValueKey<String>(newMatchedPath)` is path-only,
  never the query string — confirms the `didUpdateWidget` re-entrancy reasoning behind
  `_maybeStartVerification`'s `_startedFor` guard is sound.
- Live production fetch of `https://app.icanbefitter.com/.well-known/assetlinks.json`
  (pre-merge) returned the Flutter-web SPA shell, not JSON — empirically confirmed the
  `vercel.json` catch-all-rewrite bug the branch fixes is real, resolving an apparent
  conflict with Vercel's own "`.well-known` is reserved" documentation for this
  project's actual observed behavior.
- `AndroidManifest.xml` grepped in full, independently, by both round 1 and round 2:
  confirmed at the merge-base (`git show bddba4d8:...`) there was no
  `app.icanbefitter.com` / `autoVerify` / `/confirm` / `/reset` App Link entry at all —
  only the pre-existing OAuth custom-scheme filter — so the new `autoVerify` filter is
  genuinely new to this branch, not a pre-existing fact being misdescribed.
- `docs/sot_registry.yaml`'s repointed `line_range` citations (`signOutInProgress`,
  `signOut`/`_performSignOut`, `postSessionRedirect`, the terms-write block inside
  `_ensureLocalUser`) were spot-checked against actual current file content by round 1,
  round 2, and again after the round-2 fix's own +4-line shift (the `alreadyAuthenticatedConfirmMessage`
  constant's doc-comment addition); `scripts/check_sot_registry_parity.dart` reports
  0 errors on the final state.
- `flutter analyze lib/` (whole tree, not scoped, per this repo's own warning that
  scoped analyze can miss `part`-file breakage): round 1 ran it clean (45 pre-existing
  `info`-level issues, none in the touched files). A background analyze run during the
  round-2 fix pass caught a real, new `invalid_use_of_visible_for_testing_member`
  warning (the `alreadyAuthenticatedConfirmMessage` constant, added for round 2's fix,
  was marked `@visibleForTesting` while being legitimately read by production code in
  `confirm_email_screen.dart`) — fixed by removing the annotation, since the constant's
  whole purpose is cross-file production use, unlike `confirmEmailAuthGuardState` and
  `confirmEmailErrorState`, which remain `@visibleForTesting` since only tests call
  them from outside this file.
- Targeted test run after the full fix sequence: `test/auth/confirm_email_screen_test.dart`
  (6 tests) + `test/contracts/confirm_email_error_mapping_test.dart` (6 tests) — 12/12
  passed.

## B-pass (account → required, per CLAUDE.md §4.3)

**`docs/reviews/email-confirm-ux-bpass.md`** — 7 findings, 0 false alarms, all
`status: accepted` and fixed in commit `41163a42`: the `pathPrefix` → `path` exact-match
tightening on the new App Link intent-filter; the bare-bool `_started` guard replaced
with the token-keyed `_startedFor` + `didUpdateWidget` re-entrancy fix; the missing
success → `/restoring` navigation test; the `vercel.json` `.well-known` rewrite; and
three smaller findings on error-state mapping and the loading-state escape hatch. Skill
tuning-history entry present in `.claude/skills/code-review/SKILL.md` dated 2026-09-16,
satisfying the §5.1 self-evolution gate.

## What this record does NOT claim

- The reachability of the Brevo-sent confirmation email past spam filtering — that
  remediation (the spam-folder hint in the confirmation copy) is a copy/UX change
  verified by reading the rendered copy, not something a test can assert against a
  real inbox.
- Whether the Supabase email-template edit (manually applied by the founder in the
  Supabase dashboard, outside this repo) exactly matches what's assumed here — the
  founder verified and corrected this by hand; it is not version-controlled and this
  record does not re-verify it.
- The remaining OI-205 gap (same-vs-different-account distinction, requiring real
  session-capture/restore design) — deliberately not attempted this batch, tracked on
  the OI board with the corrected risk picture, not silently dropped.
- Runtime behavior of the new Android App Link beyond what `flutter test` and the live
  `.well-known` fetch cover — round 1's suggested post-merge smoke check
  (`curl -I https://app.icanbefitter.com/.well-known/assetlinks.json`, expecting real
  JSON not the SPA shell) has not been re-run after this final state; still
  recommended once deployed.
