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

  static const String testEmail = 'qa@icanbefitter.com';
  static const String testPassword = 'QA_Test_2024!';

  static const supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY');

  /// Returns true if env vars are configured. Tests should skip if false.
  static bool get hasCredentials =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;

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
    if (id == null) return;

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
        await _client.from(table).delete().eq('user_id', id);
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
