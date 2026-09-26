---
bug_id: 3a7c1e
date: 2026-05-17
batch: open-issues OI-10 (cross-account guard auto-inheritance)
status: fixed
symptom: |
  No live symptom — preventive enforcement. The existing
  `auth_invalidation_contract_test.dart` (post APK Test #15.3 / Bug
  c4055a) already auto-discovers new providers in `lib/features/`
  and enforces every user-scoped one watches `authUserIdTokenProvider`.
  But it maintains a manual EXEMPTIONS list inside the test file —
  a slow-drift surface where a future developer could add an entry
  without documenting why it's exempt. The fix forces the exempt
  status to be self-declared in the file itself.
concept: cross_account_guard_exempt_declaration
sot_registry_entry: auth_hive_owner_agreement
writers:
  - { file: lib/features/auth/providers/referral_code_stash_provider.dart, method: provider declaration, line: 1 }
  - { file: lib/features/auth/providers/auth_provider.dart, method: provider declaration, line: 1 }
  - { file: lib/features/auth/providers/auth_invalidation_provider.dart, method: provider declaration, line: 1 }
readers:
  - { file: test/contracts/auth_invalidation_contract_test.dart, method: OI-10 exempt-marker check, line: 100 }
hive_key_prefix: ""
hive_key_formula: ""
sync_methods: []
restore_methods: []
cloud_table: ""
cloud_columns: []
contract_test_path: test/contracts/auth_invalidation_contract_test.dart
ist_handling: []
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: []
cross_account_guard: "the test gates this guard itself"
forbidden_patterns_checked:
  - { pattern: "AUTH_INVALIDATION_EXEMPT", absent_outside_canonical: false }
proposed_fix: |
  Two parts:
  (1) Test extended — new sub-test `OI-10 — exempt files self-declare
      exemption marker in source` asserts every path in the test's
      `exemptions` set contains a `// AUTH_INVALIDATION_EXEMPT: <reason>`
      comment in its actual source.
  (2) The 3 exempt files annotated:
      - `referral_code_stash_provider.dart`: pre-auth surface — stash
        must survive the signed-out → signed-in transition.
      - `auth_provider.dart`: auth source-of-truth — can't self-watch
        without creating a circular rebuild loop.
      - `auth_invalidation_provider.dart`: defines authUserIdTokenProvider
        itself; tautology to watch itself.

  The pre-existing auto-discovery walk over `lib/features/` ALREADY
  catches new user-scoped providers added without the watch. This
  fix closes the remaining slow-drift surface: someone adding a new
  file to the exemption list without a code-side justification.
regression_test_planned:
  - test/contracts/auth_invalidation_contract_test.dart
---
# Body

## Why this matters

Cross-account leak via cached Riverpod state was the 2026-05-12 / Bug
c4055a class — sign-out + new sign-in (same session, different user)
returned the previous user's profile because 56 user-scoped providers
had cached their build() return values against the old user's namespaced
Hive boxes. The c4055a fix added `ref.watch(authUserIdTokenProvider)`
to every affected provider so they auto-invalidate on auth change.

The existing `auth_invalidation_contract_test.dart` is the structural
prevention — it auto-discovers new providers + requires the watch. Three
files are LEGITIMATELY exempt (pre-auth surface, auth source-of-truth,
the auth provider itself).

OI-10's specific ask: make those 3 exemptions DOCUMENTED in code, not
just in a test-internal Set. So a reviewer reading the exempt file
itself can see why it's exempt without cross-referencing the test.

## What was missing

Manual exemption set inside the test:

```dart
final exemptions = <String>{
  'lib/features/auth/providers/referral_code_stash_provider.dart',
  'lib/features/auth/providers/auth_provider.dart',
  'lib/features/auth/providers/auth_invalidation_provider.dart',
};
```

No code-side annotation. Reviewer reading the exempt file alone has
no signal that it's exempt or why.

## Fix

The test now ADDITIONALLY asserts each exempt file contains a
`AUTH_INVALIDATION_EXEMPT:` marker comment. The 3 files now have
explicit justifications at the top of the file.

Adding a new exemption now requires:
1. Add file path to the test's exemptions set, AND
2. Add `AUTH_INVALIDATION_EXEMPT: <reason>` comment to the file itself.

If only (1) is done, the new sub-test fails. The exemption is
self-documenting.

## Verification

```
$ flutter test test/contracts/auth_invalidation_contract_test.dart
All tests passed! (2 cases — existing guard + new OI-10 marker check)
```

## Closing

closes-oi: OI-10
