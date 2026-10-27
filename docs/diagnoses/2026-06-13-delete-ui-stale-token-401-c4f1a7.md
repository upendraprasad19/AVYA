---
bug_id: c4f1a7
date: 2026-06-13
batch: e2e-obs-fixes
status: fixed
blast_radius: catastrophic
recurrence: true
related_bugs: [d3a1c7, e8a1c3]
symptom: >
  Live web E2E (Obs#9): on the DPDP "Type to confirm" erasure screen, tapping
  the enabled "IRREVERSIBLE — DELETE MY ACCOUNT" button surfaced
  "Couldn't delete account. Try again or contact support." and the account was
  NOT deleted. Root cause: delete_account_screen.invokeDeleteFunction called
  `client.functions.invoke('delete-account', ...)` RAW — no token refresh.
  supabase_flutter attaches the current session's access token as the Bearer; on
  a backgrounded / aged web session (supabase-js auto-refresh throttled while the
  tab is hidden) that token is STALE → delete-account (verify_jwt=true) 401s →
  FunctionException → the catch fell through to the opaque "generic" error. The
  button was wired correctly (the earlier "dead button" read was a CanvasKit
  automation hit-test artifact); the EF CALL failed. A whole-codebase sweep found
  the SAME freshness gap at 3 more authed callers: assess-body-composition
  (user_repository), redeem-referral (referral_repository), and the two video
  endpoints (video_render_provider) — the d3a1c7 §2.31 sweep missed all four.
concept: edge_function_caller_token_freshness
sot_registry_entry: not_applicable
contract_test_path: test/contracts/delete_account_fresh_token_test.dart
writers: >
  lib/features/profile/screens/delete_account_screen.dart (invokeDeleteFunction →
  SupabaseService.callFunction, which ensureFreshToken()s + cold-start-retries);
  lib/shared/repositories/user_repository.dart (assessBodyComposition → callFunction);
  lib/features/profile/repositories/referral_repository.dart (redeem → callFunction);
  lib/features/train/providers/video_render_provider.dart (ensureFreshToken before
  the video-render-trigger + video-status raw invokes — GET/queryParameters).
readers: >
  The authed Edge Functions delete-account / assess-body-composition /
  redeem-referral / video-render-trigger / video-status, each of which validates
  the Bearer via getUser(token) and 401s a stale token.
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: account_deletion_log
cloud_columns: "not_applicable (client-side token-freshness fix; no schema change)"
ist_handling: not_applicable
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: false
forbidden_patterns_checked:
  - "RAW client.functions.invoke('<authed-fn>') without a preceding ensureFreshToken — REMOVED at all 4 client callers; replaced with SupabaseService.callFunction (refresh + retry) or an explicit ensureFreshToken() before the invoke. Mechanically enforced by scripts/check_authed_invoke_fresh_token.dart (gate, empty baseline)."
proposed_fix: >
  Route every authed Edge Function call through SupabaseService.callFunction (the
  canonical wrapper — refreshes the JWT via ensureFreshToken + cold-start retry)
  OR `await SupabaseService.instance.ensureFreshToken()` immediately before a raw
  invoke that needs GET/queryParameters. For delete-account specifically, also
  decode a FunctionException status==401 to a distinct "session expired — sign
  out and back in" message instead of the opaque generic error. The new gate
  check_authed_invoke_fresh_token.dart (shipped one commit earlier, §4.11) makes
  any future raw-invoke regression hard-fail at pre-commit.
regression_test_planned: >
  test/contracts/delete_account_fresh_token_test.dart — source-grep (comment-
  stripped): delete_account_screen routes delete-account through callFunction
  (NOT raw functions.invoke) and decodes the 401 to 'session_expired'; the three
  swept callers use callFunction / ensureFreshToken; the gate baseline is empty.
touched_layers_checked:
  - { tier: 1, layer: client_code, status: fixed_in_this_batch, evidence: "4 callers route through callFunction / ensureFreshToken; flutter analyze clean; check_authed_invoke_fresh_token PASS (0 baselined); delete_account_fresh_token_test green" }
  - { tier: 6, layer: edge_function_code_vs_deploy, status: verified, evidence: "the 5 target EFs already validate getUser(token) correctly (delete-account v6, the rest verified by check_edge_function_auth_pattern PASS) — the bug is purely the CLIENT sending a stale token; no EF redeploy needed" }
  - { tier: 12, layer: client_server_contract, status: fixed_in_this_batch, evidence: "client now sends a freshly-refreshed user token to every authed EF; the delete flow's live-proof is the v6 EF erasure that already succeeded with a fresh minted token during the E2E" }
impact_analysis: >
  Catastrophic/DPDP: a user on an aged web session (or any client whose token had
  expired) literally could not delete their account via the UI — the §17 erasure
  button returned a generic failure on every tap. The same stale-token class also
  silently broke body-composition assessment, referral redemption, and video
  render for backgrounded-web users. This is a RECURRENCE of §2.31 (diagnose
  d3a1c7, 2026-06-09), whose own rule said "grep ALL functions.invoke callsites"
  yet missed these four — codifying the class in prose + one source-grep test did
  not prevent recurrence, so this batch lands the mechanical gate
  (check_authed_invoke_fresh_token.dart) as the durable backstop. Sibling to e8a1c3
  (the server-side half of the same delete-account failure: the EF auth had also
  been broken, fixed + deployed v6 earlier this batch).
---

# Delete-account UI fails on a stale web token → "Couldn't delete account" (c4f1a7)

## What happened
On the DPDP erasure screen the confirm button fired `_onConfirmDelete`, which
called `invokeDeleteFunction` → a RAW `client.functions.invoke('delete-account')`.
On a backgrounded/aged web tab supabase-js had not refreshed the session, so the
attached Bearer was stale → the EF 401'd → FunctionException → the generic
"Couldn't delete account" snackbar (matches the founder's screenshot). The button
itself was correctly wired; the *call* failed.

## Why the sweep mattered
Grepping every `functions.invoke(` in `lib/` (the §2.31 rule) found the identical
gap at `assess-body-composition`, `redeem-referral`, and the two video endpoints —
the d3a1c7 sweep had missed all four. Fixed in the same commit; the new gate
`check_authed_invoke_fresh_token.dart` now fails any future raw invoke that skips
the refresh.

## Fix
- delete-account / assess-body-composition / redeem-referral → `SupabaseService.callFunction` (refresh + cold-start retry).
- video-render-trigger / video-status → `await ensureFreshToken()` before the raw invoke (kept raw for GET/queryParameters).
- delete screen: FunctionException status==401 → "session expired" message (distinct from generic).

## See also
- docs/diagnoses/...-d3a1c7... (§2.31 founding incident; the sweep this recurs from)
- docs/diagnoses/2026-06-12-...-e8a1c3.md (the server-side half of the delete-account failure)
- scripts/check_authed_invoke_fresh_token.dart (the gate that prevents the next recurrence)
