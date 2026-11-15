import 'dart:async';

import 'package:flutter/foundation.dart';

/// OI-505 (b): the time limit of a coach chat turn, and the flag that tells an
/// ABANDONED call to stop sending.
///
/// Plan docs/plans/2026-11-13-coach-late-link-timeout-retry.md fix 2, diagnose
/// c8f2a4. The coach call (`AiService.chat` / `chatWithMedia`) had no time limit:
/// on 2026-11-13 a request hung through a database outage for 19 minutes before
/// the browser dropped it and the user saw "Something went wrong". The notifier
/// now bounds the call with a timeout; a Dart `Future.timeout` abandons the
/// future but does not stop it, so the call's retry loops (the cold-start
/// retry, the direct HTTP fallback) would keep re-sending the same turn and
/// could reserve a second row. They check [expired] before every send instead.
class CoachCallBudget {
  /// Set by the caller's timeout handler. A call that sees it stops sending
  /// and throws; the throw lands on the abandoned future and is ignored.
  bool expired = false;

  /// Throws a [TimeoutException] when the budget has expired. Placed before
  /// every network send of a coach call (the entry of each fallback, the top
  /// of each retry loop iteration, after a token refresh).
  void throwIfExpired() {
    if (expired) {
      throw TimeoutException('coach call abandoned (budget expired)');
    }
  }

  /// Test seam: a short chat timeout so a notifier test does not wait 75 s.
  /// Real Hive disk I/O never drains inside `fakeAsync`, so the notifier tests
  /// are plain tests with an override of a few milliseconds.
  @visibleForTesting
  static Duration? chatTimeoutOverride;

  /// Test seam for the photo turn's timeout.
  @visibleForTesting
  static Duration? mediaTimeoutOverride;

  /// Test seam for the whole-turn deadline of the chat path.
  @visibleForTesting
  static Duration? turnDeadlineOverride;

  /// A chat call is abandoned after this long (5 times the measured p95 of
  /// ai-proxy, above the cold-start retry chain of about 20 s plus Gemini). A
  /// legitimately slower turn finishes on the server and a Retry gets its
  /// stored answer (fix 4).
  static const Duration chatTimeout = Duration(seconds: 75);

  /// A photo turn uploads and analyses an image: longer.
  static const Duration mediaTimeout = Duration(seconds: 120);

  /// The whole chat turn, the auth re-send included: a hard deadline from the
  /// first send.
  static const Duration turnDeadline = Duration(seconds: 90);

  /// The session refresh before an auth re-send is bounded on its own.
  static const Duration authRefreshTimeout = Duration(seconds: 15);

  /// An auth error that arrives after this is NOT re-sent: refresh (15 s) plus
  /// the shortest useful re-send (15 s) must still fit [turnDeadline].
  static const Duration latestAuthResend = Duration(seconds: 60);

  /// The shortest time a re-send is given.
  static const Duration minimumResend = Duration(seconds: 15);

  /// Test seam for [minimumResend].
  @visibleForTesting
  static Duration? minimumResendOverride;

  /// Test seam for [latestAuthResend].
  @visibleForTesting
  static Duration? latestAuthResendOverride;

  /// Test seam for [authRefreshTimeout].
  @visibleForTesting
  static Duration? authRefreshTimeoutOverride;

  /// What the auth re-send may use: the rest of the turn deadline, never less
  /// than the minimum. [elapsed] is the turn's own stopwatch.
  static Duration resendTimeout(Duration elapsed) {
    final left = effectiveTurnDeadline - elapsed;
    final floor = minimumResendOverride ?? minimumResend;
    return left < floor ? floor : left;
  }

  static Duration get effectiveLatestAuthResend =>
      latestAuthResendOverride ?? latestAuthResend;
  static Duration get effectiveAuthRefreshTimeout =>
      authRefreshTimeoutOverride ?? authRefreshTimeout;
  static Duration get effectiveChatTimeout => chatTimeoutOverride ?? chatTimeout;
  static Duration get effectiveMediaTimeout =>
      mediaTimeoutOverride ?? mediaTimeout;
  static Duration get effectiveTurnDeadline =>
      turnDeadlineOverride ?? turnDeadline;
}
