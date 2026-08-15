// test/supabase/cleanup_target_guard_test.dart
//
// The delete boundary for SupabaseTestHelper.cleanup() and the pgvector
// deletes. `cleanup()` DELETEs across 12 tables of the PRODUCTION project
// (dedsavbjuwgarrhphgnl) and CI runs it on every push to main, so "which user
// may it target?" is a safety question, not a hygiene one. OI-115.
//
// WHY THIS FILE NEEDS NO CREDENTIALS, AND WHY THAT IS LOAD-BEARING.
//   `assertDisposableTarget` is pure and parameterised, and [qaUserIds] is a
//   `const Set`. So every assertion here runs in the "Unit Tests" CI job, which
//   invokes `flutter test test/` with NO `--dart-define` at all.
//
//   That constraint is the whole reason this file pins a UUID SET rather than
//   an email literal. An earlier draft of this guard (branch
//   supabase-ci-http-mock) pinned `disposableTestEmail == 'qa@icanbefitter.com'`.
//   The moment that constant becomes `String.fromEnvironment(...)` it evaluates
//   to '' in the dart-define-less Unit Tests job and the pin fails — greening
//   one CI job by reddening another. A uuid set has no such coupling: it is
//   const, it is identical in every job, and it does not move when the
//   credential moves. Which is also exactly why it makes a better boundary.

library;

import 'package:flutter_test/flutter_test.dart';

import 'supabase_test_helper.dart';

/// A real QA account id — the one CI is allowed to wipe.
const _qaId = '039b8eb3-f9e9-4673-b7eb-7f14c1a53bc4';

/// A plausible NON-QA id. Shaped like a real uuid so the test exercises set
/// membership rather than a formatting reject.
const _realUserId = 'c1d2e3f4-a5b6-4c7d-8e9f-0a1b2c3d4e5f';

void main() {
  group('assertDisposableTarget — what it refuses', () {
    test('refuses when there is no authenticated session', () {
      expect(
        () => SupabaseTestHelper.assertDisposableTarget(
            signedInId: null, targetId: _qaId),
        throwsA(isA<StateError>().having(
            (e) => e.message, 'message', contains('no authenticated session'))),
        reason: 'deleting without knowing whose rows these are is never valid, '
            'even when the target looks like a QA account',
      );
    });

    // THE CENTRAL CASE. This is the scenario the previous email-based guard
    // could not refuse: both sides of its comparison moved together, so
    // repointing the credential at a real account sailed through.
    test('refuses a target that is not a designated QA account', () {
      expect(
        () => SupabaseTestHelper.assertDisposableTarget(
            signedInId: _realUserId, targetId: _realUserId),
        throwsA(isA<StateError>().having((e) => e.message, 'message',
            contains('not a designated QA account'))),
        reason: 'repointing the credentials at a real account must be refused '
            'by the boundary, not waved through because both sides moved',
      );
    });

    test('refuses a QA target while signed in as somebody else', () {
      expect(
        () => SupabaseTestHelper.assertDisposableTarget(
            signedInId: _realUserId, targetId: _qaId),
        throwsA(isA<StateError>()),
      );
    });

    test('refuses a non-QA target while signed in as a QA account', () {
      expect(
        () => SupabaseTestHelper.assertDisposableTarget(
            signedInId: _qaId, targetId: _realUserId),
        throwsA(isA<StateError>()),
        reason: 'a stray uid argument must not reach a non-QA account',
      );
    });

    test('allows the designated QA account deleting its own rows', () {
      expect(
        () => SupabaseTestHelper.assertDisposableTarget(
            signedInId: _qaId, targetId: _qaId),
        returnsNormally,
      );
    });
  });

  group('qaUserIds — the pin', () {
    // Moving this set moves the safety boundary itself. If the QA account is
    // genuinely changed, change it here AND consciously accept that every
    // account named by the new value becomes deletable by CI on every push.
    //
    // Pinned by UUID, never by email — see the file header for why an email pin
    // breaks the dart-define-less Unit Tests job the moment the credential
    // becomes environment-backed.
    test('contains exactly the designated disposable QA account', () {
      expect(SupabaseTestHelper.qaUserIds, equals({_qaId}),
          reason: 'widening this set is a deliberate, reviewable act — it must '
              'never happen as a side effect of a credential change');
    });

    test('does not contain a real-looking user id', () {
      expect(SupabaseTestHelper.qaUserIds.contains(_realUserId), isFalse);
    });
  });

  group('cleanup() wiring — ZERO deletes when the guard refuses', () {
    late List<String> attempted;

    setUp(() {
      attempted = <String>[];
      SupabaseTestHelper.deleteRows = (table, userId) async {
        attempted.add('$table/$userId');
      };
    });

    tearDown(SupabaseTestHelper.resetSeams);

    // THE MIRROR TEST. Asserting only that a StateError was thrown would pass
    // against a guard placed AFTER the deletes — the rows would already be
    // gone. The seam records every delete actually issued, so this asserts the
    // property that matters: nothing was deleted.
    test('issues no deletes at all when the target is refused', () async {
      await expectLater(
        SupabaseTestHelper.cleanup(_realUserId),
        throwsA(isA<StateError>()),
      );
      expect(attempted, isEmpty,
          reason: 'the guard must run BEFORE the first delete, not after — a '
              'refusal that still wiped 12 tables would be worthless');
    });

    test('a null session issues no deletes and does not throw', () async {
      // cleanup() with no session and no uid cannot know whose rows to remove,
      // so it returns without issuing anything. Deliberately silent rather than
      // loud: it runs in setUp, and throwing here would mask the real
      // setUpAll failure in every test of the file.
      await SupabaseTestHelper.cleanup();
      expect(attempted, isEmpty);
    });
  });
}
