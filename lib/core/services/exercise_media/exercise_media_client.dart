// lib/core/services/exercise_media/exercise_media_client.dart
//
// The ONE HTTP class that reads the private `exercise-media` bucket (Batch M2a, Task 6, G2). One Dio client, one route:
//
//   GET <supabase url>/storage/v1/object/authenticated/exercise-media/<object name>
//   Authorization: Bearer <the user's access token>      apikey: <anon key>
//
// It is never `storage.from(...)` (a source-grep test pins that), never `package:http` (Gate 45), and it validates the object
// name it puts in the URL because this class is the one place the route is built.
//
// OUTCOMES (`MediaFetchOutcome`)
//   fetched         a 200 whose body passed `isWellFormedWebp`.
//   refused         the server or the body said no: another 4xx, an unexpected 1xx/2xx/3xx, a body that is not a WebP, or a name
//                   that does not match the object-name pattern. Retry later, never "this exercise has no animation".
//   unreachable     5xx, a timeout, a connection error or any other `DioException`.
//   unauthenticated there is no usable session (no token, a null token, an anonymous session, or a seam that threw). ZERO
//                   requests, and unlike `refused` it must never arm a per-name back-off that the next account would inherit.
//
// AUTH. 400 and 401 are retried at most ONCE, after a forced token refresh, and only if no forced refresh happened in the last
// 60 s process-wide (forty absent files cost one refresh, not forty). A 200 never triggers a refresh. Both default seams (the
// token and the anonymous check) are wrapped in `catch (_)`, which catches every throwable: `Supabase.instance` throws an
// `AssertionError` when Supabase is not initialised, and neither that nor a `LateInitializationError` is an `Exception`.
//
// PRIVACY (G15). Nothing here logs, reports or throws text that carries the token, a header or a full URL. There is no telemetry
// parameter and no `debugPrint`; the repository above decides what to report.
//
// REDIRECTS. `followRedirects: false` so a redirect never carries the token to another host. The IO adapter honours it; the web
// adapter has no such option and the browser follows redirects through XHR (it drops `Authorization` on a cross-origin redirect).
// The web limit is stated in docs/operations/EXERCISE_MEDIA.md.
import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:icanbefitter/core/constants/app_constants.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media_webp.dart';
import 'package:icanbefitter/core/services/supabase_service.dart';

enum MediaFetchOutcome { fetched, refused, unreachable, unauthenticated }

class MediaFetchResult {
  const MediaFetchResult(this.outcome, {this.bytes, this.status});

  final MediaFetchOutcome outcome;

  /// Set only for [MediaFetchOutcome.fetched].
  final Uint8List? bytes;

  /// The HTTP status when one was received, else null (a connection error, a timeout, no request made).
  final int? status;
}

final RegExp _objectNamePattern = RegExp(r'^[a-z0-9][a-z0-9-]*_v[1-9][0-9]*\.webp$');

class ExerciseMediaClient {
  ExerciseMediaClient({
    Dio? dio,
    Future<String?> Function({bool forceRefresh})? tokenProvider,
    bool Function()? isAnonymous,
    String? baseUrl,
    DateTime Function()? now,
    bool? isWeb,
  })  : _dio = dio ?? Dio(),
        _token = tokenProvider ?? _defaultToken,
        _isAnonymous = isAnonymous ?? _defaultIsAnonymous,
        _baseUrl = _trimSlash(baseUrl ?? AppConstants.supabaseUrl),
        _now = now ?? DateTime.now,
        _isWeb = isWeb ?? kIsWeb;

  final Dio _dio;
  final Future<String?> Function({bool forceRefresh}) _token;
  final bool Function() _isAnonymous;
  final String _baseUrl;
  final DateTime Function() _now;
  final bool _isWeb;

  /// The last forced token refresh, process-wide (a static timestamp read through [_now]).
  static DateTime? _lastForcedRefresh;
  static const Duration _refreshCooldown = Duration(seconds: 60);
  static const Duration _wholeFetchTimeout = Duration(seconds: 60);

  @visibleForTesting
  static void resetCooldown() => _lastForcedRefresh = null;

  static String _trimSlash(String s) => s.endsWith('/') ? s.substring(0, s.length - 1) : s;

  static Future<String?> _defaultToken({bool forceRefresh = false}) => SupabaseService.instance.ensureFreshToken(
        // A buffer longer than any token lifetime forces the refresh through the same joined path. It can still hand back the
        // SAME token (a still-fresh token, or a refresh that failed on an unexpired one); the retry then simply fails again.
        buffer: forceRefresh ? const Duration(hours: 24) : const Duration(minutes: 5),
      );

  /// The SAME session `ensureFreshToken` reads (`client.auth.currentSession`, not `SupabaseService.currentSession`, which is
  /// null whenever `_initialized` is false). A null session reads as "not anonymous" only because the token seam then returns
  /// null and the request is never made.
  static bool _defaultIsAnonymous() => SupabaseService.instance.client.auth.currentSession?.user.isAnonymous == true;

  /// Total: nothing escapes as an exception.
  Future<MediaFetchResult> fetch(String objectName) async {
    try {
      if (!_objectNamePattern.hasMatch(objectName)) {
        return const MediaFetchResult(MediaFetchOutcome.refused);
      }
      final cancel = CancelToken();
      final work = _fetch(objectName, cancel);
      // Web already has a whole-request cap (xhr.timeout). Native's receiveTimeout is per chunk, so a trickling connection
      // would hold a request open for minutes: bound the whole fetch and CANCEL the request when the bound is hit.
      if (_isWeb) return await work;
      return await work.timeout(_wholeFetchTimeout, onTimeout: () {
        cancel.cancel('exercise media fetch timed out');
        return const MediaFetchResult(MediaFetchOutcome.unreachable);
      });
    } catch (_) {
      return const MediaFetchResult(MediaFetchOutcome.unreachable);
    }
  }

  Future<MediaFetchResult> _fetch(String name, CancelToken cancel) async {
    try {
      final String? token;
      try {
        if (_isAnonymous()) return const MediaFetchResult(MediaFetchOutcome.unauthenticated);
        token = await _token(forceRefresh: false);
      } catch (_) {
        return const MediaFetchResult(MediaFetchOutcome.unauthenticated);
      }
      if (token == null || token.isEmpty) return const MediaFetchResult(MediaFetchOutcome.unauthenticated);

      final first = await _get(name, token, cancel);
      if (first.outcome != MediaFetchOutcome.refused || (first.status != 400 && first.status != 401)) return first;

      // At most ONE retry, and only if no forced refresh happened in the last 60 s process-wide.
      final t = _now();
      final last = _lastForcedRefresh;
      if (last != null && t.difference(last) < _refreshCooldown) return first;
      _lastForcedRefresh = t;
      String? forced;
      try {
        forced = await _token(forceRefresh: true);
      } catch (_) {
        forced = null;
      }
      if (forced == null || forced.isEmpty) return first;
      return await _get(name, forced, cancel);
    } catch (_) {
      return const MediaFetchResult(MediaFetchOutcome.unreachable);
    }
  }

  Future<MediaFetchResult> _get(String name, String token, CancelToken cancel) async {
    final Response<List<int>> r;
    try {
      r = await _dio.get<List<int>>(
        '$_baseUrl/storage/v1/object/authenticated/exercise-media/$name',
        cancelToken: cancel,
        options: Options(
          responseType: ResponseType.bytes,
          validateStatus: (_) => true,
          followRedirects: false,
          headers: <String, Object>{
            'Authorization': 'Bearer $token',
            'apikey': AppConstants.supabaseAnonKey,
          },
          connectTimeout: const Duration(seconds: 10),
          // Native: applied per chunk once the body streams. Web: Dio sets xhr.timeout = connectTimeout + receiveTimeout, a
          // WHOLE-request cap (10 s + 120 s), so a 988 KB file needs only about 7.6 KB/s.
          receiveTimeout: _isWeb ? const Duration(seconds: 120) : const Duration(seconds: 20),
        ),
      );
    } catch (_) {
      // A DioException of any type (connection, timeout, cancel, bad certificate, unknown) or anything else thrown by the
      // adapter. Never forwarded: its text carries the URL and its request options carry the token.
      return const MediaFetchResult(MediaFetchOutcome.unreachable);
    }
    final status = r.statusCode;
    if (status == null) return const MediaFetchResult(MediaFetchOutcome.unreachable);
    if (status >= 500 && status < 600) return MediaFetchResult(MediaFetchOutcome.unreachable, status: status);
    if (status != 200) return MediaFetchResult(MediaFetchOutcome.refused, status: status);
    final data = r.data;
    if (data == null) return MediaFetchResult(MediaFetchOutcome.refused, status: status);
    final bytes = data is Uint8List ? data : Uint8List.fromList(data);
    if (!isWellFormedWebp(bytes)) return MediaFetchResult(MediaFetchOutcome.refused, status: status);
    return MediaFetchResult(MediaFetchOutcome.fetched, bytes: bytes, status: status);
  }
}
