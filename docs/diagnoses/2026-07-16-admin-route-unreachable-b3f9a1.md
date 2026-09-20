---
bug_id: b3f9a1
date: 2026-07-16
batch: admin-route-fix
status: fixed
blast_radius: account
symptom: |
  Opening app.icanbefitter.com/admin on the web lands on the normal Home
  screen, not the founder admin dashboard (URL bar became /admin/#/home).
  The dashboard code, server gate, and Edge Functions are all live and correct
  — the route was simply not reachable at that URL.
concept: admin_route_reachability
sot_registry_entry: admin_dashboard_metrics_snapshot
writers:
  - { file: lib/core/router/app_router.dart, method: _authRedirect session-open gate threads next=%2Fadmin, line: 629 }
  - { file: lib/features/auth/screens/restoring_screen.dart, method: resolveRestoreDestination allowlist, line: 56 }
readers:
  - { file: lib/features/auth/screens/restoring_screen.dart, method: _goHome + _onContinueAnyway honor resolveRestoreDestination, line: 220 }
hive_key_prefix: n/a
hive_key_formula: n/a
sync_methods: n/a
restore_methods: n/a
cloud_table: n/a
cloud_columns: n/a
contract_test_path: test/contracts/restoring_next_destination_test.dart
ist_handling: n/a
provider_invalidations: n/a
telemetry_op_types: restoring_continue_openforuser_failed (pre-existing; unchanged)
cross_account_guard: |
  Preserved. The /restoring session-open gate + the blocking openForUser
  ownership guard are untouched — only the terminal navigation DESTINATION is
  now an allowlisted value ({'/admin'} else /home). No change to who owns the
  Hive boxes or when they open.
forbidden_patterns_checked: |
  Open-redirect: the /restoring `next` query param is validated against a tiny
  allowlist ({'/admin'}) in resolveRestoreDestination; any other in-app route
  or external/absolute URL (https://, //host) falls back to /home. Pinned by
  the regression test.
proposed_fix: |
  Two parts. (1) Hosting: a Vercel redirect /admin -> /#/admin (vercel.json)
  so the founder's clean URL reaches the hash-routed /admin GoRoute, keeping
  the app's HashUrlStrategy untouched (no auth/OAuth/PWA risk). (2) Router: the
  _authRedirect session-open gate carries an allowlisted `next` when /admin is
  cold-loaded, and RestoringScreen honors it at its three terminal go-sites, so
  a fresh-tab bookmark returns to the dashboard instead of the default /home.
regression_test_planned: test/contracts/restoring_next_destination_test.dart
touched_layers_checked:
  - { layer: client_code_router_auth, status: fixed_in_this_batch, evidence: "app_router.dart _authRedirect + /restoring pageBuilder; restoring_screen.dart next field + resolveRestoreDestination + 3 go-sites; flutter analyze clean; restoring_next_destination_test green (watched RED first)" }
  - { layer: hosting_config, status: fixed_in_this_batch, evidence: "vercel.json redirects /admin + /admin/ -> /#/admin; valid JSON; to be confirmed on the Vercel preview via curl -I (expect Location: /#/admin, 307)" }
  - { layer: client_server_contract, status: verified, evidence: "cold-load traced: /admin -> Vercel 307 -> /#/admin -> Flutter route /admin -> session-gate /restoring?next=%2Fadmin -> resolveRestoreDestination -> /admin renders" }
impact_analysis: |
  Root cause is a plan gap in the admin-dashboard batch (5ea6a5fa): it assumed
  path-based web routing, but the app uses Flutter's default HashUrlStrategy
  (no setUrlStrategy anywhere), so the /admin PATH never reached the route —
  only the #/admin fragment does. Compounded by the deliberately-deferred
  B-pass Finding 4 (cold-tab /admin bounces through /restoring to /home). NOT a
  recurrence of a prior diagnose. No data path, payment, subscription, or
  auth-token change; the only auth-adjacent touch is the restoring destination,
  guarded by an allowlist. Account-tier (router + auth/restoring).
---

# Admin route unreachable on the web — hash routing + cold-load bounce (b3f9a1)

## What the founder saw
Navigated to `app.icanbefitter.com/admin`; the app loaded the normal **Daily/Home**
tab (URL became `…/admin/#/home`), not the admin dashboard.

## Root cause (two layers, both verified in code)
1. **Hash routing.** `lib/main*.dart` / `lib/app.dart` never call `setUrlStrategy` /
   `usePathUrlStrategy`, and the web build passes no `--base-href` — so Flutter's
   **default `HashUrlStrategy`** is in force. The `/admin` `GoRoute`
   (`app_router.dart`) is reachable only via the fragment `#/admin`. The bare
   `/admin` PATH is served `index.html` by Vercel's catch-all rewrite; Flutter boots
   with an empty hash and lands on `initialLocation: '/splash'` → Home. The path
   never matches the route.
2. **Cold-load bounce.** Even `#/admin` on a fresh tab hits the session-open gate:
   `_authRedirect` returns `/restoring` (owner null on cold load), and
   `RestoringScreen` always sent an onboarded user to `/home`, discarding the
   `/admin` target. Documented as B-pass Finding 4 (`admin/CLAUDE.md`).

## Fix
- **Vercel redirect** `/admin` (+ `/admin/`) → `/#/admin` (`vercel.json`) — clean URL,
  hash routing untouched.
- **Allowlisted `next` threading** — `_authRedirect` returns `/restoring?next=%2Fadmin`
  for a cold `/admin`; `RestoringScreen.resolveRestoreDestination` (allowlist `{'/admin'}`,
  default `/home`) is honored at the three terminal `context.go` sites.

## Verification
- `flutter analyze` clean; `test/contracts/restoring_next_destination_test.dart` green
  (watched RED first — `resolveRestoreDestination` undefined).
- Local web: cold-load `/#/admin` → dashboard (not `/home`).
- Vercel preview: `curl -I /admin` → `Location: /#/admin` (307); browser cold-load
  `/admin` → dashboard. Fallback if the fragment is dropped: a 3-line `web/index.html`
  guard (`location.pathname==='/admin' && !location.hash → replace('/#/admin')`).
