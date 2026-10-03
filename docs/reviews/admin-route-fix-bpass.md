---
reviewed_at: 2026-07-16T21:00:00+05:30
branch: admin-route-fix
staged_against: b6076aadac90 (working-tree vs main)
blast_radius: account
reviewer: claude-sonnet-via-skill (fresh context-blind agent a480cf5bb4e2)
lens_set: [open_redirect, writer_reader_drift, routing_reentrancy, collateral_change, vercel_config, test_quality]
findings_count: 0
verdict: accepted
---

# Code Review (B-pass) — admin-route-fix

Fresh, context-blind Sonnet reviewer over the full diff (vercel.json redirect +
the `next`-threading router/restoring change + regression test + docs).
**Zero findings.** The reviewer went beyond source-reading — it traced
go_router 17.2.3 source, the Dart SDK `Uri` decode, and the Flutter
`material → widgets → framework` export chain, and re-ran `flutter analyze` +
the contract test (8/8) to confirm.

## Clean lenses (each with the specific check run)

- **open_redirect** — `resolveRestoreDestination` is an exact-match
  `{'/admin'}.contains(next) ? next! : '/home'`. Traced null / '' / `https://…`
  / `//host` / `/admin/` / `/Admin` / `/admin?x=1` → all return `/home`.
  `Set.contains(null)` is false (no null-assert crash). No open-redirect path.
- **writer_reader_drift** — writer `restoringRedirectFor('/admin')` emits
  `/restoring?next=%2Fadmin`; reader `Uri…queryParameters['next']` decodes
  `%2F`→`/`→`/admin`, which the allowlist honors. Round-trip pinned by the test.
  go_router's `state.uri` genuinely carries the query. No drift.
- **routing_reentrancy** — `matchedLocation` is path-only (go_router
  `matchList.uri.path`), so `isOnRestoring` passthrough still fires for
  `/restoring?next=…`. `openForUser` is awaited before all three `context.go`
  sites → owner non-null on re-eval → no `/restoring` bounce-back loop.
  StartMissionBrief / mid-onboarding branches ignore `next` (a not-onboarded
  user can never land on `/admin`).
- **collateral_change** — bare `/restoring` (byte-identical) for every
  non-`/admin` route; splash + sign-in call `/restoring` with no query → `next`
  null → old `/home` default preserved; the pageBuilder is the only
  `RestoringScreen(` call site (dropping `const` strands nothing).
  `@visibleForTesting` is in scope via `material.dart` re-export chain
  (analyze clean).
- **vercel_config** — valid JSON; `redirects` precede `rewrites` (Vercel
  precedence) so `/admin` 307s rather than falling to the SPA rewrite; exact
  literal source (no `/admin/*` over-match); `permanent:false` appropriate.
  Fragment-preservation flagged as the pending Vercel-preview check (not a code
  defect) — already in the plan's verification.
- **test_quality** — no secrets; behavioral test would fail on realistic
  regressions (allowlist removal, encoding/allowlist drift); diagnose root-cause
  matches code (grep confirmed zero `setUrlStrategy` in lib/).

## Triage
0 findings. Verdict: accepted. The one non-static item (Vercel fragment
preservation) is verified on the Vercel preview before merge, per the plan.
