import 'dart:io';

import 'package:flutter_dotenv/flutter_dotenv.dart';
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

  /// Initialize dotenv, Supabase, and Hive for testing.
  /// Call once in setUpAll().
  static Future<void> init() async {
    // Load .env from project root.
    await dotenv.load(fileName: '.env');

    final url = dotenv.env['SUPABASE_URL']!;
    final anonKey = dotenv.env['SUPABASE_ANON_KEY']!;

    await Supabase.initialize(url: url, anonKey: anonKey);
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
