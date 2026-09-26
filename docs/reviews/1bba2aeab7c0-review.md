---
reviewed_at: 2026-06-11T18:30:00+05:30
staged_against: 1bba2aeab7c0
blast_radius: catastrophic
reviewer: claude-sonnet-via-bpass-subagent
lens_set: [migration_correctness, broken_legit_caller, secdef_guard_logic, search_path_shadowing, secrets_in_tree, test_doc_accuracy]
findings_count: 3
verdict: accepted
---

# Code Review (B-pass) — security migration 090/091 (c9b3e2)

Fresh context-blind Sonnet review of the staged diff (migrations 090+091, live
verification SQL, contract test, diagnose-doc). Change is **already applied live**
(founder-authorized) and closes anon/authenticated EXECUTE on SECURITY DEFINER
functions exposed over PostgREST.

## Finding 1 — P1 (claimed) → **FALSE_ALARM (verified live)**
- **claim:** `cron_call_log_cleanup_7d()` doesn't exist; the real fn is
  `cleanup_cron_call_log()` (repo mig 068/069), so the REVOKE/ALTER targeted a
  non-existent function → either 090 rolled back, or the real cleanup fn is unhardened.
- **verification (live, vs `dedsavbjuwgarrhphgnl`):**
  `SELECT proname, prosecdef, has_function_privilege('anon',oid,'EXECUTE') FROM pg_proc
   WHERE proname IN ('cron_call_log_cleanup_7d','cleanup_cron_call_log')` →
  **only `cron_call_log_cleanup_7d` exists** (secdef=true, anon_exec=**false**,
  auth_exec=**false**). `cleanup_cron_call_log` does NOT exist live (renamed). The
  agent reasoned from stale repo migration files, not live state (the
  subagent-existence-claim class — CLAUDE.md). The function exists, was correctly
  hardened, and 090 fully applied (guard + search_path confirmed present post-apply).
- **disposition:** false alarm; no action.

## Finding 2 — P2 (claimed) → **FALSE_ALARM**
- **claim:** the contract test pins a non-existent function name (false confidence).
- **verification:** the function exists live (Finding 1); the test correctly pins it.
- **disposition:** false alarm; no action.

## Finding 3 — style nit → **not enforced, no action**
- **claim:** migration files lack a 4-line `Intent/Destructive/Rollback/Linked-diagnose`
  header (migrations/CLAUDE.md).
- **verification:** the pre-commit gate batch ran and flagged ONLY
  check_code_review_pass_exists (not a header gate) → the header is not a blocking
  gate. The files already carry an explanatory header + `diagnose c9b3e2` reference.
  Adding a formal header now would change the applied files' hashes (drift vs the
  ledger) for zero enforcement benefit.
- **disposition:** noted, not actioned.

## Confirmed CLEAN by the reviewer (adversarial attacks that held)
- **Legit-caller breakage:** `match_memories` is the only client `.rpc()` to a touched
  fn and is search_path-only (grants untouched). EFs use service_role (re-granted in
  091). `update_streak_progress` re-granted to `authenticated` → self-write survives.
- **Guard logic:** `IF auth.uid() IS NOT NULL AND p_user_id <> auth.uid()` blocks
  cross-account writes, passes service_role/cron (null uid) + legit self-write; the
  CREATE OR REPLACE body is a verbatim copy of mig 056 (version checks, FOR UPDATE,
  insert-at-v1 preserved).
- **search_path shadowing:** inclusive `public, extensions, vault, private` resolves
  pgvector ops + vault reads; no unqualified collision in the touched bodies.
- **Idempotency:** REVOKE/GRANT/ALTER + CREATE OR REPLACE all re-runnable.
- **Secrets:** none in diff.

## Verdict: accepted
Zero real bugs. The two flagged findings are false alarms from a stale repo function
name (verified against live pg_proc); the header nit is non-blocking. The fix is
correct and live-verified (advisor re-run cleared 15/16 anon-exec + all 9 search_path).
