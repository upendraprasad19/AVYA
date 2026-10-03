---
bug_id: a1e6f2
date: 2026-09-21
batch: observation-batch-and-digest-redesign (A7)
status: fixed
blast_radius: feature
symptom: |
  Founder observation #7: "email wrong. check our email." The app showed 2
  different, both-wrong support addresses across 2 screens: the Profile
  contact card showed `support@avya.app` (a leftover from the app's prior
  "Avya" branding), and the delete-account subscription-cancel error message
  showed `support@icanbefitter.com` (a plausible-looking address nobody
  actually monitors). Neither matched the founder's real inbox.
concept: support_contact_email
sot_registry_entry: support_contact_email
writers:
  - { file: lib/features/profile/screens/profile/screen.dart, method_or_widget: "build (contact card)", line: 305 }
  - { file: lib/features/profile/screens/delete_account_screen.dart, method_or_widget: "razorpay_cancel_failed error branch", line: 165 }
readers: []
hive_key_prefix: (n/a — literal UI string, not Hive-backed)
hive_key_formula: (n/a)
sync_methods: []
restore_methods: []
cloud_table: (n/a)
cloud_columns: []
contract_test_path: test/contracts/support_contact_email_writer_to_reader_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: Not applicable — static UI string literal, no user data.
forbidden_patterns_checked:
  - "support@avya.app"
  - "support@icanbefitter.com (old variant)"
proposed_fix: |
  Update both literal strings to the founder-confirmed canonical address,
  upendra@icanbefitter.com. Register a `support_contact_email` concept in
  docs/sot_registry.yaml (presence_only: true — a literal-string SoT, no
  Hive/cloud round-trip to pin) so a future drift is at least documented,
  even though no gate can mechanically enforce a literal string across files
  without a dedicated grep-gate (out of scope for this batch — noted as a
  residual, not silently accepted).
regression_test_planned:
  - test/contracts/support_contact_email_writer_to_reader_test.dart
impact_analysis: |
  Purely cosmetic text change in 2 files, no logic touched. No client-server
  contract, no schema, no Hive key. Zero risk of regressing anything else.
touched_layers_checked:
  - { tier: 1, name: "Client code", status: fixed_in_this_batch, evidence: "Both literal strings updated; flutter test test/contracts/support_contact_email_writer_to_reader_test.dart passes 3/3." }
mutation_proven:
  mutated: "Reverted lib/features/profile/screens/profile/screen.dart:305 from 'upendra@icanbefitter.com' back to 'support@avya.app', confirmed applied by reading the file."
  result: "Ran flutter test test/contracts/support_contact_email_writer_to_reader_test.dart: RED — 2 of 3 tests failed (the canonical-address assertion on that file, and the no-stale-variant sweep, which named the exact file:string). Reverted the mutation; re-ran: GREEN, 3/3 passed."
  confirmed_applied: "Read the file (Edit tool's own before/after) to confirm the string matched the intended mutation both times."
---

## Summary

The support email shown to users had drifted to 2 different wrong addresses across
2 screens — a leftover "Avya" brand domain on the Profile contact card, and an
unmonitored `icanbefitter.com` address on the delete-account error message.

## Root cause

No single source of truth for this literal string. Each screen's author typed a
plausible-looking address independently at different points in the app's history
(the `avya.app` domain predates the ICANBEFITTER rebrand).

## Fix

Updated both literal strings to `upendra@icanbefitter.com` (founder-confirmed
canonical address, this session). Registered `support_contact_email` in
`docs/sot_registry.yaml` as a `presence_only` literal-string concept so the
2 sites are at least documented together, with a source-grep test as the
regression guard.

## Verification

- New test asserts the canonical address at both sites, and sweeps every
  `.dart` file under `lib/features/profile/` for either stale variant.
- Mutation proof: reverted one site back to the old string — the sweep test
  caught it by name; reverted, 3/3 green again.

## Files changed

- Modified: `lib/features/profile/screens/profile/screen.dart`
- Modified: `lib/features/profile/screens/delete_account_screen.dart`
- Modified: `docs/sot_registry.yaml` (new `support_contact_email` concept)
- Created: `test/contracts/support_contact_email_writer_to_reader_test.dart`
- Created: this diagnose-doc.
