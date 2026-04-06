import 'package:flutter/foundation.dart';
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

  /// Fetches or generates a referral code for the current user.
  /// Returns the code string, or null on failure.
  Future<String?> getOrCreateReferralCode() async {
    final userId = currentUser?.id;
    if (userId == null) return null;

    // Check for existing code
    final rows = await client
        .from('referral_codes')
        .select('code')
        .eq('user_id', userId)
        .limit(1);

    if (rows.isNotEmpty) return rows.first['code'] as String?;

    // Generate new code with retry for collisions
    final profile = client.auth.currentUser?.userMetadata;
    final name = (profile?['full_name'] as String?) ?? 'USER';
    final prefix = name.replaceAll(RegExp(r'[^a-zA-Z]'), '').toUpperCase();
    final shortPrefix = prefix.length >= 4 ? prefix.substring(0, 4) : prefix.padRight(4, 'X');

    for (int attempt = 0; attempt < 5; attempt++) {
      final seed = DateTime.now().microsecondsSinceEpoch + attempt * 1000;
      final random = (1000 + seed % 9000).toString();
      final candidate = 'AVYA-$shortPrefix$random';
      try {
        await client.from('referral_codes').insert({
          'user_id': userId,
          'code': candidate,
        });
        return candidate;
      } catch (e) {
        if (attempt == 4) {
          debugPrint('[SupabaseService.getOrCreateReferralCode] $e');
          return null;
        }
      }
    }
    return null;
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
    } catch (e) {
      debugPrint('[SupabaseService.callFunction] refreshSession failed: $e');
      // Check if we still have a valid session — it may not have expired yet
      final session = client.auth.currentSession;
      if (session == null) {
        throw Exception('No active session. Please sign in again.');
      }
      // Session exists but refresh failed — proceed with existing token.
      // The token may still be valid within its JWT expiry window.
    }

    return client.functions.invoke(
      name,
      headers: headers,
      body: body,
    );
  }
}
