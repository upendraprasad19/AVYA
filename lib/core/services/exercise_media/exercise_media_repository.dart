// lib/core/services/exercise_media/exercise_media_repository.dart
//
// On-demand delivery of ONE exercise animation (Batch M2a, Task 7): store hit, else one download, else a miss. No bulk download,
// no persisted daily counter and no plan-window pin in this batch (the M2c draft).
//
// RULES (each is pinned by a lettered case in exercise_media_repository_behavioral_test.dart):
//   - The kill switch guards the SINK: `ensure` checks `enabled()` FIRST and, when it is false, returns null with ZERO client calls
//     and ZERO store reads.
//   - `ensure` is TOTAL (G15): its whole body is inside try/catch; a failing store read or telemetry call is a miss (bytes just
//     fetched are still returned). Telemetry on this path is never awaited: `unawaited(ErrorTelemetry.x(...).catchError((_) {}))`.
//   - ONE in-flight download per object name, covering the fetch AND the `store.put` (removed in `whenComplete` after both).
//   - On-demand back-off: a `refused` or `unreachable` client call stamps the time it COMPLETED for that name; an `ensure` less
//     than `kOnDemandMinInterval` later makes zero client calls and returns null. A success, an `unauthenticated` outcome and a
//     blocked attempt stamp nothing.
//   - An unwritable store (a `put` that throws) arms a back-off of `kStoreUnwritableBackoff`: no `put` is attempted while it is
//     armed, and `ensure` still returns the fetched bytes. (Accepted limit: on a store that cannot keep files every open of that
//     exercise downloads again, bounded by the user's taps and watched by the session counter. A second accepted limit: an
//     `ensure` that misses in the store a few milliseconds before another's `put` lands, and resumes after that one's in-flight
//     entry is cleared, downloads the file once more.)
//   - Session cost net: the length of every fetched file is added to an in-memory counter BEFORE `store.put` (an unwritable store
//     is the very loop the net exists for); the first time it reaches `sessionBytesAlert` ONE `exercise_media_session_over_budget`
//     event is sent. Nothing is ever blocked by it. It is a LOW-priority breadcrumb that `ErrorTelemetry` drops during its
//     rate-limit cooldown (accepted limit, written into EXERCISE_MEDIA.md and OI-444).
//   - First-outcome breadcrumbs: the first `refused` and the first `unreachable` result of the process each send ONE event
//     carrying the HTTP status (or `none`), so a systematic refusal does not look like "offline". A best-effort breadcrumb, not a
//     guarantee (the latch is consumed on the attempt).
//   - `evict(media)` deletes the blob AND bans the name for the session (a file the decoder rejected must not be fetched again).
import 'dart:async';
import 'dart:typed_data';

import 'package:icanbefitter/core/services/error_telemetry.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media_client.dart';
import 'package:icanbefitter/core/services/exercise_media/exercise_media_store.dart';

/// A name whose last client call ended `refused` or `unreachable` is not asked again for this long.
const Duration kOnDemandMinInterval = Duration(seconds: 10);

/// After a `put` throws, no `put` is attempted for this long.
const Duration kStoreUnwritableBackoff = Duration(minutes: 5);

/// The per-platform delivery switches. Task 1's verdicts set one false: S3 and S3b blocked on web, S1 "no" or the S6 rule on a
/// platform. Unobserved verdicts ship true (docs/audit/library-m2-spike-findings.md).
const bool kWebAnimationsFetchEnabled = true;
const bool kNativeAnimationsFetchEnabled = true;

/// Which platform switch applies.
bool animationsPlatformEnabled({required bool isWeb, required bool webSwitch, required bool nativeSwitch}) =>
    isWeb ? webSwitch : nativeSwitch;

class ExerciseMediaRepository {
  ExerciseMediaRepository({
    required ExerciseMediaClient client,
    required ExerciseMediaStore store,
    DateTime Function()? now,
    bool Function()? enabled,
    int sessionBytesAlert = 100 * 1024 * 1024,
  })  : _client = client,
        _store = store,
        _now = now ?? DateTime.now,
        _enabled = enabled ?? (() => true),
        _sessionBytesAlert = sessionBytesAlert;

  final ExerciseMediaClient _client;
  final ExerciseMediaStore _store;
  final DateTime Function() _now;
  final bool Function() _enabled;
  final int _sessionBytesAlert;

  final Map<String, Future<Uint8List?>> _inFlight = <String, Future<Uint8List?>>{};
  final Map<String, DateTime> _blockedAt = <String, DateTime>{};
  final Set<String> _banned = <String>{};
  DateTime? _unwritableSince;

  int _sessionBytes = 0;
  int _sessionFiles = 0;
  bool _sessionAlerted = false;
  bool _firstRefusedSent = false;
  bool _firstUnreachableSent = false;

  /// Telemetry never delays the caller and never throws into it.
  static void _report(Object error, StackTrace stack, String reason) {
    unawaited(ErrorTelemetry.recordNonFatal(error, stack, reason: reason).catchError((Object _) {}));
  }

  static void _event(String opType, String message) {
    unawaited(ErrorTelemetry.logEvent(opType, message: message).catchError((Object _) {}));
  }

  /// The animation bytes for [media]: from the store, else downloaded once; null when unavailable. Never throws.
  Future<Uint8List?> ensure(ExerciseMedia media) async {
    try {
      if (!_enabled()) return null;
      final name = media.objectName;
      if (_banned.contains(name)) return null;

      Uint8List? hit;
      try {
        hit = await _store.read(name);
      } catch (e, st) {
        _report(e, st, 'exercise_media_repository_read');
        hit = null;
      }
      if (hit != null) return hit;

      final running = _inFlight[name];
      if (running != null) return await running;

      final blockedAt = _blockedAt[name];
      if (blockedAt != null && _now().difference(blockedAt) < kOnDemandMinInterval) return null;

      late final Future<Uint8List?> future;
      future = _download(name).whenComplete(() {
        if (identical(_inFlight[name], future)) _inFlight.remove(name);
      });
      _inFlight[name] = future;
      return await future;
    } catch (e, st) {
      _report(e, st, 'exercise_media_repository_ensure');
      return null;
    }
  }

  Future<Uint8List?> _download(String name) async {
    final result = await _client.fetch(name);
    switch (result.outcome) {
      case MediaFetchOutcome.unauthenticated:
        return null;
      case MediaFetchOutcome.refused:
      case MediaFetchOutcome.unreachable:
        _blockedAt[name] = _now(); // the time the call COMPLETED
        _firstOutcome(result);
        return null;
      case MediaFetchOutcome.fetched:
        final bytes = result.bytes;
        if (bytes == null) return null;
        _countSession(bytes.length); // BEFORE the put, and whether or not the put is skipped
        await _putGuarded(name, bytes);
        return bytes;
    }
  }

  Future<void> _putGuarded(String name, Uint8List bytes) async {
    final since = _unwritableSince;
    if (since != null && _now().difference(since) < kStoreUnwritableBackoff) return; // armed: no put
    try {
      await _store.put(name, bytes);
      _unwritableSince = null;
    } catch (e, st) {
      _unwritableSince = _now();
      _report(e, st, 'exercise_media_repository_put');
    }
  }

  void _countSession(int length) {
    _sessionBytes += length;
    _sessionFiles++;
    if (!_sessionAlerted && _sessionBytes >= _sessionBytesAlert) {
      _sessionAlerted = true;
      _event('exercise_media_session_over_budget', 'bytes=$_sessionBytes files=$_sessionFiles');
    }
  }

  void _firstOutcome(MediaFetchResult r) {
    final status = r.status?.toString() ?? 'none';
    if (r.outcome == MediaFetchOutcome.refused && !_firstRefusedSent) {
      _firstRefusedSent = true;
      _event('exercise_media_first_refused', 'status=$status');
    } else if (r.outcome == MediaFetchOutcome.unreachable && !_firstUnreachableSent) {
      _firstUnreachableSent = true;
      _event('exercise_media_first_unreachable', 'status=$status');
    }
  }

  /// Drops the cached file and bans the name for this session (the decoder rejected it). Total.
  Future<void> evict(ExerciseMedia media) async {
    final name = media.objectName;
    _banned.add(name); // recorded regardless of what the delete does
    try {
      await _store.delete(name);
    } catch (e, st) {
      _report(e, st, 'exercise_media_repository_evict');
    }
  }
}
