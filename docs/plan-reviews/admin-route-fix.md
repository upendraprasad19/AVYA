---
branch: admin-route-fix
blast_radius: account
review_rounds: 2
ground_truth_verified: true
verdict: converged
bpass: accepted
bpass_review: docs/reviews/admin-route-fix-bpass.md
recorded_at: 2026-07-16T21:05:00+05:30
---

# Plan-review record — admin-route-fix

Keystone record for CLAUDE.md §4.12 (account-tier merge to main). Fixes the
founder-only `/admin` dashboard being unreachable on the web (hash routing +
cold-load `/restoring` bounce). Diagnose `b3f9a1`.

## Review rounds (2 independent, context-blind, ground-truth-verified)

1. **Root-cause investigation (2 parallel context-blind Explore agents).** One
   verified the web URL strategy against code (no `setUrlStrategy` anywhere →
   Flutter default HashUrlStrategy, base href `/`) → the `/admin` path can't
   reach the route, only `#/admin`. The other traced `_authRedirect` +
   `RestoringScreen` and confirmed the cold-load bounce (`/restoring` always
   lands `/home`) with exact file:line, matching the documented B-pass Finding 4.
   The plan (Vercel redirect + allowlisted `next`-threading) was written on
   those verified findings; the founder chose the redirect approach.
2. **B-pass (`/code-review`, fresh context-blind Sonnet)** over the full
   implementation diff — 6 lenses (open-redirect, writer/reader drift,
   routing re-entrancy, collateral change, vercel config, test quality).
   **0 findings.** Record: `docs/reviews/admin-route-fix-bpass.md`
   (verdict: accepted). Account-tier → no Hermes required.

## Ground-truth verification

- Web URL strategy confirmed against source (grep: zero `setUrlStrategy` /
  `usePathUrlStrategy` in `lib/`; base href unset → `/`).
- The `%2Fadmin` writer→reader round-trip verified by executing
  `Uri.parse('/restoring?next=%2Fadmin').queryParameters['next']` in the
  passing contract test (decodes to `/admin`).
- `flutter analyze` clean; `restoring_next_destination_test.dart` 8/8 green
  (watched RED first — `resolveRestoreDestination` undefined).
- The one item not statically verifiable — Vercel preserving the `#/admin`
  fragment in the redirect `Location` — is verified on the Vercel preview
  (curl `-I /admin` → `Location: /#/admin`) BEFORE the merge to main; a
  documented `web/index.html` client-side fallback exists if it doesn't.

## Convergence

Small, tightly-scoped account-tier fix. B-pass found nothing; no re-review
needed. Verdict: converged.
