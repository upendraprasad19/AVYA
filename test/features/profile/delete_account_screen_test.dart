// test/features/profile/delete_account_screen_test.dart
//
// Validates the 2-step hard-delete flow introduced in APK Test #11
// Task H1 (DPDP compliance).
//
// Approach: source-scan + logic tests. Full widget tests require deep
// Hive bootstrap + Supabase mock seams. Source-scan tests follow the
// convention established in test/profile/profile_screen_layout_test.dart
// (verifies invariants without pumping widgets). Logic tests probe the
// validation predicate directly by extracting it from the screen's public
// contract.
//
// Test groups:
//   H1-A — Validation predicate (case-sensitivity, both-parts required)
//   H1-B — Source invariants (copy, error codes, token construction)
//   H1-C — Profile_screen migration (no old dialog, new push call)
//   H1-D — Router wiring (route registered)
//   H1-E — softDeleteAccount @Deprecated

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// ── Paths ────────────────────────────────────────────────────────────────
const _screenPath =
    'lib/features/profile/screens/delete_account_screen.dart';
const _profilePath =
    'lib/features/profile/screens/profile_screen.dart';
const _routerPath =
    'lib/core/router/app_router.dart';
const _repoPath =
    'lib/shared/repositories/user_repository.dart';

String _src(String p) => File(p).readAsStringSync();

// ── Validation helper (mirrors _confirmValid logic) ─────────────────────
//
// Extracted logic for unit testing WITHOUT pumping widgets.
// Must stay in sync with _DeleteAccountScreenState._confirmValid.
bool _validateConfirm(String input, String fullName) {
  final firstName = fullName.split(' ').first;
  if (firstName.isEmpty) return false;

  final text = input.trim();
  final spaceIdx = text.indexOf(' ');
  if (spaceIdx < 0) return false;
  final enteredFirst = text.substring(0, spaceIdx);
  final enteredSuffix = text.substring(spaceIdx + 1);

  final firstNameOk = enteredFirst.toLowerCase() == firstName.toLowerCase();
  final deleteSuffixOk = enteredSuffix == 'DELETE';
  return firstNameOk && deleteSuffixOk;
}

void main() {
  // ── H1-A: Validation predicate ──────────────────────────────────────────
  group('H1-A — Validation predicate', () {
    const name = 'Avyaansh';

    test('Disabled when only first name (no DELETE)', () {
      expect(_validateConfirm('Avyaansh', name), isFalse);
    });

    test('Disabled when DELETE is lowercase', () {
      expect(_validateConfirm('Avyaansh delete', name), isFalse,
          reason: 'DELETE must be uppercase — "delete" must be rejected');
    });

    test('Disabled when DELETE is mixed case', () {
      expect(_validateConfirm('Avyaansh Delete', name), isFalse,
          reason: 'Only uppercase DELETE must be accepted');
    });

    test('Disabled when first name is wrong', () {
      expect(_validateConfirm('John DELETE', name), isFalse);
    });

    test('Enabled when first name case-insensitive + DELETE uppercase', () {
      expect(_validateConfirm('Avyaansh DELETE', name), isTrue);
    });

    test('Enabled when first name is lowercase (case-insensitive match)', () {
      expect(_validateConfirm('avyaansh DELETE', name), isTrue,
          reason: 'First name match must be case-insensitive');
    });

    test('Enabled when first name is uppercase', () {
      expect(_validateConfirm('AVYAANSH DELETE', name), isTrue);
    });

    test('Disabled when empty input', () {
      expect(_validateConfirm('', name), isFalse);
    });

    test('Enabled when DELETE has trailing space (trim() strips it)', () {
      // input.trim() is applied before splitting, so trailing whitespace
      // is removed — 'Avyaansh DELETE ' → 'Avyaansh DELETE' → valid.
      expect(_validateConfirm('Avyaansh DELETE ', name), isTrue,
          reason: 'trim() on input removes trailing space — result is valid');
    });

    test('Works with multi-word full name — first word only needed', () {
      // full_name = "Upendra Prasad" → firstName = "Upendra"
      expect(_validateConfirm('Upendra DELETE', 'Upendra Prasad'), isTrue);
    });

    test('Disabled when second word is supplied instead of first', () {
      expect(_validateConfirm('Prasad DELETE', 'Upendra Prasad'), isFalse);
    });
  });

  // ── H1-B: Source invariants ─────────────────────────────────────────────
  group('H1-B — Source invariants', () {
    final src = _src(_screenPath);

    // ── DPDP blast-radius copy ────────────────────────────────────────────
    test('Contains "Delete your profile, workouts, meals, weight history, photos."', () {
      expect(
        src,
        contains('Delete your profile, workouts, meals, weight history, photos.'),
        reason: 'Step 1 must list exact DPDP data-erasure disclosure',
      );
    });

    test('Contains subscription cancellation copy', () {
      expect(
        src,
        contains('Cancel your active subscription'),
        reason: 'Step 1 must disclose subscription cancellation',
      );
    });

    test('Contains "Sign you out on every device."', () {
      expect(
        src,
        contains('Sign you out on every device.'),
      );
    });

    test('Contains Razorpay retention copy (What stays)', () {
      expect(
        src,
        contains('Razorpay payment receipts'),
        reason: 'What stays section must mention Razorpay receipts per tax law',
      );
    });

    test('Contains anonymous community contributions copy', () {
      expect(
        src,
        contains('Anonymous community contributions'),
        reason: 'What stays section must mention community contributions remain',
      );
    });

    test('Contains 30-day backup purge copy', () {
      expect(
        src,
        contains('Backups will purge within 30 days.'),
      );
    });

    test('Contains "This cannot be undone."', () {
      expect(src, contains('This cannot be undone.'));
    });

    // ── Final button ──────────────────────────────────────────────────────
    test('Final button uses AppColors.bad background', () {
      expect(
        src,
        contains('AppColors.bad'),
        reason: 'Final delete button must have AppColors.bad background',
      );
    });

    test('Final button label contains "IRREVERSIBLE — DELETE MY ACCOUNT"', () {
      expect(src, contains('IRREVERSIBLE — DELETE MY ACCOUNT'));
    });

    // ── Confirmation token construction ───────────────────────────────────
    test('Token is constructed as DELETE-MY-ACCOUNT-<userId.substring(0,8)>', () {
      expect(
        src,
        contains("'DELETE-MY-ACCOUNT-\${userId.substring(0, "),
        reason: 'Confirmation token must start with DELETE-MY-ACCOUNT- prefix '
            'followed by userId.substring(0, 8) (or min length guard)',
      );
    });

    // ── Error code handling ───────────────────────────────────────────────
    test('Handles razorpay_cancel_failed error code', () {
      expect(
        src,
        contains('razorpay_cancel_failed'),
        reason: 'Must surface Razorpay cancel failure with support contact copy',
      );
    });

    test('Handles confirmation_token_mismatch error code', () {
      expect(
        src,
        contains('confirmation_token_mismatch'),
      );
    });

    test('Support email present in error copy', () {
      expect(src, contains('support@icanbefitter.com'));
    });

    // ── Hive + signOut on success ─────────────────────────────────────────
    test('Calls clearAllData on success path', () {
      expect(
        src,
        contains('clearAllData()'),
        reason: 'Hive wipe must happen on the 200 success path',
      );
    });

    test('Calls auth.signOut on success path', () {
      expect(
        src,
        contains('signOut('),
        reason: 'Auth signOut must be called after clearAllData on success',
      );
    });

    test('Does NOT call clearAllData in the catch block (no Hive wipe on failure)', () {
      // The catch block(s) must NOT contain clearAllData — they only
      // reset loading state and show a snackbar.
      //
      // Strategy: split the source at the start of the success path
      // ('await UserRepository.instance.clearAllData()') and confirm
      // the text AFTER that point (the catch blocks) does NOT repeat
      // clearAllData.
      final successIdx = src.indexOf('await UserRepository.instance.clearAllData()');
      expect(successIdx, isNot(-1),
          reason: 'clearAllData must exist in success path');

      // Everything after the success call (catch blocks, error handler).
      // Offset 50 skips past 'clearAllData();' (43 chars) safely.
      final afterSuccess = src.substring(successIdx + 50);
      expect(
        afterSuccess,
        isNot(contains('clearAllData()')),
        reason:
            'clearAllData must NOT appear in catch/error blocks — Hive '
            'must not be wiped on failure so user retains local data',
      );
    });

    // ── Step 1 / Step 2 state ─────────────────────────────────────────────
    test('Uses _step local variable to toggle between step 1 and step 2', () {
      expect(src, contains('_step'));
    });

    test('KEEP MY ACCOUNT CTA is present', () {
      expect(src, contains('KEEP MY ACCOUNT'));
    });

    test('DELETE literal validation comment or string present', () {
      // Either the validation doc comment or the literal 'DELETE'
      // string appears to enforce case-sensitive matching.
      expect(src, contains("== 'DELETE'"));
    });
  });

  // ── H1-C: profile_screen.dart migration ─────────────────────────────────
  group('H1-C — Profile screen migration', () {
    final src = _src(_profilePath);

    test('No longer contains _showDeleteAccountDialog method definition', () {
      expect(
        src,
        isNot(contains('void _showDeleteAccountDialog')),
        reason:
            'Old soft-delete dialog must be removed from profile_screen.dart',
      );
    });

    test('No longer calls softDeleteAccount', () {
      expect(
        src,
        isNot(contains('softDeleteAccount')),
        reason:
            'profile_screen.dart must not call the deprecated softDeleteAccount',
      );
    });

    test('Pushes to /profile/delete-account route', () {
      expect(
        src,
        contains('/profile/delete-account'),
        reason:
            'Danger zone Delete Account tap must navigate to the new screen',
      );
    });
  });

  // ── H1-D: Router wiring ──────────────────────────────────────────────────
  group('H1-D — Router wiring', () {
    final src = _src(_routerPath);

    test('Route path delete-account is registered', () {
      expect(
        src,
        contains("path: 'delete-account'"),
        reason: 'App router must declare the delete-account sub-route under /profile',
      );
    });

    test('DeleteAccountScreen is imported', () {
      expect(
        src,
        contains('delete_account_screen.dart'),
      );
    });

    test('DeleteAccountScreen builder is present', () {
      expect(
        src,
        contains('DeleteAccountScreen()'),
      );
    });
  });

  // ── H1-E: softDeleteAccount REMOVED ─────────────────────────────────
  // audit-2026-05-16 E.8 — `softDeleteAccount` method deleted from
  // UserRepository (founder approved Phase D NEEDS_DECISION 4 Option A).
  // The H1-E group is inverted: assert the method NO LONGER exists.
  // Hard-delete via `delete-account` Edge Function (DeleteAccountScreen)
  // is the canonical path.
  group('H1-E — softDeleteAccount removed (audit 2026-05-16 E.8)', () {
    final src = _src(_repoPath);

    test('softDeleteAccount method no longer exists', () {
      expect(
        src,
        isNot(contains('static Future<void> softDeleteAccount')),
        reason:
            'audit-2026-05-16 E.8 deleted softDeleteAccount. Hard-delete '
            'via delete-account Edge Function (DeleteAccountScreen) is the '
            'canonical path. If you re-add this method you re-open the '
            'class of bug Test #11 H1 closed.',
      );
    });
  });
}
