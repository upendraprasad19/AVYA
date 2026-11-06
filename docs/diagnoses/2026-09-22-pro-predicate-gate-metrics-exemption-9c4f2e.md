---
bug_id: 9c4f2e
date: 2026-09-22
batch: observation-batch-and-digest-redesign (post-push gate)
status: fixed
blast_radius: feature
symptom: |
  Full-suite pre-push run failed on `test/contracts/pro_predicate_adoption_test.dart`:
  "no Edge Function READS users.subscription_status to decide tier" —
  Expected empty, Actual: `[supabase/functions/_shared/founder_digest_content.ts
  matches \.eq\(\s*['"]subscription_status['"]]`.
concept: pro_predicate_adoption_gate
sot_registry_entry: not_applicable
writers:
  - { file: supabase/functions/_shared/founder_digest_content.ts, method_or_widget: "lapsedYesterdayRead", line: 880 }
readers:
  - { file: test/contracts/pro_predicate_adoption_test.dart, method_or_widget: "'no Edge Function READS users.subscription_status to decide tier' test", line: 90 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: "users (read-only, metrics count)"
cloud_columns: [subscription_status, subscription_expires_at]
contract_test_path: test/contracts/pro_predicate_adoption_test.dart
ist_handling:
  - "lapsedYesterdayRead windows on yStart/tStart, the digest's own already-established IST day boundaries — unchanged by this fix."
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable — a single admin-only digest metric query, no per-user access decision results from it.
forbidden_patterns_checked:
  - ".eq(\"subscription_status\", \"pro\") read to DECIDE a user's tier or gate a feature (the class this gate exists to catch — not present here)"
proposed_fix: |
  This is NOT the bug class `pro_predicate_adoption_test.dart` exists to
  catch (a 2026-07-26 incident where `morning-alert` used
  `users.subscription_status` as the source of truth to decide whether to
  send PRO-tier AI content, serving stale/expired users). The digest's
  `lapsedYesterday` metric reads the same column for a categorically
  different purpose: it COUNTS how often `subscription_status` still says
  'pro' after `subscription_expires_at` has already passed — i.e. it
  measures the exact cache-vs-truth drift the gate exists to keep out of
  access decisions elsewhere. No user's tier, access, or AI-generated
  content depends on this read; it only feeds a founder-facing KPI number.
  Rewriting the query to use `fetchProUserIds()`/`isProUser()` (the gate's
  own suggested fix) would defeat the metric's purpose outright — those
  helpers report who is AUTHORITATIVELY pro right now via the `subscriptions`
  table, not who the stale `users` cache still claims is pro after expiry,
  which is precisely the drift being measured.

  Fixed by adding one narrow, explicit, self-verifying exemption to the gate
  rather than either bypassing it wholesale or breaking the metric:
  `test/contracts/pro_predicate_adoption_test.dart` now strips one exact,
  named literal snippet (`.eq("subscription_status", "pro")`) from
  `founder_digest_content.ts` ONLY, before running the violation patterns —
  scoped by exact-string removal rather than a file-level skip, so a
  DIFFERENT, illegitimate read added later to the same file is still caught.
  A companion `expect` fails loudly if the snippet ever stops matching
  verbatim (moved/reformatted/removed), so the exemption cannot silently go
  stale or widen.
regression_test_planned:
  - test/contracts/pro_predicate_adoption_test.dart
impact_analysis: |
  Test-only change (plus the pre-existing, already-shipped digest code,
  which is not touched by this fix). No production behavior changes: the
  digest metric already existed and already ran this query; only the gate's
  own scope was corrected. The gate's positive control and its other 3
  assertions are untouched and still enforce the real rule everywhere else
  in supabase/functions/.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: not_applicable, evidence: "Edge Function + Dart test only, no client code touched." }
  - { tier: 6, name: "Edge Function code vs deploy", status: verified, evidence: "founder_digest_content.ts already deployed as part of this batch's founder-digest redesign (Part B); this fix touches only the test, not the function." }
mutation_proven:
  mutated: "Removed the exemption block (both constants and the strip-and-assert logic) from pro_predicate_adoption_test.dart, confirmed applied by reading the file."
  result: "Ran flutter test test/contracts/pro_predicate_adoption_test.dart: RED — the 'no Edge Function READS...' test failed again, reproducing the exact original violation against founder_digest_content.ts. Also separately mutated the exemption snippet constant to a non-matching string (with the strip logic restored) to prove the companion self-check fires: RED on the new 'reviewed metrics-only exemption snippet ... no longer appears verbatim' assertion, not a silent pass-through. Restored both; re-ran: GREEN, 4/4 passed."
  confirmed_applied: "Read the file after each mutation and after the restore to confirm exact content."
---

## Summary

The pre-push full suite failed `pro_predicate_adoption_test.dart`'s gate
against `users.subscription_status` reads, flagging a read this batch's
founder-digest redesign (Part B) added in `founder_digest_content.ts`.

## Root cause

Not a code bug — a gate-scope gap. The gate's blanket source-grep cannot
distinguish "read `subscription_status` to decide a user's tier/access" (the
real, historically-costly bug it exists to catch) from "read
`subscription_status` to measure how often it has drifted from
`subscription_expires_at`" (a read-only reporting metric with no access
consequence), and the digest's new `lapsedYesterday` KPI is the latter.

## Fix

Added one narrow, named, self-verifying exemption to the gate for the exact
reviewed snippet, rather than loosening the gate's patterns generally or
rewriting the metric to use the authoritative-but-wrong-for-this-purpose
`subscriptions` table.

## Verification

- `flutter test test/contracts/pro_predicate_adoption_test.dart`: 4/4 green
  after the fix.
- Mutation proof: removing the exemption reproduces the original failure;
  corrupting the exemption's snippet constant (exemption logic still present)
  fails loudly on its own companion self-check rather than silently passing.

## Files changed

- Modified: `test/contracts/pro_predicate_adoption_test.dart`
- Created: this diagnose-doc.
