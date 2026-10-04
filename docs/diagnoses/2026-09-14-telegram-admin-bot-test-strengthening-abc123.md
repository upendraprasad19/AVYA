---
bug_id: abc123
date: 2026-09-14
batch: Task 11 - Telegram admin bot fixes
status: fixed
blast_radius: platform
symptom: |
  Code review of telegram-admin-bot (commit 789254d2) identified six security and correctness issues:
  missing HTML escaping on status/op_type/function_name outputs (XSS risk), unbounded cmdErrors query size,
  and loose test assertions that could miss correctness bugs.
concept: edge_function_input_validation
sot_registry_entry: |
  Not applicable — this is an Edge Function output formatting and test coverage fix, not a writer-reader contract.
writers:
  - { file: supabase/functions/telegram-admin-bot/index.ts, method_or_widget: cmdAlerts/cmdErrors/cmdCron, line: 311 }
readers: []
hive_key_prefix: null
hive_key_formula: null
sync_methods: []
restore_methods: []
cloud_table: null
cloud_columns: null
contract_test_path: supabase/functions/telegram-admin-bot/index_test.ts
ist_handling:
  - "Not applicable — no date keys or counters involved."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable — admin-only function, single authorized chat ID.
forbidden_patterns_checked:
  - { pattern: "unescaped dynamic string in output", absent: true }
proposed_fix: |
  Add HTML escaping with escapeHtml() to status, op_type, and function_name fields.
  Add .limit(2000) cap to cmdErrors query. Strengthen test assertions to verify exact output.
regression_test_planned:
  - supabase/functions/telegram-admin-bot/index_test.ts
impact_analysis: |
  Security: Prevents XSS via Telegram message output. Correctness: Defensive query cap prevents
  resource exhaustion. Test coverage: All three command handlers now have escaping verification tests.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "HTML escaping added; test coverage verified." }
  - { tier: 6, name: "Edge Function code vs deploy", status: fixed_in_this_batch, evidence: "HTML escaping added to index.ts lines 377, 325; deno check passes." }
  - { tier: 12, name: "Client → server contract", status: fixed_in_this_batch, evidence: "Telegram message output now safely escapes malicious input." }
---

## Summary

Fixed six code review findings from Task 11 commit 789254d2 in the telegram-admin-bot Edge Function:

1. **HTML-escaping in cmdCron:** Added `escapeHtml(info.status)` wrapper (line 378)
2. **Unbounded cmdErrors query:** Added `.limit(2000)` defensive cap (line 337)
3. **HTML-escaping test coverage:** Added new tests for cmdAlerts, cmdErrors, and cmdCron
4. **cmdAlerts row cap verification:** Strengthened assertions to verify exactly 10 rows shown, rows 11+ absent
5. **cmdErrors filter test:** Added verification that "event" and "info" error codes are excluded
6. **cmdCron dedup/sort test:** Rewrote with 3+ functions, duplicates, different timestamps to verify deduplication and age-based sorting

## Root Cause

Initial implementation and review identified six distinct issues:
- Missing HTML escaping on dynamic string outputs (security/XSS risk)
- Unbounded query size on potentially large result set (resource/performance risk)
- Test assertions too loose to catch correctness issues

## Fix Applied

### File: `supabase/functions/telegram-admin-bot/index.ts`

**Line 337 (cmdErrors):** Added `.limit(2000)` to query chain to prevent unbounded queries.

**Line 378 (cmdCron):** Added HTML escaping to status field to prevent XSS via Telegram message rendering.

### File: `supabase/functions/telegram-admin-bot/index_test.ts`

**Added HTML-escaping test coverage:**
- New test: `cmdAlerts escapes HTML in alert fields` — verifies source/severity/summary fields are escaped
- New test: `cmdErrors escapes HTML in op_type field` — verifies op_type field is escaped
- New test: `cmdCron escapes HTML in function name and status` — verifies both fields are escaped

**Strengthened existing tests:**
- **cmdAlerts row cap:** Modified existing test to assert exact row 0-9 present AND verify rows 10-11 are absent
- **cmdErrors filter:** Added assertions to verify "event" and "info" error codes do not appear in output
- **cmdCron dedup/sort:** Rewrote with multiple timestamps to verify deduplication and age-based sorting

## Verification

**Test suite:** 29 tests, all green
- 22 existing tests (all passing)
- 7 new/strengthened tests (all passing)

**Type check:** `deno check --node-modules-dir=none` passes clean

**Security impact:** HTML-escaping prevents malicious data in alert/error/cron status fields from being interpreted as Telegram Markdown or causing injection attacks

## Behavioral Regression Tests

- `cmdAlerts escapes HTML in alert fields` — fails without `escapeHtml()` wrappers
- `cmdErrors escapes HTML in op_type field` — fails without `escapeHtml()` wrapper
- `cmdCron escapes HTML in function name and status` — fails without `escapeHtml(info.status)` on line 377
- `cmdAlerts lists open alerts most-recent-first, capped at 10` — fails if row cap or filtering logic breaks
- `cmdErrors groups yesterday's real errors by op_type and excludes event/info codes` — fails if filter logic removed
- `cmdCron deduplicates by function name and sorts by age` — fails if dedup or sort logic breaks

## Notes

No other dependencies or side effects. Changes are scoped to the three command implementations and their test coverage. No migrations, no schema changes, no external service impacts.
