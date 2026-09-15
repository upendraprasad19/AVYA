---
reviewed_at: 2026-07-23
staged_against: origin/main
blast_radius: account
reviewer: claude-sonnet-via-skill
lens_set: [writer_reader_drift, function_exception_swallow, blast_radius_mismatch, secrets_in_tree, unawaited_no_error_sink]
findings_count: 3
verdict: accepted
---

# Code Review — PKCE password-reset detection fix

## Finding 1 — P2 — writer_reader_drift / test-coverage-gap
- **file:line:** `lib/features/auth/screens/splash_screen.dart:128-141` (reader), `lib/core/utils/password_recovery_detector.dart:48-50` (writer of the PKCE branch)
- **claim:** For the PKCE branch, `PasswordRecoveryResult(isRecovery: true)` returns null tokens (correct — nothing to stash). Confirmed no crash: `_runDeferredInit`'s `setSession` call is guarded by `rt != null && rt.isNotEmpty`, so it correctly no-ops for the PKCE case. Residual gap: no test exercises the actual `/reset` → authenticated-session → `updateUser()` succeeding end-to-end; only the pure classification logic is pinned.
- **verification:** Traced `supabase_flutter-2.12.4/lib/src/supabase_auth.dart` — `Supabase.initialize()` awaits the code exchange before returning, consistent with the diagnose doc's observed evidence (user landed authenticated).
- **suggested-fix:** Not a code change — covered by the plan's existing founder-gated live-link verification step (request a real reset email, click it, confirm `/reset` loads and `updateUser()` succeeds). No test can safely exercise this without live Supabase state.
- **status:** accepted (covered by planned manual verification, not a code fix)

## Finding 2 — P3 — blast_radius_mismatch (external dependency, tier 11 coverage)
- **file:line:** `docs/diagnoses/2026-07-23-password-reset-pkce-code-not-detected-b7d4e2.md` `touched_layers_checked`
- **claim:** The fix's correctness depends on the Supabase Auth dashboard's Redirect-URL allowlist including `https://app.icanbefitter.com/reset` (this repo already hit the sibling bug once — diagnose `e9f2a4`, dashboard Site URL overriding `redirectTo`). `touched_layers_checked` didn't cite Tier 11 (external services) despite the fix's correctness hinging on that dashboard config.
- **verification:** The diagnose doc's own worked example (the observed URL landing at `/reset?code=...`) is evidence the allowlist is already correct today, but this wasn't cited as the tier-11 entry.
- **suggested-fix:** Add a Tier 11 entry to the diagnose doc citing the observed URL as verification evidence.
- **status:** fixed — added below.

## Finding 3 — No finding — hash-routing / hard-coded shapes (checked, ruled out)
Verified the app's `HashUrlStrategy` + Vercel catch-all rewrite doesn't interfere: `Uri.base` still reflects the real browser path+query regardless of the SPA rewrite, and `PasswordRecoveryDetector.detect` runs in `main()` before GoRouter initializes — entirely independent of hash routing. No bug.

## Founder triage notes
(none — both findings are non-blocking; Finding 2 fixed inline, Finding 1 already covered by the plan's manual verification step)
