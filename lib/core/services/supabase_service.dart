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
    // Runtime guard — works in both debug AND release builds.
    // (assert() is stripped in release, so this is the real safety net.)
    if (AppConstants.supabaseUrl.isEmpty ||
        AppConstants.supabaseAnonKey.isEmpty) {
      throw StateError(
        'SUPABASE_URL or SUPABASE_ANON_KEY is empty. '
        'Build with: flutter run --dart-define-from-file=.env --flavor dev',
      );
    }

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

  /// Returns a fresh access token, refreshing proactively if the current
  /// JWT expires within [buffer]. Returns null if no session exists or
  /// refresh fails and the token is already expired.
  Future<String?> ensureFreshToken({
    Duration buffer = const Duration(seconds: 60),
  }) async {
    final session = client.auth.currentSession;
    if (session == null) return null;

    // Check if token expires within the buffer window
    final expiresAt = session.expiresAt;
    if (expiresAt != null) {
      final expiryTime = DateTime.fromMillisecondsSinceEpoch(expiresAt * 1000);
      if (DateTime.now().isAfter(expiryTime.subtract(buffer))) {
        // Token is about to expire or already expired — refresh
        try {
          final refreshed = await client.auth.refreshSession();
          return refreshed.session?.accessToken;
        } catch (e) {
          debugPrint('[SupabaseService.ensureFreshToken] refresh failed: $e');
          // If token is already past expiry, return null (caller should handle)
          if (DateTime.now().isAfter(expiryTime)) return null;
          // Token hasn't expired yet, return existing
          return session.accessToken;
        }
      }
    }

    // Token is still fresh
    return session.accessToken;
  }

  /// Shortcut to invoke a Supabase Edge Function by [name].
  ///
  /// Proactively refreshes the JWT if it expires within 60 seconds.
  /// Returns the response directly — callers handle non-200 status codes.
  Future<FunctionResponse> callFunction(
    String name, {
    Map<String, String>? headers,
    Map<String, dynamic>? body,
  }) async {
    // Proactive token refresh — avoids sending an expired JWT
    final token = await ensureFreshToken();
    if (token == null && client.auth.currentSession == null) {
      throw Exception('No active session. Please sign in again.');
    }

    // Single attempt — no auto-retry here.
    // Callers (e.g. AiCoachProvider) handle auth errors at their own level.
    final response = await client.functions.invoke(
      name,
      headers: headers,
      body: body,
    );

    return response;
  }
}
