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

  /// Initialize Supabase and Hive for testing.
  /// Call once in setUpAll().
  static Future<void> init() async {
    _mockSharedPreferences();

    await Supabase.initialize(url: supabaseUrl, anonKey: supabaseAnonKey);
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
