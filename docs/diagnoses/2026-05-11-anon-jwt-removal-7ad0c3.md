---
bug_id: 7ad0c3
date: 2026-05-11
batch: audit-2026-05-11
status: partial
symptom: .claude/settings.local.json was tracked in git AND contained the Supabase anon JWT in committed permission entries; the same JWT also appears in git history (lib/core/constants/app_constants.dart commit ef878af, removed in 5c40925) so simple file removal does not retire the leaked credential.
concept: anon_jwt_leak
sot_registry_entry: anon_jwt_leak
writers:
  - { file: .gitignore, method_or_widget: gitignore_settings_local, line: 1 }
readers: []
hive_key_prefix: "n/a"
hive_key_formula: "null"
sync_methods: []
restore_methods: []
cloud_table: "n/a"
cloud_columns: []
contract_test_path: "n/a — JWT rotation is a Supabase Dashboard action (user-action U-2)"
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: n/a
forbidden_patterns_checked: ["anon_jwt_committed_to_settings_local"]
proposed_fix: Two-part fix - (1) git rm --cached .claude/settings.local.json + add to .gitignore prevents future re-commits; (2) USER-ACTION U-2 - rotate Supabase anon JWT in Dashboard - API - Reset anon key, capture into .env, rebuild APK. The leaked JWT remains valid until rotation regardless of file removal.
regression_test_planned: []
---
# Audit C-3: Supabase anon JWT leaked via .claude/settings.local.json + git history

## Bug

Two leakage paths for the project's Supabase anon JWT:

1. **Currently on main:** `.claude/settings.local.json:118-119` (committed in commit `d89f0fe`). Embedded inside `Bash(curl ... apikey: ...)` permission entries.
2. **Git history forever:** commit `ef878af` `lib/core/constants/app_constants.dart` + `supabase_service.dart`. Removed in `5c40925` but lives in history; cannot be scrubbed without rewriting history (BFG / `git filter-repo`).

Decoded JWT: `role=anon, ref=dedsavbjuwgarrhphgnl, iat=1774253852, exp=2089829852` — valid until **2036**.

## Cause

Anon JWTs are public-by-design for Supabase clients, BUT (a) embedding it in a committed agent permission file is a `.gitignore` discipline failure that risks future commits of a `sbp_*` service-role token by the same pattern; (b) combined with audit C-1's open RLS on `subscriptions` (now closed), the leaked anon JWT could be used to call PostgREST endpoints from anywhere.

## Fix

This commit closes the **file-removal** half:
- `git rm --cached .claude/settings.local.json` — removes from tracking, leaves on disk
- Append to `.gitignore` — prevents future re-commits

## Follow-up — user-action U-2 (still required)

The anon JWT itself remains valid until rotated. Removing the file from main does not retire the credential. User must:

1. Supabase Dashboard → API → Reset anon key
2. Capture new JWT into `.env`
3. Rebuild APK with new key (`--dart-define-from-file=.env`)
4. Old anon JWT becomes inert

Combined with audit C-1 / 7ad0c1 (subscriptions RLS lockdown, now applied), the rotated JWT closes the exploit chain.

This diagnose is marked `status: partial` because the file-removal half is complete but the rotation half awaits user action.

## Related

- 7ad0c1 (subscriptions RLS lockdown — primary mitigation for what the leaked JWT would have enabled)
- CLAUDE.md §2a (Supabase Project — Confirmed Identity)
