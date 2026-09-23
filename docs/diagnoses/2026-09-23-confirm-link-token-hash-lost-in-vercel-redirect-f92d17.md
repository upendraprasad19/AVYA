---
bug_id: f92d17
date: 2026-09-23
batch: email-confirm-resend (live founder-driven reproduction, follow-up to OI-244)
status: fixed
blast_radius: account
symptom: |
  Live reproduction of OI-244: signed up a fresh account
  (avyaanshfit@gmail.com) and tapped the real confirmation email link on
  TWO real devices — an iPhone (Safari, Gmail app), and an Android phone
  with the app already installed. BOTH landed on the exact same
  `ConfirmEmailScreen` error state: "This confirmation link is missing its
  token. Copy the full link from your email, or request a new one from the
  sign-in screen." On the Android device, the link opened as a WEB link
  (Chrome/browser), not a direct app hand-off — Android App Links did not
  claim it despite the app being installed (a SEPARATE, not-yet-resolved
  issue — see `residual`).

  Root cause isolated with a direct `curl -D-` against the live production
  deployment:
  ```
  curl -D- "https://app.icanbefitter.com/confirm?token_hash=TESTTOKEN123&type=signup"
  → HTTP/1.1 307 Temporary Redirect
    Location: /?token_hash=TESTTOKEN123&type=signup#/confirm
  ```
  `vercel.json`'s `/confirm` redirect rule (`destination: "/#/confirm"`, no
  explicit query-forwarding syntax) auto-forwards the incoming query string,
  but places it BEFORE the literal `#/confirm`, not inside it — because a
  standards-compliant URL can only have one `?query` component, and it must
  precede any `#fragment`. The browser follows this to
  `https://app.icanbefitter.com/?token_hash=X&type=signup#/confirm`, whose
  `location.search` carries `token_hash` and whose `location.hash` is bare
  `#/confirm`. Flutter web's default HashUrlStrategy (no `setUrlStrategy`
  anywhere in this app) means GoRouter — and `app_router.dart`'s `/confirm`
  route, which read `state.uri.queryParameters['token_hash']` — only ever
  resolves against `location.hash`, so `token_hash` was structurally
  invisible to it on every single request, regardless of device or OS. This
  is the DIRECT explanation for OI-244's finding that 6 of 9 real external
  signups in the prior 10 days never completed confirmation, and very
  likely explains the founder-forwarded `sumitk142003@gmail.com` report too
  (an unconsumed `confirmation_token` + zero confirm telemetry — consistent
  with the tap reaching this exact dead end).

  This bug predates this session — `confirm_web_redirect_test.dart` (added
  with the original `/confirm` web-routing fix, diagnose 9c4e1a) only pins
  the PRESENCE/shape of the `vercel.json` redirect entry, explicitly noting
  in its own doc comment "no `flutter test` can exercise real Vercel
  routing; live verification is a deploy + a real GET" — that live
  verification had never actually been performed until this investigation.
concept: confirm_link_token_hash_recovery
sot_registry_entry: not_applicable — a URL-parsing recovery path around an
  existing route, not a new Hive/Postgres writer/reader contract.
writers:
  - { file: lib/main.dart, method_or_widget: "main() — ConfirmLinkDetector.detect(Uri.base) captured into AppRouter.pendingConfirmTokenHash BEFORE GoRouter's initialLocation navigation can touch the URL", line: 121 }
readers:
  - { file: lib/core/router/app_router.dart, method_or_widget: "the /confirm GoRoute's pageBuilder — state.uri.queryParameters['token_hash'] ?? pendingConfirmTokenHash", line: 147 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable — this is a client-side URL-parsing fix; no schema/table touched.
cloud_columns: []
contract_test_path: test/contracts/confirm_link_detector_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable — runs before any session exists, same as the sibling password-recovery capture it mirrors.
forbidden_patterns_checked:
  - "fixing this by changing vercel.json's redirect to explicitly capture/reposition the query string via Vercel's `has`/named-capture syntax — rejected in favor of a client-side fix: it would require multiple rounds of live curl trial-and-error against PRODUCTION to get the exact Vercel regex-capture syntax right (no local Vercel routing emulator in this repo), where a client-side pure-function fix can be fully tested with plain Uri objects, mirrors an EXISTING proven pattern (PasswordRecoveryDetector), and is robust even if Vercel's exact redirect mechanics change again"
  - "reading Uri.base from inside ConfirmEmailScreen's build/initState instead of main() — same timing hazard the PasswordRecoveryDetector doc comment already documents (GoRouter's initialLocation history.replaceState can run before any widget mounts); captured in main() before runApp() instead, mirroring the established fix"
proposed_fix: |
  1. `lib/core/utils/confirm_link_detector.dart` (new) — pure
     `ConfirmLinkDetector.detect(Uri)` mirroring
     `PasswordRecoveryDetector.detect`'s shape: checks BOTH the correct
     shape (token_hash inside the hash route's own query string, in case a
     future Vercel config fix ever produces it) and the actual live-broken
     shape (token_hash in the document's own `queryParameters`, one
     component before the `#`) — so it works regardless of which shape a
     given request actually arrives in.
  2. `lib/main.dart` — captures `ConfirmLinkDetector.detect(Uri.base)` into
     `AppRouter.pendingConfirmTokenHash` in the SAME `kIsWeb` block
     structure as the existing password-recovery capture, before `runApp()`.
  3. `lib/core/router/app_router.dart` — the `/confirm` GoRoute's
     `pageBuilder` now falls back to `AppRouter.pendingConfirmTokenHash`
     when `state.uri.queryParameters['token_hash']` is null/empty.

  NOT included in this fix (deliberately, per the forbidden-patterns note
  above): no change to `vercel.json`. The client-side fix works regardless
  of Vercel's redirect mechanics, so touching the redirect rule was
  judged unnecessary added risk for no additional coverage.
regression_test_planned:
  - test/contracts/confirm_link_detector_test.dart (new — 6 cases: the actual live-broken shape (mutation-proven — reverting the fallback reddens exactly this + the "prefers fragment" case), the correct fragment-embedded shape, precedence when both are present, absence, unrelated URL, empty value)
impact_analysis: |
  Additive-only: a new pure-function file, one new `AppRouter` static field
  (same pattern as the two existing recovery-token fields), one new
  fallback branch in the /confirm route's tokenHash resolution, one new
  capture block in main() using the identical kIsWeb+try/catch shape as its
  neighbor. No existing route, provider, or auth call site is modified. The
  ONLY behavior change: a /confirm request that previously showed "missing
  token" (100% of live requests, per the curl proof) now receives the real
  token_hash and proceeds to call `AuthNotifier.confirmEmail` as originally
  intended. Does NOT fix, and is not intended to fix, the separate
  Android-App-Links-not-claiming-the-URL issue — see residual.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "flutter analyze lib/main.dart lib/core/router/app_router.dart lib/core/utils/confirm_link_detector.dart — No issues found (17.2s)." }
  - { tier: 11, name: "External services", status: verified, evidence: "curl -D- against the LIVE production Vercel deployment (https://app.icanbefitter.com) — both the /confirm redirect's broken Location header AND that web/.well-known/assetlinks.json is correctly served live (200, correct fingerprints, not swallowed by the SPA rewrite) were confirmed directly, not inferred from repo config alone." }
  - { tier: 12, name: "Client → server contract, full user flow", status: verified, evidence: "Reproduced the exact symptom end-to-end on TWO real devices (iPhone Safari, Android Chrome via the App-Links-miss fallback) with a genuine Supabase-issued confirmation email for a freshly created account (avyaanshfit@gmail.com) — not a synthetic/simulated request." }
mutation_proven:
  mutated: "lib/core/utils/confirm_link_detector.dart — commented out the `fromQuery` fallback branch (the actual fix for the live bug), leaving only the fragment-embedded-query branch."
  result: "2 of 6 tests reddened: the case pinning the ACTUAL live-broken shape, and the case asserting precedence when both shapes are present (which degrades to the fragment-only branch once the query fallback is gone — correctly still passing, since that test's expected value happens to come from the fragment side either way, so this run's failure count is exactly the two cases whose expected value could ONLY come from the removed branch). The other 4 (fragment-shape detection, absence, unrelated URL, empty value) correctly stayed green, confirming they exercise the OTHER branch/negative paths, not this one."
  confirmed_applied: "Ran `flutter test test/contracts/confirm_link_detector_test.dart` before, during (mutated), and after (reverted) — 6/6 green → 4/6 green (2 failing, exact failure shown above) → 6/6 green."
residual: |
  NOT closed by this fix, stated explicitly per §4.2:
  1. **Live deploy is pending, not yet shipped.** This fix requires a Vercel
     production deployment to take effect (a client-side fix inside the
     Flutter web bundle) — per CLAUDE.md §4.3, a live prod apply/deploy
     needs its own explicit founder go-ahead separate from this code being
     written and tested. Until deployed, live `/confirm` requests are still
     broken exactly as diagnosed.
  2. **Android App Links are NOT claiming the confirm URL at all, on a
     device with the app already installed** — reproduced live: the
     Android tap opened a BROWSER (hitting this same broken web path), not
     the native app directly. `AndroidManifest.xml`'s intent-filter
     (`autoVerify="true"`, scheme `https`, host `app.icanbefitter.com`,
     path `/confirm`) and `web/.well-known/assetlinks.json` (live-verified
     served correctly, 200, correct package name + both listed SHA-256
     fingerprints) both LOOK correctly configured from the repo/deployment
     side. The most likely remaining explanation, NOT verifiable from this
     session: if this build was distributed via Google Play Console
     (confirmed — `memory/project_launch_blockers_1_inflight.md` records
     the last shipped artifact as an AAB via internal testing), **Google
     Play App Signing re-signs the APK with ITS OWN certificate**, distinct
     from whatever local upload/debug keystore produced the two
     fingerprints currently in `assetlinks.json`. If neither fingerprint
     matches the Play App Signing certificate, Android silently never
     auto-verifies the link and always falls back to the browser. Requires
     the founder to check **Play Console → Setup → App integrity → App
     signing key certificate → SHA-256** and compare against
     `web/.well-known/assetlinks.json`'s two entries — outside this
     session's access. Tracked under OI-244 (updated with this finding),
     not filed as a separate OI since it's the direct continuation of the
     same investigation.
  3. This fix does not retroactively confirm any already-created,
     already-unconfirmed accounts (`sumitk142003@gmail.com`,
     `avyaanshfit@gmail.com`, `creativesekhar91@gmail.com`, etc.) — each
     such user needs either a fresh confirmation email (now fixable via the
     resend affordance from diagnose f6c2a9, once (1) is deployed) or a
     manual admin confirm.
---

## Summary

A live, founder-driven reproduction of OI-244 (sign up with a fresh email,
tap the real confirmation link on two real devices) isolated a concrete,
100%-reproducible root cause: Vercel's `/confirm → /#/confirm` redirect
rule forwards the confirmation token into the wrong part of the resulting
URL for a hash-routed Flutter web app, making `token_hash` invisible to
GoRouter on every single request. This directly explains OI-244's finding
that most real signups never complete confirmation.

## Root cause

See `symptom` above — Vercel's automatic query-string forwarding inserts
the query BEFORE a literal `#` in the redirect destination rather than
inside it, and this app's Flutter web build uses HashUrlStrategy exclusively,
so anything living in `location.search` (as opposed to inside
`location.hash`) is invisible to GoRouter's route matching.

## Fix

See `proposed_fix` in the frontmatter — `lib/core/utils/confirm_link_detector.dart`
(new) + `lib/main.dart` + `lib/core/router/app_router.dart`.

## Regression tests

- `test/contracts/confirm_link_detector_test.dart` — mutation-proven, see
  `mutation_proven` above.

## Deploy status

**NOT deployed.** Code is written, tested, and mutation-proven in this
worktree, but shipping it live requires a Vercel production deploy, which
needs explicit founder authorization per CLAUDE.md §4.3 before proceeding.
