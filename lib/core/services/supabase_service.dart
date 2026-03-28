import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Singleton wrapper around the Supabase client.
///
/// Supabase is used for:
///   - Auth (Email + Google OAuth + Phone OTP)
///   - Backup & cross-device restore
///   - AI training corpus (snapshots, conversations)
///   - Community DB growth (custom foods/exercises)
///   - Subscription verification
///
/// It is NOT the primary database — Hive handles all reads/writes locally.
class SupabaseService {
  SupabaseService._();
  static final SupabaseService _instance = SupabaseService._();
  static SupabaseService get instance => _instance;

  bool _initialized = false;

  /// Initialize the Supabase client. Call once in main() before runApp().
  Future<void> initialize() async {
    if (_initialized) return;

    await Supabase.initialize(
      url: dotenv.env['SUPABASE_URL']!,
      anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
    );

    _initialized = true;
  }

  /// The global Supabase client instance.
  /// Throws if Supabase has not been initialized.
  SupabaseClient get client => Supabase.instance.client;

  /// Current authenticated user, or null if not signed in.
  /// Returns null if Supabase is not initialized.
  User? get currentUser {
    if (!_initialized) return null;
    return client.auth.currentUser;
  }

  /// Current auth session, or null.
  Session? get currentSession {
    if (!_initialized) return null;
    return client.auth.currentSession;
  }

  /// Whether a user is currently authenticated.
  /// Returns false if Supabase is not initialized.
  bool get isAuthenticated {
    if (!_initialized) return false;
    return currentUser != null;
  }

  /// Shortcut to invoke a Supabase Edge Function by [name].
  Future<FunctionResponse> callFunction(
    String name, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
  }) {
    return client.functions.invoke(
      name,
      headers: headers,
      body: body,
    );
  }
}
