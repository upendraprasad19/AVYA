import 'package:icanbefitter/core/constants/app_constants.dart';
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
  // Stored so concurrent callers await the same Future and never double-init.
  Future<void>? _initFuture;

  /// Initialize the Supabase client. Call once in main() before runApp().
  /// Safe to call concurrently — only one actual init will run.
  Future<void> initialize() async {
    if (_initialized) return;
    _initFuture ??= _doInitialize();
    await _initFuture;
  }

  Future<void> _doInitialize() async {
    assert(AppConstants.supabaseUrl.isNotEmpty, 'SUPABASE_URL not set — pass --dart-define-from-file=.env');
    assert(AppConstants.supabaseAnonKey.isNotEmpty, 'SUPABASE_ANON_KEY not set — pass --dart-define-from-file=.env');

    await Supabase.initialize(
      url: AppConstants.supabaseUrl,
      anonKey: AppConstants.supabaseAnonKey,
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

  /// Whether Supabase has been successfully initialized.
  bool get isInitialized => _initialized;

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
  }) async {
    // Ensure JWT is fresh before calling edge functions
    try {
      await client.auth.refreshSession();
    } catch (_) {
      // Refresh failed — proceed anyway, the invoke will surface the auth error
    }

    return client.functions.invoke(
      name,
      headers: headers,
      body: body,
    );
  }
}
