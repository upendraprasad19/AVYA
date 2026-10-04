---
bug_id: r2w6y9
date: 2026-09-22
batch: observation-batch-and-digest-redesign (post-push gate)
status: fixed
blast_radius: feature
symptom: |
  Full-suite pre-push run failed
  `test/features/profile/delete_account_screen_test.dart`: "H1-B — Source
  invariants Support email present in error copy" — Expected contains
  'support@icanbefitter.com', Actual: source text with no match.
concept: support_contact_email
sot_registry_entry: support_contact_email
writers:
  - { file: lib/features/profile/screens/delete_account_screen.dart, method_or_widget: "razorpay_cancel_failed error branch", line: 165 }
readers:
  - { file: test/features/profile/delete_account_screen_test.dart, method_or_widget: "'Support email present in error copy' test", line: 207 }
hive_key_prefix: not_applicable
hive_key_formula: not_applicable
sync_methods: []
restore_methods: []
cloud_table: not_applicable
cloud_columns: []
contract_test_path: test/features/profile/delete_account_screen_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable — static UI string literal, no user data.
forbidden_patterns_checked:
  - "support@icanbefitter.com (the address this batch's own A7 fix, diagnose a1e6f2, deliberately moved away from)"
proposed_fix: |
  This batch's own A7 fix (diagnose a1e6f2, same batch) updated
  `delete_account_screen.dart`'s `razorpay_cancel_failed` error copy from
  `support@icanbefitter.com` (an unmonitored address) to
  `upendra@icanbefitter.com` (the founder-confirmed canonical address), and
  added a NEW contract test (`support_contact_email_writer_to_reader_test.dart`)
  pinning the new address at that write site. However, this PRE-EXISTING test
  — `delete_account_screen_test.dart`'s own "Support email present in error
  copy" check, written before A7 for an earlier, different reason — still
  asserted the OLD address literal and was never swept when A7 landed. This
  is exactly the class CLAUDE.md's own value-semantics-grep pitfall entry
  describes: a batch that changes a stored/displayed value's meaning must
  sweep test/ for every existing assertion of the OLD value, not just add a
  new test for the new one.

  Fixed by updating this pre-existing assertion to the same canonical
  address A7 already established, with a comment cross-referencing that fix.
regression_test_planned:
  - test/features/profile/delete_account_screen_test.dart
impact_analysis: |
  Test-only change. No production code touched — `delete_account_screen.dart`
  already correctly shows the new canonical address (A7 already shipped it in
  this same batch); only this one pre-existing, unswept assertion pinned the
  address A7 deliberately moved away from. Zero risk to the running app.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: verified, evidence: "flutter test test/features/profile/delete_account_screen_test.dart: 47/47 passed after fix (was 1 failure)." }
mutation_proven:
  mutated: "Reverted the assertion from contains('upendra@icanbefitter.com') back to contains('support@icanbefitter.com'), confirmed applied by reading the file."
  result: "Ran flutter test test/features/nutrition/counter_increment_on_analyse_test.dart together with test/features/profile/delete_account_screen_test.dart (both mutated at once): RED — combined count showed exactly -2 failures, one per file, reproducing this exact original failure (contains 'support@icanbefitter.com' against source with no match). Restored to upendra@icanbefitter.com; re-ran both files together: GREEN, 47/47 passed."
  confirmed_applied: "Read the file after the revert and after the restore to confirm the exact literal each time."
---

## Summary

The pre-push full suite failed a pre-existing test pinning the support email
shown in the delete-account screen's error copy — not because the copy is
wrong, but because this batch's own A7 fix moved the copy to a new canonical
address without sweeping this earlier, unrelated test that still pinned the
old one.

## Root cause

Writer/reader drift introduced by A7 itself: the writer
(`delete_account_screen.dart`'s error copy) moved to
`upendra@icanbefitter.com`; A7 registered and tested that new value at the
write site, but a DIFFERENT, pre-existing reader
(`delete_account_screen_test.dart`'s own "Support email present in error
copy" test, written earlier for the same file but not part of A7's own
change) still asserted the address A7 replaced.

## Fix

Updated the pre-existing assertion to `upendra@icanbefitter.com`, with a
comment citing A7 (diagnose a1e6f2) so the connection is visible to future
readers of this file.

## Verification

- `flutter test test/features/profile/delete_account_screen_test.dart`:
  47/47 green after the fix.
- Mutation proof: reverting to the old address reproduces the original
  failure; restoring returns to green.

## Files changed

- Modified: `test/features/profile/delete_account_screen_test.dart`
- Created: this diagnose-doc.
