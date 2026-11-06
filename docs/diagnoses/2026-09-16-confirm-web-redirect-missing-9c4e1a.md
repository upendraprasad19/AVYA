---
bug_id: 9c4e1a
date: 2026-09-16
batch: obs-batch-2026-09-16
status: fixed
blast_radius: account
symptom: >-
  A founder's friend attempted a real signup. He tapped the "Confirm signup"
  link from his email on a phone with the app NOT installed. His browser
  opened the webapp, and after a moment he was dropped back on the sign-up/
  sign-in screen showing the "check your email... then sign in" message
  again — the account was never actually confirmed, and there was no way to
  complete signup from that device.
concept: web_confirm_link_routing
recurrence: >-
  NOT a recurrence of either open issue this could plausibly be confused
  with, checked directly against docs/audit/OPEN_INDEX.md before proposing
  any fix: OI-205 (the "/confirm" interim guard) only fires for an
  ALREADY-AUTHENTICATED user opening the link — this user was never
  authenticated, he was signing up fresh. OI-208 (a `_teardown()` timeout
  leaving device-identity bound) is about SIGN-OUT, unrelated to signup.
  This is a genuinely new bug in the email-confirm-ux batch that shipped
  earlier the same day (2026-09-16) — the batch added a bare-path `/confirm`
  GoRoute for Android App Links but never gave it the web-routing treatment
  its own `/admin` precedent already established.
related_bugs: b3f9a1
sot_registry_entry: not_applicable — static Vercel web-routing config, not a Hive/Postgres writer/reader concept. The closest precedent (/admin's identical redirect, diagnose b3f9a1) also carries no SoT registry entry.
writers:
  - { file: vercel.json, method: "redirects[] entry for /confirm", line: 10 }
  - { file: vercel.json, method: "redirects[] entry for /confirm/ (trailing slash)", line: 11 }
readers:
  - { file: lib/core/router/app_router.dart, method: "GoRoute('/confirm') reading state.uri.queryParameters['token_hash']", line: 147 }
  - { file: lib/features/auth/screens/confirm_email_screen.dart, method: "ConfirmEmailScreen(tokenHash:) -> _maybeStartVerification", line: 48 }
hive_key_prefix: n/a — no Hive key participates; this is web-routing config
hive_key_formula: n/a
sync_methods: []
restore_methods: []
cloud_table: none
cloud_columns: []
contract_test_path: test/contracts/confirm_web_redirect_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - { pattern: "a GoRoute with a bare (non-/#/) path segment added to app_router.dart with no matching entry in vercel.json's redirects[]", absent_after_fix: true }
proposed_fix: >-
  Add `{ "source": "/confirm", "destination": "/#/confirm", "permanent": false }`
  and the trailing-slash variant to `vercel.json`'s `redirects` array,
  mirroring the existing `/admin` entries byte-for-byte in shape. This lets
  Vercel redirect the bare `/confirm?token_hash=X` request to
  `/#/confirm?token_hash=X` BEFORE the SPA catch-all `rewrites` rule would
  otherwise serve `index.html` with the bare path still in the URL bar
  (Vercel's redirect matching runs before rewrites, and the query string is
  passed through to the destination automatically — same mechanism the
  catch-all rewrite already relies on, confirmed live: the pre-fix symptom
  itself was Vercel serving index.html with token_hash still intact in the
  URL, i.e. query-string passthrough already works, only the hash-fragment
  translation was missing). Once the fragment is `/#/confirm?token_hash=X`,
  GoRouter's HashUrlStrategy reads it exactly like any in-app navigation,
  and `state.uri.queryParameters['token_hash']` resolves as
  `confirm_email_screen.dart` already expects. Also corrected the false
  claim in `lib/features/auth/CLAUDE.md` asserting no separate web-fallback
  implementation was needed, and added a pitfall-table row for the general
  class (any new bare-path GoRoute needs its own vercel.json redirect in the
  same commit).
regression_test_planned:
  - test/contracts/confirm_web_redirect_test.dart
touched_layers_checked:
  - { tier: 1_client_code, status: verified, evidence: "grepped lib/ for setUrlStrategy — zero hits, confirming HashUrlStrategy is genuinely the default in use (not an assumption carried over from the /admin diagnose). app_router.dart:142-148 GoRoute and confirm_email_screen.dart's tokenHash consumption both read verbatim, unchanged by this fix — only the routing CONFIG changed, not the client code path." }
  - { tier: 2_hive, status: not_applicable, evidence: "no Hive key participates" }
  - { tier: 3_postgres_schema, status: not_applicable, evidence: "no schema involvement" }
  - { tier: 4_postgres_data, status: not_applicable, evidence: "no table read or written" }
  - { tier: 5_migrations_applied, status: not_applicable, evidence: "no migration" }
  - { tier: 6_edge_function_code_vs_deploy, status: not_applicable, evidence: "no Edge Function involvement — Supabase's confirm link points at our own domain, not an EF" }
  - { tier: 7_cron_jobs, status: not_applicable, evidence: "no cron involvement" }
  - { tier: 8_rls_policies, status: not_applicable, evidence: "no RLS path — verifyOTP is a GoTrue call, not a table read gated by RLS" }
  - { tier: 9_storage, status: not_applicable, evidence: "no storage objects" }
  - { tier: 10_secrets, status: not_applicable, evidence: "no secret read or written" }
  - { tier: 11_external_services, status: fixed_in_this_batch, evidence: "fixed_in_this_batch, not verified: vercel.json is deployed by Vercel on push/merge to main, and this repo's `flutter test` has no way to issue a real HTTPS GET against app.icanbefitter.com/confirm. OWED: after this batch deploys, verify live with `curl -sI https://app.icanbefitter.com/confirm?token_hash=x` and confirm a 307/308 to /#/confirm (or open it in a real mobile browser with no app installed) before treating this as closed end-to-end. test/contracts/confirm_web_redirect_test.dart proves the config's presence and shape only." }
  - { tier: 12_client_server_contract, status: verified, evidence: "the contract between the redirect destination and the GoRoute's query-param read was traced by hand: vercel.json's destination /#/confirm has no trailing ?, so Vercel appends the original request's query string verbatim, producing /#/confirm?token_hash=X; GoRouter's hash strategy parses everything after # including its own ?query exactly like an in-app link, landing on state.uri.queryParameters['token_hash'] unchanged." }
impact_analysis: >-
  Account-tier by the corrected blast_radius.yaml entry this batch also adds
  (vercel.json previously fell through to the default `feature` tier, which
  did not reflect that it gates whether ANY user without the app installed
  can complete a bare-path web flow at all). Purely additive JSON change —
  the existing /admin redirect and the .well-known/ rewrite exclusion are
  both re-asserted unchanged by the new test, so this cannot regress either.
  No migration, no Edge Function redeploy, no client rebuild required — it
  takes effect on the next Vercel deploy of this branch once merged. Real-
  world impact until fixed: total signup-completion blocker for every user
  who does not already have the app installed, i.e. effectively every
  external user today (pre-Play-Store — go-live-blockers memory already
  notes Play Billing is 0 code and the app isn't listed yet), since Android
  App Links' autoVerify has nothing to intercept without the app present.
---

# `/confirm` links dead-end on the web for anyone without the app installed

## What was actually wrong

Today's email-confirm-ux batch pointed Supabase's "Confirm signup" email
template at `app.icanbefitter.com/confirm?token_hash=...` and registered a
matching bare-path `GoRoute('/confirm')` in `app_router.dart` — but this app
has no `setUrlStrategy` call anywhere, so Flutter web defaults to
**HashUrlStrategy**. GoRouter only ever resolves the `/#/<path>` fragment
form; a bare path is invisible to it. The exact same constraint already
governs `/admin` (`lib/features/admin/CLAUDE.md:114`, diagnose `b3f9a1`),
which is why `vercel.json` redirects `/admin` → `/#/admin` before Vercel's
SPA catch-all `rewrites` rule would otherwise serve `index.html` for the
bare path. `/confirm` never got the equivalent entry.

So a real signup, from a phone with the app not installed, played out like
this:

1. Browser requests `https://app.icanbefitter.com/confirm?token_hash=X`.
2. No matching `redirects` entry → Vercel's catch-all `rewrites` rule serves
   `index.html`, URL bar unchanged (`/confirm?token_hash=X` — confirmed
   directly, this is exactly what the pre-fix symptom looked like).
3. Flutter web boots. HashUrlStrategy reads `location.hash`, which is empty.
4. GoRouter falls back to its `initialLocation` (`/splash`).
5. `token_hash` sits in `location.search`, which the hash strategy never
   reads — `ConfirmEmailScreen` never mounts, `AuthNotifier.confirmEmail`
   never runs, `verifyOTP` never fires. The email is never actually
   confirmed.
6. Unauthenticated and unconfirmed, the user lands back on sign-in/sign-up,
   which correctly (if confusingly, with no other explanation on screen)
   re-shows "check your email... then sign in."

This also directly contradicted a claim written into the SAME batch's own
`lib/features/auth/CLAUDE.md`: *"anyone without the app lands on the same
route as a normal web page (one Flutter codebase, so 'web fallback' needs
no separate implementation)."* False — "one Flutter codebase" says nothing
about whether Vercel's routing config in front of it reaches that codebase
at all for a given bare path. `/admin` needed a redirect; `/confirm` needed
the identical one and never got it.

## Why this wasn't a false positive — checked against the two open issues it could be confused with

- **OI-205** (`/confirm`'s already-authenticated guard) only applies when a
  session already exists. The friend was never authenticated — he was
  attempting first signup. Does not match.
- **OI-208** (`_teardown()` timeout leaving device identity bound) is a
  sign-OUT gap. Unrelated to a fresh signup that never reaches
  `verifyOTP` in the first place. Does not match.

This is a new bug in code the same batch shipped hours earlier, not a
recurrence of either tracked gap.

## The fix

```json
"redirects": [
  { "source": "/admin", "destination": "/#/admin", "permanent": false },
  { "source": "/admin/", "destination": "/#/admin", "permanent": false },
  { "source": "/confirm", "destination": "/#/confirm", "permanent": false },
  { "source": "/confirm/", "destination": "/#/confirm", "permanent": false }
]
```

Byte-for-byte the same shape as the existing `/admin` entries. Vercel
appends the original request's query string to a destination with no `?` of
its own, so `/confirm?token_hash=X` → `/#/confirm?token_hash=X` — a fragment
GoRouter parses exactly like any in-app link, `token_hash` included.

Also corrected `lib/features/auth/CLAUDE.md`'s false "no separate
implementation" claim, and added a pitfall-table row generalizing the class:
**any new bare-path `GoRoute` needs its own `vercel.json` redirect added in
the same commit** — registering the route in `app_router.dart` proves
nothing about whether the web build can ever reach it.

## Regression test

`test/contracts/confirm_web_redirect_test.dart` parses `vercel.json` as real
JSON (not string-`contains`) and asserts: the `/confirm` and `/confirm/`
redirects exist and point at `/#/confirm`; the pre-existing `/admin`
redirect and the `.well-known/` rewrite exclusion both survive unchanged;
and `app_router.dart`'s `/confirm` route still reads `token_hash` off the
query string. **Mutation evidence (this IS the pre-fix state, not a
synthetic mutation):** run against `vercel.json` before this fix, exactly 2
of 5 assertions redden (the two `/confirm`-redirect checks) while the other
3 (the `/admin` survival check, the `.well-known/` exclusion check, and the
`app_router.dart` token_hash check) stay green — confirming the test
isolates precisely the missing entries and nothing else.

This is a static-config fix with no way to exercise real Vercel redirect
behavior from `flutter test` — the test pins presence and shape only. Live
verification is owed after deploy (tier 11 in `touched_layers_checked`
above): `curl -sI https://app.icanbefitter.com/confirm?token_hash=x` should
307/308 to a `Location` ending in `/#/confirm?token_hash=x`, or the same
link opened on a real device with no app installed should reach the
"Confirming your account..." screen instead of dead-ending.

## Blast-radius registry gap also closed

`vercel.json` had no explicit entry in `docs/blast_radius.yaml` and fell
through to `default_tier: feature` — despite gating whether ANY bare-path
web route (including the already-critical `/admin`) is reachable at all.
Added `{ glob: "vercel.json", tier: account }` so a future change to this
file gets the `behavioral_test_path` + `code_review_b_pass` discipline the
`account` tier requires, rather than silently under-classifying again.
