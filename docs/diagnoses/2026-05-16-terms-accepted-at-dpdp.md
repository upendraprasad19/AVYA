---
bug_id: 2026-05-16-terms-accepted-at-dpdp
date: 2026-05-16
batch: audit 2026-05-16 Phase E.3 (DPDP compliance gap)
status: fixed
symptom: |
  Cloud `users.terms_accepted_at` and `users.terms_version` are 100% NULL
  across every production row (live SQL: `null_count = 4 / total = 4` for
  both columns at audit time). DPDP §22 requires the controller to retain
  proof of consent for every Data Principal; the gap means we cannot prove
  any user consented to our ToS / Privacy Policy. The Hive-side
  `_ensureLocalUser` upward sync at `auth_provider.dart:505-516` is gated
  on `userBox.get('terms_accepted_at') != null`, so it never fires for
  email sign-up users — the inline pre-checked checkbox introduced in
  APK Test #2 / Q2 never wrote anything to Hive on tap.
concept: terms_acceptance_audit_trail
sot_registry_entry: users_terms_consent_writer
writers:
  - { file: lib/features/auth/screens/sign_in_screen.dart, method: _buildEmailView_signup_onPressed, line: 620 }
  - { file: lib/features/auth/providers/auth_provider.dart, method: _ensureLocalUser_upward_sync, line: 511 }
readers:
  - { file: lib/features/auth/providers/auth_provider.dart, method_or_widget: _ensureLocalUser, line: 508 }
hive_key_prefix: "terms_accepted_at | terms_version"
hive_key_formula: "literal keys on userBox (per-user scoped via HiveUserSession)"
sync_methods: [_ensureLocalUser]
restore_methods: [_ensureLocalUser]
cloud_table: users
cloud_columns: [terms_accepted_at, terms_version]
contract_test_path: test/contracts/terms_signup_writes_test.dart
ist_handling:
  - { file: lib/features/auth/screens/sign_in_screen.dart, line: 622, note: "UTC ISO8601 is canonical for timestamptz columns; IST contract applies to date-keys only" }
provider_invalidations: []
telemetry_op_types:
  success: []
  failure: [users_upsert_failed, users_unique_violation_23505, users_fk_violation_23503]
cross_account_guard: |
  userBox is per-user scoped via HiveUserSession; cross-account writes are
  impossible by construction. The Hive write happens BEFORE signUp completes
  (no user exists yet on the device when CREATE ACCOUNT is tapped), so the
  values are seeded into whichever userBox owns the resulting session once
  `_ensureLocalUser` opens it. The existing auth_provider upward sync
  enforces `eq('id', user.id)` so cross-account UPDATE is also impossible.
forbidden_patterns_checked:
  - { pattern: "userBox.put('terms_accepted_at', ...) before signUpWithEmail", absent: false }
  - { pattern: "userBox.put('terms_version', ...) before signUpWithEmail", absent: false }
  - { pattern: "AppConstants.termsVersion (not hardcoded literal)", absent: false }
  - { pattern: "DateTime.now().toUtc().toIso8601String() (not naive local)", absent: false }
proposed_fix: |
  Single-layer fix at the CREATE ACCOUNT button onPressed handler in
  `sign_in_screen.dart _buildEmailView`. Before calling
  `authNotifier.signUpWithEmail(email, password)`, write both keys to
  userBox synchronously (Future fire-and-forget since the values are
  primitives; failure is non-fatal because the upward sync is gated on
  Hive presence anyway — pre-fix behavior was equivalent to a no-op):
  ```dart
  try {
    HiveService.instance.userBox.put('terms_accepted_at',
        DateTime.now().toUtc().toIso8601String());
    HiveService.instance.userBox.put('terms_version',
        AppConstants.termsVersion);
  } catch (_) {}
  ```
  The existing `_ensureLocalUser` upward sync at auth_provider.dart:505-516
  already projects these keys to `users.terms_accepted_at` /
  `users.terms_version` when Hive carries a value; no server-side change is
  needed. The pre-checked checkbox + visible-and-tickable affordance + the
  two underlined links (Privacy Policy + Terms) constitute the affirmative
  action under DPDP §11.
regression_test_planned:
  - test/contracts/terms_signup_writes_test.dart
---

# Body

## Symptom

Audit 2026-05-16 Agent 3 ran column-by-column NULL counts across 385
columns of 32 non-zero tables. Two stood out:

```
SELECT
  COUNT(*) FILTER (WHERE terms_accepted_at IS NULL) AS null_accepted_at,
  COUNT(*) FILTER (WHERE terms_version IS NULL)     AS null_version,
  COUNT(*) AS total
FROM public.users;
-- null_accepted_at = 4, null_version = 4, total = 4
```

Every single production user has NULL consent timestamps. The columns
themselves exist (migration 032, 2026-04-20). The Hive-side `TermsModal`
that originally fed them was retired on the sign-in path in APK Test #4 /
OBS-A (see `sign_in_screen.dart:66-78` comment block) — Q2 replaced it
with an inline pre-checked checkbox. The replacement never wrote to Hive.

Result: DPDP §22 requires the controller to retain proof of consent for
every Data Principal. We have zero such proof for any user in production.

## Cause

1. **APK Test #2 / Q2 (2026-04-25)** moved consent capture from a
   standalone `TermsModal` (which DID write to userBox) to an inline
   pre-checked checkbox on the sign-up form. The checkbox state lives in
   widget local state (`_privacyAccepted`) and only gates the CREATE
   ACCOUNT button — there is no Hive write on tick or on tap.

2. **The upward sync was already correct.** `auth_provider.dart:508-516`
   reads `userBox.get('terms_accepted_at')` after auth completes and, if
   present, UPDATEs `users.terms_accepted_at` + `users.terms_version`
   cleanly. But the gate `if (termsAcceptedAt is String && ...)` returned
   false for every email sign-up since Q2 because nothing was writing
   the Hive key.

3. **Other auth paths**: Google OAuth + phone OTP have no equivalent
   ToS UI at all in the current flow. They are out of scope for this
   fix — flagged for follow-up in Phase E.15 doc updates.

This is the **same writer/reader drift family** seen across Tests #6 →
#16.1 (per `feedback_writer_reader_field_drift_recurring.md`), just at
the UI-to-Hive boundary instead of Hive-to-cloud. The reader
(`_ensureLocalUser`) was correct and unchanged; the writer was dropped
in a UX refactor and nobody noticed because the column NULL state was
the pre-Q2 norm (terms columns were freshly added).

## Fix

`sign_in_screen.dart _buildEmailView` CREATE ACCOUNT onPressed now
writes both keys synchronously into `HiveService.instance.userBox`
before calling `authNotifier.signUpWithEmail(...)`. The writes use:

- `DateTime.now().toUtc().toIso8601String()` for the timestamp — the
  cloud column is `timestamptz`, and UTC ISO8601 is the canonical
  interchange form. The IST date-key contract (CLAUDE.md §15) applies
  to date columns / Hive date-key strings, NOT instant timestamps.
- `AppConstants.termsVersion` for the version — bumping the constant
  forces re-acceptance app-wide (matches the existing `TermsModal`
  skip-gate contract documented in CLAUDE.md §7).

The try/catch swallows Hive failure as non-fatal: a failed write leaves
the system in the same NULL-cloud state as pre-fix, which is bad but
not worse, and crucially does not block the auth flow itself. The
existing `_ensureLocalUser` upward sync picks the values up on the
first post-auth pass — no Edge Function change required.

A new contract test
(`test/contracts/terms_signup_writes_test.dart`, 6 sub-tests) pins:

1. `userBox.put('terms_accepted_at', ...)` present.
2. `userBox.put('terms_version', ...)` present.
3. `AppConstants.termsVersion` referenced (not a hardcoded literal).
4. Both writes appear **lexically before** the
   `authNotifier.signUpWithEmail(` call site in the file (no race with
   `_ensureLocalUser`).
5. Timestamp uses `DateTime.now().toUtc().toIso8601String()` (not naive
   local time).
6. `app_constants.dart` import is present.

## Verification

```
$ flutter test test/contracts/terms_signup_writes_test.dart
00:00 +6: All tests passed!
```

Manual: live SQL post-deploy must show new sign-ups landing with
non-NULL `terms_accepted_at` / `terms_version`. Audit follow-up at the
next batch retrospective.

## Follow-ups (deferred — NOT in this fix)

- **Google OAuth + phone OTP consent capture.** Both paths skip the
  email-form checkbox entirely. Either (a) add a one-time consent gate
  before the OAuth/OTP initiation, or (b) accept that the Welcome
  screen's inline footer "By continuing, you agree to ..." is the
  affirmative action and stamp Hive at the moment of CONTINUE WITH
  GOOGLE / SEND OTP tap. Flag for Phase E.15 / next audit.
- **Retroactive stamp for existing 4 users.** A one-shot SQL UPDATE
  could backfill `terms_accepted_at = users.created_at` for rows where
  the user is known to have signed up post-Q2 (all 4 production rows).
  Defer to Phase F if founder approves the legal interpretation.
