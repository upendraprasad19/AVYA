import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive/hive.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shared test helper for all Supabase integration tests.
///
/// Provides auth, cleanup, and query utilities so individual test files
/// can focus on assertions rather than setup boilerplate.
///
/// Usage:
///   setUpAll(() => SupabaseTestHelper.init());
///   setUp(() => SupabaseTestHelper.cleanup());
///   tearDownAll(() => SupabaseTestHelper.dispose());
class SupabaseTestHelper {
  SupabaseTestHelper._();

  /// The QA account these suites sign in as. Environment-driven — never a
  /// literal, because the literal was committed to git and is in its history
  /// regardless (OI-116), and because a hardcoded account cannot be changed
  /// without a code change.
  ///
  /// Safe to make environment-driven ONLY because the delete boundary no longer
  /// reads it: [qaUserIds] is keyed on UUID. Under the previous email-comparing
  /// guard, an environment-driven email would have recreated the aliasing
  /// tautology by a new route — both sides of the comparison moving together.
  static const String testEmail =
      String.fromEnvironment('SUPABASE_TEST_EMAIL');
  static const String testPassword =
      String.fromEnvironment('SUPABASE_TEST_PASSWORD');

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Whether ALL FOUR credential inputs are present.
  ///
  /// FOUR, not two, and the count is the whole point. This getter previously
  /// checked only url + anonKey. Adding an environment-driven email and password
  /// without widening it turns a credential-absent run from a loud SKIP into a
  /// live `signInWithPassword(email: '', password: '')` — which fails with
  /// `AuthApiException: Invalid login credentials`, byte-identical to a WRONG
  /// password and to the failure this whole batch exists to fix. The run would
  /// look like a code defect instead of a missing secret.
  static bool get hasCredentials => credentialsComplete(
        supabaseUrl,
        supabaseAnonKey,
        testEmail,
        testPassword,
      );

  /// Pure predicate behind [hasCredentials], so the four-input rule is testable
  /// without compile-time defines (they are `const`; a test cannot vary them).
  @visibleForTesting
  static bool credentialsComplete(
    String url,
    String anonKey,
    String email,
    String password,
  ) =>
      url.isNotEmpty &&
      anonKey.isNotEmpty &&
      email.isNotEmpty &&
      password.isNotEmpty;

  /// The ONLY user ids `cleanup()` and the pgvector deletes may ever target.
  ///
  /// WHY A UUID SET AND NOT AN EMAIL (OI-115).
  ///   The obvious guard compares the signed-in EMAIL against the constant the
  ///   sign-in itself uses. Both sides then move together, so the one scenario
  ///   it exists to stop — "repoint the constant at an account that DOES exist,
  ///   because sign-in was failing" — passes straight through. A guard that
  ///   cannot refuse its own stated scenario is not a guard.
  ///
  ///   A uuid set does not move when the credential moves. Repointing
  ///   `testEmail` (or, once it is environment-driven, the secret behind it)
  ///   yields a `signedInId` simply absent from this set, and the delete is
  ///   refused. Widening it means consciously editing a literal list of ids — a
  ///   visible, reviewable diff, which is the point. An email is a mutable
  ///   label; a uuid is the thing rows are actually keyed by.
  ///
  ///   It is also `const`, so it is identical in the dart-define-less "Unit
  ///   Tests" CI job. An email pin would evaluate to '' there the moment the
  ///   credential became environment-backed, greening one job by reddening
  ///   another.
  ///
  ///   Real accounts this protects: `test2@gmail.com` … `test7@gmail.com` and
  ///   every human account on the production project. `cleanup()` DELETEs across
  ///   12 tables of `dedsavbjuwgarrhphgnl` and CI runs it on every push to main.
  @visibleForTesting
  static const Set<String> qaUserIds = <String>{
    // test6@gmail.com — the designated disposable QA account.
    '039b8eb3-f9e9-4673-b7eb-7f14c1a53bc4',
  };

  /// Seam: issues one table's delete. Overridable so a test can assert that
  /// ZERO deletes were issued when the guard refuses — asserting only that a
  /// StateError was thrown would pass against a guard placed AFTER the delete.
  @visibleForTesting
  static Future<void> Function(String table, String userId) deleteRows =
      _realDeleteRows;

  static Future<void> _realDeleteRows(String table, String userId) async {
    await _client.from(table).delete().eq('user_id', userId);
  }

  /// Restores [deleteRows] to the real implementation. Call in tearDown.
  @visibleForTesting
  static void resetSeams() {
    deleteRows = _realDeleteRows;
  }

  /// Refuses any delete whose target is not a designated QA account.
  ///
  /// Pure and parameterised (it does not read `currentUser` itself) so it can be
  /// exercised with no network and no credentials — see
  /// test/supabase/cleanup_target_guard_test.dart.
  ///
  /// Three independent refusals, in order:
  ///   1. no authenticated session at all;
  ///   2. the target is not in [qaUserIds];
  ///   3. the target is not the CURRENT session's own id — so a stray `uid`
  ///      argument cannot delete a different QA account's rows either.
  @visibleForTesting
  static void assertDisposableTarget({
    required String? signedInId,
    required String targetId,
  }) {
    if (signedInId == null) {
      throw StateError(
        'SupabaseTestHelper cleanup REFUSED: no authenticated session. These '
        'deletes hit 12 tables of the PRODUCTION project and must never run '
        'without knowing whose rows they are.',
      );
    }
    if (!qaUserIds.contains(targetId)) {
      throw StateError(
        'SupabaseTestHelper cleanup REFUSED: target "$targetId" is not a '
        'designated QA account. If you repointed the test credentials to make '
        'sign-in work, that is exactly the mistake this guard exists to stop — '
        'add the new account\'s UUID to qaUserIds deliberately, or point the '
        'credentials back. Deleting here would wipe 12 tables of real data.',
      );
    }
    if (targetId != signedInId) {
      throw StateError(
        'SupabaseTestHelper cleanup REFUSED: asked to delete rows for user '
        '"$targetId" while signed in as "$signedInId". Cleanup may only ever '
        'delete the current session\'s own rows.',
      );
    }
  }

  static late SupabaseClient _client;
  static String? _userId;

  /// The authenticated Supabase client.
  static SupabaseClient get client => _client;

  /// The test user's UUID (set after sign-in).
  static String get userId {
    if (_userId == null) {
      throw StateError('Call signIn() before accessing userId');
    }
    return _userId!;
  }

  /// Drops the mock `HttpClient` that `TestWidgetsFlutterBinding` installs.
  ///
  /// The binding is REQUIRED here — `Supabase.initialize()` needs the
  /// shared_preferences platform channel — but it also installs an
  /// `HttpOverrides` whose mock client answers EVERY request with 400 and never
  /// touches the network. These are integration tests whose entire purpose is
  /// to reach the real project, so the mock has to go.
  ///
  /// Without this the failure is actively misleading rather than merely
  /// unhelpful: sign-in throws `AuthUnknownException(... status code 400)`,
  /// which reads exactly like a rejected anon key, so the natural response is
  /// to go re-verify credentials that were never the problem. The 400 comes
  /// from Flutter, not from Supabase. This is what a red `main` looked like on
  /// 2026-08-12, the first time the CI job ran with real secrets (OI-105).
  ///
  /// Exposed (rather than inlined) so a test can assert it actually happened —
  /// see `test/scripts/supabase_test_helper_http_test.dart`.
  @visibleForTesting
  static void debugRemoveHttpMock() {
    TestWidgetsFlutterBinding.ensureInitialized();
    HttpOverrides.global = null;
  }

  /// Register a mock SharedPreferences channel handler so that
  /// Supabase.initialize() works in pure `flutter test` (no device).
  static void _mockSharedPreferences() {
    debugRemoveHttpMock();
    const channel = MethodChannel('plugins.flutter.io/shared_preferences');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (MethodCall call) async {
      if (call.method == 'getAll') return <String, dynamic>{};
      if (call.method == 'setBool' ||
          call.method == 'setString' ||
          call.method == 'remove') {
        return true;
      }
      return null;
    });
  }

  /// Restore real networking after the test binding has stubbed it out.
  ///
  /// MUST be called AFTER `TestWidgetsFlutterBinding.ensureInitialized()` (which
  /// `_mockSharedPreferences()` does) and BEFORE any Supabase call, because that
  /// binding installs an `HttpOverrides.global` returning **status 400 with an
  /// empty body for every request, without making a network call at all**.
  /// Flutter says so itself in the run output:
  ///
  ///   "When running a test suite that uses TestWidgetsFlutterBinding, all HTTP
  ///    requests will return status code 400, and no network request will
  ///    actually be made."
  ///
  /// These are INTEGRATION tests: their whole purpose is to talk to real
  /// Supabase. Under the stub, `signIn()` fails in `setUpAll` with
  /// `AuthUnknownException(... status code 400)` and every file in
  /// `test/supabase/` aborts before its first assertion.
  ///
  /// The binding itself cannot simply be dropped — `Supabase.initialize()`
  /// needs the mocked `shared_preferences` MethodChannel, which requires it.
  /// So: keep the binding, drop only its HTTP interception.
  ///
  /// WHY THIS LAY DORMANT UNTIL 2026-08-12: the suite is gated on
  /// [hasCredentials], and the repo had no Actions secrets, so every file took
  /// its `SKIPPED` branch and the CI job reported green while verifying nothing
  /// (OI-105). The moment `SUPABASE_URL` / `SUPABASE_ANON_KEY` were added, the
  /// tests ran for the first time and hit this immediately. Diagnose: 3b7e1c.
  /// Public (not `_private`) so the regression test can drive it directly and
  /// assert the BEHAVIOUR — that a request actually reaches a real socket —
  /// rather than source-grepping for the assignment. Everything on this class
  /// is test-facing already.
  static void restoreRealHttp() {
    HttpOverrides.global = null;
  }

  /// Installs the test binding AND undoes its HTTP stub, in that order.
  ///
  /// ORDER IS LOAD-BEARING: `_mockSharedPreferences()` calls
  /// `TestWidgetsFlutterBinding.ensureInitialized()`, which is what INSTALLS the
  /// stub. Calling [restoreRealHttp] first and the binding second re-installs it
  /// and the fix silently evaporates.
  ///
  /// Extracted as its own method so both facts are TESTABLE without a live
  /// Supabase URL — round-2 review showed that deleting the `restoreRealHttp()`
  /// call from `init()`, and inverting the two lines, BOTH left the suite green.
  /// The behavioural test drove `restoreRealHttp()` directly and never drove the
  /// sequence. See test/supabase/http_override_restored_test.dart.
  ///
  /// Any test file that installs the binding itself instead of calling
  /// [init] must call this (or [restoreRealHttp]) too — see
  /// test/edge_functions/{ai_proxy,pgvector}_test.dart.
  @visibleForTesting
  static void prepareBinding() {
    _mockSharedPreferences();
    restoreRealHttp();
  }

  /// Initialize Supabase and Hive for testing.
  /// Call once in setUpAll().
  ///
  /// [url] / [anonKey] override the compile-time `--dart-define` values. They
  /// exist ONLY so the wiring test can point a real `init()` at a loopback
  /// server: the defines are `const`, so without an override no test could drive
  /// this method at all.
  static Future<void> init({String? url, String? anonKey}) async {
    prepareBinding();

    await Supabase.initialize(
        url: url ?? supabaseUrl, anonKey: anonKey ?? supabaseAnonKey);
    _client = Supabase.instance.client;

    // Initialize Hive in a temp directory for tests.
    final tempDir = await Directory.systemTemp.createTemp('hive_test_');
    Hive.init(tempDir.path);
  }

  /// Sign in as the QA test user. Returns the user's UUID.
  static Future<String> signIn() async {
    final response = await _client.auth.signInWithPassword(
      email: testEmail,
      password: testPassword,
    );
    _userId = response.user!.id;
    return _userId!;
  }

  /// Sign out the current user.
  static Future<void> signOut() async {
    await _client.auth.signOut();
    _userId = null;
  }

  /// Delete all test data for the given user from all sync-relevant tables.
  /// Call in setUp() to ensure each test starts clean.
  static Future<void> cleanup([String? uid]) async {
    final id = uid ?? _userId;
    // No session → no id → nothing to delete. This returns SILENTLY rather than
    // throwing, and that is a deliberate, narrow choice: `cleanup()` runs in
    // `setUp`, so when `setUpAll`'s sign-in has already failed every test would
    // otherwise report this instead of the real cause. No delete can be issued
    // on this path, so it is not a hole — but do not mistake it for the guard.
    // The guard is [assertDisposableTarget], and it runs whenever there IS an id.
    if (id == null) return;

    // OUTSIDE the try/catch below — a StateError raised here must reach the
    // runner, and `catch (_)` would swallow it, turning a refusal into a
    // silent skip. Same reason pgvector's guard sits outside its own catch.
    assertDisposableTarget(signedInId: _userId, targetId: id);

    // Order matters — FK constraints. Delete children before parents.
    final tables = [
      'user_daily_snapshots',
      'ai_coach_interactions',
      'memory_embeddings',
      'streaks',
      'weight_logs',
      'nutrition_logs',
      'workout_logs',
      'body_measurements',
      'sleep_logs',
      'user_progress',
      'user_profile',
      'user_preferences',
    ];

    for (final table in tables) {
      try {
        await deleteRows(table, id);
      } catch (_) {
        // Table might not exist or have no matching rows — skip.
      }
    }
  }

  /// Query a table for the test user's rows.
  static Future<List<Map<String, dynamic>>> queryTable(
    String table, {
    String userIdColumn = 'user_id',
    String? uid,
  }) async {
    final id = uid ?? _userId;
    if (id == null) throw StateError('No userId — call signIn() first');

    final rows = await _client
        .from(table)
        .select()
        .eq(userIdColumn, id);
    return List<Map<String, dynamic>>.from(rows);
  }

  /// Insert a row into a table. Returns the inserted row.
  static Future<Map<String, dynamic>> insertRow(
    String table,
    Map<String, dynamic> data,
  ) async {
    final rows = await _client.from(table).insert(data).select();
    return Map<String, dynamic>.from(rows.first);
  }

  /// Upsert a row into a table.
  static Future<void> upsertRow(
    String table,
    Map<String, dynamic> data, {
    String onConflict = 'user_id',
  }) async {
    await _client.from(table).upsert(data, onConflict: onConflict);
  }

  /// Clean up Supabase and Hive resources. Call in tearDownAll().
  static Future<void> dispose() async {
    try {
      await signOut();
    } catch (_) {}
    await Hive.close();
  }
}
